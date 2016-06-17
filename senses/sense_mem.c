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

#define RGBA(r, g, b, a) SHMIF_RGBA(r, g, b, a)

struct page_ch {
	struct senseye_ch* channel;
	struct map_ctx* mctx;
	uintptr_t base;
	size_t size;
};

struct {
/* tracing and synchronization */
	pid_t pid;
	size_t mcache_sz;
	struct map_descr* mcache;

/* cursor tracking */
	ssize_t sel;
	size_t sel_lim, sel_page;
	uintptr_t sel_base;
	size_t sel_size;
	bool skip_inode, write_enable;

/* external connections */
	struct senseye_cont* cont;
	size_t last_chbase;
} msense = {
 .skip_inode = true,
 .last_chbase = 256
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

	size_t size = ent->endaddr - ent->addr;
	char wbuf[64];
	snprintf(wbuf, sizeof(wbuf), "%d@%" PRIxPTR, (int)msense.pid, base);
	struct senseye_ch* ch = senseye_open(msense.cont, wbuf, base);

	if (NULL == ch){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx "
			"couldn't open data channel\n", (uintptr_t) ent->addr, size);
		memif_closemapping(mctx);
		return;
	}

	pthread_t pth;
	struct page_ch* pch = malloc(sizeof(struct page_ch));
	if (NULL == pch){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx "
			"couldn't setup processing storage\n", base, size);
		memif_closemapping(mctx);
		return;
	}

	pch->channel = ch;
	pch->mctx = mctx;
	pch->base = base;
	pch->size = size;

	if (-1 == pthread_create(&pth, NULL, data_loop, pch)){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx "
			"couldn't spawn processing thread\n", base, size);
		ch->close(ch);
		free(pch);
		memif_closemapping(mctx);
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
			launch_addr(msense.pid, &msense.mcache[msense.sel], msense.last_chbase);
		}
		else if (strcmp(ev->io.label, "r") == 0 || strcmp(ev->io.label, "f") == 0){
			free(msense.mcache);
			msense.mcache = memif_mapdescr(msense.pid, 0,
				strcmp(ev->io.label, "f") == 0 ?
				FILTER_READ : FILTER_NONE, &msense.mcache_sz
			);
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
		update_preview(SHMIF_RGBA(0x00, 0xff, 0x00, 0xff));
}

static void push_data(struct rwstat_ch* ch,
	struct map_ctx* map, uint8_t* buf, bool repos)
{
	size_t left = ch->left(ch);
	ch->switch_clock(ch, RW_CLK_BLOCK);
	ch->wind_ofs(ch, memif_addr(map));
	uint64_t nc = memif_copy(map, buf, left);
	if (0 == nc){
		memif_reset(map);
		nc = memif_copy(map, buf, left);
		if (0 == nc)
			return;
	}
	else{
		if (repos)
			memif_seek(map, -nc, SEEK_CUR);

		if (nc != left)
			memset(buf + nc, '\0', left - nc);
	}

	int ign;
	ch->data(ch, buf, left, &ign);
}

static void damage_mem(struct rwstat_ch* ch,
	uint64_t ofs, uint8_t* buf, size_t buf_sz, enum damage_flags fl)
{
	struct arcan_shmif_cont* cont = ch->context(ch);
	struct page_ch* pch = ch->damage_tag;
	struct map_ctx* memmap = pch->mctx;

	if (fl & FLAG_RELATIVE){
		fprintf(stderr, "damage_mem - recalc offset\n");
		return;
	}

	if (fl & FLAG_INSERT){
		fprintf(stderr, "damage_mem - inject unsupported\n");
		return;
	}

	memif_write(memmap, ofs, buf, buf_sz);
}

void* data_loop(void* th_data)
{
/* map convenience aliases and work directly with the stats channel
 * rather than going through the sense_ abstraction */
	struct page_ch* pch = (struct page_ch*)th_data;
	struct rwstat_ch* ch = pch->channel->in;
	struct arcan_shmif_cont* cont = ch->context(ch);
	struct map_ctx* memmap = pch->mctx;

	size_t buf_sz = ch->left(ch);
	uint8_t* buf = malloc(buf_sz);

	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(IDENT),
		.ext.message.data = "msense"
	};

	ch->event(ch, &ev);
	push_data(ch, memmap, buf, true);

	uint64_t cofs = 0;

	if (memif_canwrite(memmap) && msense.write_enable){
		ch->damage = damage_mem;
		ch->damage_tag = pch;
	}

	while (buf && arcan_shmif_wait(cont, &ev) != 0){
		if (rwstat_consume_event(ch, &ev)){
			continue;
		}

/* might have been resized during consume */
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
			if (ev.tgt.ioevs[0].iv == -1){
				memif_seek(memmap, -2 * ch->left(ch), SEEK_CUR);
			}
			push_data(ch, memmap, buf, ev.tgt.ioevs[0].iv == 0);
		}
		default:
		break;
		}
	}

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

	size_t count = msense.mcache_sz;
	if (count == 0){
		draw_text(c, "couldn't read mappings", 2, y, white);
		arcan_shmif_signal(c, SHMIF_SIGVID);
		return;
	}

	struct map_descr* mcache = msense.mcache;

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
		uint8_t r = mcache[ofs].perm[0] == 'r' ? 0xff : 0x55;
		uint8_t g = mcache[ofs].perm[1] == 'w' ? 0xff : 0x55;
		uint8_t b = mcache[ofs].perm[2] == 'x' ? 0xff : 0x55;

		if (cc == 0){
			msense.sel_base = mcache[ofs].addr;
			msense.sel_size = mcache[ofs].endaddr - mcache[ofs].addr;
			cc--;
		}
		else if (cc > 0)
			cc--;

/* draw addr + text in fitting color */
		char wbuf[256];
		shmif_pixel col = SHMIF_RGBA(r, g, b, 0xff);
		snprintf(wbuf, 256, "%"PRIx64"(%dk)", mcache[ofs].addr,
			(int)((mcache[ofs].endaddr - mcache[ofs].addr) / 1024));

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
	enum ARCAN_FLAGS connectfl = SHMIF_CONNECT_LOOP;

	if (2 != argc && 3 != argc){
		printf("usage: sense_mem [-w] process_id\n");
		return EXIT_FAILURE;
	}

	if (argc == 3){
		if (strcmp(argv[1], "-w") == 0){
			fprintf(stderr, "Write support enabled\n");
			msense.write_enable = true;
		}
	}

	msense.pid = strtol(argv[argc == 3 ? 2 : 1], NULL, 10);
	msense.mcache = memif_mapdescr(msense.pid, 0, FILTER_NONE, &msense.mcache_sz);
	if (!msense.mcache){
		fprintf(stderr, "Couldn't open/parse process (%d)\n", (int) msense.pid);
		return EXIT_FAILURE;
	}

	if (!senseye_connect(SENSE_MEM, NULL, stderr, &cont, &aarr, connectfl))
		return EXIT_FAILURE;

/* dimension the control window to match the size of
 * the base-address and its width */
	int desw = (fontw + 1) * (sizeof(void*) + 8 + 3);
	if (!arcan_shmif_resize(cont.context(&cont), desw, 512))
		return EXIT_FAILURE;

	msense.cont = &cont;
	update_preview(SHMIF_RGBA(0x00, 0xff, 0x00, 0xff));

	cont.dispatch = control_event;

	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(IDENT),
		.ext.message.data = "msense_main"
	};
	arcan_shmif_enqueue(msense.cont->context(msense.cont), &ev);

	while (senseye_pump(&cont, true)){
	}

	return EXIT_SUCCESS;
}
