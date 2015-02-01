/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This sensor periodically monitors the memory pages of a process
 * providing data similar to fsense. It is rather slow, naive and crude -
 * relying on being able to ptrace having access to /proc/pid/mem interface,
 * which any ol' DRM will disable on first breath.
 *
 * Possible improvements include:
 *
 *  - Extend with solutions for other environments: gdb/lldb plugin
 *
 *  - Being able to run as a process parasite; inject, grab another thread,
 *    handle the obvious "program unmapped memory while being read" race.
 *    Other sneaky option would be inject + fork and use COW semantics
 *    to protect us.
 *
 *  - Use the alpha channel for good: pattern/entropy encoding support already
 *    provides us with 254 different highlight groups. Combine that with a
 *    classifier like capstone and we can get a quick overview of changes in
 *    +x pages, useful for those nasty JITs, polymorphs and unpackers.
 *
 * Current Issues:
 *
 *  - synch_copy is still incomplete, process control issues?
 *  - stepframe is still incomplete (depends on synch_copy)
 */
#define _LARGEFILE64_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <inttypes.h>
#include <stdint.h>
#include <unistd.h>
#include <stdbool.h>
#include <pthread.h>
#include <string.h>
#include <errno.h>
#include <math.h>

#include <arcan_shmif.h>
#include <poll.h>

#include <sys/types.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <sys/ptrace.h>

#include "senseye.h"
#include "font_8x8.h"
#include "rwstat.h"

struct page_ch {
	struct senseye_ch* channel;
	int fd;
	uintptr_t base;
	size_t size;
};

struct {
/* tracing and synchronization */
	bool ptrace;
	pid_t pid;
	pthread_mutex_t plock;

/* cursor tracking */
	ssize_t sel;
	size_t sel_lim, sel_page;
	uintptr_t sel_base;
	size_t sel_size;

/* external connections */
	struct senseye_cont* cont;
} msense = {0};

static void update_preview(shmif_pixel ccol);
void* data_loop(void*);

/*
 * try to acquire a handle into the memory of the process
 * at a specific base and width, if successful, spawn a new
 * data connection to senseye.
 */
static void launch_addr(uintptr_t base, size_t size)
{
	char wbuf[sizeof("/proc//mem") + 8];
	snprintf(wbuf, sizeof(wbuf), "/proc/%d/mem", (int) msense.pid);
	int fd = open(wbuf, O_RDONLY);
	if (-1 == fd){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx open (%s) failed, %s\n",
			base, size, wbuf, strerror(errno));
		return;
	}

	if (-1 == lseek64(fd, base, SEEK_SET)){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx  couldn't seek, %s\n",
			base, size, strerror(errno));
		close(fd);
		return;
	}

/* or calculate base by sqrt -> prev POT */
	snprintf(wbuf, sizeof(wbuf), "%d@%" PRIxPTR, (int)msense.pid, base);
	struct senseye_ch* ch = senseye_open(msense.cont, wbuf, 512);

	if (NULL == ch){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx "
			"couldn't open data channel\n", base, size);
		close(fd);
		return;
	}

	pthread_t pth;
	struct page_ch* pch = malloc(sizeof(struct page_ch));
	if (NULL == pch){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx "
			"couldn't setup processing storage\n", base, size);
		close(fd);
		return;
	}

	pch->channel = ch;
	pch->fd = fd;
	pch->base = base;
	pch->size = size;

	if (-1 == pthread_create(&pth, NULL, data_loop, pch)){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx "
			"couldn't spawn processing thread\n", base, size);
		ch->close(ch);
		free(pch);
		close(fd);
		return;
	}
}

/*
 * basic input mapping for the control- channel UI,
 * check senseye/senses/msense_main.lua
 */
static void control_event(struct senseye_cont* cont, arcan_event* ev)
{
	bool refresh = false;

	if (ev->category == EVENT_IO){
		if (strcmp(ev->label, "UP") == 0){
			msense.sel = (msense.sel - 1 < 0) ? msense.sel_lim - 1 : msense.sel - 1;
			refresh = true;
		}
		else if (strcmp(ev->label, "DOWN") == 0){
			msense.sel = (msense.sel + 1) % (msense.sel_lim);
			refresh = true;
		}
		else if (strcmp(ev->label, "LEFT") == 0){
			msense.sel -= msense.sel_page;
			if (msense.sel < 0)
				msense.sel += msense.sel_lim;
			refresh = true;
		}
		else if (strcmp(ev->label, "RIGHT") == 0){
			msense.sel += msense.sel_page;
			if (msense.sel >= msense.sel_lim)
				msense.sel = 0;
			refresh = true;
		}
		else if (strcmp(ev->label, "SELECT") == 0){
			if (!msense.ptrace)
				fprintf(stderr, "cannot inspect segment, ptrace support disabled.\n");
			else
				launch_addr(msense.sel_base, msense.sel_size);
		}
	}

	if (refresh)
		update_preview(RGBA(0x00, 0xff, 0x00, 0xff));
}

static void synch_copy(struct rwstat_ch* ch, int fd, uint8_t* buf, size_t nb)
{
	ch->switch_clock(ch, RW_CLK_BLOCK);
	pthread_mutex_lock(&msense.plock);

	ssize_t nr = read(fd, buf, nb);
	if (-1 == nr){
		fprintf(stderr, "Couldn't read from page offset, code: %d\n", errno);
		nr = 0;
	}

	if (nr != nb)
		memset(buf + nr, '\0', nb - nr);

	ptrace(PTRACE_CONT, msense.pid, NULL, NULL);
	pthread_mutex_unlock(&msense.plock);

	int ign;
	ch->data(ch, buf, nb, &ign);
}

void* data_loop(void* th_data)
{
/* we ignore the senseye- abstraction here and works
 * directly with the rwstat and shmif context */
	struct page_ch* pch = (struct page_ch*)th_data;
	struct rwstat_ch* ch = pch->channel->in;
	struct arcan_shmif_cont* cont = ch->context(ch);

	size_t buf_sz = ch->left(ch);
	uint8_t* buf = malloc(buf_sz);

	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_IDENT,
		.ext.message = "msense"
	};

	ch->event(ch, &ev);

	synch_copy(ch, pch->fd, buf, buf_sz);

	while (buf && arcan_shmif_wait(cont, &ev) != 0){
		if (rwstat_consume_event(ch, &ev)){
			if (ch->left(ch) > buf_sz){
				free(buf);
				buf_sz = ch->left(ch);
				buf = malloc(buf_sz);
			}

			continue;
		}

		if (ev.category == EVENT_TARGET)
		switch(ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
			return NULL;
		break;

		case TARGET_COMMAND_STEPFRAME:{
			if (ev.tgt.ioevs[0].iv == 0){
				off64_t ofs = lseek64(pch->fd, 0, SEEK_CUR);
				if (-1 == ofs)
					goto error;
			 	synch_copy(ch, pch->fd, buf, buf_sz);
				lseek64(pch->fd, ofs, SEEK_SET);
			}
/* 0, refresh current position, 1/-1 step row, 2/-2 step block size */
		}
		default:
		break;
		}
	}

error:
	pch->channel->close(pch->channel);
	free(th_data);
	return NULL;
}

static FILE* get_map_descr(pid_t pid)
{
	char wbuf[sizeof("/proc//maps") + 8];
	snprintf(wbuf, sizeof(wbuf), "/proc/%d/maps", (int) msense.pid);
	FILE* fpek = fopen(wbuf, "r");
	return fpek;
}

/*
 * more complex here than in other senses due to the dynamic
 * nature of proc/pid/maps and that the currently selected
 * item won't fit in the allocated output buffer.
 */
static void update_preview(shmif_pixel ccol)
{
/* clear window */
	struct arcan_shmif_cont* c = msense.cont->context(msense.cont);
	draw_box(c, 0, 0, c->addr->w, c->addr->h, RGBA(0x00, 0x00, 0x00, 0xff));
	FILE* fpek = get_map_descr(msense.pid);
	if (!fpek){
		fprintf(stderr, "couldn't open proc/pid/maps for reading.\n");
		exit(EXIT_FAILURE);
	}

/* get number of entries */
	size_t count;
	for (count = 0; !feof(fpek); count++)
		while(fgetc(fpek) != '\n' && !feof(fpek))
			;
	fseek(fpek, 0, SEEK_SET);

/* clamp */
	if (msense.sel >= count)
		msense.sel = count - 1;

	msense.sel_lim = count - 1;
	size_t nl = c->addr->h / (fonth + 1);
	msense.sel_page = nl;

	int page = 0;
 	if (msense.sel > 0)
		page = msense.sel / nl;

	size_t sc = page * nl;

/* if we don't fit, skip to page, note TOCTU here */
	while(sc && !feof(fpek)){
		while(fgetc(fpek) != '\n'){
			if (feof(fpek))
				break;
		}
		sc--;
	}

	int y = 0;
	int cc = msense.sel % nl;

/* each step requires reprocessing the proc entry, expensive
 * but provides a somewhat more accurate view (inotify etc. doesn't
 * do anything on proc, so other option to work with a cache would
 * be to take advantage of ptrace. */
	while(!feof(fpek) && y < c->addr->h){
		long long addr, endaddr, offset, inode = 0;
		char perm[6], device[16];
		int ret = fscanf(fpek, "%llx-%llx %6s %llx %16s %llx",
			&addr, &endaddr, perm, &offset, device, &inode);
		if (0 == ret){
				while (fgetc(fpek) != '\n' && !feof(fpek))
					;
			continue;
		}

		if (-1 == ret || ret == EOF)
		break;

		uint8_t r = perm[0] == 'r' ? 0xff : 0x55;
		uint8_t g = perm[1] == 'w' ? 0xff : 0x55;
		uint8_t b = perm[2] == 'x' ? 0xff : 0x55;

		draw_box(c, fontw, y, c->addr->w, y + fonth, RGBA( (perm[0] == 'r') & 0xff,
			(perm[1] == 'w') & 0xff, (perm[2] == 'x') & 0xff, 0xff));

		if (cc == 0){
			msense.sel_base = addr + offset;
			msense.sel_size = endaddr - addr;
			cc--;
		}
		else if (cc > 0)
			cc--;

/* draw addr + text in fitting color */
		char wbuf[256];
		shmif_pixel col = RGBA(r, g, b, 0xff);
		snprintf(wbuf, 256, "%llx(%dk)", addr, (int)((endaddr - addr) / 1024));
		draw_text(c, wbuf, fontw + 1, y, col);

		y += fonth + 1;
	}

	draw_box(c, 0, (msense.sel % nl) * (fonth+1), fontw, fonth, ccol);
	fclose(fpek);
	arcan_shmif_signal(c, SHMIF_SIGVID);
}

int main(int argc, char* argv[])
{
	struct senseye_cont cont;
	struct arg_arr* aarr;

	if (2 != argc){
		printf("usage: psense process_id\n");
		return EXIT_FAILURE;
	}

	msense.pid = strtol(argv[1], NULL, 10);

	FILE* fp = get_map_descr(msense.pid);
	if (!fp){
		fprintf(stderr, "Couldn't open /proc/%d/maps, reason: %s\n",
			(int) msense.pid, strerror(errno));
		return EXIT_FAILURE;
	}
	fclose(fp);

	if (!senseye_connect(NULL, stderr, &cont, &aarr))
		return EXIT_FAILURE;

/* dimension the control window to match the size of
 * the base-address and its width */
	int desw = (fontw + 1) * (sizeof(void*) + 8 + 3);
	if (!arcan_shmif_resize(cont.context(&cont), desw, 512))
		return EXIT_FAILURE;

	if (-1 == ptrace(PTRACE_ATTACH, msense.pid, NULL, NULL)){
		fprintf(stderr, "ptrace(%d) failed, page "
			"inspection disabled\n", (int)msense.pid);
		msense.ptrace = false;
	}
	else{
		msense.ptrace = true;
		waitpid(msense.pid, NULL, 0);
		pthread_mutex_init(&msense.plock, NULL);
	}

	msense.cont = &cont;
	update_preview(RGBA(0x00, 0xff, 0x00, 0xff));

	cont.dispatch = control_event;

	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_IDENT,
		.ext.message = "msense_main"
	};
	arcan_shmif_enqueue(msense.cont->context(msense.cont), &ev);

	while (senseye_pump(&cont)){
	}

	return EXIT_SUCCESS;
}
