/*
 * Copyright 2015, Björn Ståhl
 * License: 3-Claused BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: Support implementation for the often used scenario of
 * connecting to senseye and registering, spawning a new thread for
 * each requested translation segment, unpacking input data,
 * tracking offset, flushing queues, shutting down etc.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

#include <arcan_shmif.h>

/*
 * called every time there is input to process,
 * return true if the output segment should be updated.
 * called with a NULL buf on cleanup.
 */
typedef bool (*xlt_populate)(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf);

/*
 * called when there is an event that should be forwarded,
 * i.e. not handled by the wrapper
 */
typedef bool (*xlt_input)(struct arcan_shmif_cont* out, arcan_event* ev);

/*
 * wrap the necessary translator foreplay, will block indefinetely
 *
 * xlt_populate is required,
 * xlt_input may be NULL,
 * void tag may contain state to forward
 *
 * returns true if there was a completed connect / process cycle,
 * false otherwise.
 */
enum xlt_flags {
	XLT_NONE = 0,
	XLT_DYNSIZE = 1
};

bool xlt_setup(const char* ident, xlt_populate, xlt_input, enum xlt_flags);
