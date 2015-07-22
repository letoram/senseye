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
	uint64_t ofs;
};

struct map_descr* memif_mapdescr(PROCESS_ID pid, bool filter, size_t* count)
{
	size_t n = 0;
	vm_size_t size = 0;
	size_t ofs = 0;
	vm_address_t address = 0;
	uint32_t nesting_depth = 0;
	mach_msg_type_number_t region_count = 0;
	struct vm_region_submap_info_64 info;

/* figure out number of mappings */
/*
 * pcache[ofs].addr = address;
	 pcache[ofs].endaddr = address + size;
	 pcache[ofs].inode = 0;
	 pcache[ofs].offset = 0;
	 if(info.protection & VM_PROT_READ) pcache[ofs].perm[0] = 'r';
	 if(info.protection & VM_PROT_WRITE) pcache[ofs].perm[1] = 'w';
	 if(info.protection & VM_PROT_EXECUTE) pcache[ofs].perm[2] = 'x';
	 pcache[ofs].device[0] = '\0';
		memset(&info, '\0', sizeof(struct vm_region_submap_info_64));

		while (1) {
			region_count = VM_REGION_SUBMAP_INFO_COUNT_64;
			kr = vm_region_recurse_64(msense.task, &address, &size, &nesting_depth,
					(vm_region_info_64_t)&info, &region_count);

			if(KERN_SUCCESS != kr)
				break;

			if (info.is_submap) {
				nesting_depth++;
				continue;
			}
			else
				break;
		}

		if(KERN_SUCCESS != kr) {
			if(KERN_INVALID_ADDRESS == kr) {
				fprintf(stderr, "Couldn't get infomation for address 0x%lx\n", address);
			}
			break;
		}

		if(size == 0)
			break;

		address += size;
		ofs++;
	}
 */

	task_t task;
	kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
	if(kr != KERN_SUCCESS){
		fprintf(stderr, "Couldn't open task port for pid %d, reason: %s\n",
			(int) pid, mach_error_string(kr));
		return NULL;
	}

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

	return NULL;
}

struct map_ctx* memif_openmapping(PROCESS_ID pid, struct map_descr* ent)
{
	struct map_ctx* res = malloc(sizeof(struct map_ctx));
	res->ofs = 0;
	res->address = ent->addr;
	kern_return_t kr = task_for_pid(mach_task_self(), pid, &res->task);
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

uint64_t memif_seek(struct map_ctx* ctx, int64_t ofs, int mode)
{
	if (mode == SEEK_SET){
		ctx->ofs = ofs;
	}
	else if (mode == SEEK_CUR){
		ctx->ofs += ofs < 0 ?
			(ofs < -(ctx->ofs) ? -(ctx->ofs) : ofs) : ofs;
	}

	return ctx->ofs;
}
