/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This translator implements a hex-view style representation,
 * supporting regular, color-coded and detailed viewing modes.
 */

#include "xlt_supp.h"
#include "font_8x8.h"
#include <inttypes.h>

enum render_mode {
	RM_SIMPLE = 0,
	RM_COLOR  = 1,
	RM_DETAIL = 2,
	RM_ENDM
};

static enum render_mode def_rm = RM_SIMPLE;

static const char* mode_lut[] = {
	"Simple",
	"Color",
	"Detailed",
	"Error"
};

struct hex_user {
	enum render_mode rm;
	int c_col, c_row;
	int col, row;
};

static bool input(struct arcan_shmif_cont* out, arcan_event* ev)
{
	if (ev->io.datatype == EVENT_IDATATYPE_DIGITAL && out->user){
		struct hex_user* ctx = out->user;
		if (strcmp(ev->label, "UP") == 0)
			ctx->row = ctx->row > 0 ? ctx->row - 1 : 0;
		else if (strcmp(ev->label, "DOWN") == 0)
			ctx->row++;
		else if (strcmp(ev->label, "RIGHT") == 0)
			ctx->col++;
		else if (strcmp(ev->label, "LEFT") == 0)
			ctx->col = ctx->col > 0 ? ctx->col - 1 : 0;
		else if (strcmp(ev->label, "TAB") == 0)
			ctx->rm = ctx->rm+1 >= RM_ENDM ? RM_SIMPLE : ctx->rm + 1;
	}
	else
		;
	return true;
}

static char hlut[16] = {'0', '1', '2', '3', '4', '5',
	'6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};

static inline void draw_ch(struct arcan_shmif_cont* out,
	uint8_t ch, ssize_t col, size_t row)
{
	if (col < 0)
		return;

/* box should indicate alignment */
	draw_box(out, col, row, fontw+2, fonth+2, RGBA(0x00, 0x00, 0x00, 0xff));

/* lookup color against bytevalue if needed */
	shmif_pixel color = RGBA(0xcc, 0xcc, 0xcc, 0xff);

	draw_char(out, hlut[ch >> 4 & 0xf], col, row, color);
	draw_char(out, hlut[ch >> 0 & 0xf], col+fontw+2, row, color);
}

static void draw_header(struct arcan_shmif_cont* out,
	struct hex_user* actx, uint64_t pos, uint8_t pct)
{
	size_t buf_sz = (out->addr->w - 4) / (fontw+2);
	if (buf_sz <= 1)
		return;

	char chbuf[buf_sz];
	snprintf(chbuf, buf_sz, "%s [%d:%d] @ %"PRIx64" %d%%",
		mode_lut[actx->rm], actx->row, actx->col, pos, (int)pct);
	draw_box(out, 0, 0, out->addr->w, fonth+2, RGBA(0x44, 0x44, 0x44, 0xff));
	draw_text(out, chbuf, 2, 2, RGBA(0xff, 0xff, 0xff, 0xff));
}

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	if (!buf){
		free(out->user);
		return false;
	}

	if (!out->user){
		out->user = malloc(sizeof(struct hex_user));
		memset(out->user, '\0', sizeof(struct hex_user));
		((struct hex_user*)out->user)->rm= def_rm;
	}

	draw_box(out, 0, fonth+2,
		out->addr->w, out->addr->h, RGBA(0x00, 0x00, 0x00, 0xff));

/* based on CRLF mode and desired left row / column, forward buf */
	struct hex_user* actx = out->user;
	if (newdata)
		actx->row = actx->col = 0;

	size_t orig_sz = buf_sz;

/* wrap is simpler, just skip number of characters, row size is just
 * aligned with window dimensions */
	size_t sb = actx->col + actx->row * (out->addr->w / (fontw + 2));
	size_t buf_ind = 0;

	if (buf_sz > sb){
		buf_sz -= sb;
		buf += sb;
	}
	else
		buf_sz = 0;

	size_t w_lim = out->addr->w - fontw;

	if (actx->rm == RM_DETAIL)
		w_lim = (w_lim > 68*(fontw+2) ? 68*(fontw+2) : w_lim);

	for (size_t row = fonth+2; row < out->addr->h - fonth; row += fonth + 2)
		for (size_t col = 2; col < w_lim; col += 2*(fontw+2))
			draw_ch(out, buf[buf_ind++], col, row);

	draw_header(out, actx, pos, (float)(orig_sz - buf_sz) / (float)orig_sz * 100.0);
	return true;
}

int main(int argc, char* argv[])
{
	return xlt_setup("hex", populate, input, XLT_DYNSIZE) == true ?
		EXIT_SUCCESS : EXIT_FAILURE;
}
