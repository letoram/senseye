/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This translator implements a hex-view style representation,
 * supporting regular, color-coded and detailed viewing modes.
 */

#include <arcan_shmif.h>
#include "libsenseye.h"
#include "font_8x8.h"
#include <inttypes.h>
#include <ctype.h>
#include <assert.h>

/* generate 256 width LUT */
#include "xlt_hex_color.h"
shmif_pixel color_lut[256];

enum render_mode {
	RM_SIMPLE = 0,
	RM_COLOR  = 1,
	RM_DETAIL_SIMPLE = 2,
	RM_DETAIL_COLOR  = 3,
	RM_ENDM
};

static enum render_mode def_rm = RM_SIMPLE;

static const char* mode_lut[] = {
	"Simple",
	"Color",
	"Detailed/Simple",
	"Detailed/Color",
	"Error"
};

struct hex_user {
	enum render_mode rm;
	int last_w, last_h;
	int col, row;
};

#define ROW_WIDTH(X) ( ((X) - 2 * (fontw+2)) / (3*(fontw+2)) + 1 )

static bool input(struct arcan_shmif_cont* out, arcan_event* ev)
{
	if (ev->io.datatype == EVENT_IDATATYPE_DIGITAL && out->user){
		struct hex_user* ctx = out->user;
		if (strcmp(ev->io.label, "UP") == 0){
			if (ctx->row > 0){
				ctx->row--;
			}
			else
				ctx->col = 0;
		}
		else if (strcmp(ev->io.label, "DOWN") == 0)
			ctx->row++;
		else if (strcmp(ev->io.label, "RIGHT") == 0){
			if (ctx->col + 1 > ROW_WIDTH(out->addr->w)){
				ctx->row++;
				ctx->col = 0;
			}
			else
				ctx->col++;
		}
		else if (strcmp(ev->io.label, "LEFT") == 0){
			if (ctx->col == 0){
				if (ctx->row > 0){
					ctx->row--;
					ctx->col = ROW_WIDTH(out->addr->w);
				}
			}
			else
				ctx->col--;
		}
		else if (strcmp(ev->io.label, "TAB") == 0)
			ctx->rm = ctx->rm+1 >= RM_ENDM ? RM_SIMPLE : ctx->rm + 1;
	}
	else
		;
	return true;
}

static char hlut[16] = {'0', '1', '2', '3', '4', '5',
	'6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};

static inline void draw_ch(struct arcan_shmif_cont* out,
	struct hex_user* actx, uint8_t ch, ssize_t col, size_t row)
{
	if (col < 0)
		return;

/* box should indicate alignment */
	draw_box(out, col,
		row, 2*(fontw+2), fonth+1, SHMIF_RGBA(0x00, 0x00, 0x00, 0xff));

/* lookup color against bytevalue if needed */
	shmif_pixel color = actx->rm == RM_SIMPLE || actx->rm == RM_DETAIL_SIMPLE ?
		SHMIF_RGBA(0xcc, 0xcc, 0xcc, 0xff) : color_lut[ch];

	draw_char(out, hlut[ch >> 4 & 0xf], col, row, color);
	draw_char(out, hlut[ch >> 0 & 0xf], col+fontw+2, row, color);
}

static void draw_header(struct arcan_shmif_cont* out,
	struct hex_user* actx, uint64_t pos)
{
	size_t buf_sz = (out->addr->w - 4) / (fontw+2);
	if (buf_sz <= 1)
		return;

	char chbuf[buf_sz];
	snprintf(chbuf, buf_sz, "%s @ %"PRIx64, mode_lut[actx->rm], pos);
	draw_box(out, 0, 0, out->addr->w, fonth+2, SHMIF_RGBA(0x44, 0x44, 0x44, 0xff));
	draw_text(out, chbuf, 1, 1, SHMIF_RGBA(0xff, 0xff, 0xff, 0xff));
}

/*
 * dec: val,  u8: 128, u16:  65535, u32: 4,294,967,295
 * asc: 'a',  s8:-127, s16: -32768, s32:-2,147,483,648
 * u64:
 * s64:
 * float: 0.123456 double: 0.133131313131
 */

/* currently lack font support for drawing more exotic stuff (unicode, ...) */
static const int reserved_rows = 6;
static void draw_footer(struct arcan_shmif_cont* out, struct hex_user* actx,
	uint8_t* buf, size_t buf_sz)
{
	int y = (int)out->addr->h - (reserved_rows * fonth + 2);
	size_t chw = out->addr->w / (fontw / 2);

	if (y < 0 || chw == 0)
		return;

	struct {
		union {
			uint8_t l8;
			int8_t s8;
			uint16_t l16;
			int16_t s16;
			uint32_t l32;
			int32_t s32;
			uint64_t l64;
			int64_t s64;
			float f;
			double lf;
		};
	} vbuf = {.l64 = 0};

	memcpy(&vbuf, buf, buf_sz < sizeof(vbuf) ? buf_sz : sizeof(vbuf));

	draw_box(out, 0, y, out->addr->w,
		out->addr->h - y, SHMIF_RGBA(0x44, 0x44, 0x44, 0xff));
	y+=2;

/* a little bit messy as we want to have the labels in one color
 * and the actual data in another */

	char work[chw];
#define DO_ROW(label, data, ...) { snprintf(work, chw, label); \
	draw_text(out, work, 1, y, SHMIF_RGBA(0xff, 0xff, 0xff, 0xff));\
	snprintf(work, chw, data, __VA_ARGS__);\
	draw_text(out, work, 1, y, SHMIF_RGBA(0x44, 0xff, 0x44, 0xff));\
	y += fonth + 2;\
	}

	char flt_ch = isascii(*buf) && *buf != '\n' && *buf != '\0' ? *buf : ' ';

	const char row1_label[] = "ASCII:  x8:     x16:       x32:            x64:";
	const char row1_data[] = "      %c    %4"PRIxLEAST8"     %6"PRIxLEAST16
		"     %11"PRIxLEAST32"     %20"PRIxLEAST64;
	DO_ROW(row1_label, row1_data, flt_ch, vbuf.l8, vbuf.l16, vbuf.l32, vbuf.l64);

	const char row2_label[] = "        u8:     u16:       u32:            u64:";
	const char row2_data[] = "           %4"PRIuLEAST8"     %6"PRIuLEAST16
		"     %11"PRIuLEAST32"     %20"PRIuLEAST64;
	DO_ROW(row2_label, row2_data, vbuf.l8, vbuf.l16, vbuf.l32, vbuf.l64);

	const char row3_label[] = "        s8:     s16:       s32:            s64:";
	const char row3_data[] = "           %4"PRIiLEAST8"     %6"PRIiLEAST16
		"     %11"PRIiLEAST32"     %20"PRIiLEAST64;
	DO_ROW(row3_label, row3_data, vbuf.s8, vbuf.s16, vbuf.s32, vbuf.s64);

	const char row4_label[] = "Float:                  Double:";
	const char row4_data[]  = "       %12g            %g";
	DO_ROW(row4_label, row4_data, vbuf.f, vbuf.lf);

#undef DO_ROW
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
		out->addr->w, out->addr->h, SHMIF_RGBA(0x00, 0x00, 0x00, 0xff));

	struct hex_user* actx = out->user;
	if (newdata || actx->last_w != out->addr->w || actx->last_h != out->addr->h){
		actx->row = actx->col = 0;
		actx->last_w = out->addr->w;
		actx->last_h = out->addr->h;
	}

	size_t buf_ind = 0;
	size_t n_rows = (out->addr->h - fonth+2) / (fonth+2);
	size_t footer = actx->rm >= RM_DETAIL_SIMPLE ? reserved_rows : 0;
	if (footer >= n_rows)
		footer = 0;

	size_t ch_w = 3*(fontw+2);

/* we ignore 'scrolling outside buffer' cases, meta+mouse motion is
 * more useful - for the ascii xlt we had to be slightly more flexible
 * due to possibly infinitely long lines */
	if (actx->row+1 > (n_rows - footer))
		actx->row = 0;

	int cursor_ind = (ROW_WIDTH(out->addr->w) * actx->row + actx->col);
	size_t ylim = out->addr->h - footer * (fonth+2);
	size_t xlim = ROW_WIDTH(out->addr->w) * ch_w;

	for (size_t row = fonth+3; row < ylim; row += fonth + 2)
		for (size_t col = 2; col < xlim && buf_ind < buf_sz; col += ch_w){

/* underline current position and mark related sizes, e.g. +2, 4, 8 */
			if (buf_ind == cursor_ind)
				draw_box(out, col-1, row-1, ch_w+2, fonth+3, SHMIF_RGBA(0x00, 0xff, 0x00, 0xff));
			else if (buf_ind == cursor_ind+1)
				draw_box(out, col-1, row-1, ch_w+2, fonth+3, SHMIF_RGBA(0xff, 0xff, 0x00, 0xff));
			else if (buf_ind > cursor_ind && buf_ind <= cursor_ind+3)
				draw_box(out, col-1, row-1, ch_w+2, fonth+3, SHMIF_RGBA(0xff, 0x00, 0x00, 0xff));
			else if (buf_ind > cursor_ind+3 && buf_ind <= cursor_ind+7)
				draw_box(out, col-1, row-1, ch_w+2, fonth+3, SHMIF_RGBA(0xff, 0x00, 0xff, 0xff));

			draw_ch(out, actx, buf[buf_ind++], col, row);
		}

	draw_header(out, actx, pos+cursor_ind);
	if(actx->rm >= RM_DETAIL_SIMPLE && footer && cursor_ind < buf_sz)
		draw_footer(out, actx, &buf[cursor_ind], buf_sz - cursor_ind);

	return true;
}

int main(int argc, char* argv[])
{
/* nice namespace pollution GIMP-export */
	enum ARCAN_FLAGS confl = SHMIF_CONNECT_LOOP;
	if (width != 256){
		printf("error, xlt_hex was built with a broken color "
			"table, fix xlt_hex_color.h\n");
		return EXIT_FAILURE;
	}

	for (size_t i = 0; i < 256; i++){
		uint8_t pixel[3];
		HEADER_PIXEL(header_data, pixel);
		color_lut[i] = SHMIF_RGBA(pixel[0], pixel[1], pixel[2], 0xff);
	}

	return xlt_setup("hex", populate, input, XLT_DYNSIZE, confl) == true ?
		EXIT_SUCCESS : EXIT_FAILURE;
}
