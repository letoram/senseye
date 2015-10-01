/*
 * Sample implementation of integ_dbif, for testing / tuning purposes
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>

#include "integ.h"

struct integ_ctx {
	uint64_t cookie;
};

struct integ_ctx* integ_open(const char* rd)
{
	struct integ_ctx* rv = malloc(sizeof(struct integ_ctx));
	rv->cookie = 0xfeedface;
}

void integ_close(struct integ_ctx** ctx)
{
	if (!ctx || (*ctx)->cookie != 0xfeedface)
		return;

	(*ctx)->cookie = 0xdeadbeef;
	free(*ctx);
}

void integ_help(FILE* out)
{
	fprintf(out, "integ_test implementation, any resource arg works");
}

int integ_seek_abs(struct integ_ctx* ctx, uint64_t pos)
{
	return -1;
}

uint64_t integ_get_pos(struct integ_ctx* ctx)
{
	return 0;
}

int integ_seek_rel(struct integ_ctx* ctx, uint64_t step, int dir)
{
	return -1;
}

int toggle_bkpt(uint64_t pos, bool watch)
{
	return -1;
}

ssize_t integ_read(struct integ_ctx* ctx, uint8_t* buf, size_t ntr)
{
	return -1;
}

struct pgtbl_ent* integ_pagetbl(struct integ_ctx* ctx, size_t* count)
{
	return NULL;
}

struct pos_info* integ_sample_pos(struct integ_ctx* ctx, uint64_t pos)
{
	return NULL;
}
