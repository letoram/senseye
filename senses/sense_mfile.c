/*
 * Copyright 2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: Mfile is simplified sensor that implements side-by-side
 * comparison of multiple input sources. As such, it does not make use of the
 * rwstats or senseye_connect support as they focus a lot of mapping and
 * transfer modes that do not make sense here. This means that we don't have to
 * follow other restrictions, e.g. having a base that is a power of two.
 */

#include <stdlib.h>
#include <stdio.h>
#include <inttypes.h>
#include <limits.h>
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

struct ent {
	uint8_t* map;
	size_t map_sz;
	int fd;
	const char* arg;
};

enum pack_mode {
	PACK_INTENS = 0,
	PACK_TIGHT,
	PACK_TNOALPHA
};

static size_t pack_szlut[] = {
	1, 4, 3
};

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
	{"help",   no_argument,       NULL, '?'},
	{NULL, no_argument, NULL, 0}
};

struct ent* load_context(char** files, size_t nfiles, size_t* min, size_t* max)
{
	struct ent* res = malloc(sizeof(struct ent) * nfiles);
	memset(res, '\0', sizeof(struct ent) * nfiles);
	*max = 0;
	*min = INT_MAX;

	for (size_t i=0; i < nfiles; i++){
		struct ent* dent = &res[i];
		dent->fd = open(files[i], O_RDONLY);
		if (-1 == dent->fd){
			fprintf(stderr, "Failed while trying to open %s\n", files[i]);
			return NULL;
		}

		struct stat buf;
		if (1 == fstat(dent->fd, &buf)){
			fprintf(stderr, "Couldn't get stat for %s, reason: %s\n",
				files[i], strerror(errno));
			return NULL;
		}

		if (!S_ISREG(buf.st_mode)){
			fprintf(stderr, "Invalid file mode for %s, expecting a normal file.\n",
				files[i]);
		}

		dent->map_sz = buf.st_size;
		dent->map = mmap(NULL, dent->map_sz, PROT_READ, MAP_PRIVATE, dent->fd, 0);
		if (dent->map == MAP_FAILED){
			fprintf(stderr,
				"Failed to map %s, reason: %s\n", files[i], strerror(errno));
			return NULL;
		}

		if (dent->map_sz > *max)
			*max = dent->map_sz;

		if (dent->map_sz < *min)
			*min = dent->map_sz;
	}

	return res;
}

static inline shmif_pixel pack_pixel(enum pack_mode mode, uint8_t* buf)
{
	switch(mode){
	case PACK_INTENS:
		return RGBA(*buf, *buf, *buf, 0xff);
	case PACK_TIGHT:
		return RGBA(buf[0], buf[1], buf[2], buf[3]);
	case PACK_TNOALPHA:
		return RGBA(buf[0], buf[1], buf[2], 0xff);
	}
}

static void draw_tile(struct arcan_shmif_cont* dst,
	struct ent* ent, size_t pos, size_t x, size_t y,
	enum pack_mode mode, size_t base)
{
	size_t ntw = base*base;
	size_t step = pack_szlut[mode];
	ntw = ent->map_sz < pos + ntw * step ? (ent->map_sz - pos) / step : ntw;

	size_t row = y;
	size_t col = x;
	size_t row_lim = base+y;
	size_t col_lim = base+x;

	uint8_t* buf = ent->map + pos;

	for (; row < row_lim && ntw; row++)
		for (col = x; col < col_lim && ntw; col++, ntw--, buf += step)
			dst->vidp[row*dst->pitch+col] = pack_pixel(mode, buf);

	for (; row < row_lim; row++)
		for (col = x; col < col_lim; col++)
			dst->vidp[row*dst->pitch+col] = RGBA(0x00, 0x00, 0x00, 0xff);
}

static void refresh_data(struct arcan_shmif_cont* dst,
	struct ent* entries, size_t n_entries, size_t base,
	enum pack_mode mode, size_t pos
)
{
	size_t y = 0, x = 0;

/* flood-fill "draw_tile", this could well be thread- split per tile */
	for (size_t i = 0; i < n_entries && y <= dst->h - base; i++){
		draw_tile(dst, &entries[i], pos, x, y, mode, base);
		x = x + base;
		if (x + base > dst->w){
			x = 0;
			y += base;
		}
	}

/* generate diff tile if requested, and draw that one in a "fake" ent */

	arcan_shmif_signal(dst, SHMIF_SIGVID);
}

int main(int argc, char* argv[])
{
	struct arcan_shmif_cont cont;
	struct arg_arr* aarr;

	size_t base = 64;
	off_t ofs = 0;
	enum pack_mode pack_mode = PACK_INTENS;

	bool difftile = false;
	int ch;

	while((ch = getopt_long(argc, argv, "d?", longopts, NULL)) >= 0)
	switch(ch){
	case '?' :
		return usage();
	break;
	case 'd' :
		difftile = true;
	break;
	}

	if (optind >= argc - 1){
		printf("Error: missing filenames (need >= 2)\n");
		return usage();
	}

	size_t min_r, max_r, n_ent = argc - optind;
	struct ent* entries = load_context(argv + optind, n_ent, &min_r, &max_r);
	if (entries == NULL)
		return EXIT_FAILURE;

	if (NULL == getenv("ARCAN_CONNPATH"))
		setenv("ARCAN_CONNPATH", "senseye", 0);
	cont = arcan_shmif_open(SEGID_SENSOR, SHMIF_CONNECT_LOOP, &aarr);
	unsetenv("ARCAN_CONNPATH");

	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_IDENT,
		.ext.message = "mfsense"
	};
	arcan_shmif_enqueue(&cont, &ev);

	int tbase = ceilf(sqrtf(n_ent));

	if (!arcan_shmif_resize(&cont, tbase * base, tbase * base)){
		fprintf(stderr, "Couldn't resize shmif segment, try with a smaller number "
			" of tiles or a smaller base dimension.\n");
		return EXIT_FAILURE;
	}

/* events we need to implement:
 *  PAUSE, DISPLAYHINT, UNPAUSE, STEPFRAME, EXIT
 *   TARGET_COMMAND_GRAPHMODE,
 *    20, 21, 22 => PACK_INTENS, PACK_TIGHT, PACK_TNOALPHA
 *
 */

	refresh_data(&cont, entries, n_ent, base, pack_mode, ofs);

	while (arcan_shmif_wait(&cont, &ev) != 0){
		if (ev.category == EVENT_TARGET)
			switch(ev.tgt.kind){
			case TARGET_COMMAND_PAUSE:
			break;
			case TARGET_COMMAND_DISPLAYHINT:
			break;
			case TARGET_COMMAND_UNPAUSE:
			break;
			case TARGET_COMMAND_STEPFRAME:
				switch (ev.tgt.ioevs[0].iv){
				case -1: ofs = ofs > pack_szlut[pack_mode] * base ?
					ofs - pack_szlut[pack_mode] * base : 0;
				break;
				case 1: ofs += base * pack_szlut[pack_mode]; break;
				case -2: ofs = ofs > pack_szlut[pack_mode] * base * base ?
					ofs - pack_szlut[pack_mode] * base * base : 0;
				break;
				case 2: ofs += base * base * pack_szlut[pack_mode]; break;
				}
				refresh_data(&cont, entries, n_ent, base, pack_mode, ofs);

			/* +- 1 small, 2 large */
			break;
			case TARGET_COMMAND_GRAPHMODE:
/* should we acknowledge the change in pack mode? */
				if (ev.tgt.ioevs[0].iv >= 20 && ev.tgt.ioevs[0].iv <= 22)
					pack_mode = ev.tgt.ioevs[0].iv - 20;
				refresh_data(&cont, entries, n_ent, base, pack_mode, ofs);
			break;
			default:
			break;
		}
	}
/* events:
 *  EXTERNAL_FRAMESTATUS,
 *  framenumber = local cont, pts = total_cont
 */
	arcan_shmif_drop(&cont);

	return EXIT_SUCCESS;
}
