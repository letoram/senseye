/* (C)opyright, 2014-2015 Björn Ståhl
 * License: BSD 3-clause, see COPYING file in the senseye source repository.
 * Reference: senseye.arcan-fe.com
 * Description: This mainly takes care of some rwstat+event_decoding
 * foreplay for having one connection to multiple data channels feed
 * with the senseye appl.
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

#include <sys/stat.h>
#include <sys/resource.h>

#include "sense_supp.h"
#include "rwstat.h"

static FILE* logout;

#define FLOG(...) ( (logout ? fprintf(logout, __VA_ARGS__) : true ) )

/*
 * default options, modifyable dynamically thorough various events
 * and changeable at load time through the arcan_args mechanism.
 */
struct {
	enum rwstat_pack def_pack;
	enum rwstat_mapping def_map;
	struct arg_arr* args;
	bool paused;
}
opts = {
	.def_map = MAP_WRAP,
	.def_pack = PACK_TNOALPHA,
	.paused = true
};

struct senseye_priv {
	struct arcan_shmif_cont cont;
	bool paused, running, noforward;
	int framecount;
};

static void dispatch_event(arcan_event* ev,
	struct rwstat_ch* ch, struct senseye_priv* chp)
{
	if (rwstat_consume_event(ch, ev))
		return;

	if (ev->category == EVENT_TARGET)
	switch (ev->tgt.kind){
		case TARGET_COMMAND_REQFAIL:
			chp->running = false;
		break;

		case TARGET_COMMAND_PAUSE:
			chp->paused = true;
		break;

		case TARGET_COMMAND_DISPLAYHINT:{
			size_t base = ev->tgt.ioevs[0].iv;
			if (base > 0 && (base & (base - 1)) == 0 &&
				arcan_shmif_resize(&chp->cont, base, base))
				ch->resize(ch, base);
			else
				FLOG("Senseye:FDsense: bad displayhint: %d\n", ev->tgt.ioevs[0].iv);
		}

/* resize buffer to new base */
		break;

		case TARGET_COMMAND_UNPAUSE:
			chp->paused = false;
		break;

		case TARGET_COMMAND_STEPFRAME:
			chp->framecount = ev->tgt.ioevs[0].iv;
		break;

		case TARGET_COMMAND_EXIT:
			chp->running = false;
		break;

		default:
#ifdef _DEBUG
			printf("unhandled event : %s\n", arcan_shmif_eventstr(ev, NULL, 0));
#endif
		break;
		}
}

static bool cont_refresh(struct senseye_cont* scont,
	shmif_pixel* vidp, size_t w, size_t h)
{
	return false;
}

static struct arcan_shmif_cont* cont_getctx(struct senseye_cont* ctx)
{
	return &ctx->priv->cont;
}

static void cont_dispatch(struct senseye_cont* cont, arcan_event* ev)
{
}

bool senseye_connect(const char* key, FILE* log,
	struct senseye_cont* dcont, struct arg_arr** darg)
{
	logout = log;
	if (!key){
		if ( (key = getenv("ARCAN_CONNPATH")) == NULL){
			FLOG("Senseye, attempting to connect to arcan using 'senseye' key");
			key = "senseye";
		}
	}

	dcont->priv = malloc(sizeof(struct senseye_priv));
	if (!dcont->priv)
		return false;
	memset(dcont->priv, '\0', sizeof(struct senseye_priv));
	dcont->refresh = cont_refresh;
	dcont->dispatch = cont_dispatch;
	dcont->context = cont_getctx;

	setenv("ARCAN_CONNPATH", key, 0);
	dcont->priv->cont = arcan_shmif_open(SEGID_SENSOR, SHMIF_CONNECT_LOOP, darg);
	unsetenv("ARCAN_CONNPATH");

	opts.args = *darg;
	if (dcont->priv->cont.addr != NULL)
		return true;

	free(dcont->priv);
	dcont->priv = NULL;
	return false;
}

static void ch_pump(struct senseye_ch* ch)
{
	if (!ch || !ch->in_pr)
		return;

	struct senseye_priv* priv = ch->in_pr;
	struct arcan_event ev;

	while(arcan_shmif_poll(&priv->cont, &ev) != 0)
		dispatch_event(&ev, ch->in, priv);
}

static ssize_t ch_data(struct senseye_ch* ch, const void* buf, size_t ntw)
{
	if (!ch || !ch->in_pr)
		return -1;

	struct senseye_priv* chp = ch->in_pr;
	size_t ofs = 0;

retry:
	if (!chp->running)
		return -1;

/* flush if the controlling UI has specified one or several framesteps */
	if (!chp->paused || chp->framecount > 0){
		int fc;

		while (chp->framecount > 0 && ntw - ofs > 0){
			ofs += ch->in->data(ch->in, (uint8_t*) buf + ofs, ntw, &fc);
			chp->framecount -= fc;
		}
	}
/* otherwise, block thread, wait for user action and retry */
	else{
		arcan_event ev;
		if (arcan_shmif_wait(&chp->cont, &ev)){
			dispatch_event(&ev, ch->in, chp);
			goto retry;
		}
	}

	ch_pump(ch);
	return ofs;
}

static off_t ch_seek(struct senseye_ch* ch, long long sv)
{
	if (!ch || !ch->in_pr)
		return -1;

/* reset intermediate buffers, change file offset according to sv / whence */

	return 0;
}

static void ch_flush(struct senseye_ch* ch)
{
	if (!ch || !ch->in_pr)
		return;

	ch->in->tick(ch->in);
}

static void ch_queue(struct senseye_ch* ch, arcan_event* ev)
{
	if (!ch || !ch->in_pr)
		return;

	ch->in->event(ch->in, ev);
}

static void ch_close(struct senseye_ch* ch)
{
	if (!ch || !ch->in_pr)
		return;

	ch_flush(ch);

	struct senseye_priv* chp = ch->in_pr;
	arcan_shmif_drop(&chp->cont);
	ch->in->free(&ch->in);
	chp->running = false;
}

static void process_event(struct senseye_cont* cont, arcan_event* ev)
{
	if (ev->category == EVENT_TARGET){
		if (ev->tgt.kind == TARGET_COMMAND_STEPFRAME){
			if (cont->refresh(cont, cont->priv->cont.vidp,
				cont->priv->cont.addr->w,
				cont->priv->cont.addr->h)){
				arcan_shmif_signal(&cont->priv->cont, SHMIF_SIGVID);
			}
		}
	}

	cont->dispatch(cont, ev);
}

bool senseye_pump(struct senseye_cont* cont, bool block)
{
	struct senseye_priv* cpriv = cont->priv;
	arcan_event sr;

	if (block){
		if (!arcan_shmif_wait(&cpriv->cont, &sr) ||
			(sr.category == EVENT_TARGET && sr.tgt.kind == TARGET_COMMAND_EXIT))
				return false;
		else
			process_event(cont, &sr);
		return true;
	}

	int rc = arcan_shmif_poll(&cpriv->cont, &sr);
	if (rc > 0)
		process_event(cont, &sr);

	return rc != -1;
}

struct senseye_ch* senseye_open(struct senseye_cont* cont,
	const char* const ident, size_t base)
{
	if (!cont || !cont->priv)
		return NULL;

	struct senseye_priv* cpriv = cont->priv;

	struct senseye_ch scp = {
		.pump  = ch_pump,
	 	.data  = ch_data,
		.seek  = ch_seek,
		.flush = ch_flush,
		.queue = ch_queue,
		.close = ch_close
	}, *rv = NULL;

	int tag = random();
	arcan_event sr = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_SEGREQ,
		.ext.segreq.width = base,
		.ext.segreq.height = base,
		.ext.segreq.id = tag
	};
	arcan_shmif_enqueue(&cpriv->cont, &sr);

/*
 * as we are blocking, we also need to interleave other
 * events that may already be queued or if the request
 * management is deferred for any (UX)- reason.
 */
	while(arcan_shmif_wait(&cpriv->cont, &sr)){
		if (sr.category == EVENT_TARGET && (
			sr.tgt.kind == TARGET_COMMAND_NEWSEGMENT ||
			sr.tgt.kind == TARGET_COMMAND_REQFAIL)){

			if (sr.tgt.kind == TARGET_COMMAND_REQFAIL)
				break;

			rv = malloc(sizeof(struct senseye_ch));
			if (!rv)
				break;

			*rv = scp;
			struct senseye_priv* cp = malloc(sizeof(struct senseye_priv));
			if (!cp)
				goto fail;

			rv->in_pr = cp;
			cp->paused = true;
			cp->running = true;
			cp->framecount = 0;
			cp->cont = arcan_shmif_acquire(&cpriv->cont,
				NULL, SEGID_SENSOR, SHMIF_DISABLE_GUARD);
			if (!cp->cont.addr)
				goto fail;

			rv->in = rwstat_addch(RW_CLK_BLOCK,
				opts.def_map, opts.def_pack, base, &cp->cont);
			rv->in_handle = cp->cont.epipe;
			rwstat_addpatterns(rv->in, opts.args);
			break;
		}
		else
			process_event(cont, &sr);
	}

	return rv;

fail:
	if (rv){
		free(rv->in_pr);
		free(rv);
	}

	return NULL;
}
