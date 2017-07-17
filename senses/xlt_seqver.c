/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This translator is for debugging / testing purposes using
 * the sequence.bin tests input. It verifies the input buffer and notifies
 * if it is not in incremental + wrap-around order.
 */

#include <inttypes.h>
#include <arcan_shmif.h>
#include "libsenseye.h"
#include "font_8x8.h"

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	if (!buf)
		return false;

	size_t ofs = 0;

	if (out->addr->w != 320 || out->addr->h != 32)
		arcan_shmif_resize(out, 320, 32);

	while (ofs++ < buf_sz)
		if ((uint8_t)(buf[ofs-1]+1) != buf[ofs])
			break;

	draw_box(out, 0, 0, out->addr->w, out->addr->h,
		SHMIF_RGBA(0x00, 0x00, 0x00, 0xff));

	if (ofs < buf_sz){

			FILE* fpek = fopen("dump.raw", "w");
			fwrite(in->vidp, in->addr->w *
				in->addr->h * sizeof(shmif_pixel), 1, fpek);
			fclose(fpek);

		char buf[32];
		snprintf(buf, sizeof(buf), "Failed at %"PRIu64" +%zu (%" PRIu8
			" vs. %" PRIu8 ")", pos, ofs, (uint8_t)(buf[ofs-1]+1), buf[ofs]);

		draw_text(out, buf, 4, 4, SHMIF_RGBA(0xff, 0x00, 0x00, 0xff));
	}
	else
		draw_text(out, "Passed", 4, 4, SHMIF_RGBA(0x00, 0xff, 0x00, 0xff));

	return true;
}

int main(int argc, char** argv)
{
	enum ARCAN_FLAGS confl = SHMIF_CONNECT_LOOP;
	return xlt_setup("SEQUENCE.BIN VERIFY", populate, NULL, XLT_NONE, confl) ==
		true ? EXIT_SUCCESS : EXIT_FAILURE;
}
