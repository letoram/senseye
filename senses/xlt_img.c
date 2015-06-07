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
	VIEW_LIST = 0,
	VIEW_AUTO = 1,
	VIEW_MANUAL = 2,
	VIEW_LAST = 3
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

struct {
	char ident[8];
	uint8_t buf[10];
	size_t used;
} magic[] = {
	{
		.ident = "GIF87",
		.buf = {0x47, 0x49, 0x46, 0x38, 0x37, 0x61},
		.used = 6
	},
	{
		.ident = "GIF89",
		.buf = {0x47, 0x49, 0x46, 0x38, 0x39, 0x61},
		.used = 6
	},
	{
		.ident = "PNG",
		.buf = {0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a},
		.used = 8
	},
	{
		.ident = "BMP",
		.buf = {0x42, 0x4d},
		.used = 2
	}
};

static bool input(struct arcan_shmif_cont* out, arcan_event* ev)
{

	struct xlti_ctx* ctx = out->user;
	if (strcmp(ev->io.label, "TAB") == 0){
		ctx->current = (ctx->current + 1) % VIEW_LAST;
		return true;
	}
	else if (strcmp(ev->io.label, "ENTER") == 0 && ctx->found != -1){
		ctx->last = ctx->current;
		ctx->current = VIEW_MANUAL;
	}
	else
		return false;

	return true;
}

/*
 * Return a list of possible starting offset and magic[] indexes for the hairy
 * case of supporting decoding and detection across sample window edges, we'll
 * need some buffer support class that is invalidated across seeks. Something
 * for later.
 */
struct scanres {
	uint8_t magic;
	size_t ofs;
};
static size_t scan(size_t buf_sz, uint8_t* buf, struct scanres** out)
{
	size_t magic_count = sizeof(magic) / sizeof(magic[0]);
	size_t oc[sizeof(magic)/sizeof(magic[0])] = {0};

	for (size_t i = 0; i < buf_sz; i++)
		for (size_t j = 0; j < magic_count; j++)
			if (buf[i] == magic[j].buf[ oc[j] ]){
				oc[j]++;
				if (oc[j] >= magic[j].used){
					printf("Match: %s\n", magic[j].ident);
					oc[j] = 0;
				}
			}
			else
				oc[j] = 0;

	*out = NULL;
	return 0;
}

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	if (!buf){
		free(out->user);
		out->user = NULL;
		return false;
	}

/* we work with the entire buffer at once, so only scan when
 * something has changed */
	if (!newdata)
		return false;

	struct xlti_ctx* ctx = out->user;
	if (!out->user){
		ctx = out->user = malloc(sizeof(struct xlti_ctx));
		memset(ctx, sizeof(struct xlti_ctx), '\0');
		ctx->current = VIEW_AUTO;
		ctx->found = -1;
	}

/* depending on view mode, we autodecode first or just list matches */
	struct scanres* res;
	scan(buf_sz, buf, &res);

	return false;
}

int main(int argc, char** argv)
{
	enum SHMIF_FLAGS confl = SHMIF_CONNECT_LOOP;

	return xlt_setup("IMG", populate, input, XLT_NONE, confl) == true ?
		EXIT_SUCCESS : EXIT_FAILURE;
}
