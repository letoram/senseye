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

#include <arcan_shmif.h>
#include <poll.h>

#include <sys/types.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/resource.h>

#include "senseye.h"
#include "rwstat.h"

struct {
	uint8_t* fmap;
	pthread_mutex_t flock;
	struct senseye_cont* cont;
	size_t fmap_sz;
	size_t ofs;
	size_t bytes_perline;

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

/*
 * invoked whenever the ofset has been changed from the primary segment
 */
static uint8_t bss_block[1024];
static void force_refresh(struct rwstat_ch* ch)
{
	int ign;
	size_t lofs;

	size_t nb = ch->row_size(ch);
	size_t bsz = nb * ch->context(ch)->addr->h;

	pthread_mutex_lock(&fsense.flock);
	if (fsense.ofs > fsense.fmap_sz - bsz)
		fsense.ofs = fsense.fmap_sz - bsz;
	lofs = fsense.ofs;
	pthread_mutex_unlock(&fsense.flock);

	size_t left = ch->left(ch);
	if (left > fsense.fmap_sz - lofs){
		ch->data(ch, fsense.fmap, fsense.fmap_sz - lofs, &ign);
		while (ign != 1)
			ch->data(ch, bss_block, 1024, &ign);
	}
	else
		ch->data(ch, fsense.fmap + fsense.ofs, left, &ign);

	struct arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_FRAMESTATUS,
		.ext.framestatus.framenumber = (lofs+1) / fsense.bytes_perline,
		.ext.framestatus.pts = bsz / fsense.bytes_perline
	};
	arcan_shmif_enqueue(fsense.cont->context(fsense.cont), &outev);

	ch->wind_ofs(ch, fsense.ofs);
}

static void refresh_data(struct rwstat_ch* ch, size_t pos, size_t ntw)
{
	struct arcan_event outev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_FRAMESTATUS,
		.ext.framestatus.framenumber = (pos + 1) / fsense.bytes_perline,
		.ext.framestatus.pts = ntw / fsense.bytes_perline
	};

	arcan_shmif_enqueue(fsense.cont->context(fsense.cont), &outev);
	int ign;
	ch->wind_ofs(ch, pos);
	ch->data(ch, fsense.fmap + pos, ntw, &ign);
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
	while (1){
		struct pollfd fds[2] = {
			{	.fd = fsense.pipe_in, .events = pollev },
			{ .fd = cont->epipe, .events = pollev }
		};

		int sv = poll(fds, 2, -1);

/* non-blocking, just flush */
		read(fsense.pipe_in, &sv, 4);

/* parent marked seek, force step, switch to block mode */
		if ( (fds[0].revents & POLLIN) )
			force_refresh(ch);

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

			case TARGET_COMMAND_STEPFRAME:{
				size_t nb = ch->row_size(ch);
				size_t bsz = nb * cont->addr->h;

				if (ev.tgt.ioevs[0].iv == -1){
					ch->switch_clock(ch, RW_CLK_BLOCK);
					pthread_mutex_lock(&fsense.flock);

					if (fsense.ofs < nb)
						fsense.ofs = 0;
					else
						fsense.ofs -= nb;
					size_t lofs = fsense.ofs;
					pthread_mutex_unlock(&fsense.flock);

					refresh_data(ch, lofs, bsz);
				}
				else if (ev.tgt.ioevs[0].iv == 1){
					ch->switch_clock(ch, RW_CLK_BLOCK);
					pthread_mutex_lock(&fsense.flock);
					fsense.ofs += nb;
					if (fsense.ofs + bsz > fsense.fmap_sz)
						fsense.ofs = fsense.fmap_sz - bsz;
					size_t lofs = fsense.ofs;
					pthread_mutex_unlock(&fsense.flock);

					refresh_data(ch, lofs, bsz);
				}
				else if (ev.tgt.ioevs[0].iv == -2){
					ch->switch_clock(ch, RW_CLK_BLOCK);
					pthread_mutex_lock(&fsense.flock);
					if (fsense.ofs < bsz)
						fsense.ofs = 0;
					else
						fsense.ofs -= bsz;
					size_t lofs = fsense.ofs;

					if (lofs + bsz > fsense.fmap_sz)
						lofs = fsense.fmap_sz - bsz;

					pthread_mutex_unlock(&fsense.flock);
					refresh_data(ch, lofs, bsz);
				}
				else if (ev.tgt.ioevs[0].iv == 2){
					size_t bsz = nb * cont->addr->h;
					ch->switch_clock(ch, RW_CLK_BLOCK);
					pthread_mutex_lock(&fsense.flock);
					fsense.ofs += bsz;
					if (fsense.ofs > fsense.fmap_sz - bsz)
						fsense.ofs = fsense.fmap_sz - bsz;
					size_t lofs = fsense.ofs;
					pthread_mutex_unlock(&fsense.flock);
					refresh_data(ch, lofs, bsz);
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

int main(int argc, char* argv[])
{
	struct senseye_cont cont;
	struct arg_arr* aarr;
	size_t base = 256;

	if (2 != argc){
		printf("usage: fsense filename\n");
		return EXIT_FAILURE;
	}

	int fd = open(argv[1], O_RDONLY);
	struct stat buf;
	if (-1 == fstat(fd, &buf)){
		fprintf(stderr, "couldn't stat file, check permissions and file state.\n");
		return EXIT_FAILURE;
	}

	if (!S_ISREG(buf.st_mode)){
		fprintf(stderr, "invalid file mode, expecting a regular file.\n");
		return EXIT_FAILURE;
	}

	if (buf.st_size < base * base && buf.st_size < 128 * 512){
		fprintf(stderr, "file too small, expecting "
			"*at least* %zu and %zu bytes.\n", base*base, (size_t) (128 * 512));
		return EXIT_FAILURE;
	}

	fsense.fmap = mmap(NULL, buf.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (MAP_FAILED == fsense.fmap){
		fprintf(stderr, "couldn't mmap file.\n");
		return EXIT_FAILURE;
	}

	if (!senseye_connect(NULL, stderr, &cont, &aarr))
		return EXIT_FAILURE;

	if (!arcan_shmif_resize(cont.context(&cont), 128, 512))
		return EXIT_FAILURE;

	struct senseye_ch* ch = senseye_open(&cont, argv[1], base);
	if (!ch){
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
	fsense.fmap_sz = buf.st_size;
	pthread_t pth;
	pthread_create(&pth, NULL, data_loop, ch);

	update_preview(cont.context(&cont), fsense.fmap, buf.st_size);
	fsense.cont = &cont;
	cont.dispatch = control_event;

	while (senseye_pump(&cont)){
	}

	return EXIT_SUCCESS;
}
