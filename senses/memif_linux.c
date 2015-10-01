/* 2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: Linux / proc implementation of the memif- interface
 */
#define _LARGEFILE64_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <inttypes.h>
#include <stdint.h>
#include <unistd.h>
#include <stdbool.h>
#include <pthread.h>
#include <string.h>
#include <errno.h>
#include <math.h>

#include <sys/types.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/resource.h>

#include "memif.h"

#ifdef DISABLE_WRITE
#define O_MASK O_RONLY
#else
#define O_MASK O_RDWR
#endif

/* lseek interface really is awful, there must be better ways to do this */
static bool seek64(int fd, uint64_t addr)
{
	if (addr > INT64_MAX){
		lseek(fd, 0, SEEK_SET);
		do{
			lseek64(fd, INT64_MAX, SEEK_CUR);
			addr -= INT64_MAX;
		} while (addr > INT64_MAX);
		if (addr)
			lseek64(fd, addr, SEEK_CUR);
		return true;
	}
	else
		return -1 != lseek64(fd, addr, SEEK_SET);
}

struct map_descr* memif_mapdescr(PROCESS_ID pid,
	size_t min_sz, enum memif_filter filter, size_t* count)
{
	int mdescr = -1;
	char wbuf[sizeof("/proc//maps") + 20];
	snprintf(wbuf, sizeof(wbuf), "/proc/%d/maps", (int) pid);
	FILE* fpek = fopen(wbuf, "r");

	if (filter != FILTER_NONE){
		snprintf(wbuf, sizeof(wbuf), "/proc/%d/mem", (int) pid);
		mdescr = open(wbuf, O_MASK);
	}

/* populate list of entries, first get limit */
	for (*count = 0; !feof(fpek); (*count)++)
		while(fgetc(fpek) != '\n' && !feof(fpek))
			;
	fseek(fpek, 0, SEEK_SET);

/* note there is a time-of-check-time-of-use-risk here */
	size_t pcache_sz = *count * sizeof(struct map_descr);
	struct map_descr* pcache = malloc(pcache_sz);
	if (!pcache)
		return NULL;
	memset(pcache, '\0', pcache_sz);

	size_t ofs = 0;
	while(!feof(fpek) && ofs < *count){
		unsigned long long int dadr[4];
		int ret = fscanf(fpek, "%llx-%llx %5s %llx %5s %llx", &dadr[0],
			&dadr[1], pcache[ofs].perm, &dadr[2], pcache[ofs].device, &dadr[3]);

		if (0 == ret){
				while (fgetc(fpek) != '\n' && !feof(fpek))
					;
			continue;
		}

/* usually the file- mapped pages aren't that interesting in this context,
 * so only process entries that have the matching inode set to 0 */
		if (dadr[3] == 0 && dadr[1] > dadr[0] && dadr[1] - dadr[0] > 0){
			if (filter){
				char junk[4096];
				if (!seek64(mdescr, dadr[0]))
					continue;

				if (-1 == read(mdescr, junk, 4096))
					continue;
			}
			pcache[ofs].addr = dadr[0];
			pcache[ofs].endaddr = dadr[1];
			pcache[ofs].sz = dadr[1] - dadr[0];
			if (pcache[ofs].sz > min_sz)
				ofs++;
		}
	}

	if (-1 != mdescr)
		close(mdescr);

	if (ofs <= 1){
		free(pcache);
		*count = 0;
		return NULL;
	}

	*count = ofs-1;
	return pcache;
}

struct map_ctx {
	uint64_t address;
/* due to painful seek semantics, we track ofs separately */
	uint64_t ofs;
	size_t sz;
	int fd;
};

struct map_ctx* memif_openmapping(PROCESS_ID pid, struct map_descr* ent)
{
	char wbuf[sizeof("/proc//mem") + 8];
	snprintf(wbuf, sizeof(wbuf), "/proc/%d/mem", (int) pid);
	int fd = open(wbuf, O_MASK);
	if (-1 == fd){
		fprintf(stderr, "launch_addr(%" PRIx64 ")+%zx open (%s) failed, %s\n",
			ent->addr, ent->sz, wbuf, strerror(errno));
		return NULL;
	}

	if (-1 == lseek64(fd, ent->addr, SEEK_SET)){
		fprintf(stderr, "launch_addr(%" PRIx64 ")+%zx  couldn't seek, %s\n",
			ent->addr, ent->endaddr - ent->addr, strerror(errno));
		close(fd);
		return NULL;
	}

	fprintf(stderr, "launch_addr(%" PRIx64 ")+%zx seek, %s\n",
		ent->addr, ent->endaddr - ent->addr, strerror(errno));
	struct map_ctx* mctx = malloc(sizeof(struct map_ctx));
	mctx->fd = fd;
	mctx->address = ent->addr;
	mctx->sz = ent->sz;
	return mctx;
}

void memif_closemapping(struct map_ctx* map)
{
	if (!map)
		return;

	close(map->fd);
	memset(map, '\0', sizeof(struct map_ctx));
}

bool memif_reset(struct map_ctx* map)
{
	if (map->ofs == 0)
		return false;

	memif_seek(map, 0, SEEK_SET);
	return true;
}

size_t memif_copy(struct map_ctx* map, uint8_t* buf, size_t buf_sz)
{
	if (!map || !buf)
		return 0;

	ssize_t nr = read(map->fd, buf, buf_sz);
	if (nr >= 0){
		map->ofs += nr;
		return nr;
	}
	return 0;
}

bool memif_canwrite(struct map_ctx* ctx)
{
#ifdef DISABLE_WRITE
	return false;
#else
	return true;
#endif
}

size_t memif_write(
	struct map_ctx* ctx, uint64_t ofs, uint8_t* buf, size_t buf_sz)
{
	if (!ctx || !buf)
		return 0;

	uint64_t endaddr = ctx->address + ctx->sz;
/* clamp to range */
	if (ofs < ctx->address || ofs > endaddr)
		return 0;

	buf_sz = (ofs + buf_sz > endaddr) ? endaddr - ofs : buf_sz;
	memif_seek(ctx, ofs, SEEK_SET);

	int64_t tot = 0;
	while (buf_sz){
		ssize_t nw = write(ctx->fd, buf, buf_sz);
		if (-1 == nw){
			if (errno == EAGAIN || errno == EINTR)
				continue;
			else
				break;
		}
		tot += nw;
		buf_sz -= nw;
		buf += nw;
	}

	memif_seek(ctx, -1 * tot, SEEK_CUR);
	return tot;
}

uint64_t memif_addr(struct map_ctx* ent)
{
	return ent->address + ent->ofs;
}

/* lseek64 and friends don't really work here because of off64_t size
 * limitations, we need to dive into llseek */
uint64_t memif_seek(struct map_ctx* ent, int64_t ofs, int mode)
{
	int64_t newofs = ofs;

	if (mode == SEEK_CUR){
		newofs += ent->ofs;
		if (newofs < 0)
			newofs = 0;
	}

	newofs = newofs >= ent->sz ? 0 : newofs;

	if (seek64(ent->fd, ent->address + newofs))
		ent->ofs = newofs;

	return ent->address + ent->ofs;
}
