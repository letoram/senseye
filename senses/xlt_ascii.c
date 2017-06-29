/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: Simple 7-bit ascii translator
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <arcan_shmif.h>

#include "libsenseye.h"
#include "font_8x8.h"
#include <inttypes.h>

enum linefeed_mode {
	LF_WRAP = 0,
	LF_ACCEPT_CRLF,
	LF_ACCEPT_LF,
	LF_ENDM
};

static const char* mode_lut[] = {
	"Wrap",
	"CR/LF",
	"LF",
	"Error"
};

struct ascii_user {
	int gc;
	enum linefeed_mode lfm;

	int col;
	int row;
};

enum linefeed_mode def_lfm = LF_WRAP;

static bool input(struct arcan_shmif_cont* out, arcan_event* ev)
{
	if (ev->io.datatype == EVENT_IDATATYPE_DIGITAL && out->user){
		struct ascii_user* ctx = out->user;
		if (strcmp(ev->io.label, "UP") == 0)
			ctx->row = ctx->row > 0 ? ctx->row - 1 : 0;
		else if (strcmp(ev->io.label, "DOWN") == 0)
			ctx->row++;
		else if (strcmp(ev->io.label, "RIGHT") == 0)
			ctx->col++;
		else if (strcmp(ev->io.label, "LEFT") == 0)
			ctx->col = ctx->col > 0 ? ctx->col - 1 : 0;
		else if (strcmp(ev->io.label, "TAB") == 0)
			ctx->lfm = ctx->lfm+1 >= LF_ENDM ? 0 : ctx->lfm + 1;
	}
	else
		;
	return true;
}

static inline void draw_ch(struct arcan_shmif_cont* out,
	uint8_t ch, ssize_t col, size_t row)
{
	if (col < 0)
		return;

	draw_box(out, col, row, fontw+2, fonth+2, SHMIF_RGBA(0x00, 0x00, 0x00, 0xff));

	if (ch < 127)
		draw_char(out, ch, col, row, SHMIF_RGBA(0xcc, 0xcc, 0xcc, 0xff));
	else
		draw_box(out, col, row, fontw, fonth, SHMIF_RGBA(0x55, 0x00, 0x00, 0xff));
}

static size_t find_lf(enum linefeed_mode mode, size_t buf_sz, uint8_t* buf)
{
	size_t pos = 0;

	if (mode == LF_ACCEPT_LF){
		while(pos < buf_sz)
			if (buf[pos++] == '\n')
				return pos;
	}
	else if (mode == LF_ACCEPT_CRLF){
		while(pos < buf_sz-1)
			if (buf[pos] == '\r' && buf[pos+1] == '\n')
				return pos + 2;
			else
				pos++;
	}

	return pos;
}

static void draw_header(struct arcan_shmif_cont* out,
	struct ascii_user* actx, uint64_t pos, uint8_t pct)
{
	size_t buf_sz = (out->w - 4) / (fontw+2);
	if (buf_sz <= 1)
		return;

	char chbuf[buf_sz];
	snprintf(chbuf, buf_sz, "%s [%d:%d] @ %"PRIx64" %d%%",
		mode_lut[actx->lfm], actx->row, actx->col, pos, (int)pct);
	draw_box(out, 0, 0, out->w, fonth+2, SHMIF_RGBA(0x44, 0x44, 0x44, 0xff));
	draw_text(out, chbuf, 2, 2, SHMIF_RGBA(0xff, 0xff, 0xff, 0xff));
}

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	if (!buf){
		free(out->user);
		return false;
	}

	struct ascii_user* actx = out->user;
	if (!actx){
		actx = out->user = malloc(sizeof(struct ascii_user));
		memset(actx, '\0', sizeof(struct ascii_user));
		actx->lfm = def_lfm;
		actx->gc = 0xdeadbeef;
	}

	draw_box(out, 0, fonth+2,
		out->w, out->h, SHMIF_RGBA(0x00, 0x00, 0x00, 0xff));

/* based on CRLF mode and desired left row / column, forward buf */
	if (newdata)
		actx->row = actx->col = 0;

	size_t orig_sz = buf_sz;

/* wrap is simpler, just skip number of characters, row size is just
 * aligned with window dimensions */
	if (actx->lfm == LF_WRAP){
		size_t sb = actx->col + actx->row * (out->w / (fontw + 2));
		size_t buf_ind = 0;

		if (buf_sz > sb){
			buf_sz -= sb;
			buf += sb;
		}
		else
			buf_sz = 0;

		for (size_t row = fonth+2; row < out->h - fonth; row += fonth + 2)
			for (size_t col = 2;
				col < out->w - fontw && buf_ind < buf_sz; col += fontw + 2)
					draw_ch(out, buf[buf_ind++], col, row);
	}
	else if (actx->lfm == LF_ACCEPT_CRLF || actx->lfm == LF_ACCEPT_LF){
/* skip first n rows */
		for (int i = 0; i < actx->row && buf_sz > 0; i++){
			size_t count = find_lf(actx->lfm, buf_sz, buf);
			buf_sz -= count;
			buf += count;
		}
/* then draw / sample at offset */
		for (size_t row = fonth+2; row < out->h - fonth; row += fonth + 2){
			size_t nch = find_lf(actx->lfm, buf_sz, buf);
			size_t ind = actx->col;
				for (size_t col = 2;
					col < out->w - fontw && ind < nch; col += fontw + 2)
				draw_ch(out, buf[ind++], col, row);

			buf += nch;
			buf_sz -= nch;
		}
	}

	draw_header(out, actx, pos,
		(float)(orig_sz - buf_sz) / (float)orig_sz * 100.0);
	return true;
}

int main(int argc, char* argv[])
{
	enum ARCAN_FLAGS confl = SHMIF_CONNECT_LOOP;
	return xlt_setup("ASCII", populate, input, XLT_DYNSIZE, confl) == true ?
		EXIT_SUCCESS : EXIT_FAILURE;
}
