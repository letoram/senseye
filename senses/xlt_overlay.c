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
#include <math.h>

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	if (!buf)
		return false;

	memcpy(out->vidp, in->vidp, out->addr->w *
		out->addr->h * sizeof(shmif_pixel));

	return true;
}

static bool over_pop(bool newdata, struct arcan_shmif_cont* in,
	int zoom_range[4], struct arcan_shmif_cont* over,
	struct arcan_shmif_cont* out, uint64_t pos,
	size_t buf_sz, uint8_t* buf, struct xlt_session* sess)
{
/* don't have any state hidden in over- tag */
	if (!buf)
		return false;

/* need to clear (or track zoom + precision etc. which means its usually
 * just cheaper to reset between updates */
	int bpp = buf_sz / (in->w*in->h);
	draw_box(over, 0, 0, over->w, over->h, RGBA(0x00, 0x00, 0x00, 0x00));

	float w = zoom_range[2] - zoom_range[0];
	float h = zoom_range[3] - zoom_range[1];

	if (bpp != 1 || w < 0.0001 || h < 0.0001 || over->w < w || over->h < h)
		return false;

/* scale factors */
	float b_w = (float)over->w / w;
	float b_h = (float)over->h / h;
	float d_w = round(b_w);
	float d_h = round(b_h);

	static char msg[] = "All good things to those that wait";
	uint8_t ch = 0;

/* draw as tiles, fill in with text if the tile is large enough */
	for (size_t y = zoom_range[1]; y < zoom_range[3]; y++)
		for (size_t x = zoom_range[0]; x < zoom_range[2]; x++){
			uint8_t pxv = buf[bpp * (y * in->w + x)];
			int xpos = round( (float)(x-zoom_range[0]) * b_w );
			int ypos = round( (float)(y-zoom_range[1]) * b_h );

/* we fight a lot of precision issues here, and the possibility that
 * we have a non-uniform sized output target, round each square upwards */
			if (pxv > 200){
				draw_box(over, xpos, ypos, d_w, d_h, RGBA(0xff, 0x00, 0x00, 0xff));

				if (d_w > fontw && d_h > fonth)
					draw_char(over, msg[ch = (ch + 1) % (sizeof(msg)-1)],
						xpos + 1, ypos + 1, RGBA(0xff, 0xff, 0xff, 0xff));
			}
		}

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
