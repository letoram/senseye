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

/*
 * tracks basic/default setup that is copied to every new
 * session that is spawned off in its own thread or process.
 *
 * sess is 'pending' while waiting for the subsegments that
 * are planned to populate them
 */
struct xlt_context {
	int cookie;

	struct xlt_session* sess;
	struct arg_arr* args;
	struct arcan_shmif_cont main;

	enum xlt_flags flags;

	xlt_populate populate;
	xlt_input input;
	xlt_overlay overlay;
	xlt_input overlay_input;
};

struct xlt_session {
	uint8_t* buf;

	uint64_t vpts;
	size_t buf_sz;
	size_t unpack_sz;
	size_t pack_sz;
	size_t base_ofs;

	xlt_populate populate;
	xlt_input input;
	xlt_overlay overlay;
	xlt_input overlay_input;

	enum xlt_flags flags;

	int zoom_range[4];

	struct {
		size_t ofs;
		bool got_input;
	} pending_input;

	struct {
		bool got_dh;
		size_t width, height;
	} pending_update;

	struct arcan_shmif_cont in;
	struct arcan_shmif_cont olay;
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
 * recall that this does not compensate for mapping mode,
 * so data may appear to be "wrong" if the underlying mapping
 * is flawed.
 */
static void populate(struct xlt_session* s)
{
	if (s->buf_sz < s->unpack_sz){
		free(s->buf);
		s->buf = malloc(s->unpack_sz);
		s->buf_sz = s->unpack_sz;
	}

/* we reset this as the likely interested offset must have changed */
	s->base_ofs = 0;

/* maintain a copy to be able to release vidp quicker, making room
 * for a new frame */
	if (s->pack_sz == 4)
		memcpy(s->buf, s->in.vidp, s->unpack_sz);
	else{
		uint8_t* outb = s->buf;

		for (size_t i = 0; i < s->in.addr->w * s->in.addr->h; i++){
			shmif_pixel cp = s->in.vidp[i];
			*outb++ = (cp & 0x000000ff);
			if (s->pack_sz == 1)
				continue;

			*outb++ = (cp & 0x0000ff00) >>  8;
			*outb++ = (cp & 0x00ff0000) >> 16;
		}
	}
}

static inline void update_overlay(struct xlt_session* sess, bool nd)
{
	if (sess->overlay && sess->olay.addr && sess->overlay(nd, &sess->in,
		sess->zoom_range, &sess->olay, &sess->out,
		sess->vpts, sess->unpack_sz, sess->buf, sess))
		arcan_shmif_signal(&sess->olay, SHMIF_SIGVID | SHMIF_SIGBLK_ONCE);
}

void xlt_ofs_coord(struct xlt_session* sess,
	size_t ofs, size_t* x, size_t* y)
{
	if (ofs > 0)
		ofs = (ofs / sess->pack_sz) + (ofs % sess->pack_sz);

	if (ofs > 0){
		*y = ofs / sess->in.w;
		*x = ofs - (*y * sess->in.w);
	}
	else{
		*x = 0;
		*y = 0;
	}
}

static inline void update_buffers(
	struct xlt_session* sess, bool newdata)
{
	if (sess->populate(newdata, &sess->in, &sess->out,
		sess->vpts + sess->base_ofs, sess->unpack_sz - sess->base_ofs,
		sess->buf + sess->base_ofs)){

		update_overlay(sess, newdata);

		arcan_shmif_signal(&sess->out, SHMIF_SIGVID);
		sess->in.addr->vready = false;
	}
}

/*
 * 2-phase commit expensive events (touch x / y + resize)
 */
static void event_commit(struct xlt_session* s)
{
	if (s->pending_update.got_dh){
		s->pending_update.got_dh = false;
		arcan_shmif_resize(&s->out,
			s->pending_update.width, s->pending_update.height);
	}

	if (s->pending_input.got_input){
		if (s->pending_input.ofs > s->unpack_sz){
			fprintf(stderr, "request to set invalid base "
				"offset (%zu vs %zu) ignored\n", s->pending_input.ofs, s->unpack_sz);
		}
		else{
			s->base_ofs = s->pending_input.ofs;
			update_buffers(s, false);
		}
		s->pending_input.got_input = false;
	}
}

static void overlay_event(struct xlt_session* sess)
{
	arcan_event ev;
	while (arcan_shmif_poll(&sess->olay, &ev) != 0){
		if (ev.category == EVENT_IO){
			if (sess->overlay_input)
				sess->overlay_input(&sess->olay, &ev);
			continue;
		}

		if (ev.category != EVENT_TARGET)
			continue;

		if (ev.tgt.kind == TARGET_COMMAND_EXIT){
			arcan_shmif_drop(&sess->olay);
			return;
		}

		if (ev.tgt.kind == TARGET_COMMAND_DISPLAYHINT){
			arcan_shmif_resize(&sess->olay,
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv);
		}
	}
}

static bool dispatch_event(struct xlt_session* sess, arcan_event* ev)
{
	if (ev->category == EVENT_TARGET){
		if (ev->tgt.kind == TARGET_COMMAND_EXIT)
			return false;
	else if (ev->tgt.kind == TARGET_COMMAND_NEWSEGMENT){
		if (sess->olay.addr)
			arcan_shmif_drop(&sess->olay);

		sess->olay = arcan_shmif_acquire(&sess->in,
			NULL, SEGID_MEDIA, SHMIF_DISABLE_GUARD);
		sess->zoom_range[0] = 0;
		sess->zoom_range[1] = 0;
		sess->zoom_range[2] = sess->olay.w;
		sess->zoom_range[3] = sess->olay.h;
		arcan_shmif_resize(&sess->olay, sess->in.w, sess->in.h);
	}
/* really weird packing sizes are ignored / clamped */
	else if (ev->tgt.kind == TARGET_COMMAND_GRAPHMODE){
		sess->pack_sz = ev->tgt.ioevs[0].iv;
		if (sess->pack_sz <= 0){
			fprintf(stderr, "translator: invalid packing size (%d) received.\n",
				(int)sess->pack_sz);
		}
		if (sess->pack_sz > 4){
			fprintf(stderr, "translator: unaccepted packing size (%zu), "
				"will clamp to 4 bytes, expect corruption.\n", sess->pack_sz);
				sess->pack_sz = 4;
			}
			sess->unpack_sz = sess->pack_sz * sess->in.w * sess->in.h;
		}
		else if (ev->tgt.kind == TARGET_COMMAND_DISPLAYHINT){
			if ((sess->flags & XLT_DYNSIZE)){
				size_t width = ev->tgt.ioevs[0].iv;
				size_t height = ev->tgt.ioevs[1].iv;
				width = width < 32 ? 32 : width;
				height = height < 32 ? 32 : height;
				arcan_shmif_resize(&sess->out, width, height);
				update_buffers(sess, false);
			}
		}
		else if (ev->tgt.kind == TARGET_COMMAND_SEEKTIME){
/* use to set local window offset, or hint of global position? */
		}
		else if (ev->tgt.kind == TARGET_COMMAND_STEPFRAME){
			if (ev->tgt.ioevs[0].iv > 0 || sess->buf == NULL){
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
	else if (ev->category == EVENT_IO){
		if (ev->io.datatype == EVENT_IDATATYPE_TOUCH){
			sess->pending_input.ofs = (ev->io.input.touch.y *
				sess->in.addr->w + ev->io.input.touch.x) * sess->pack_sz;
			sess->pending_input.got_input = true;
		}
		if (ev->io.datatype == EVENT_IDATATYPE_ANALOG){
			for (int i = 0; i < 4; i++)
				sess->zoom_range[i] = ev->io.input.analog.axisval[i];
			update_overlay(sess, false);
		}
		if (sess->input && ev->category == EVENT_IO)
			if (sess->input(&sess->out, ev))
				update_buffers(sess, false);
	}
	else
		;

	return true;
}

static void* process(void* inarg)
{
	struct xlt_session* sess = inarg;
	arcan_event ev;

	if (sess->overlay){
		ev.category = EVENT_EXTERNAL,
		ev.ext.kind = ARCAN_EVENT(IDENT),
/* only ident accepted on this subsegment */
		sprintf((char*)ev.ext.message.data, "OVERLAY");
		arcan_shmif_enqueue(&sess->out, &ev);
	}

/* two phase flush so that some events that can come in piles,
 * (input / displayhint) only apply the latest one */
	while (arcan_shmif_wait(&sess->in, &ev)){
		flush_output_events(sess);
		if (!dispatch_event(sess, &ev))
			goto end;

		while(arcan_shmif_poll(&sess->in, &ev) != 0)
			if (!dispatch_event(sess, &ev))
				goto end;

		if (sess->olay.addr)
			overlay_event(sess);

		event_commit(sess);
	}

end:
	arcan_shmif_drop(&sess->in);
	arcan_shmif_drop(&sess->olay);
	arcan_shmif_drop(&sess->out);

	return NULL;
}

static void setup_session(struct xlt_context* ctx, struct xlt_session* sess)
{
	memset(sess, '\0', sizeof(struct xlt_session));
	sess->pack_sz = 1;
	sess->input = ctx->input;
	sess->populate = ctx->populate;
	sess->overlay = ctx->overlay;
	sess->overlay_input = ctx->overlay_input;
	sess->flags = ctx->flags;
}

struct xlt_context* xlt_open(const char* ident,
	enum xlt_flags flags, enum ARCAN_FLAGS confl)
{
	struct xlt_context* res = malloc(sizeof(struct xlt_context));
	if (!res)
		return NULL;
	memset(res, '\0', sizeof(struct xlt_context));
	res->cookie = 0xfeedface;

	struct arg_arr* darg;
	setenv("ARCAN_CONNPATH", "senseye", 0);
	struct arcan_shmif_cont mcon = arcan_shmif_open(SEGID_ENCODER, confl, &darg);

	if (!mcon.addr){
		free(res);
		return NULL;
	}

	res->flags = flags;

/* assume we're connected or have FATALFAIL at this point */
	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(IDENT)
	};
	res->main = mcon;
	snprintf((char*)ev.ext.message.data,
		sizeof(ev.ext.message.data) /
		sizeof(ev.ext.message.data[0]), "%s", ident
	);
	arcan_shmif_enqueue(&res->main, &ev);

	return res;
}

void xlt_config(struct xlt_context* ctx,
	xlt_populate pop, xlt_input inp, xlt_overlay overl, xlt_input inp_ov)
{
	ctx->sess = malloc(sizeof(struct xlt_session));
	ctx->populate = pop;
	ctx->input = inp;
	ctx->overlay = overl;
	ctx->overlay_input = inp_ov;
	setup_session(ctx, ctx->sess);
}

static bool process_event(struct xlt_context* ctx, arcan_event* ev)
{
	struct xlt_session* pending = ctx->sess;

	if (ev->category == EVENT_TARGET)
	switch (ev->tgt.kind){
	case TARGET_COMMAND_NEWSEGMENT:
	if (ev->tgt.ioevs[1].iv == 1){
		pending->in = arcan_shmif_acquire(&ctx->main,
			NULL, SEGID_ENCODER, SHMIF_DISABLE_GUARD);
	}
	else{
		pending->out = arcan_shmif_acquire(&ctx->main,
			NULL, SEGID_SENSOR, SHMIF_DISABLE_GUARD);
		pending->pack_sz = ev->tgt.ioevs[0].iv ? ev->tgt.ioevs[0].iv : 1;
	}

/* sweet spot for attempting fork + seccmp-bpf */
	if (pending->in.addr && pending->out.addr){
		pthread_t pth;

		pending->unpack_sz = pending->pack_sz * pending->in.w * pending->in.h;
		if (-1 == pthread_create(&pth, NULL, process, pending)){
			fprintf(stderr, "couldn't spawn translation thread, giving up.\n");
			return false;
		}

		ctx->sess = malloc(sizeof(struct xlt_session));
		setup_session(ctx, ctx->sess);
	}

	break;
	case TARGET_COMMAND_EXIT:
		return false;
	default:
	break;
	}

	return true;
}

bool xlt_pump(struct xlt_context* ctx)
{
	arcan_event ev;
	int rc;

	while ( (rc = arcan_shmif_poll(&ctx->main, &ev)) > 0)
		process_event(ctx, &ev);

	return rc == 0;
}

bool xlt_wait(struct xlt_context* ctx)
{
	arcan_event ev;

	while (arcan_shmif_wait(&ctx->main, &ev))
		process_event(ctx, &ev);

	return true;
}

bool xlt_setup(const char* tag, xlt_populate pop,
	xlt_input inp, enum xlt_flags flags, enum ARCAN_FLAGS confl)
{
	assert(pop);
	assert(tag);

	struct xlt_context* ctx = xlt_open(tag, flags, confl);
	if (!ctx)
		return false;

	xlt_config(ctx, pop, inp, NULL, NULL);

	return xlt_wait(ctx);
}

void xlt_free(struct xlt_context** ctx)
{
	if (!ctx || !(*ctx) || (*ctx)->cookie != 0xfeedface)
		return;

	arcan_shmif_drop(&(*ctx)->main);
	free((*ctx)->sess);
	*ctx = NULL;
}
