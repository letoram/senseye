/*
 * Copyright 2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This translator implements an overlay test case.  An overlay
 * uses the manual setup mode to add another populate style function that will
 * be called in chain (input -> populate, input_overlay -> overlay).
 *
 * It will be either invisible (GRAPHMODE will switch it off) or drawn
 * blended on top of the data window. This is primarily done to aid UI
 * interaction where the 'disconnect' between the normal data window and
 * the translator output it undesired.
 *
 * They support separate input, but with some resize and update in lock-step.
 * Primariy use-case is showing symbol information and sizes rendered on top
 * of the data window. This will only work with the 'dumb' mapping mode.
 *
 * Overlays will be created / destroyed more dynamically as the user
 * is free to switch the feature on or off.
 */

#include "xlt_supp.h"
#include "font_8x8.h"

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	if (!buf)
		return false;

	if (in->addr->w != out->addr->w || in->addr->h != out->addr->h)
		arcan_shmif_resize(out, in->addr->w, in->addr->h);

	memcpy(out->vidp, in->vidp, out->addr->w *
		out->addr->h * sizeof(shmif_pixel));

	return true;
}

static bool over_pop(bool newdata, struct arcan_shmif_cont* in,
	float zoom_range[8], struct arcan_shmif_cont* over,
	struct arcan_shmif_cont* out, uint64_t pos,
	size_t buf_sz, uint8_t* buf)
{
	if (!buf)
		return false;

/* we also need to communicate scale-factor and offset in order
 * to determine if we should draw additional detail or not */

	uint8_t rc = 0;
	shmif_pixel* pxp = over->vidp;
	for (size_t y = 0; y < over->h; y++)
		for (size_t x = 0; x < over->w; x++, rc++, pxp++)
			*pxp = RGBA(rc, 0, 0, rc > 127 ? rc : 0x00);

	return true;
}

static bool over_inp(struct arcan_shmif_cont* cont, arcan_event* ev)
{
	printf("input %s on overlay\n", arcan_shmif_eventstr(ev, NULL, 0));
	return false;
}

int main(int argc, char** argv)
{
	enum SHMIF_FLAGS confl = SHMIF_CONNECT_LOOP;
	struct xlt_context* ctx = xlt_open("overlay", XLT_DYNSIZE, confl);
	if (!ctx)
		return EXIT_FAILURE;

	xlt_config(ctx, populate, NULL, over_pop, over_inp);
	xlt_wait(ctx);
	xlt_free(&ctx);

	return EXIT_SUCCESS;
}
