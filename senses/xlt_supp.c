#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <pthread.h>
#include <string.h>
#include <assert.h>
#include <sys/types.h>
#include <unistd.h>
#include <inttypes.h>

#include "xlt_supp.h"

struct xlt_session {
	uint8_t* buf;

	uint64_t vpts;
	size_t buf_sz;
	size_t unpack_sz;
	size_t pack_sz;
	size_t base_ofs;

	xlt_populate populate;
	xlt_input input;
	enum xlt_flags flags;

	struct arcan_shmif_cont in;
	struct arcan_shmif_cont out;
};

/*
 * just ignore for now
 */
static bool flush_output_events(struct xlt_session* sess)
{
	arcan_event ev;

	while (arcan_shmif_poll(&sess->out, &ev) != 0);
	return false;
}

/*
 * most likely something wrong / broken with this function
 */
static void populate(struct xlt_session* s)
{
	if (s->buf_sz < s->unpack_sz){
		free(s->buf);
		s->buf = malloc(s->unpack_sz);
		s->buf_sz = s->unpack_sz;
	}

/* we reset this as the likely interested
 * offset must have changed */
	s->base_ofs = 0;

	if (s->pack_sz == 4)
		memcpy(s->buf, s->in.vidp, s->unpack_sz);
	else{
		uint8_t* outb = s->buf;

		for (size_t i = 0; i < s->in.addr->w * s->in.addr->h; i++){
			av_pixel cp = s->in.vidp[i];
			*outb++ = (cp & 0x000000ff);
			if (s->pack_sz == 1)
				continue;

			*outb++ = (cp & 0x0000ff00) >>  8;
			*outb++ = (cp & 0x00ff0000) >> 16;
		}
	}
}

static inline void update_buffers(
	struct xlt_session* sess, bool newdata)
{
	if (sess->populate(newdata, &sess->in, &sess->out,
		sess->vpts + sess->base_ofs, sess->unpack_sz - sess->base_ofs,
		sess->buf + sess->base_ofs)){
			arcan_shmif_signal(&sess->out, SHMIF_SIGVID);
		sess->in.addr->vready = false;
	}
}

static void* process(void* inarg)
{
	struct xlt_session* sess = inarg;
	arcan_event ev;

	while (arcan_shmif_wait(&sess->in, &ev) != 0){
		flush_output_events(sess);

		if (ev.category == EVENT_TARGET){
			if (ev.tgt.kind == TARGET_COMMAND_EXIT)
				break;
/* really weird packing sizes are ignored / clamped */
			else if (ev.tgt.kind == TARGET_COMMAND_GRAPHMODE){
				sess->pack_sz = ev.tgt.ioevs[0].iv;
				if (sess->pack_sz <= 0){
					fprintf(stderr, "translator: invalid packing size (%d) received.\n",
						(int)sess->pack_sz);
				}
				if (sess->pack_sz > 4){
					fprintf(stderr, "translator: unaccepted packing size (%zu), "
						"will clamp to 4 bytes, expect corruption.\n", sess->pack_sz);
					sess->pack_sz = 4;
				}
			}
			else if (ev.tgt.kind == TARGET_COMMAND_DISPLAYHINT){
				if ((sess->flags & XLT_DYNSIZE)){
					size_t width = ev.tgt.ioevs[0].iv;
					size_t height = ev.tgt.ioevs[1].iv;
					arcan_shmif_resize(&sess->out, width, height);
					update_buffers(sess, false);
				}
			}
			else if (ev.tgt.kind == TARGET_COMMAND_SEEKTIME){
/* use to set local window offset, or hint of global position? */
			}
			else if (ev.tgt.kind == TARGET_COMMAND_STEPFRAME){
				if (ev.tgt.ioevs[0].iv > 0 || sess->buf == NULL){
					sess->vpts = sess->in.addr->vpts;
					populate(sess);
					update_buffers(sess, true);
				}
				else
					update_buffers(sess, false);
			}
			else
				;
		}
		else if (ev.category == EVENT_IO){
			if (ev.io.datatype == EVENT_IDATATYPE_TOUCH){
				size_t ofs = (ev.io.input.touch.y *
					sess->in.addr->w + ev.io.input.touch.x) * sess->pack_sz;

				if (ofs > sess->unpack_sz){
					fprintf(stderr, "request to set invalid base "
						"offset (%zu vs %zu) ignored\n", ofs, sess->unpack_sz);
				}
				else{
					sess->base_ofs = ofs;
					update_buffers(sess, false);
				}
			}
			if (sess->input && ev.category == EVENT_IO)
				if (sess->input(&sess->out, &ev))
					update_buffers(sess, true);
		}
		else
			;

/* on EVENT_IO, use that to move working offset in buffer */
	}

	fprintf(stderr, "translator: lost translation process\n");
	arcan_shmif_drop(&sess->in);
	arcan_shmif_drop(&sess->out);

	return NULL;
}

bool xlt_setup(const char* tag, xlt_populate pop,
	xlt_input inp, enum xlt_flags flags)
{
	struct arg_arr* darg;
	assert(pop);
	assert(tag);

	setenv("ARCAN_CONNPATH", "senseye", 0);
	struct arcan_shmif_cont ctx = arcan_shmif_open(
		SEGID_ENCODER, SHMIF_CONNECT_LOOP, &darg);

/* assume we're connected or have FATALFAIL at this point */
	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_IDENT,
	};
	snprintf((char*)ev.ext.message,
		sizeof(ev.ext.message) / sizeof(ev.ext.message[0]), "%s", tag);
	arcan_shmif_enqueue(&ctx, &ev);

	struct xlt_session* pending = malloc(sizeof(struct xlt_session));
	memset(pending, '\0', sizeof(struct xlt_session));
	pending->input = inp;
	pending->populate = pop;
	pending->flags = flags;

	while (arcan_shmif_wait(&ctx, &ev) != -1){
		if (ev.category == EVENT_TARGET)
			switch (ev.tgt.kind){
			case TARGET_COMMAND_NEWSEGMENT:
				if (ev.tgt.ioevs[1].iv == 1){
					pending->in = arcan_shmif_acquire(&ctx, NULL,
						SEGID_ENCODER, SHMIF_DISABLE_GUARD);
				}
				else{
					pending->out = arcan_shmif_acquire(&ctx, NULL,
						SEGID_SENSOR, SHMIF_DISABLE_GUARD);
					pending->pack_sz = ev.tgt.ioevs[0].iv;
				}

/* sweet spot for attempting fork + seccmp-bpf */
				if (pending->in.addr && pending->out.addr){
					pthread_t pth;

					pending->unpack_sz = pending->pack_sz * pending->in.addr->w *
						pending->in.addr->h;
					if (-1 == pthread_create(&pth, NULL, process, pending)){
						fprintf(stderr, "couldn't spawn translation thread, giving up.\n");
						goto end;
					}

					pending = malloc(sizeof(struct xlt_session));
					memset(pending, '\0', sizeof(struct xlt_session));
					pending->input = inp;
					pending->populate = pop;
					pending->flags = flags;
				}

			break;
			case TARGET_COMMAND_EXIT:
				goto end;
			default:
			break;
			}
	}

end:
	arcan_shmif_drop(&ctx);
	free(pending);

	return true;
}
