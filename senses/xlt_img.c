/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This translator hooks up the STB image parser and provides
 * decoding / preview (assuming that there is enough data in the currently
 * sampled / packed buffer for that to be possible, this depends on the
 * base dimensions and the active packing mode).
 * Status: Incomplete, does not work.
 *
 *  - replace load_from_memory with load_from_callbacks so we can track
 *  the number of used bytes. If overlay is present, fill the area consumed
 *  by the last decode.
 *
 *  - missing manual navigation in list mode
 *
 *  - output ofs in header as well
 */

#include <inttypes.h>

#include "xlt_supp.h"
#include "font_8x8.h"

enum view_mode {
	VIEW_LIST    = 0,
	VIEW_AUTO    = 1,
	VIEW_MANUAL  = 2,
	VIEW_DECODE  = 3,
	VIEW_DECODED = 4
};

/*
 * high false-positive rate and low relevance, just ignore them for now
 */
#define STBI_NO_TGA
#define STBI_NO_PIC
#define STBI_NO_PNM
#define STBI_NO_PSD
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#define STBI_IMAGE_STATIC
#include "stb_image.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"

struct scanres {
	uint8_t magic;
	size_t ofs;
};

struct xlti_ctx {
	size_t count, found;
	struct scanres* items;
	enum view_mode current, last;
	bool invalidated;

	int over_state;
	size_t over_pos, over_count;
};

struct {
	char ident[16];
	uint8_t buf[10];
	size_t used;
/* only useful for LIST mode to hint something was found but that
 * there's not currently any decoder available */
	bool decodable;
} magic[] = {
	{
		.ident = "GIF87",
		.buf = {0x47, 0x49, 0x46, 0x38, 0x37, 0x61},
		.used = 6,
		.decodable = true
	},
	{
		.ident = "GIF89",
		.buf = {0x47, 0x49, 0x46, 0x38, 0x39, 0x61},
		.used = 6,
		.decodable = true
	},
	{
		.ident = "PNG",
		.buf = {0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a},
		.used = 8,
		.decodable = true
	},
	{
		.ident = "JPEG",
		.buf = {0xff, 0xd8},
		.used = 2,
		.decodable = true
	},
	{
		.ident = "BMP",
		.buf = {0x42, 0x4d},
		.used = 2,
		.decodable = true
	}
};

static bool input(struct arcan_shmif_cont* out, arcan_event* ev)
{
	struct xlti_ctx* ctx = out->user;

	if (strcmp(ev->io.label, "a") == 0){
		ctx->current = VIEW_AUTO;
	}
	else if (strcmp(ev->io.label, "m") == 0){
		ctx->current = VIEW_MANUAL;
	}
	else if (strcmp(ev->io.label, "l") == 0){
		ctx->current = VIEW_LIST;
	}
	else if (strcmp(ev->io.label, "ENTER") == 0 && ctx->current != VIEW_AUTO){
		ctx->last = ctx->current;
		ctx->current = VIEW_DECODE;
	}
	else
		return false;

	ctx->invalidated = true;
	return true;
}

/*
 * Populate out with up to out_lim members where each member specify
 * what type was found and the offset in buf it was found. Returns the
 * number of elements that were set.
 */
static size_t scan(uint8_t* buf, size_t buf_sz,
	struct scanres* out, size_t out_lim)
{
	size_t magic_count = sizeof(magic) / sizeof(magic[0]);
	size_t oc[sizeof(magic)/sizeof(magic[0])] = {0};
	size_t rc = 0;

	for (size_t i = 0; i < buf_sz && rc < out_lim-1; i++)
		for (size_t j = 0; j < magic_count && rc < out_lim-1; j++)
			if (buf[i] == magic[j].buf[ oc[j] ]){
				oc[j]++;
				if (oc[j] >= magic[j].used){
					out->magic = j;
					out->ofs = i-(magic[j].used-1);
					out++;
					rc++;
/* possibly validate / hint by decoding header as well */
					oc[j] = 0;
				}
			}
			else
				oc[j] = 0;

	return rc;
}

/* big optimization here would be tracking if the state of the page
 * is "already empty" and avoid the memset and possibly transfer */
static bool over_pop(bool newdata, struct arcan_shmif_cont* in,
	int zoom_ofs[4], struct arcan_shmif_cont* over,
	struct arcan_shmif_cont* out, uint64_t pos,
	size_t buf_sz, uint8_t* buf, struct xlt_session* sess)
{
	struct xlti_ctx* ctx = out->user;
/* don't have any state hidden in over- tag */
	if (!buf)
		return false;

	memset(over->vidp, '\0', sizeof(shmif_pixel) * over->h * over->pitch);

	if (ctx->over_pos < pos)
		return true;

/* scale factors */
	float w = zoom_ofs[2] - zoom_ofs[0];
	float h = zoom_ofs[3] - zoom_ofs[1];

	float b_w = (float)over->w / w;
	float b_h = (float)over->h / h;
	float d_w = ceil(b_w);
	float d_h = ceil(b_h);

	size_t ofs = ctx->over_pos - pos;

	size_t x1, y1, x2, y2;
	xlt_ofs_coord(sess, ofs, &x1, &y1);
	xlt_ofs_coord(sess, ofs + ctx->over_count, &x2, &y2);

	shmif_pixel col = ctx->over_state == 1 ? RGBA(0x00, 0xff, 0x00, 0xff) :
		RGBA(0xff, 0x00, 0x00, 0xff);

/* if within zoom_range, draw_box with d_w, d_h */
	while ((x1 != x2 || y1 != y2) && y1 <= zoom_ofs[3] && y1 <= y2){
		if (x1 >= zoom_ofs[0] && y1 >= zoom_ofs[1] &&
			x1 <= zoom_ofs[2] && y1 <= zoom_ofs[3])
				draw_box(over, (x1 - zoom_ofs[0]) * b_w,
					(y1 - zoom_ofs[1]) * b_h, d_w, d_h, col);

		x1++;
		if (x1 >= zoom_ofs[2]){
			x1 = zoom_ofs[0]; y1++;
		}
	}

	return true;
}

static size_t draw_header(struct arcan_shmif_cont* c, struct xlti_ctx* ctx)
{
	draw_box(c, 0, 0, c->w, fonth + 4, RGBA(0x44, 0x44, 0x44, 0xff));
	switch (ctx->current){
	case VIEW_LIST:
		draw_text(c, "View Mode (List), a: auto-decode, m: manual",
			2, 2, RGBA(0xff, 0xff, 0xff, 0xff));
	break;
	case VIEW_AUTO:
		draw_text(c, "View Mode (Auto), l: list m: manual",
			2, 2, RGBA(0xff, 0xff, 0xff, 0xff));
	break;
	case VIEW_DECODE:
		draw_text(c, "View Mode (List), decoding",
			2, 2, RGBA(0xff, 0xff, 0xff, 0xff));
	break;

	case VIEW_MANUAL:
		draw_text(c, "View Mode (Manual), a: auto-decode, l: list, enter: decode",
			2, 2, RGBA(0xff, 0xff, 0xff, 0xff));
	break;
	default:
	break;
	}

	return fonth + 6;
}

struct stbi_inf {
	uint8_t* buf;
	size_t buf_sz;
	size_t fpos;
};

static int stbi_cb_read(void* user, char* data, int sz)
{
	struct stbi_inf* inf = user;
	sz = inf->buf_sz - inf->fpos > sz ? sz : inf->buf_sz - inf->fpos;
	memcpy(data, &inf->buf[inf->fpos], sz);
	inf->fpos += sz;
	return sz;
}

static void stbi_cb_skip(void* user, int n)
{
	struct stbi_inf* inf = user;
	if (n > 0)
		inf->fpos = inf->fpos + n > inf->buf_sz ? inf->buf_sz : inf->fpos + n;
	else
		inf->fpos = (-1 * n) > inf->fpos ? 0 : inf->fpos + n;
}

static int stbi_cb_eof(void* user)
{
	struct stbi_inf* inf = user;
	return (inf->fpos >= inf->buf_sz);
}

static stbi_io_callbacks stbi_cb = {
	.read = stbi_cb_read,
	.skip = stbi_cb_skip,
	.eof = stbi_cb_eof
};

/* for the overlay, simply draw the regions that were found during each
 * decode, and if we have a specialized handler (that can show header data),
 * invoke that */

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	size_t nr = out->h / (fonth + 1);
	struct xlti_ctx* ctx = out->user;

	if (!buf){
		if (ctx){
			free(ctx->items);
			ctx->items = NULL;
		}
		free(out->user);
		out->user = NULL;
		return false;
	}

	if (!ctx){
		ctx = out->user = malloc(sizeof(struct xlti_ctx));
		memset(ctx, '\0', sizeof(struct xlti_ctx));
		ctx->current = VIEW_LIST;
		ctx->found = -1;
		goto alloc_nv;
	}

	if (!newdata && !ctx->invalidated && nr == 0)
		return false;
	ctx->invalidated = false;

/* handle dynamic size, list will show the amount that can fit in one window */
	if (nr > ctx->count){
alloc_nv:
		ctx->count = nr;
		free(ctx->items);
		ctx->items = malloc(sizeof(struct scanres) * ctx->count);
		if (!ctx->items)
			return (ctx->count = 0);
	}

/* depending on view mode, we autodecode first or just list matches */
	switch (ctx->current){
	case VIEW_LIST:{
		draw_box(out, 0, 0, out->w, out->h, RGBA(0x00, 0x00, 0x00, 0xff));
		size_t y = draw_header(out, ctx);

		ctx->found = scan(buf, buf_sz, ctx->items, ctx->count);
		if (ctx->found)
			for (size_t i = 0; i < ctx->found; i++){
				char scratch[32];
				snprintf(scratch, 32, "%s @ %zu", magic[ctx->items[i].magic].ident,
					ctx->items[i].ofs);
				draw_text(out, scratch,
					(fontw+1)*2, y + i * (fonth + 1), RGBA(0x00,0xff,0x00,0xff));
			}
		return true;
	}
	break;

	case VIEW_AUTO:{
		draw_box(out, 0, 0, out->w, out->h, RGBA(0x00, 0x00, 0x00, 0xff));
		ctx->found = scan(buf, buf_sz, ctx->items, ctx->count);
		size_t y = draw_header(out, ctx);

		if (ctx->found){
			int w, h, f;
			for (size_t i = 0; i < 1 && ctx->found; i++){
				struct stbi_inf inf = {
					.buf = buf + ctx->items[i].ofs,
					.buf_sz = buf_sz - ctx->items[i].ofs
				};
				uint8_t* res = stbi_load_from_callbacks(&stbi_cb, &inf, &w, &h, &f, 4);
				ctx->over_pos = pos + ctx->items[i].ofs;
				ctx->over_count = inf.fpos;

				if (res){
					ctx->over_state = 1;
					char scratch[64];
					snprintf(scratch, 64, "@%"PRIu64": decoded %s [%d * %d]",
						pos + ctx->items[i].ofs, magic[ctx->items[i].magic].ident, w, h);

/* inf fpos hints at the number of bytes consumed */
					draw_text(out, scratch,
						(fontw+1)*2, y, RGBA(0x00,0xff,0x00,0xff));

					y+=fonth+2;

					stbir_resize_uint8(
						res, w, h, 0,
						(uint8_t*) &out->vidp[y * out->pitch], out->w, out->h-y, 0,
					4);

					free(res);
					break;
				}
				else{
					ctx->over_state = -1;
					draw_text(out, "Decoding failed",
						(fontw+1)*2, y, RGBA(0xff, 0x00, 0x00, 0xff));
					const char* msg = stbi_failure_reason();
					if (msg)
						draw_text(out, msg, (fontw+1)*2, y+fonth+2,
							RGBA(0xff, 0x00, 0x00, 0xff));
				}
			}
		}
		else{
			draw_text(out, "No supported formats found",
				(fontw+1)*2, y, RGBA(0xff, 0x00, 0x00, 0xff));
			draw_text(out, stbi_failure_reason(),
				(fontw+1)*2, y+fonth+2, RGBA(0xff, 0x00, 0x00, 0xff));
		}
		return true;
	}
	break;

/* manual decoding still missing */
	default:
	break;
	}

	return false;
}

int main(int argc, char** argv)
{
	enum SHMIF_FLAGS confl = SHMIF_CONNECT_LOOP;
	struct xlt_context* ctx = xlt_open("IMG", XLT_DYNSIZE, confl);
	if (!ctx)
		return EXIT_FAILURE;

	xlt_config(ctx, populate, input, over_pop, NULL);
	xlt_wait(ctx);
	xlt_free(&ctx);

	return EXIT_SUCCESS;
}
