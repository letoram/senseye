/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This translator hooks up the STB image parser and provides
 * decoding / preview (assuming that there is enough data in the currently
 * sampled / packed buffer for that to be possible, this depends on the
 * base dimensions and the active packing mode).
 * Status: Incomplete, does not work.
 */

#include <inttypes.h>

#include "xlt_supp.h"
#include "font_8x8.h"

enum view_mode {
	VIEW_AUTO = 0,
	VIEW_AUTO_SIMPLE,
	VIEW_MANUAL,
	VIEW_DECODE,
	VIEW_DECODED
};

/*
 * high false-positive rate
 */
#define STBI_NO_TGA
#define STBI_NO_PIC
#define STBI_NO_PNM
#define STBI_NO_PSD
#define STBI_IMAGE_STATIC
#define STBI_NO_FAILURE_STRINGS
#include "stb_image.h"

struct xlti_ctx {
	off_t found;
	enum view_mode current, last;
};

/*
 * GIF: (87a) 47 49 46 38 37 61
        (89a) 47 49 46 38 39 61
 *
 * PNG: 89 50 4E 47 0D 0A 1A 0A
 * JPEG: FF D8 FF E0
 * BMP: 42 4D
 */

static bool input(struct arcan_shmif_cont* out, arcan_event* ev)
{
	struct xlti_ctx* ctx = out->user;
	if (strcmp(ev->io.label, "TAB") == 0){
		if (ctx->current >= VIEW_DECODE)
			ctx->current = ctx->last;
		else
			ctx->current = (ctx->current + 1) % VIEW_DECODE;
	}
	else if (strcmp(ev->io.label, "ENTER") == 0 && ctx->found != -1){
		ctx->last = ctx->current;
		ctx->current = VIEW_DECODE;
	}
	else
		return false;

	return true;
}

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	struct xlti_ctx* ctx = out->user;

	if (!buf){
		free(out->user);
		out->user = NULL;
		return false;
	}

	if (!out->user){
		out->user = malloc(sizeof(struct xlti_ctx));
		memset(out->user, sizeof(struct xlti_ctx), '\0');
		ctx->current = VIEW_AUTO;
		ctx->found = -1;
	}

/*
	size_t ofs = 0;
	int w, h, c;
 */

/* [ scan mode ]
 * 1. sweep magic values from table in comments,
 *    check matches against stbi_info, if reasonable: add to scanlist
 *    (ofs, type)
 */

/* [ basic decode ]
	uint32_t* imgbuf = (uint32_t*) stbi_load_from_memory(
		(stbi_uc const*) buf + ctx->found, buf_sz - ctx->found, &w, &h, &c, 4);

	if (-1 == ctx->found){
		draw_box(out, 0, 0, out->addr->w, out->addr->h,
			RGBA(0x00, 0x00, 0x00, 0xff));
	}
	else {
		char tmpbuf[ sizeof("Possible Match: XXX, 9999x9999x4") ];
		snprintf(tmpbuf, sizeof(tmpbuf), "Possible Match: %.3s, %.4d*%.f4dx%.1d",
			stbi_lut[type], w, h, c);

		draw_text(out, tmpbuf, 4, 4, RGBA(0x00, 0xff, 0x00, 0xff));
	}
*/

	return true;
}

int main(int argc, char** argv)
{
	enum SHMIF_FLAGS confl = SHMIF_CONNECT_LOOP;

	return xlt_setup("IMG", populate, input, XLT_NONE, confl) == true ?
		EXIT_SUCCESS : EXIT_FAILURE;
}
