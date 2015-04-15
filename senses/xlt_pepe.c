#include "xlt_supp.h"
#include "font_8x8.h"
#include <inttypes.h>

static bool input(struct arcan_shmif_cont* cont, arcan_event* ev)
{
	return false;
}

static bool populate(bool data, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
/* PE parser:
 * scan for magic header, when found --
 *  check offset and possibly invalidate (if new data)
 *  send to ParsePEFromFile (but need to patch to use memory buffer)
 */
	return false;
}

int main(int argc, char* argv[])
{
	return xlt_setup("PE", populate, input, XLT_DYNSIZE) == true ?
		EXIT_SUCCESS : EXIT_FAILURE;
}
