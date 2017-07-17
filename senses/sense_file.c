/*
 * Copyright 2014-2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: mmaps a file and implements a preview- window and a main
 * data channel that build on the rwstats statistics code along with the
 * senseye arcan shmif wrapper.
 *
 *  1. update preview with status of the input channel
 *  2. coreopts for statistics / etc.
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
#include <stdatomic.h>

#include <arcan_shmif.h>
#include <poll.h>

#include <sys/types.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/resource.h>

#include "libsenseye.h"
#include "rwstat.h"
#include "sense_file_ch.c"

#define EPSILON 0.0000001f

struct data_window {
	struct senseye_ch* ch;
	pthread_t pth;
	int id;
	int pipe_in;
	int pipe_out;
};

static struct {
	uint8_t* map;
	size_t map_sz;
	struct senseye_cont cont;
	bool wrap;
	uint32_t alloc;
} fsense;

static int usage()
{
	printf("Usage: sense_file [options] filename\n"
		"\t-W,--wrap \tenable wrapping at EOF\n"
		"\t-w x,--width=x \tpreview window width (default: 128)\n"
		"\t-h x,--height=x \tpreview window height (default: 512)\n"
		"\t-p x,--pcomp=x \thistogram row-row comparison in preview\n"
		"\t               \targ. val (0.0 - 1.0) sets cutoff level\n"
		"\t-d,--pdetail \tuse entire data range for pcomparison\n"
		"\t-?,--help \tthis text\n"
	);

	return EXIT_SUCCESS;
}

void control_event(struct senseye_cont* cont, arcan_event* ev)
{
	int nonsense = 0;
	printf("control event\n");
/*
	if (ev->category == EVENT_TARGET){
		switch(ev->tgt.kind){
		case TARGET_COMMAND_SEEKTIME:
			fsense.ofs = fsense.bytes_perline * ev->tgt.ioevs[1].fv;
			write(fsense.pipe_out, &nonsense, sizeof(nonsense));
		break;
		default:
		break;
		}
	}
 */
}

static const struct option longopts[] = {
	{"wrap",   no_argument,       NULL, 'w'},
	{"width",  required_argument, NULL, 'w'},
	{"height", required_argument, NULL, 'h'},
	{"pcomp",  required_argument, NULL, 'p'},
	{"pdetail",no_argument,       NULL, 'd'},
	{"help",   required_argument, NULL, '?'},
	{NULL, no_argument, NULL, 0}
};

float cmp_histo(int32_t* a, int32_t* b, float roww)
{
	float bcf = 0, sum_1 = 0, sum_2 = 0;
	for (size_t i = 0; i < 256; i++){
		float na = ((float)a[i]+EPSILON) / roww;
		float nb = ((float)b[i]+EPSILON) / roww;
		bcf += sqrt(na * nb);
		sum_1 += na;
		sum_2 += nb;
	}
	float rnd = floor(sum_1 + 0.5);
	bcf = bcf > rnd ? rnd : bcf;
	return 1.0 - sqrtf(rnd - bcf);
}

static bool rebuild_preview(struct senseye_cont* cont,
	uint8_t* map, size_t map_sz, float cutoff, bool detailed)
{
/* update preview, try to retain a ~60 fps synch- rate */
	struct arcan_shmif_cont* c = cont->context(cont);
	size_t step_sz = map_sz / (c->w * c->h);
	if (step_sz == 0)
		step_sz = 1;

	size_t bytes_perline = step_sz * c->w;
	size_t pos = 0;
	size_t row = 0;

/* clear before generating preview */
	for (size_t i = 0; i < c->w * c->h; i++)
		c->vidp[i] = SHMIF_RGBA(0x00, 0x00, 0x00, 0xff);

	const int byte_threshold = 10 * 1024 * 1024;

/* using histograms in preview to try and find edges between datatypes */
	int32_t dr[256];
	int32_t cr[256];

	while (pos + step_sz < map_sz && row < c->h){
		size_t cpos = pos;
		for (size_t i = 0; i < c->w && pos < map_sz; i++){
			c->vidp[row * c->w + i] = SHMIF_RGBA(0x00, map[pos], 0x00, 0xff);

			if (!(isnan(cutoff))){
				if (detailed)
					for (size_t j = 0; j < step_sz && pos < map_sz; j++)
						dr[map[pos+j]]++;
				else
					dr[map[pos]]++;
			}

			pos += step_sz;
		}
/* can do this on the preview sample scale or detailed */
		if (!isnan(cutoff)){
			float val = cmp_histo(dr, cr, detailed ? step_sz * c->w : c->w);
			memcpy(cr, dr, sizeof(dr));
			memset(dr, '\0', sizeof(dr));
			if (val < cutoff)
				for(size_t i = 0; i < c->w; i++)
					c->vidp[row * c->w + i] |= SHMIF_RGBA(0xff, 0x00, 0x00, 0x00);
		}

/* update events to maintain interactivity, may exit */
		if (!senseye_pump(cont, false))
			return false;

/* draw preview- processing "edge" */
		if (cpos > byte_threshold){
			for (size_t i = 0; i < c->w && row < c->h; i++)
				c->vidp[(row+1) * c->w + i] = SHMIF_RGBA(0xff, 0x00, 0x00, 0xff);
			arcan_shmif_signal(c, SHMIF_SIGVID);
		}

		row++;
	}
	arcan_shmif_signal(c, SHMIF_SIGVID);
	return true;
}

static bool spawn_ch(
	size_t ofs, const char* name, size_t base, bool wrap, struct data_window* dst)
{
	struct senseye_ch* chan = senseye_open(&fsense.cont, name, base);
	struct fsense_thdata* thd = malloc(sizeof(struct fsense_thdata));
	static int chind = 1;
	if (!chan || !thd){
		fprintf(stderr, "couldn't map data channel, parent rejected.\n");
		return false;
	}
/* use a pipe to signal / wake to split polling events on shared memory
 * interface with communication between main and secondary segments */
	int pipes[4];

	pipe(pipes);
	pipe(&pipes[2]);
	for (size_t i = 0; i < 4; i++)
		fcntl(pipes[i], F_SETFL, O_NONBLOCK);
	*thd = (struct fsense_thdata){
		.ch = chan,
		.fmap = fsense.map,
		.sz = fsense.map_sz,
		.wrap = wrap,
		.ind = chind,
		.pipe_in = pipes[0],
		.pipe_out = pipes[3]
	};
	pthread_t pth;
	pthread_create(&pth, NULL, data_window_loop, thd);
	*dst = (struct data_window){
		.ch = chan,
		.pth = pth,
		.id = chind++,
		.pipe_out = pipes[1],
		.pipe_in = pipes[2]
	};
	return true;
}

int main(int argc, char* argv[])
{
	enum ARCAN_FLAGS connectfl = SHMIF_CONNECT_LOOP;
	struct arg_arr* aarr;
	size_t base = 256;
	size_t p_w = 128;
	size_t p_h = 512;
	bool detailed = false, wrap = false;
	float cutoff = NAN;
	int ch;

	while((ch = getopt_long(argc, argv, "Ww:h:p:d?", longopts, NULL)) >= 0)
	switch(ch){
	case '?' :
		return usage();
	break;
	case 'p' :
		cutoff = strtof(optarg, NULL);
		cutoff = (isinf(cutoff)||isnan(cutoff)||cutoff<=0.0||cutoff>1.0) ?
			0.9 : cutoff;
	break;
	case 'd' : detailed = true;
	break;
	case 'W' :
		wrap = true;
	break;
	case 'w' :
		p_w = strtol(optarg, NULL, 10);
		if (p_w == 0 || p_w > PP_SHMPAGE_MAXW){
			printf("invalid -w,--width arguments, %zu "
				"larger than permitted: %zu\n", p_w, (size_t) PP_SHMPAGE_MAXW);
			return EXIT_FAILURE;
		}
	break;
	case 'h' :
		p_h = strtol(optarg, NULL, 10);
		if (p_h == 0 || p_h > PP_SHMPAGE_MAXH){
			printf("invalid -h,--height arguments, %zu "
				"larger than permitted: %zu\n", p_h, (size_t ) PP_SHMPAGE_MAXH);
			return EXIT_FAILURE;
		}
	break;
	}

	if (optind >= argc){
		printf("Error: missing filename\n");
		return usage();
	}

	int fd = open(argv[optind], O_RDONLY);
	struct stat buf;
	if (-1 == fstat(fd, &buf)){
		fprintf(stderr, "couldn't stat file, check permissions and file state.\n");
		return EXIT_FAILURE;
	}

	if (buf.st_size == 0){
		fprintf(stderr, "empty file encountered\n");
		return EXIT_FAILURE;
	}

	if (!S_ISREG(buf.st_mode)){
		fprintf(stderr, "invalid file mode, expecting a regular file.\n");
		return EXIT_FAILURE;
	}

	fsense.map_sz = buf.st_size;
	fsense.map = mmap(NULL, fsense.map_sz, PROT_READ, MAP_PRIVATE, fd, 0);
	if (MAP_FAILED == fsense.map){
		fprintf(stderr, "couldn't mmap file.\n");
		return EXIT_FAILURE;
	}

	if (!senseye_connect(NULL, stderr, &fsense.cont, &aarr, connectfl))
		return EXIT_FAILURE;

	if (!arcan_shmif_resize(fsense.cont.context(&fsense.cont), p_w, p_h))
		return EXIT_FAILURE;

	struct data_window dwnd;

	fsense.cont.dispatch = control_event;

	if (spawn_ch(0, argv[1], base, wrap, &dwnd) &&
		rebuild_preview(&fsense.cont, fsense.map, fsense.map_sz, cutoff, detailed)){
		while (senseye_pump(&fsense.cont, true))
			;
	}

/*
 * ENUMERATE ALL CHANNELS, DROP, DELETE DESCRIPTORS
 */
	arcan_shmif_drop(fsense.cont.context(&fsense.cont));
	return EXIT_SUCCESS;
}
