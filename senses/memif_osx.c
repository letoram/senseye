/* 2015, Joshua Hill, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: OSX implementation of the memif- interface
 */

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
#include <mach/mach.h>

#include "memif.h"

struct map_ctx {
	vm_address_t address;
	task_t task;
	size_t sz;
	uint64_t ofs;
};

static size_t get_vmmap_entries(task_t task) {
	size_t n = 0;
	vm_size_t size = 0;
	vm_address_t address = 0;
	kern_return_t kr = KERN_SUCCESS;

	while (1) {
		uint32_t nesting_depth;
		mach_msg_type_number_t count;
		struct vm_region_submap_info_64 info;

		count = VM_REGION_SUBMAP_INFO_COUNT_64;
		kr = vm_region_recurse_64(task,
			&address, &size, &nesting_depth, (vm_region_info_64_t)&info, &count);
		if (kr == KERN_INVALID_ADDRESS) {
				break;
		} else if (kr) {
			mach_error("vm_region:", kr);
			break; /* last region done */
		}
		if (info.is_submap) {
			nesting_depth++;
		} else {
			address += size;
			n++;
		}
	}

	return n;
}

struct map_descr* memif_mapdescr(PROCESS_ID pid,
	size_t min_sz, enum memif_filter filter, size_t* outc)
{
	task_t task;
	kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
	if(kr != KERN_SUCCESS){
		fprintf(stderr, "Couldn't open task port for pid %d, reason: %s\n",
			(int) pid, mach_error_string(kr));
		return NULL;
	}

	size_t count = get_vmmap_entries(task);
	if (0 == count)
		return NULL;

	struct map_descr* pcache = malloc(sizeof(struct map_descr) * count);
	memset(pcache, '\0', sizeof(struct map_descr) * count);

	size_t ofs = 0;
	vm_size_t size = 0;
	vm_address_t address = 0;
	uint32_t nesting_depth = 0;
	mach_msg_type_number_t region_count = 0;
	struct vm_region_submap_info_64 info;

	while(ofs < count){
		region_count = 0;
		nesting_depth = 0;
		memset(&info, '\0', sizeof(struct vm_region_submap_info_64));

		while(1){
			region_count = VM_REGION_SUBMAP_INFO_COUNT_64;
			kr = vm_region_recurse_64(task, &address, &size, &nesting_depth,
					(vm_region_info_64_t)&info, &region_count);

			if(KERN_SUCCESS != kr)
				break;

			if (info.is_submap){
				nesting_depth++;
				continue;
			}
			else
				break;
		}

		if(KERN_SUCCESS != kr){
			if(KERN_INVALID_ADDRESS == kr){
				fprintf(stderr, "Couldn't get infomation for address 0x%lx\n", address);
			}
			break;
		}

		if (size == 0)
			break;

		if (size < min_sz)
			goto step;

		if (filter != FILTER_NONE){
			uint8_t buf[2048];
			vm_size_t nr;
			kern_return_t kr = vm_read_overwrite(task,
				address, 2048, (vm_address_t) buf, &nr);

			if (kr != KERN_SUCCESS)
				goto step;
		}

		pcache[ofs].addr = address;
		pcache[ofs].endaddr = address + size;
		pcache[ofs].perm[0] = info.protection & VM_PROT_READ ? 'r' : ' ';
		pcache[ofs].perm[1] = info.protection & VM_PROT_WRITE ? 'w' : ' ';
		pcache[ofs].perm[2] = info.protection & VM_PROT_EXECUTE ? 'x' : ' ';
		pcache[ofs].device[0] = '\0';

		address += size;
		ofs++;
		continue;
step:
		address += size;
		count--;
	}

	*outc = ofs;
	return pcache;
}

bool memif_canwrite(struct map_ctx* ctx)
{
	return false;
}

size_t memif_write(struct map_ctx* ctx, uint64_t ofs, uint8_t* buf, size_t buf_sz)
{
	return 0;
}

struct map_ctx* memif_openmapping(PROCESS_ID pid, struct map_descr* ent)
{
	struct map_ctx* res = malloc(sizeof(struct map_ctx));
	res->ofs = 0;
	res->address = ent->addr;
	kern_return_t kr = task_for_pid(mach_task_self(), pid, &res->task);
	res->sz = ent->endaddr - ent->addr;
/* test res, if fail, return NULL and clean */
	return res;
}

void memif_closemapping(struct map_ctx* ctx)
{
	if (ctx){
		memset(ctx, '\0', sizeof(struct map_ctx));
		free(ctx);
	}
}

/*
 * (for when we add process control:)
 * kr = task_resume(msense.task);
	if(KERN_SUCCESS != kr) {
		fprintf(stderr, "Couldn't resume our task with pid %d, reason %s\n",
			msense.pid, mach_error_string(kr));
	kr = task_suspend(msense.task);
	if(KERN_SUCCESS != kr) {
		fprintf(stderr, "Couldn't suspend task from pid %d, reason %s\n",
			(int) msense.pid, mach_error_string(kr));
		return EXIT_FAILURE;
	}
 */

size_t memif_copy(struct map_ctx* ctx, uint8_t* buffer, size_t size)
{
	kern_return_t kr = KERN_SUCCESS;
	vm_size_t count = 0;

	size_t to_read = 0;
	size_t have_read = 0;

	while(size > 0){
		to_read = (size > 0x800) ? 0x800 : size;
		count = to_read;

		kr = vm_read_overwrite(ctx->task,
			ctx->address + ctx->ofs, to_read, (vm_address_t) buffer, &count);

		if(kr != KERN_SUCCESS){
			fprintf(stderr, "Couldn't read 0x%zx bytes from 0x%"PRIxPTR"\n",
				size, (uintptr_t) (ctx->address + ctx->ofs));
			return 0;
		}
		else if(count != to_read){
			fprintf(stderr, "Weird read 0x%zx bytes from 0x%"PRIxPTR"\n",
				size, (uintptr_t) (ctx->address + ctx->ofs));
		}

		ctx->ofs += to_read;
		size -= to_read;
		have_read += to_read;
		buffer += to_read;
	}

	return have_read;
}

bool memif_reset(struct map_ctx* ent)
{
	if (ent->ofs){
		ent->ofs = 0;
		return true;
	}
	return false;
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

	ent->ofs = newofs >= ent->sz ? 0 : newofs;

	return ent->address + ent->ofs;
}
