/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This translator merely mirrors the contents of the
 * input segment on the output one, optionally with packing.
 */

#include <arcan_shmif.h>
#include "libsenseye.h"

static bool populate(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	if (!buf)
		return false;

	if (in->addr->w != out->addr->w || in->addr->h != out->addr->h)
		arcan_shmif_resize(out, in->addr->w, in->addr->h);

	memcpy(out->vidp, in->vidp, out->addr->w *
		out->addr->h * sizeof(shmif_pixel));

	return true;
}

int main(int argc, char** argv)
{
	enum ARCAN_FLAGS confl = SHMIF_CONNECT_LOOP;
	return xlt_setup("VERIFY", populate, NULL, XLT_NONE, confl) ?
		EXIT_SUCCESS : EXIT_FAILURE;
}
