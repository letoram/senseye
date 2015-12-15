/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This translator is just used to test crash management
 * in the main UI and support scripts, the 10th newdata update will abort().
 * The overlay will show the counter state.
 */

#include "xlt_supp.h"
#include "font_8x8.h"
static int ccount;

static bool over_pop(bool newdata, struct arcan_shmif_cont* in,
	int zoom_range[4], struct arcan_shmif_cont* over,
	struct arcan_shmif_cont* out, uint64_t pos,
	size_t buf_sz, uint8_t* buf, struct xlt_session* sess)
{
	if (!buf)
		return false;

	char outb[4];
	draw_box(over, 0, 0, over->w, fonth+4, RGBA(0x00, 0x00, 0x00, 0x00));
	snprintf(outb, 4, "%d", ccount);
	draw_text(over, outb, 2, 2, RGBA(0xff, 0xff, 0x00, 0xff));

	return true;
}

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	if (!buf)
		return false;

	if (in->addr->w != out->addr->w || in->addr->h != out->addr->h)
		arcan_shmif_resize(out, in->addr->w, in->addr->h);

	if (newdata && ccount++ > 9)
		abort();

	memcpy(out->vidp, in->vidp, out->addr->w *
		out->addr->h * sizeof(shmif_pixel));

	return true;
}

int main(int argc, char** argv)
{
	enum ARCAN_FLAGS confl = SHMIF_CONNECT_LOOP;
	struct xlt_context* ctx = xlt_open("CRASH", XLT_DYNSIZE, confl);
	if (!ctx)
		return EXIT_FAILURE;

	xlt_config(ctx, populate, NULL, over_pop, NULL);
	xlt_wait(ctx);
	xlt_free(&ctx);

	return EXIT_SUCCESS;
}
