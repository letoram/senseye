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
	uint64_t addr, endaddr, offset, inode;
	char perm[6];
 	char device[16];
};

/*
 * refresh the page mapping for a specific process, if >filter< is set, perform
 * additional (possibly costly) tests for reachability and similar properties.
 * Returns NULL on missing pid or access violation.  Not expected to be thread
 * safe.
 */
struct map_descr* memif_mapdescr(PROCESS_ID pid, bool filter, size_t* count);

/*
 * allocate a control context ofr a specific mapping (ent), return NULL on
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
static size_t memif_copy(struct map_ctx*, uint8_t* buf, size_t buf_sz);

/*
 * seek to a specific offset relative to the current ofset, return true or false
 * depending on if the seek operation was successful (within the bounds of the
 * underlying mapping) or not.
 */
static uint64_t memif_seek(struct map_ctx*, int64_t ofs, int mode);
