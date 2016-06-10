/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: A simple sensor that wraps a single binary status window
 * signal around a transfer channel connected to STDIN, sampling and
 * forwarding on STDOUT.
 */
#include <stdlib.h>
#include <stdio.h>
#include <inttypes.h>
#include <stdint.h>
#include <unistd.h>
#include <poll.h>
#include <stdbool.h>
#include <errno.h>
#include <sys/types.h>
#include <fcntl.h>
#include <pthread.h>

#include <arcan_shmif.h>
#include "sense_supp.h"

static size_t inp_buf_sz = 1024 * 1;
static struct arcan_shmif_cont* shm;

bool control_refresh(shmif_pixel* vidp, size_t w, size_t h)
{
	return false;
}

void control_event(arcan_event* ev)
{

}

void* data_loop(void* ptr)
{
	struct senseye_ch* ch = ptr;

/* register type so UI gets mapped correctly */
	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(IDENT),
		.ext.message.data = "psense"
	};

	ch->queue(ch, &ev);

/* polling will happen in two layers, here and during pump/read */
	short pollev = POLLIN | POLLERR | POLLHUP | POLLNVAL;
	struct pollfd fds[2] = {
		{	.fd = STDIN_FILENO, .events = pollev },
		{ .fd = ch->in_handle, .events = pollev }
	};

	while (1){
		int sv = poll(fds, 2, -1);

		if (-1 == sv){
			if (errno == EAGAIN || errno == EINTR)
				continue;
		}

/* flush event queues first as they may change state / processing */
		if ( (fds[1].revents & POLLIN) > 0)
			ch->pump(ch);

		if ( (fds[0].revents | POLLIN) ){
			size_t buffer[inp_buf_sz];
			ssize_t nr = read(STDIN_FILENO, buffer, inp_buf_sz);

/* will block / wait until the user has stepped through and processed */
			if (nr > 0){
				ch->data(ch, buffer, nr);

/* flush to output */
				off_t ofs = 0;
				while (nr - ofs > 0){
					ssize_t nw = write(STDOUT_FILENO, buffer + ofs, nr - ofs);
					if (-1 == nw && errno != EAGAIN && errno != EINTR)
						goto error;
					ofs += nw;
				}
			}
		}

/* any errors or dead? */
		if ( ((fds[0].revents | fds[1].revents )
			& ( POLLERR | POLLHUP | POLLNVAL ) ) > 0){
error:
		for (size_t i = 0; i < shm->addr->w * shm->addr->h; i++)
			shm->vidp[i] = SHMIF_RGBA(0xff, 0x00, 0x00, 0xff);
				arcan_shmif_signal(shm, SHMIF_SIGVID);

			ch->close(ch);
			return NULL;
		}
	}

	return NULL;
}

int main(int argc, char* argv[])
{
	struct senseye_cont cont;
	struct arg_arr* aarr;
	enum ARCAN_FLAGS connectfl = SHMIF_CONNECT_LOOP;

	if (!senseye_connect(SENSE_PIPE, NULL, stderr, &cont, &aarr, connectfl))
		return EXIT_FAILURE;

	shm = cont.context(&cont);
	if (!arcan_shmif_resize(shm, 32, 32))
		return EXIT_FAILURE;

	for (size_t i = 0; i < shm->addr->w * shm->addr->h; i++)
		shm->vidp[i] = SHMIF_RGBA(0x00, 0xff, 0x00, 0xff);
	arcan_shmif_signal(shm, SHMIF_SIGVID);

	size_t base = 256;

/*
 * just use aarr to override possible defaults to permit
 * different sampling bases / running behavior from the start
 */
	if (aarr){
		const char* val;
		if (arg_lookup(aarr, "base", 0, &val)){
			size_t bv = strtoul(val, NULL, 10);

			if (bv > 0 && (bv & (bv - 1)) == 0 &&
				bv <= PP_SHMPAGE_MAXW && bv <= PP_SHMPAGE_MAXH)
				base = bv;
			else
				fprintf(stderr, "base=%zu argument ignored, must be power of two\n",bv);
		}

		if (arg_lookup(aarr, "buffer_size", 0, &val)){
			size_t bv = strtoul(val, NULL, 10);
			inp_buf_sz = bv > 65536 || bv == 0 ? 64 * 1024 : bv;
		}
	}

	struct senseye_ch* ch = senseye_open(&cont, "STDIN", base);
	if (!ch){
		fprintf(stderr, "couldn't map data channel, parent rejected.\n");
		return EXIT_FAILURE;
	}
	else {
		pthread_t pth;
		pthread_create(&pth, NULL, data_loop, ch);
	}

	while (senseye_pump(&cont, true)){
	}

	return EXIT_SUCCESS;
}
