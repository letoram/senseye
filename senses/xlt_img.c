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

/* for the overlay, simply draw the regions that were found during each
 * decode, and if we have a specialized handler (that can show header data),
 * invoke that */

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	size_t nr = out->h / (fonth + 1);
	struct xlti_ctx* ctx = out->user;

	if (!buf){
		if (ctx)
			free(ctx->items);
		free(out->user);
		out->user = NULL;
		return false;
	}

	if (!ctx){
		ctx = out->user = malloc(sizeof(struct xlti_ctx));
		memset(ctx, sizeof(struct xlti_ctx), '\0');
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
				uint8_t* res = stbi_load_from_memory(
					(stbi_uc const*) buf + ctx->items[i].ofs, buf_sz - ctx->items[i].ofs,
					&w, &h, &f, ARCAN_SHMPAGE_VCHANNELS
				);
				if (res){
					char scratch[64];
					snprintf(scratch, 64, "@%"PRIu64": decoded %s [%d * %d]",
						pos + ctx->items[i].ofs, magic[ctx->items[i].magic].ident, w, h);

					draw_text(out, scratch,
						(fontw+1)*2, y, RGBA(0x00,0xff,0x00,0xff));

					y+=fonth+2;

					stbir_resize_uint8(
						res, w, h+y, 0,
						(uint8_t*) &out->vidp[y * out->pitch], out->w, out->h-y, 0,
					4);

					free(res);
					break;
				}
				else{
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

	return xlt_setup("IMG", populate, input, XLT_DYNSIZE, confl) == true ?
		EXIT_SUCCESS : EXIT_FAILURE;
}
