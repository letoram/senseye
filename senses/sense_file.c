/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: mmaps a file and implements a preview- window and a main
 * data channel that build on the rwstats statistics code along with the
 * senseye arcan shmif wrapper.
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

#include "sense_supp.h"
#include "rwstat.h"

struct {
	uint8_t* fmap;
	pthread_mutex_t flock;
	bool wrap;

	struct senseye_cont* cont;
	size_t fmap_sz;
	size_t ofs;
	size_t bytes_perline;
	size_t ent_size;

	int pipe_in;
	int pipe_out;
} fsense = {0};

/*
 * input mapping :
 *  LCLICK (move position)
 */
void control_event(struct senseye_cont* cont, arcan_event* ev)
{
	int nonsense = 0;

	if (ev->category == EVENT_TARGET){
		switch(ev->tgt.kind){
		case TARGET_COMMAND_SEEKTIME:
			pthread_mutex_lock(&fsense.flock);
			fsense.ofs = fsense.bytes_perline * ev->tgt.ioevs[1].iv;
			pthread_mutex_unlock(&fsense.flock);
			write(fsense.pipe_out, &nonsense, sizeof(nonsense));
		break;
		default:
		break;
		}
	}
}

static void refresh_data(struct rwstat_ch* ch, size_t pos)
{
	size_t nb = ch->row_size(ch);
	struct arcan_shmif_cont* cont = ch->context(ch);
	size_t ntw = nb * cont->addr->h;

	struct arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_FRAMESTATUS,
		.ext.framestatus.framenumber = (pos + 1) / fsense.bytes_perline,
		.ext.framestatus.pts = ntw / fsense.bytes_perline
	};
	arcan_shmif_enqueue(fsense.cont->context(fsense.cont), &outev);

	ch->wind_ofs(ch, pos);

	int ign;
	size_t left = fsense.fmap_sz - pos;
	if (ntw > left){
		ch->data(ch, fsense.fmap + pos, left, &ign);
		if (fsense.wrap)
			ch->data(ch, fsense.fmap, ntw - left, &ign);
		else
			ch->data(ch, NULL, ntw - left, &ign);
	}
	else
		ch->data(ch, fsense.fmap + pos, ntw, &ign);
}

static size_t fix_ofset(struct rwstat_ch* ch, ssize_t ofs)
{
	if (ofs > (ssize_t) fsense.fmap_sz){
		if (fsense.wrap)
			ofs = 0;
		else
			ofs = fsense.fmap_sz;
	}

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
		.ext.message = "fsense"
	};

	short pollev = POLLIN | POLLERR | POLLHUP | POLLNVAL;
	ch->event(ch, &ev);
	ch->switch_clock(ch, RW_CLK_BLOCK);

	while (1){
		struct pollfd fds[2] = {
			{	.fd = fsense.pipe_in, .events = pollev },
			{ .fd = cont->epipe, .events = pollev }
		};

		int sv = poll(fds, 2, -1);

/* non-blocking, just flush */
		read(fsense.pipe_in, &sv, 4);

		if ( (fds[0].revents & POLLIN) ){
			pthread_mutex_lock(&fsense.flock);
			size_t lofs = fsense.ofs;
			pthread_mutex_unlock(&fsense.flock);
			refresh_data(ch, lofs);
		}

		arcan_event ev;
		while (arcan_shmif_poll(cont, &ev) != 0){

			if (rwstat_consume_event(ch, &ev))
				continue;

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
				pthread_mutex_lock(&fsense.flock);
					fsense.ofs = fix_ofset(ch, ev.tgt.ioevs[1].iv);
					size_t lofs = fsense.ofs;
				pthread_mutex_unlock(&fsense.flock);
				refresh_data(ch, lofs);
			}

			case TARGET_COMMAND_STEPFRAME:{
				size_t nb = ch->row_size(ch);

				if (ev.tgt.ioevs[0].iv == -1 || ev.tgt.ioevs[0].iv == 1){
					pthread_mutex_lock(&fsense.flock);
					fsense.ofs = fix_ofset(ch, fsense.ofs +
						ch->row_size(ch) * ev.tgt.ioevs[0].iv);
					size_t lofs = fsense.ofs;
					pthread_mutex_unlock(&fsense.flock);

					refresh_data(ch, lofs);
				}
				else if (ev.tgt.ioevs[0].iv == 0){
					pthread_mutex_lock(&fsense.flock);
					size_t lofs = fsense.ofs;
					pthread_mutex_unlock(&fsense.flock);
					refresh_data(ch, lofs);
				}
				else if (ev.tgt.ioevs[0].iv == -2 || ev.tgt.ioevs[0].iv == 2){
					size_t bsz = nb * ch->context(ch)->addr->h;
					pthread_mutex_lock(&fsense.flock);
					fsense.ofs = fix_ofset(ch, fsense.ofs +
						bsz * (ev.tgt.ioevs[0].iv == -2 ? -1 : 1));
					size_t lofs = fsense.ofs;
					pthread_mutex_unlock(&fsense.flock);
					refresh_data(ch, lofs);
				}
			}
			default:
			break;
			}
		}

	}
}

static void update_preview(struct arcan_shmif_cont* c, uint8_t* buf, size_t s)
{
	size_t np = c->addr->w * c->addr->h;
	size_t step_sz = s / np;

	shmif_pixel* px = c->vidp;
	uint8_t* wb = buf;
	while (wb - buf < s){
		uint8_t val = *wb;
		*px++ = RGBA(0, val, 0, 0xff);
		wb += step_sz;
	}

	fsense.bytes_perline = step_sz * c->addr->w;
	arcan_shmif_signal(c, SHMIF_SIGVID);
}

static int usage()
{
	printf("Usage: sense_file [options] filename\n"
		"\t-W,--wrap \tenable wrapping at EOF\n"
		"\t-w=,--width= \tpreview window width (default: 128)\n"
		"\t-h=,--heigth= \tpreview window height (default: 512)\n"
		"\t-?=,--help= \tthis text\n"
	);

	return EXIT_SUCCESS;
}

static const struct option longopts[] = {
	{"wrap",   no_argument,       NULL, 'w'},
	{"width",  required_argument, NULL, 'w'},
	{"height", required_argument, NULL, 'h'},
	{"help",   required_argument, NULL, '?'},
	{NULL, no_argument, NULL, 0}
};

int main(int argc, char* argv[])
{
	struct senseye_cont cont;
	struct arg_arr* aarr;
	size_t base = 256;
	size_t p_w = 128;
	size_t p_h = 512;
	int ch;

	while((ch = getopt_long(argc, argv, "Ww:h:?", longopts, NULL)) >= 0)
	switch(ch){
	case '?' :
		return usage();
	break;
	case 'W' :
		fsense.wrap = true;
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

	if (!S_ISREG(buf.st_mode)){
		fprintf(stderr, "invalid file mode, expecting a regular file.\n");
		return EXIT_FAILURE;
	}

	if (buf.st_size < base * base && buf.st_size < p_w * p_h){
		fprintf(stderr, "file too small, expecting "
			"*at least* %zu and %zu bytes.\n", base*base, (size_t) (p_w * p_h));
		return EXIT_FAILURE;
	}

	fsense.fmap = mmap(NULL, buf.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (MAP_FAILED == fsense.fmap){
		fprintf(stderr, "couldn't mmap file.\n");
		return EXIT_FAILURE;
	}

	if (!senseye_connect(NULL, stderr, &cont, &aarr))
		return EXIT_FAILURE;

	if (!arcan_shmif_resize(cont.context(&cont), p_w, p_h))
		return EXIT_FAILURE;

	struct senseye_ch* chan = senseye_open(&cont, argv[1], base);
	if (!chan){
		fprintf(stderr, "couldn't map data channel, parent rejected.\n");
		return EXIT_FAILURE;
	}

/* use a pipe to signal / wake to split polling events on
 * shared memory interface with communication between main and secondary
 * segments */
	int sigpipe[2];
	pipe(sigpipe);
	fsense.pipe_in = sigpipe[0];
	fsense.pipe_out = sigpipe[1];
	fcntl(sigpipe[0], F_SETFL, O_NONBLOCK);
	fcntl(sigpipe[1], F_SETFL, O_NONBLOCK);

	pthread_mutex_init(&fsense.flock, NULL);
	fsense.fmap_sz = buf.st_size - 1;
	pthread_t pth;
	pthread_create(&pth, NULL, data_loop, chan);

	update_preview(cont.context(&cont), fsense.fmap, buf.st_size);
	fsense.cont = &cont;
	cont.dispatch = control_event;

	while (senseye_pump(&cont)){
	}

	return EXIT_SUCCESS;
}
