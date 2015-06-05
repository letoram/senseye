/*
 * Copyright:
 * 2015, Joshua Hill, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This sensor periodically monitors the memory pages of a process
 * providing data similar to fsense. It is similar to sense_linmem, but using
 * OSX- native calls.
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

#include <arcan_shmif.h>
#include <poll.h>

#include <sys/types.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <mach/mach.h>

#include "sense_supp.h"
#include "font_8x8.h"
#include "rwstat.h"

struct page_ch {
	struct senseye_ch* channel;
	vm_address_t base;
	size_t size;
};

struct {
/* tracing and synchronization */
	bool suspended;
	pid_t pid;
	task_t task;
	pthread_mutex_t plock;
	vm_address_t address;
	off_t offset;

/* cursor tracking */
	ssize_t sel;
	size_t sel_lim, sel_page;
	uintptr_t sel_base;
	size_t sel_size;
	bool skip_inode;

/* external connections */
	struct senseye_cont* cont;
} msense = {
 .skip_inode = true
};

static void update_preview(shmif_pixel ccol);
void* data_loop(void*);

/*
 * attempt to read the requested number of bytes from
 * the process and write it into the buffer
 */
static size_t task_read(vm_address_t addr, void* buffer, size_t size)
{
	kern_return_t kr = KERN_SUCCESS;
	vm_size_t count = 0;

	size_t to_read = 0;
	size_t have_read = 0;

	while(size > 0) {
		to_read = (size > 0x800) ? 0x800 : size;
		count = to_read;

		kr = vm_read_overwrite(msense.task,
			addr, to_read, (vm_address_t) buffer, &count);

		if(kr != KERN_SUCCESS){
			fprintf(stderr, "Couldn't read 0x%zx bytes from 0x%lx\n", size, addr);
			return 0;
		}
		else if(count != to_read){
			fprintf(stderr, "Weird read of 0x%zx bytes from 0x%lx\n", size, addr);
		}

		addr += to_read;
		size -= to_read;
		have_read += to_read;
		buffer = ((uint8_t*) buffer) + to_read;
	}

	return have_read;
}

/*
 * try to acquire a handle into the memory of the process at a specific base
 * and width, if successful, spawn a new data connection to senseye.
 */
static void launch_addr(vm_address_t base, size_t size)
{
	char wbuf[128];
	memset(wbuf, '\0', sizeof(wbuf));

	msense.offset = 0;
	msense.address = base;

/* or calculate base by sqrt -> prev POT */
	snprintf(wbuf, sizeof(wbuf), "%d@%" PRIxPTR, (int)msense.pid, base);
	struct senseye_ch* ch = senseye_open(msense.cont, wbuf, 512);

	if (NULL == ch){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx "
			"couldn't open data channel\n", base, size);
		return;
	}

	pthread_t pth;
	struct page_ch* pch = malloc(sizeof(struct page_ch));
	if (NULL == pch){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx "
			"couldn't setup processing storage\n", base, size);
		return;
	}

	pch->channel = ch;
	pch->base = base;
	pch->size = size;

	if (-1 == pthread_create(&pth, NULL, data_loop, pch)){
		fprintf(stderr, "launch_addr(%" PRIxPTR ")+%zx "
			"couldn't spawn processing thread\n", base, size);
		ch->close(ch);
		free(pch);
		return;
	}
}

/*
 * basic input mapping for the control- channel UI, check
 * senseye/senses/msense_main.lua
 */
static void control_event(struct senseye_cont* cont, arcan_event* ev)
{
	bool refresh = false;

	if (ev->category == EVENT_IO){
		if (strcmp(ev->io.label, "UP") == 0){
			msense.sel = (msense.sel - 1 < 0) ? msense.sel_lim - 1 : msense.sel - 1;
			refresh = true;
		}
		else if (strcmp(ev->io.label, "DOWN") == 0){
			msense.sel = (msense.sel + 1) % (msense.sel_lim);
			refresh = true;
		}
		else if (strcmp(ev->io.label, "LEFT") == 0){
			msense.sel -= msense.sel_page;
			if (msense.sel < 0)
				msense.sel = msense.sel_lim - 1;
			if (msense.sel < 0)
				msense.sel = 0;
			refresh = true;
		}
		else if (strcmp(ev->io.label, "RIGHT") == 0){
			msense.sel += msense.sel_page;
			if (msense.sel >= msense.sel_lim)
				msense.sel = 0;
			refresh = true;
		}
		else if (strcmp(ev->io.label, "SELECT") == 0){
			launch_addr(msense.sel_base, msense.sel_size);
		}
	}

	if (ev->category == EVENT_TARGET &&
		ev->tgt.kind == TARGET_COMMAND_DISPLAYHINT){
		size_t width = ev->tgt.ioevs[0].iv;
		size_t height = ev->tgt.ioevs[1].iv;

		arcan_shmif_resize(cont->context(cont), width, height);
		refresh = true;
	}

	if (refresh)
		update_preview(RGBA(0x00, 0xff, 0x00, 0xff));
}

static size_t synch_copy(struct rwstat_ch* ch,
	struct page_ch* pch, uint8_t* buf, size_t nb)
{
	ch->switch_clock(ch, RW_CLK_BLOCK);
	pthread_mutex_lock(&msense.plock);

	size_t nr = task_read(pch->base, buf, pch->size);

	if(0 == nr) {
		fprintf(stderr, "error reading 0x%zx bytes from address 0x%lx\n",
			nb, msense.address);
		nr = 0;
	}

	if (nr != nb)
		memset(buf + nr, '\0', nb - nr);


/*
 * Doesn't make much sense to resume this constantly when we
 * only suspended it in the beginning. Need to find a better
 * place (if it's even needed)

	kr = task_resume(msense.task);
	if(KERN_SUCCESS != kr) {
		fprintf(stderr, "Couldn't resume our task with pid %d, reason %s\n",
			msense.pid, mach_error_string(kr));
	}
	msense.suspended = false;
*/

	pthread_mutex_unlock(&msense.plock);

	int ign;
	ch->data(ch, buf, nb, &ign);
	return nr;
}

void* data_loop(void* th_data)
{
/* we ignore the senseye- abstraction here and works
 * directly with the rwstat and shmif context */
	struct page_ch* pch = (struct page_ch*)th_data;
	struct rwstat_ch* ch = pch->channel->in;
	struct arcan_shmif_cont* cont = ch->context(ch);

	ssize_t nc = 0;
	size_t buf_sz = ch->left(ch);
	uint8_t* buf = malloc(buf_sz);
	if(NULL == buf) {
		fprintf(stderr, "Couldn't allocate memory for this page\n");
		goto error;
	}

	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_IDENT,
		.ext.message = "msense"
	};

	ch->event(ch, &ev);

	nc = synch_copy(ch, pch, buf, buf_sz);
	if (0 == nc)
		fprintf(stderr, "Couldn't read from address 0x%lx at offset 0x%llx\n",
			msense.address, msense.offset);

	while (arcan_shmif_wait(cont, &ev) != 0){

		if (rwstat_consume_event(ch, &ev)){
			continue;
		}

		if (ch->left(ch) > buf_sz){
			free(buf);
			buf_sz = ch->left(ch);

			buf = malloc(buf_sz);
			if(NULL == buf) {
				fprintf(stderr, "Couldn't allocate memory for this page\n");
				goto error;
			}
		}

		nc = synch_copy(ch, pch, buf, buf_sz);
		if (0 == nc)
			fprintf(stderr, "Couldn't read from address 0x%lx at offset 0x%llx\n",
				msense.address, msense.offset);


		if (ev.category == EVENT_TARGET)
		switch(ev.tgt.kind){
		case TARGET_COMMAND_EXIT:{
			return NULL;
		}

		case TARGET_COMMAND_DISPLAYHINT:{
			size_t base = ev.tgt.ioevs[0].iv;
			if (base > 0 && (base & (base - 1)) == 0){
				if(arcan_shmif_resize(cont, base, base))
					ch->resize(ch, base);
			}
			break;
		}

		case TARGET_COMMAND_STEPFRAME:{
			if (ev.tgt.ioevs[0].iv == 0){
				nc = synch_copy(ch, pch, buf, buf_sz);
				if (0 == nc)
					fprintf(stderr, "Couldn't read from address 0x%lx at offset 0x%llx\n",
						msense.address, msense.offset);
			}
			else if (ev.tgt.ioevs[0].iv == 1){
				nc = synch_copy(ch, pch, buf, buf_sz);
				if (0 == nc)
					fprintf(stderr, "Couldn't read from address 0x%lx at offset 0x%llx\n",
						msense.address, msense.offset);
			}
			else if (ev.tgt.ioevs[0].iv == -1){

			}
			break;
		}
		default:
		break;
		}
	}

error:
	pch->channel->close(pch->channel);
	free(th_data);
	return NULL;
}

size_t get_vmmap_entries(task_t task) {
	size_t n = 0;
	vm_size_t size = 0;
	vm_address_t address = 0;
	kern_return_t kr = KERN_SUCCESS;

	while (1) {
		uint32_t nesting_depth;
		mach_msg_type_number_t count;
		struct vm_region_submap_info_64 info;

		count = VM_REGION_SUBMAP_INFO_COUNT_64;
		kr = vm_region_recurse_64(msense.task,
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

static void update_preview(shmif_pixel ccol)
{
/* clear window */
	struct arcan_shmif_cont* c = msense.cont->context(msense.cont);
	draw_box(c, 0, 0, c->addr->w, c->addr->h, RGBA(0x00, 0x00, 0x00, 0xff));

	int col = 1;
	draw_text(c, "r ", col*(fontw+1), 0, RGBA(0xff, 0x55, 0x55, 0xff)); col += 2;
	draw_text(c, "w ", col*(fontw+1), 0, RGBA(0x55, 0xff, 0x55, 0xff)); col += 2;
	draw_text(c, "x ", col*(fontw+1), 0, RGBA(0x55, 0x55, 0xff, 0xff)); col += 2;
	draw_text(c, "rw ", col*(fontw+1), 0, RGBA(0xff, 0xff, 0x55, 0xff));col += 3;
	draw_text(c, "rx ", col*(fontw+1), 0, RGBA(0xff, 0x55, 0xff, 0xff));col += 3;
	draw_text(c, "wx ", col*(fontw+1), 0, RGBA(0x55, 0xff, 0xff, 0xff));col += 3;
	draw_text(c, "rwx", col*(fontw+1), 0, RGBA(0xff, 0xff, 0xff, 0xff));

	struct page {
		long long addr, endaddr, offset, inode;
		char perm[6];
		char device[16];
	};

/* populate list of entries, first get limit */
		size_t count = 0;
		kern_return_t kr = KERN_SUCCESS;
		count = get_vmmap_entries(msense.task);

/* then fill VLA of page struct with the interesting ones,
 * need to be careful about TOCTU overflow */
	struct page pcache[count];
	memset(pcache, '\0', sizeof(struct page) * count);

	size_t ofs = 0;
	vm_size_t size = 0;
	vm_address_t address = 0;
	uint32_t nesting_depth = 0;
	mach_msg_type_number_t region_count = 0;
	struct vm_region_submap_info_64 info;

	while(ofs < count) {
		region_count = 0;
		nesting_depth = 0;
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

		pcache[ofs].addr = address;
		pcache[ofs].endaddr = address + size;
		pcache[ofs].inode = 0;
		pcache[ofs].offset = 0;
		if(info.protection & VM_PROT_READ) pcache[ofs].perm[0] = 'r';
		if(info.protection & VM_PROT_WRITE) pcache[ofs].perm[1] = 'w';
		if(info.protection & VM_PROT_EXECUTE) pcache[ofs].perm[2] = 'x';
		pcache[ofs].device[0] = '\0';

		address += size;
		ofs++;
	}

	if (0 == ofs)
		return;

	count = ofs-1;

/* clamp */
	if (msense.sel >= count)
		msense.sel = count - 1;

	msense.sel_lim = count;
	size_t nl = (c->addr->h - fonth - 1) / (fonth + 1);
	msense.sel_page = nl;

	int page = 0;
	if (msense.sel > 0)
		page = msense.sel / nl;

	ofs = page * nl;

	int y = fonth + 1;
	int cc = msense.sel % nl;

	while (y < c->addr->h && ofs < count){
		uint8_t r = pcache[ofs].perm[0] == 'r' ? 0xff : 0x55;
		uint8_t g = pcache[ofs].perm[1] == 'w' ? 0xff : 0x55;
		uint8_t b = pcache[ofs].perm[2] == 'x' ? 0xff : 0x55;

		if (cc == 0){
			msense.sel_base = pcache[ofs].addr + pcache[ofs].offset;
			msense.sel_size = pcache[ofs].endaddr - pcache[ofs].addr;
			cc--;
		}
		else if (cc > 0)
			cc--;

/* draw addr + text in fitting color */
		char wbuf[256];
		shmif_pixel col = RGBA(r, g, b, 0xff);
		snprintf(wbuf, 256, "%llx(%dk)", pcache[ofs].addr,
			(int)((pcache[ofs].endaddr - pcache[ofs].addr) / 1024));

		draw_text(c, wbuf, fontw + 1, y, col);
		y += fonth + 1;
		ofs++;
	}

	draw_box(c, 0, ((msense.sel % nl)+1) * (fonth+1), fontw, fonth, ccol);
	arcan_shmif_signal(c, SHMIF_SIGVID);
}

int main(int argc, char* argv[])
{
	kern_return_t kr;
	struct senseye_cont cont;
	struct arg_arr* aarr;
	enum SHMIF_FLAGS connectfl = SHMIF_CONNECT_LOOP;

	if (2 != argc){
		printf("usage: psense process_id\n");
		return EXIT_FAILURE;
	}

	msense.pid = strtol(argv[1], NULL, 10);

	kr = task_for_pid(mach_task_self(), msense.pid, &msense.task);
	if(kr != KERN_SUCCESS) {
		fprintf(stderr, "Couldn't open task port for pid %d, reason: %s\n",
			(int) msense.pid, mach_error_string(kr));
		return EXIT_FAILURE;
	}

	if (!senseye_connect(NULL, stderr, &cont, &aarr, connectfl))
		return EXIT_FAILURE;

/* dimension the control window to match the size of
 * the base-address and its width */
	int desw = (fontw + 1) * (sizeof(void*) + 8 + 3);
	if (!arcan_shmif_resize(cont.context(&cont), desw, 512))
		return EXIT_FAILURE;

/*
	kr = task_suspend(msense.task);
	if(KERN_SUCCESS != kr) {
		fprintf(stderr, "Couldn't suspend task from pid %d, reason %s\n",
			(int) msense.pid, mach_error_string(kr));
		return EXIT_FAILURE;
	}
	msense.suspended = true;
*/

	msense.cont = &cont;
	pthread_mutex_init(&msense.plock, NULL);

	update_preview(RGBA(0x00, 0xff, 0x00, 0xff));

	cont.dispatch = control_event;

	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_IDENT,
		.ext.message = "msense_main"
	};
	arcan_shmif_enqueue(msense.cont->context(msense.cont), &ev);

	while (senseye_pump(&cont, true)){
	}

	return EXIT_SUCCESS;
}
