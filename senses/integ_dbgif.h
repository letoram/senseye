/* Copyright 2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This header is for abstracting the external- tool integrator
 * used to provide both translation and data sensor in one loop / tool for
 * working with tools e.g. IDA Pro.
 */

struct integ_ctx;

/*
 * semantics of rd depends on underlying implementation, suggestion:
 * file://path, process://pid, expose semantics in integ_help
 */
struct integ_ctx* integ_open(const char* rd);

/*
 * drop resources associated with integ_ctx, clear/reset
 */
void integ_close(struct integ_ctx**);

/*
 * Describe open arguments, active backend identification etc. user-readable
 */
void integ_help(FILE*);

/*
 * Set absolute data position (if supported and available)
 */
int integ_seek_abs(struct integ_ctx*, uint64_t pos);

/*
 * Set relative
 */
int integ_seek_rel(struct integ_ctx*, uint64_t step, int dir);

/*
 *
 */
ssize_t integ_read(struct integ_ctx* ctx, uint8_t* buf, size_t ntr);

/*
 * -1 fail (not supported)
 *  0 bkpt off
 *  1 bkpt on (soft)
 *  2 bkpt on (hw)
 */
int toggle_bkpt(uint64_t pos, bool watch);

/*
 * Request a list of page-table entries that describe different known
 * positions, type and similar information to assist in navigating large
 * address spaces.
 */
enum attr_mask {
	ATTR_READ = 0,
	ATTR_WRITE,
	ATTR_EXECUTE,
	ATTR_SPECIAL
};

struct pgtbl_ent {
	uint64_t beg_addr;
	uint64_t size;
	const char* label;
	enum attr_mask attr;
};
struct pgtbl_ent* integ_pagetbl(struct integ_ctx*, size_t* count);

/*
 * NULL on fail, contents of pos_info is tied to integ_ctx management,
 * no aliasing of inf_ strings - internal memory management
 */
enum pos_mask {
	PINF_FLAT = 0,
	PINF_NESTED
};
struct pos_info {
	size_t width;
	shmif_pixel col;
	const char* inf_short;
	const char* inf_detail;
	enum pos_mask attr;
};
struct pos_info* integ_sample_pos(struct integ_ctx*, uint64_t pos);
