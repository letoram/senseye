/*
 * Copyright 2015, Björn Ståhl
 * License: 3-Claused BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: Support implementation for the often used scenario of
 * connecting to senseye and registering, spawning a new thread for each
 * requested translation segment, unpacking input data, tracking offset,
 * flushing queues, shutting down etc.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

#include <arcan_shmif.h>
#define RGBA(r,g,b,a) SHMIF_RGBA(r,g,b,a)
/*
 * called every time there is input to process, return true if the output
 * segment should be updated.  called with a NULL buf on cleanup.
 */
typedef bool (*xlt_populate)(bool newdata, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf);

/*
 * similar to xlt populate, but aligned to the base of the buffer (not
 * the marker position) and provides details on the zoomed range relative
 * to [in].
 */
struct xlt_session;
typedef bool (*xlt_overlay)(bool newdata, struct arcan_shmif_cont* in,
	int zoom_area[4], struct arcan_shmif_cont* overlay,
	struct arcan_shmif_cont* out,
	uint64_t pos, size_t buf_sz, uint8_t* buf,
	struct xlt_session*
);

/*
 * called when there is an event that should be forwarded,
 * i.e. not handled by the wrapper. Return true if the input requires
 * a new update pass, otherwise false.
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
	XLT_DYNSIZE = 1,
	XLT_FORKABLE = 2
};

/*
 * Simplified setup, will invoke populate/input (possibly from
 * different threads (or processes if forkable is set).
 */
bool xlt_setup(const char* ident, xlt_populate, xlt_input,
	enum xlt_flags, enum ARCAN_FLAGS confl);

/*
 * Manual operation, use xlt_open to make the initial connection
 * and register with the 'ident' tag. Will return a preliminary
 * context or NULL on connection failure.
 */
struct xlt_context;
struct xlt_context* xlt_open(const char* ident,
	enum xlt_flags, enum ARCAN_FLAGS confl);

void xlt_config(struct xlt_context*,
	xlt_populate, xlt_input,
/* seperate input function for overlay */
	xlt_overlay, xlt_input);

/*
 * Used on an input context that is assigned as an overlay,
 * get the x and y coordinates that corresponds to the specified
 * ofset, taking packing mode into account.
 */
void xlt_ofs_coord(struct xlt_session* sess,
	size_t ofs, size_t* x, size_t* y);

/*
 * pump the context event loop manually, will flush and then
 * return true as soon as possible. Returns false on a dead or
 * broken session.
 */
bool xlt_pump(struct xlt_context*);

/*
 * will return only after the parent connection has been terminated.
 */
bool xlt_wait(struct xlt_context*);

/*
 * Kill process group (if multiprocess- fork), drop threads
 * and free up related resources. The object pointed to will be
 * undefined after a call to this function.
 */
void xlt_free(struct xlt_context**);
