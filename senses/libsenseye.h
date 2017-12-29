/*
 * (C)opyright, 2014-2017 Björn Ståhl
 * License: BSD 3-clause, see the COPYING file in the senseye source repo.
 * Reference: senseye.arcan-fe.com
 *
 * Description:
 * This interface is used to define a senseye 'sensor', a data source that
 * has a control window and one or more data windows. The contents and the
 * behavior of the control window is up to the sensor design itself, while
 * the data window is regulated via the 'senseye_ch' struct.
 *
 * Internally, the senseye_ch samples a data source based on user controls
 * with some minor statistics, space mapping and so on.
 *
 * It builds on the 'SHMIF' API that is used for interfacing with an arcan
 * instance that runs the 'senseye' appl (for UI, controls / coordination)
 *
 * This interface is also used to define a 'translator' which works on the
 * processed data coming from the sensor via the UI. These are used to add
 * a high-level view of the data, and as such require more interaction and
 * rendering work. It is thus recommended to use in conjunction with 'TUI'
 * which is a text-oriented UI library as part of Arcan SHMIF.
 *
 * Look at the source code for 'sense_example' for a skeleton of a working
 * sensor, and 'xlt_example' for a skeleton of a working translator.
 */

#ifndef HAVE_SENSEYE
#define HAVE_SENSEYE

#ifndef HAVE_ARCAN_SHMIF
	struct arcan_event;
#endif

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

struct rwstat_ch;
struct senseye_priv;

struct senseye_ch {
/* Invoke periodically to flush the internal event queue of the channel */
	void (*pump)(struct senseye_ch*);

/* Provide an input buffer for consumption. Will return the number of bytes
 * that was consumed, which will be <= [ntw] */
	ssize_t (*data)(struct senseye_ch*, const void* buf, size_t ntw);

/* Close: there was a problem with the data source, shut down.
 * [msg] is optional but MAY refer to a user-readable error message */
	void (*close)(struct senseye_ch*, const char* msg);

/* Flush: enough data has been provided that internal tracking, statistics,
 * etc. can be computed and synchronized (expensive). */
	void (*flush)(struct senseye_ch*);

/* little need to manipulate these manually, but provided for advanced use */
	off_t (*seek)(struct senseye_ch*, long long);
	void (*queue)(struct senseye_ch*, struct arcan_event*);
	struct rwstat_ch* in;
	struct senseye_priv* in_pr;
	int in_handle;
	size_t step_sz;
};

/*
 * refresh and dispatch can be overridden with a matching prototype
 * and will be invoked as part of the _pump() loop when necessary
 */
struct senseye_cont {
	bool (*refresh)(struct senseye_cont*, shmif_pixel* vidp, size_t w, size_t h);
	void (*dispatch)(struct senseye_cont*, arcan_event* ev);
	struct arcan_shmif_cont* (*context)(struct senseye_cont* c);

	void* tag;
	struct senseye_priv* priv;
};

/*
 * Initialization - open the connection to the arcan session that is running
 * senseye. If the connection path argument is NULL, the default 'senseye'
 * key will be used, or whatever ARCAN_CONNPATH override it is that has been
 * set.
 *
 * Will return a fdsense context in which new data channels can be opened.
 * To implement event handlers, replace the .refresh and the .dispatch
 * members.
 */
bool senseye_connect(const char* key, FILE* logout,
	struct senseye_cont*, struct arg_arr**, enum ARCAN_FLAGS flags);

/*
 * treat as main-loop, implements the main control channel semantics for
 * connection with the UI (override the default refresh and event handlers in
 * the structure if needed)
 *
 * senseye_pump -> (wait or poll event?) -> TARGET_EXIT : dispatch
 *           <-------------false ------------|                |
 *                                                            |
 *           <------------- true ------[ctx:refresh] <-y--STEPFRAME
 *           <------------- true ----- [ctx:dispatch] <-y-----|
 */
bool senseye_pump(struct senseye_cont*, bool block);

/*
 * [ident] is just a hint that will be used as a textual identifier in the
 * user-interface. [base] is the initial dimensions of the data transfers to
 * the UI (should be a square power of 2 and larger than 32).
 *
 * Will maintain the event loop shown in pump until the request has been
 * handled. Will return NULL if the the request was rejected or if there is
 * already a request pending.
 */
struct senseye_ch* senseye_open(
	struct senseye_cont* cont, const char* const ident, size_t base);

struct senseye_ch* senseye_update_identity(
	struct senseye_cont* cont, const char* const ident);

/*
 * Indicate that the primary connection accepts a certain specialized input
 * See shmif_tuisym for list of valid symbols. Note that it's an arcan
 * shmif context, so it has to be extracted from the senseye_ch or the
 * senseye_cont.
 */
void senseye_register_input(
	struct arcan_shmif_cont*, const char* label,
		const char* descr, int default_sym, unsigned modifiers);

bool senseye_resize(struct senseye_cont*, size_t neww, size_t newh);

/*
 * TRANSLATOR functions
 */

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

#endif
