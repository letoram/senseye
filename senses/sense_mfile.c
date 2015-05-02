/*
 * Copyright 2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: Mfile is a specialized version of the file sensor that handle
 * multiple file inputs. The data-window is replaced with information about
 * current offsets etc.
 */

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
#include <getopt.h>

#include <arcan_shmif.h>
#include <poll.h>

#include <sys/types.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/resource.h>

#include "font_8x8.h"
#include "sense_supp.h"
#include "rwstat.h"

struct ent {
	uint8_t* map;
	size_t map_sz;
	int fd;
	const char* arg;
};

struct {
	struct senseye_cont* cont;
	struct ent* entries;
	size_t ent_max_sz, ent_min_sz;
	size_t ofs;
	size_t ent_cnt;

	bool diff;

	size_t bytes_perline;
	size_t small_step;
	size_t large_step;
} mfsense = {
	.bytes_perline = 1,
	.ent_min_sz = INT_MAX
};

void control_event(struct senseye_cont* cont, arcan_event* ev)
{
	if (ev->category == EVENT_TARGET){
		switch(ev->tgt.kind){
		case TARGET_COMMAND_SEEKTIME:
		break;
		default:
		break;
		}
	}
}

static void refresh_data(struct rwstat_ch* ch, size_t pos)
{
/*
	size_t nb = ch->row_size(ch);
	struct arcan_shmif_cont* cont = ch->context(ch);
	size_t ntw = nb * cont->addr->h;

	struct arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_FRAMESTATUS,
		.ext.framestatus.framenumber = (pos + 1) / mfsense.bytes_perline,
		.ext.framestatus.pts = ntw / mfsense.bytes_perline
	};
	arcan_shmif_enqueue(mfsense.cont->context(mfsense.cont), &outev);

	ch->wind_ofs(ch, pos);
*/
}

static size_t fix_ofset(struct rwstat_ch* ch, ssize_t ofs)
{
	if (ofs > (ssize_t) mfsense.ent_max_sz)
		ofs = mfsense.ent_max_sz;

	if (ofs < 0)
		ofs = 0;

	return ofs;
}

void* data_loop(void* th_data)
{
/* we ignore the senseye- abstraction here and works
 * directly with the rwstat and shmif context */
	struct rwstat_ch* ch = ((struct senseye_ch*)th_data)->in;
	struct arcan_shmif_cont* cont = ch->context(ch);

	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_IDENT,
		.ext.message = "mfsense"
	};

/*
 * block clock is necessary here
 */
	ch->event(ch, &ev);
	ch->switch_clock(ch, RW_CLK_BLOCK);

	while (arcan_shmif_wait(cont, &ev)){
		if (rwstat_consume_event(ch, &ev))
			continue;

		if (ev.category == EVENT_IO){
			if (strcmp(ev.io.label, "STEP_BYTE") == 0){
				mfsense.small_step = 1;
			}
			else if (strcmp(ev.io.label, "STEP_ROW") == 0){
				mfsense.small_step = 0;
			}
			else if (strcmp(ev.io.label, "STEP_HALFPAGE") == 0){
				mfsense.large_step = 1;
			}
			else if (strcmp(ev.io.label, "STEP_PAGE") == 0){
				mfsense.large_step = 0;
			}
			else if (strcmp(ev.io.label, "STEP_ALIGN_512") == 0){
				if (mfsense.ofs % 512 != 0){
					mfsense.ofs = fix_ofset(ch, mfsense.ofs - (mfsense.ofs % 512));
					refresh_data(ch, mfsense.ofs);
				}
			}
		}

		if (ev.category == EVENT_TARGET)
		switch(ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
			return NULL;
		break;

		case TARGET_COMMAND_DISPLAYHINT:{
			size_t base = ev.tgt.ioevs[0].iv;
			if (base > 0 && (base & (base - 1)) == 0 &&
				arcan_shmif_resize(cont, base, base)){
				ch->resize(ch, base);
/* we also need to check ofs against this new block-size,
 * and possible update the hinted number of lines covered
 * by the buffer */
			}
		}
		break;

		case TARGET_COMMAND_SEEKTIME:{
				mfsense.ofs = fix_ofset(ch, ev.tgt.ioevs[1].iv);
				size_t lofs = mfsense.ofs;
			refresh_data(ch, lofs);
		}

		case TARGET_COMMAND_STEPFRAME:{
			if (ev.tgt.ioevs[0].iv == -1 || ev.tgt.ioevs[0].iv == 1){
				mfsense.ofs = fix_ofset(ch, mfsense.ofs +
					(mfsense.small_step ? 1 : ch->row_size(ch)) * ev.tgt.ioevs[0].iv);
				size_t lofs = mfsense.ofs;

				refresh_data(ch, lofs);
			}
			else if (ev.tgt.ioevs[0].iv == 0){
				size_t lofs = mfsense.ofs;
				refresh_data(ch, lofs);
			}
			else if (ev.tgt.ioevs[0].iv == -2 || ev.tgt.ioevs[0].iv == 2){
				mfsense.ofs = fix_ofset(ch, mfsense.ofs +
					(ch->row_size(ch) * (ch->context(ch)->addr->h) >> mfsense.large_step)
					* (ev.tgt.ioevs[0].iv == -2 ? -1 : 1));
				size_t lofs = mfsense.ofs;
				refresh_data(ch, lofs);
			}
		}
		default:
		break;
		}
	}

	return NULL;
}

static void update_preview(struct arcan_shmif_cont* c)
{
	draw_box(c, 0, 0, c->w, c->h, RGBA(0x00, 0x00, 0x00, 0xff));
	arcan_shmif_signal(c, SHMIF_SIGVID);
}

static int usage()
{
	printf("Usage: sense_mfile [options] file1 file2 ...\n"
		"\t-d,--diff   \tlast tile is a binary difference indicator\n"
		"\t-?=,--help= \tthis text\n"
	);

	return EXIT_SUCCESS;
}

static const struct option longopts[] = {
	{"diff",   no_argument,       NULL, 'd'},
	{"help",   required_argument, NULL, '?'},
	{NULL, no_argument, NULL, 0}
};

int main(int argc, char* argv[])
{
	struct senseye_cont cont;
	struct arg_arr* aarr;
	size_t base = 256;
	int ch;

	while((ch = getopt_long(argc, argv, "Ww:h:?", longopts, NULL)) >= 0)
	switch(ch){
	case '?' :
		return usage();
	break;
	case 'd' :
		mfsense.diff = true;
	break;
	}

	if (optind >= argc - 1){
		printf("Error: missing filenames (need >= 2)\n");
		return usage();
	}

	mfsense.ent_cnt = argc - optind;
	mfsense.entries = malloc(sizeof(struct ent) * mfsense.ent_cnt);
	memset(mfsense.entries, '\0', sizeof(struct ent));

	for (size_t i=0; i < mfsense.ent_cnt; i++){
		struct ent* dent = &mfsense.entries[i];
		dent->fd = open(argv[i+optind], O_RDONLY);
		if (-1 == dent->fd){
			fprintf(stderr, "Failed while trying to open %s\n", argv[i+optind]);
			return EXIT_FAILURE;
		}

		struct stat buf;
		if (1 == fstat(dent->fd, &buf)){
			fprintf(stderr, "Couldn't get stat for %s, reason: %s\n",
				argv[i+optind], strerror(errno));
			return EXIT_FAILURE;
		}

		if (!S_ISREG(buf.st_mode)){
			fprintf(stderr, "Invalid file mode for %s, expecting a normal file.\n",
				argv[i+optind]);
		}

		dent->map_sz = buf.st_size;
		dent->map = mmap(NULL, dent->map_sz, PROT_READ, MAP_PRIVATE, dent->fd, 0);
		if (dent->map == MAP_FAILED){
			fprintf(stderr, "Failed to map %s, reason: %s\n",
				argv[i+optind], strerror(errno));
			return EXIT_FAILURE;
		}

		if (dent->map_sz > mfsense.ent_max_sz)
			mfsense.ent_max_sz = dent->map_sz;

		if (dent->map_sz < mfsense.ent_min_sz)
			mfsense.ent_min_sz = dent->map_sz;
	}

	if (!senseye_connect(NULL, stderr, &cont, &aarr)){
		fprintf(stderr, "couldn't connect to senseye server\n");
		return EXIT_FAILURE;
	}

	if (!arcan_shmif_resize(cont.context(&cont), fontw * 32, fonth * 4)){
		fprintf(stderr, "couldn't set base dimensions.\n");
		return EXIT_FAILURE;
	}

	struct senseye_ch* chan = senseye_open(&cont, argv[1], base);
	if (!chan){
		fprintf(stderr, "couldn't map data channel, parent rejected.\n");
		return EXIT_FAILURE;
	}

	update_preview(cont.context(&cont));

	pthread_t pth;
	pthread_create(&pth, NULL, data_loop, chan);

	while (senseye_pump(&cont, true)){
	}

	return EXIT_SUCCESS;
}
