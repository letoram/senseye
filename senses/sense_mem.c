/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This sensor is used for live exploration of process memory.
 * compared to the others (file, mfile, ...) it is rather unsophisticated and
 * crude still, providing only page mapping oriented navigation.
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

#include "sense_supp.h"
#include "font_8x8.h"
#include "rwstat.h"
#include "memif.h"

struct page_ch {
	struct senseye_ch* channel;
	int fd;
	uintptr_t base;
	size_t size;
};

struct {
/* tracing and synchronization */
	pid_t pid;

/* page table scanning / cache */
	struct page* pcache;
	size_t pcache_sz;

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
 * try to acquire a handle into the memory of the process at a specific base
 * and width, if successful, spawn a new data connection to senseye.
 */
static void launch_addr(PROCESS_ID pid, struct map_descr* ent, size_t base)
{
	struct map_ctx* mctx = memif_openmapping(pid, ent);
	if (!mctx)
		return;

	char wbuf[64];
	snprintf(wbuf, sizeof(wbuf), "%d@%" PRIxPTR, (int)msense.pid, base);
	struct senseye_ch* ch = senseye_open(msense.cont, wbuf, base);

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
		if (strcmp(ev->io.label, "UP") == 0){
			msense.sel = (msense.sel - 1 < 0) ? msense.sel_lim - 1 : msense.sel - 1;
			refresh = true;
		}
		else if (strcmp(ev->io.label, "DOWN") == 0){
			msense.sel = (msense.sel + 1) % (msense.sel_lim);
			refresh = true;
		}
		else if (strcmp(ev->io.label, "LEFT") == 0){
			msense.sel -= msense.sel_page;
			if (msense.sel < 0)
				msense.sel = msense.sel_lim - 1;
			if (msense.sel < 0)
				msense.sel = 0;
			refresh = true;
		}
		else if (strcmp(ev->io.label, "RIGHT") == 0){
			msense.sel += msense.sel_page;
			if (msense.sel >= msense.sel_lim)
				msense.sel = 0;
			refresh = true;
		}
		else if (strcmp(ev->io.label, "SELECT") == 0){
			if (!msense.ptrace)
				fprintf(stderr, "cannot inspect segment, ptrace support disabled.\n");
			else
				launch_addr(msense.sel_base, msense.sel_size);
		}
		else if (strcmp(ev->io.label, "r") == 0 || strcmp(ev->io.label, "f") == 0){
			free(msense.pcache);
			msense.pcache = memif_mapdescr(msense.pid,
				strcmp(ev->io.label, "f") == 0, &msense.pcache_sz);
			refresh = true;
		}
	}
	if (ev->category == EVENT_TARGET &&
		ev->tgt.kind == TARGET_COMMAND_DISPLAYHINT){
		size_t width = ev->tgt.ioevs[0].iv;
		size_t height = ev->tgt.ioevs[1].iv;

		arcan_shmif_resize(cont->context(cont), width, height);
		refresh = true;
	}

	if (refresh)
		update_preview(RGBA(0x00, 0xff, 0x00, 0xff));
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

	uint64_t cofs = 0;
	goto seek0;

	while (buf && arcan_shmif_wait(cont, &ev) != 0){
		if (rwstat_consume_event(ch, &ev)){
			continue;
		}

		if (ch->left(ch) > buf_sz){
			free(buf);
			buf_sz = ch->left(ch);
			buf = malloc(buf_sz);
		}

		if (ev.category == EVENT_TARGET)
		switch(ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
			return NULL;
		break;

		case TARGET_COMMAND_DISPLAYHINT:{
			size_t base = ev.tgt.ioevs[0].iv;
			if (base > 0 && (base & (base - 1)) == 0 &&
				arcan_shmif_resize(cont, base, base))
				ch->resize(ch, base);
		}

		case TARGET_COMMAND_STEPFRAME:{
			ssize_t nc;
			if (ev.tgt.ioevs[0].iv == 0){
seek0:
				ch->switch_clock(ch, RW_CLK_BLOCK);
				nc = memif_copy(memmap, buf, buf_sz);
/* there really isn't a "best" pad- value here, statistically speaking,
 * some >7bit value != 255 would probably be a better marker but still
 * not good */
				if (0 == nc)
					fprintf(stderr, "Couldn't read from ofset (%llu: %s)\n",
						(unsigned long long) cofs, strerror(errno));
				else{
					if (nr != buf_sz)
						memset(buf + nr, '\0', buf_sz - nr);

					int ign;
					ch->data(ch, buf, nb, &ign);
				}
				if ((uint64_t)-1 == memif_seek(memmap, -nc, SEEK_CUR)){
					fprintf(stderr, "Couldn't reset FP after copy, code: %d\n", errno);
					goto error;
				}
				cofs = memif_seek(memmap, 0, SEEK_CUR);
			}
			else if (ev.tgt.ioevs[0].iv == 1){
				ssize_t left = pch->base + pch->size - cofs;
				if (left == 0)
					goto seek0;

				if (left > buf_sz)
					cofs = memif_seek(memmap, buf_sz, SEEK_CUR);

				goto seek0;
			}
			else if (ev.tgt.ioevs[0].iv == -1){
				cofs = memif_seek(memmap, cofs - buf_sz >= pch->base ?
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

/*
 * more complex here than in other senses due to the dynamic nature of
 * proc/pid/maps and that the currently selected item won't fit in the
 * allocated output buffer.
 */
static void update_preview(shmif_pixel ccol)
{
	size_t rowsz = fonth+1;
	size_t y = rowsz;
	size_t colw = fontw+1;

	shmif_pixel white = RGBA(0xff, 0xff, 0xff, 0xff);
	struct arcan_shmif_cont* c = msense.cont->context(msense.cont);
	draw_box(c, 0, 0, c->w, y*2, RGBA(0x44, 0x44, 0x44, 0xff));
	draw_box(c, 0, y*2, c->w, c->h, RGBA(0x00,0x00,0x00,0xff));

	int col = 1;
	draw_text(c, "r  ", col*colw, 0, RGBA(0xff, 0x55, 0x55, 0xff)); col += 2;
	draw_text(c, "w  ", col*colw, 0, RGBA(0x55, 0xff, 0x55, 0xff)); col += 2;
	draw_text(c, "x  ", col*colw, 0, RGBA(0x55, 0x55, 0xff, 0xff)); col += 2;
	draw_text(c, "rw ", col*colw, 0, RGBA(0xff, 0xff, 0x55, 0xff)); col += 3;
	draw_text(c, "rx ", col*colw, 0, RGBA(0xff, 0x55, 0xff, 0xff)); col += 3;
	draw_text(c, "wx ", col*colw, 0, RGBA(0x55, 0xff, 0xff, 0xff)); col += 3;
	draw_text(c, "rwx", col*colw, 0, white);
	draw_text(c, "(r)efresh, (f)ilter", 2, y, white);
	y += rowsz;

	size_t count = msense.pcache_sz;
	if (count == 0){
		draw_text(c, "couldn't read mappings", 2, y, white);
		arcan_shmif_signal(c, SHMIF_SIGVID);
		return;
	}

	struct page* pcache = msense.pcache;

/* clamp */
	if (msense.sel >= count)
		msense.sel = count - 1;
	msense.sel_lim = count;
	size_t nl = (c->addr->h - y) / rowsz;
	msense.sel_page = nl;
	int page = 0;
 	if (msense.sel > 0)
		page = msense.sel / nl;
	size_t ofs = page * nl;
	int cc = msense.sel % nl;
	size_t start = y;

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
		y += rowsz;
		ofs++;
	}

/* cursor */
	draw_box(c, 0, start + ((msense.sel % nl)) * rowsz, fontw, fonth, ccol);
	arcan_shmif_signal(c, SHMIF_SIGVID);
}

int main(int argc, char* argv[])
{
	struct senseye_cont cont;
	struct arg_arr* aarr;
	enum SHMIF_FLAGS connectfl = SHMIF_CONNECT_LOOP;

	if (2 != argc){
		printf("usage: psense process_id\n");
		return EXIT_FAILURE;
	}

	msense.pid = strtol(argv[1], NULL, 10);
	msense.pcache = memif_mapdescr(msense.pid, false, &msense.pcache_sz);
	if (!msense.pcache){
		fprintf(stderr, "Couldn't open/parse /proc/%d/maps\n", (int) msense.pid);
		return EXIT_FAILURE;
	}

	if (!senseye_connect(NULL, stderr, &cont, &aarr, connectfl))
		return EXIT_FAILURE;

/* dimension the control window to match the size of
 * the base-address and its width */
	int desw = (fontw + 1) * (sizeof(void*) + 8 + 3);
	if (!arcan_shmif_resize(cont.context(&cont), desw, 512))
		return EXIT_FAILURE;

	msense.cont = &cont;

	msense.pcache = get_map_descr(msense.pid, false, &msense.pcache_sz);
	update_preview(RGBA(0x00, 0xff, 0x00, 0xff));

	cont.dispatch = control_event;

	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_IDENT,
		.ext.message = "msense_main"
	};
	arcan_shmif_enqueue(msense.cont->context(msense.cont), &ev);

	while (senseye_pump(&cont, true)){
	}

	return EXIT_SUCCESS;
}
