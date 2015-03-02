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
 *  - Better / real (optional) process control semantics
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

#include "sense_supp.h"
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
	bool skip_inode;

/* external connections */
	struct senseye_cont* cont;
} msense = {
 .skip_inode = true
};

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
				msense.sel = msense.sel_lim - 1;
			if (msense.sel < 0)
				msense.sel = 0;
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

static size_t synch_copy(struct rwstat_ch* ch, int fd, uint8_t* buf, size_t nb)
{
	ch->switch_clock(ch, RW_CLK_BLOCK);
	pthread_mutex_lock(&msense.plock);

	ssize_t nr = read(fd, buf, nb);
	if (-1 == nr)
		nr = 0;

	if (nr != nb)
		memset(buf + nr, '\0', nb - nr);

#ifdef PTRACE_PRCTL
	ptrace(PTRACE_CONT, msense.pid, NULL, NULL);
#endif

	pthread_mutex_unlock(&msense.plock);

	int ign;
	ch->data(ch, buf, nb, &ign);
	return nr;
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

	off64_t cofs = lseek64(pch->fd, 0, SEEK_CUR);
	goto seek0;

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
			ssize_t nc;
			if (ev.tgt.ioevs[0].iv == 0){
seek0:
				nc = synch_copy(ch, pch->fd, buf, buf_sz);
				if (0 == nc)
					fprintf(stderr, "Couldn't read from ofset (%llu)\n",
						(unsigned long long) cofs);

				if (-1 == lseek64(pch->fd, -nc, SEEK_CUR)){
					fprintf(stderr, "Couldn't reset FP after copy, code: %d\n", errno);
					goto error;
				}
				cofs = lseek64(pch->fd, 0, SEEK_CUR);
			}
			else if (ev.tgt.ioevs[0].iv == 1){
				ssize_t left = pch->base + pch->size - cofs;
				if (left == 0)
					goto seek0;

				if (left > buf_sz)
					cofs = lseek64(pch->fd, buf_sz, SEEK_CUR);

				goto seek0;
			}
			else if (ev.tgt.ioevs[0].iv == -1){
				cofs = lseek64(pch->fd, cofs - buf_sz >= pch->base ?
					cofs - buf_sz : pch->base, SEEK_SET);
				goto seek0;
			}
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
	char wbuf[sizeof("/proc//maps") + 20];
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

	int col = 1;
	draw_text(c, "r ", col*(fontw+1), 0, RGBA(0xff, 0x55, 0x55, 0xff)); col += 2;
	draw_text(c, "w ", col*(fontw+1), 0, RGBA(0x55, 0xff, 0x55, 0xff)); col += 2;
	draw_text(c, "x ", col*(fontw+1), 0, RGBA(0x55, 0x55, 0xff, 0xff)); col += 2;
	draw_text(c, "rw ", col*(fontw+1), 0, RGBA(0xff, 0xff, 0x55, 0xff));col += 3;
	draw_text(c, "rx ", col*(fontw+1), 0, RGBA(0xff, 0x55, 0xff, 0xff));col += 3;
  draw_text(c, "wx ", col*(fontw+1), 0, RGBA(0x55, 0xff, 0xff, 0xff));col += 3;
	draw_text(c, "rwx", col*(fontw+1), 0, RGBA(0xff, 0xff, 0xff, 0xff));

	FILE* fpek = get_map_descr(msense.pid);
	if (!fpek){
		fprintf(stderr, "couldn't open proc/pid/maps for reading.\n");
		exit(EXIT_FAILURE);
	}

	struct page {
		long long addr, endaddr, offset, inode;
		char perm[6];
 		char device[16];
	};

/* populate list of entries, first get limit */
	size_t count;
	for (count = 0; !feof(fpek); count++)
		while(fgetc(fpek) != '\n' && !feof(fpek))
			;
	fseek(fpek, 0, SEEK_SET);

/* then fill VLA of page struct with the interesting ones,
 * need to be careful about TOCTU overflow */
	struct page pcache[count];
	memset(pcache, '\0', sizeof(struct page) * count);

	size_t ofs = 0;
	while(!feof(fpek) && ofs < count){
		int ret = fscanf(fpek, "%llx-%llx %5s %llx %5s %llx",
			&pcache[ofs].addr, &pcache[ofs].endaddr, pcache[ofs].perm,
			&pcache[ofs].offset, pcache[ofs].device, &pcache[ofs].inode);

		if (0 == ret){
				while (fgetc(fpek) != '\n' && !feof(fpek))
					;
			continue;
		}

		if (!msense.skip_inode || (msense.skip_inode && pcache[ofs].inode == 0))
			ofs++;
	}
	if (0 == ofs)
		return;

	count = ofs-1;

/* clamp */
	if (msense.sel >= count)
		msense.sel = count - 1;

	msense.sel_lim = count;
	size_t nl = (c->addr->h - fonth - 1) / (fonth + 1);
	msense.sel_page = nl;

	int page = 0;
 	if (msense.sel > 0)
		page = msense.sel / nl;

	ofs = page * nl;

	int y = fonth + 1;
	int cc = msense.sel % nl;

/* each step requires reprocessing the proc entry, expensive
 * but provides a somewhat more accurate view (inotify etc. doesn't
 * do anything on proc, so other option to work with a cache would
 * be to take advantage of ptrace. */

	while (y < c->addr->h && ofs < count){
		uint8_t r = pcache[ofs].perm[0] == 'r' ? 0xff : 0x55;
		uint8_t g = pcache[ofs].perm[1] == 'w' ? 0xff : 0x55;
		uint8_t b = pcache[ofs].perm[2] == 'x' ? 0xff : 0x55;

		if (cc == 0){
			msense.sel_base = pcache[ofs].addr + pcache[ofs].offset;
			msense.sel_size = pcache[ofs].endaddr - pcache[ofs].addr;
			cc--;
		}
		else if (cc > 0)
			cc--;

/* draw addr + text in fitting color */
		char wbuf[256];
		shmif_pixel col = RGBA(r, g, b, 0xff);
		snprintf(wbuf, 256, "%llx(%dk)", pcache[ofs].addr,
			(int)((pcache[ofs].endaddr - pcache[ofs].addr) / 1024));

		draw_text(c, wbuf, fontw + 1, y, col);
		y += fonth + 1;
		ofs++;
	}

	draw_box(c, 0, ((msense.sel % nl)+1) * (fonth+1), fontw, fonth, ccol);
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

#ifdef PTRACE_PRCTL
	if (-1 == ptrace(PTRACE_ATTACH, msense.pid, NULL, NULL)){
		fprintf(stderr, "ptrace(%d) failed, page "
			"inspection disabled\n", (int)msense.pid);
		msense.ptrace = false;
	}
	else{
		msense.ptrace = true;
		waitpid(msense.pid, NULL, 0);
	}
#else
	msense.ptrace = true;
#endif

	msense.cont = &cont;
	pthread_mutex_init(&msense.plock, NULL);
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
