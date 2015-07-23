/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This header is for abstracting the os- level details for the
 * memory sensor, currently covering reading- memory only.  This will, in
 * future versions, cover injection and process control as well.
 */

#define PROCESS_ID pid_t

struct map_descr {
	uint64_t addr, endaddr;
	size_t sz;
	char perm[6];
 	char device[16];
};

/*
 * refresh the page mapping for a specific process, if >filter< is set, perform
 * additional (possibly costly) tests for reachability and similar properties.
 * Returns NULL on missing pid or access violation.
 */
struct map_descr* memif_mapdescr(PROCESS_ID pid, bool filter, size_t* count);

/*
 * allocate a control context for a specific mapping (ent), return NULL on
 * access violation or dated/incorrect mapping.
 */
struct map_ctx;
struct map_ctx* memif_openmapping(PROCESS_ID pid, struct map_descr* ent);

/*
 * release any metadata associated with a mapping
 */
void memif_closemapping(struct map_ctx*);

/*
 * copy up to buf_sz bytes from the current position in map_ctx into the buffer
 * pointed to by buf. return the actual number of bytes read.
 */
size_t memif_copy(struct map_ctx*, uint8_t* buf, size_t buf_sz);

/*
 * reset to initial _openmapping state, return true if this imposed any changes,
 * false if we already are at such a state.
 */
bool memif_reset(struct map_ctx*);

/*
 * get the current working address, this is an absolute position rather than
 * relative to the ctx and assumes a linear address space.
 */
uint64_t memif_addr(struct map_ctx*);

/*
 * seek to a specific offset relative to the mapping context, mode can be either
 * SEEK_SET or SEEK_CUR. Returns actual current position relative to the base
 * of the mapping context and will wrap around the size of the mapping.
 */
uint64_t memif_seek(struct map_ctx*, int64_t ofs, int mode);
