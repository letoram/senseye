#include "memif.h"

#define _LARGEFILE64_SOURCE

struct map_descr* memif_mapdescr(pid_t pid, bool filter, size_t* count)
{
	static int mdescr = -1;
	char wbuf[sizeof("/proc//maps") + 20];
	snprintf(wbuf, sizeof(wbuf), "/proc/%d/maps", (int) msense.pid);
	FILE* fpek = fopen(wbuf, "r");

	if (-1 == mdescr && filter){
		snprintf(wbuf, sizeof(wbuf), "/proc/%d/mem", (int) msense.pid);
		mdescr = open(wbuf, O_RDONLY);
	}

/* populate list of entries, first get limit */
	for (*count = 0; !feof(fpek); (*count)++)
		while(fgetc(fpek) != '\n' && !feof(fpek))
			;
	fseek(fpek, 0, SEEK_SET);

/* note there is a time-of-check-time-of-use-risk here */
	size_t pcache_sz = *count * sizeof(struct page);
	struct page* pcache = malloc(pcache_sz);
	memset(pcache, '\0', pcache_sz);

	size_t ofs = 0;
	while(!feof(fpek) && ofs < *count){
		int ret = fscanf(fpek, "%llx-%llx %5s %llx %5s %llx",
			&pcache[ofs].addr, &pcache[ofs].endaddr, pcache[ofs].perm,
			&pcache[ofs].offset, pcache[ofs].device, &pcache[ofs].inode);

		if (0 == ret){
				while (fgetc(fpek) != '\n' && !feof(fpek))
					;
			continue;
		}

/* usually the file- mapped pages aren't that interesting in this context */
		if (!msense.skip_inode || (msense.skip_inode && pcache[ofs].inode == 0)){
			if (filter){
				char junk[4096];
				if (-1 == lseek64(mdescr, pcache[ofs].addr, SEEK_SET))
					continue;
				if (-1 == read(mdescr, junk, 4096))
					continue;
			}
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

struct map_ctx;
struct map_ctx* memif_openmapping(PROCESS_ID pid, struct page_descr* ent)
{
	char wbuf[sizeof("/proc//mem") + 8];
	snprintf(wbuf, sizeof(wbuf), "/proc/%d/mem", (int) msense.pid);
	int fd = open(wbuf, O_RDONLY);
	if (-1 == fd){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx open (%s) failed, %s\n",
			base, size, wbuf, strerror(errno));
		return NULL;
	}

	if (-1 == lseek64(fd, base, SEEK_SET)){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx  couldn't seek, %s\n",
			base, size, strerror(errno));
		close(fd);
		return NULL;
	}

	struct map_ctx* mctx = malloc(sizeof struct map_ctx);
	mctx->fd = fd;
	return mctx;
}

void memif_closemapping(struct map_ctx* map)
{

}

static size_t memif_copy(struct map_ctx* map, uint8_t* buf, size_t buf_sz)
{

}

static bool memif_seek(struct map_ctx* map, uint64_t ofs)
{

}
