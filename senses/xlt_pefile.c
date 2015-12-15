/*
 * Copyright 2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in the senseye source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: This translator provides Windows PE- file parsing support,
 * including overlaying structure fields and metadata.  Notes: __packed hacks
 * and no big endian handling, no handling of higher abstractions (e.g.
 * data-directory decoding, resources) yet.
 *
 * Current state is unusable, the parsing and rendering is incomplete and
 * there is no overlay support.
 */
#include "xlt_supp.h"
#include "font_8x8.h"
#include <inttypes.h>

struct __attribute__((__packed__)) dos_header {
	uint16_t lastsz;
	uint16_t block_cnt;
	uint16_t reloc_cnt;
	uint16_t hdr_size;
	uint16_t min_alloc;
	uint16_t max_alloc;
	uint16_t stack_size;
	uint16_t stack_ptr;
	uint16_t checksum;
	uint16_t insn_ptr;
	uint16_t code_sz;
	uint16_t reloc_pos;
	uint16_t overlay_cnt;
	uint16_t reserved[4];
	uint16_t oem_id;
	uint16_t oem_inf;
	uint16_t reserved2[10];
	uint32_t e_lfanew; /* yellow */
};

struct __attribute__((__packed__)) opt_pe32_hdr {
	uint32_t ImageBase;
	uint32_t SectionAlignment;
	uint32_t FileAlignment;
	uint16_t MajorOperatingSystemVersion;
	uint16_t MinorOperatingSystemVersion;
	uint16_t MajorImageVersion;
	uint16_t MinorImageVersion;
	uint16_t MajorSubsystemVersion;
	uint16_t MinorSubsystemVersion;
	uint32_t Win32VersionValue;
	uint32_t SizeOfImage;
	uint32_t SizeOfHeaders;
	uint32_t Checksum;
	uint16_t Subsystem;
	uint16_t DllCharacteristics;
	uint32_t SizeOfStackReserve;
	uint32_t SizeOfStackCommit;
	uint32_t SizeOfHeapReserve;
	uint32_t SizeOfHeapCommit;
	uint32_t LoaderFlags;
	uint32_t NumberOfRvaAndSizes;
};

struct __attribute__((__packed__)) opt_pe32plus_hdr {
	uint64_t ImageBase;
	uint64_t ImageSize;
};

struct __attribute__((__packed__)) coff_header {
	uint8_t NTHeader[4]; /* green */
	uint16_t Machine; /* blue */
	uint16_t NumberOfSections; /* purple */
	uint32_t TimeDateStamp;
	uint32_t stbl_ptr;
	uint32_t stbl_cnt;
	uint16_t SizeOfOptionalHeader; /* res */
	uint16_t Characteristics; /* yellow */
};

struct __attribute__((__packed__)) opt_coff_header {
	uint16_t Magic; /* green */
	uint8_t MajorLinkerVersion;
	uint8_t MinorLinkerVersion;
	uint32_t SizeOfCode;
	uint32_t SizeOfInitializedData;
	uint32_t SizeOfUninitializedData;
	uint32_t AddressOfEntryPoint; /* Cyan */
	uint32_t BaseOfCode;
	uint32_t BaseOfData;
};

enum parse_state {
	STATE_TRUNC = 1,
	STATE_DOSOK = 2,
	STATE_COFFOK = 4,
	STATE_COFFOPTOK  = 8,
	STATE_PE32OK = 16,
	STATE_PE32PLUSOK = 32,
	STATE_SECTHDROK  = 64,
	STATE_SECTOK = 128,
	STATE_WEIRD = 256
};

struct __attribute__((__packed__)) sect_hdr {
	uint8_t Name[8];
	uint32_t VirtualSize;
	uint32_t VirtualAddr;
	uint32_t SizeOfRawData;
	uint32_t PointerToRawData;
	uint32_t PointerToRelocations;
	uint32_t PointerToLinenumbers;
	uint16_t NumberOfRelocations;
	uint16_t NumberOfLinenumbers;
	uint32_t Characteristics;
};

enum pe_type {
	PE32,
	PE32_PLUS
};

static const char* const pe_type_lut[] = {
	"pe32",
	"pe32_plus"
};

struct pe_file {
	struct dos_header dos;
	uint8_t* dos_data;
	size_t dos_datasz;

	struct coff_header coff;
	struct opt_coff_header coff_opt;
	union {
		struct opt_pe32_hdr pe32;
		struct opt_pe32plus_hdr pe32plus;
	};

	struct {
		uint32_t rva;
		uint32_t sz;
	} pe32_dent[16];

	uint32_t align_sect_va;
	uint32_t align_sect_pa;
	enum pe_type pe_type;

	uint8_t* secthdr_pad;
	size_t secthdr_padsz;

	struct sect_hdr* sect_hdr;
	size_t* sect_prepad;
	uint8_t** sect_data;

	enum parse_state state;
	off_t ofs_header, ofs_done, ofs_start;
};

enum drawing_modes {
	HEADER = 0,
	SECTIONS = 1,
	MODE_LAST = 2
};

struct pefh {
	struct pe_file* pef;
	int mode;
	uint64_t pos;
};

/*
 * for the "accumulation mode", we start tracking at a certain position,
 * print how many bytes etc. we are missing, and buffer
 */
static bool input(struct arcan_shmif_cont* out, arcan_event* ev)
{
	struct pefh* pefh = out->user;
	if (pefh == NULL)
		return false;

	if (strcmp(ev->io.label, "LEFT") == 0){
		pefh->mode--;
		pefh->mode = pefh->mode < 0 ? MODE_LAST - 1 : pefh->mode;
		return true;
	}
	else if (strcmp(ev->io.label,"RIGHT") == 0){
		pefh->mode = (pefh->mode + 1)	% MODE_LAST;
		return true;
	}
	return false;
}

static inline ssize_t fbufr(void* dst,
	uint8_t** buf, size_t* buf_sz, size_t sz)
{
	if (sz > *buf_sz)
		return -1;

	memcpy(dst, *buf, sz);
	*buf_sz -= sz;
	*buf += sz;
	return sz;
}

static inline struct pe_file* pe_fail(struct pe_file* res,
	enum parse_state state, off_t ofs)
{
	res->state |= state;
	res->ofs_done = ofs;
	return res;
}

static struct pe_file* pe_parse(uint8_t* buf, size_t sz)
{
	off_t ofs = 0;

	uint8_t* inbuf = buf;
	size_t inbuf_sz = sz;

	struct pe_file* res = malloc(sizeof(struct pe_file));
	memset(res, '\0', sizeof(struct pe_file));
	res->ofs_start = ofs;

	if (-11 == fbufr(&res->dos, &inbuf, &inbuf_sz, 62))
		return pe_fail(res, STATE_TRUNC, ofs);

	res->state |= STATE_DOSOK;
	ssize_t dos_body = res->dos.e_lfanew - 64;

	if (dos_body > 0){
		res->dos_data = malloc(dos_body);
		res->dos_datasz = dos_body;

		if (!res->dos_data)
			return pe_fail(res, STATE_WEIRD, ofs);

		if (-1 == fbufr(res->dos_data, &inbuf, &inbuf_sz, dos_body))
			return pe_fail(res, STATE_TRUNC, ofs);
	}

	res->ofs_header = sz - inbuf_sz;
	if (-1 == fbufr(&res->coff, &inbuf, &inbuf_sz, sizeof(struct coff_header)))
			return pe_fail(res, STATE_TRUNC, ofs);

	if (memcmp(res->coff.NTHeader, "PE\0\0", 4) != 0)
		return pe_fail(res, STATE_WEIRD, ofs);
	res->state |= STATE_COFFOK;

	if (-1 == fbufr(&res->coff_opt, &inbuf, &inbuf_sz, sizeof(struct opt_coff_header)))
		return pe_fail(res, STATE_TRUNC, ofs);
	res->state = STATE_COFFOPTOK;

	size_t sect_align_skip = 0;
	if (res->coff_opt.Magic == 0x10b){
		if (-1 == fbufr(&res->pe32, &inbuf, &inbuf_sz, sizeof(struct opt_pe32_hdr)))
			return pe_fail(res, STATE_TRUNC, ofs);

		if (res->pe32.NumberOfRvaAndSizes > 16){
			res->state |= STATE_WEIRD;
			res->pe32.NumberOfRvaAndSizes = 16;
		}
		if (-1 == fbufr(&res->pe32_dent,
			&inbuf, &inbuf_sz, 8 * res->pe32.NumberOfRvaAndSizes))
			return pe_fail(res, STATE_TRUNC, ofs);

		res->state |= STATE_PE32OK;

		res->pe_type = PE32;
		res->align_sect_va = res->pe32.SectionAlignment;
		res->align_sect_pa = res->pe32.FileAlignment;
		sect_align_skip = res->coff.SizeOfOptionalHeader + res->ofs_header +
			sizeof(struct coff_header) - (sz - inbuf_sz);
	}
	else if (res->coff_opt.Magic == 0x20b){
		res->pe_type = PE32_PLUS;
		return pe_fail(res, STATE_PE32PLUSOK | STATE_TRUNC, ofs);
	}
	else
 		return pe_fail(res, STATE_WEIRD, ofs);

	if (sect_align_skip){
		res->secthdr_pad = malloc(sect_align_skip);
		if (!res->secthdr_pad)
			return pe_fail(res, STATE_WEIRD, ofs);

		if (-1 == fbufr(res->secthdr_pad, &inbuf, &inbuf_sz, sect_align_skip))
			return pe_fail(res, STATE_TRUNC, ofs);

		res->secthdr_padsz = sect_align_skip;
	}

	if (res->coff.NumberOfSections == 0)
		return pe_fail(res, STATE_SECTHDROK | STATE_SECTOK, ofs);

	res->sect_hdr = malloc(sizeof(struct sect_hdr) * res->coff.NumberOfSections);
	res->sect_prepad = malloc(sizeof(size_t) * res->coff.NumberOfSections);
	if (NULL == res->sect_hdr || NULL == res->sect_prepad)
		return pe_fail(res, STATE_WEIRD, ofs);
	memset(res->sect_hdr, '\0', sizeof(struct sect_hdr) * res->coff.NumberOfSections);
	memset(res->sect_prepad, '\0', sizeof(size_t) * res->coff.NumberOfSections);

	if (-1 == fbufr(res->sect_hdr,
		&inbuf, &inbuf_sz, sizeof(struct sect_hdr) * res->coff.NumberOfSections))
		return pe_fail(res, STATE_WEIRD, ofs);

	res->state |= STATE_SECTHDROK;
	res->sect_data = malloc(sizeof(uint8_t*) * res->coff.NumberOfSections);
	if (NULL == res->sect_data)
		return pe_fail(res, STATE_WEIRD, ofs);
	memset(res->sect_data, '\0', sizeof(uint8_t*) * res->coff.NumberOfSections);

	for (size_t i = 0; i < res->coff.NumberOfSections; i++){
		if (res->sect_hdr[i].SizeOfRawData == 0)
			continue;

		ssize_t pad = res->sect_hdr[i].PointerToRawData -
			( (sz - inbuf_sz) - res->ofs_start);
		if (pad < 0)
			return pe_fail(res, STATE_WEIRD, ofs);

		res->sect_prepad[i] = pad;
		res->sect_data[i] = malloc(res->sect_hdr[i].SizeOfRawData + pad);
		if (NULL == res->sect_data[i])
			return pe_fail(res, STATE_WEIRD, ofs);

		if (-1 == fbufr(res->sect_data[i], &inbuf, &inbuf_sz,
			res->sect_hdr[i].SizeOfRawData + pad))
			return pe_fail(res, STATE_TRUNC, ofs);
	}

	return pe_fail(res, STATE_SECTOK, ofs);
}

static void pe_free(struct pe_file* file)
{
	if (!file)
		return;

	free(file->dos_data);
	free(file->secthdr_pad);
	free(file->sect_hdr);
	free(file->sect_prepad);

	for (size_t i = 0; i < file->coff.NumberOfSections; i++){
		free(file->sect_data[i]);
	}
	free(file->sect_data);
	free(file);
}

static bool over_pop(bool newdata, struct arcan_shmif_cont* in,
	int zoom_ofs[4], struct arcan_shmif_cont* over,
	struct arcan_shmif_cont* out, uint64_t pos,
	size_t buf_sz, uint8_t* buf, struct xlt_session* sess)
{
	return false;
}

static bool draw_pef_state(struct arcan_shmif_cont* out, struct pefh* pefh)
{
	struct pe_file* pef = pefh->pef;
	size_t y = 0;

#define DO_ROW(label, data, ...) { snprintf(work, chw, label); \
	draw_text(out, work, 1, y, RGBA(0xff, 0xff, 0xff, 0xff));\
	snprintf(work, chw, data, __VA_ARGS__);\
	draw_text(out, work, strlen(label)*fontw, y, RGBA(0x44, 0xff, 0x44, 0xff));\
	y += fonth + 2;\
	}

#define DO_PEH(label, ok) {\
		snprintf(work, chw, label);\
		draw_text(out, work, xofs, y, ok ? good : bad);\
		xofs += strlen(work) * fontw + 2;\
	}

	size_t chw = out->w / fontw;
	size_t xofs = 2;
	char work[chw];

	shmif_pixel cc = RGBA(0x00, 0x00, 0x00, 0xff);
	for (size_t i = 0; i < out->w * out->h; i++)
		out->vidp[i] = cc;

	shmif_pixel good = RGBA(0x00, 0xff, 0x00, 0xff);
	shmif_pixel bad = RGBA(0xff, 0x00, 0x00, 0xff);

	DO_PEH("complete", !(pef->state & STATE_TRUNC));
	DO_PEH("suspicious", !(pef->state & STATE_WEIRD));
	DO_PEH("dos", (pef->state & STATE_DOSOK));
	DO_PEH("coff", (pef->state & STATE_DOSOK));
	DO_PEH("coffopt", (pef->state & STATE_DOSOK));
	DO_PEH("pe/pe+", (pef->state & STATE_DOSOK));
	DO_PEH("secthdr", (pef->state & STATE_DOSOK));
	DO_PEH("sect", (pef->state & STATE_DOSOK));

	switch (pefh->mode){
	case HEADER:

	break;

	case SECTIONS:
	break;
	}

#undef DO_ROW
	return true;
}

static bool populate(bool data, struct arcan_shmif_cont* in,
	struct arcan_shmif_cont* out, uint64_t pos, size_t buf_sz, uint8_t* buf)
{
	struct pefh* pefh = out->user;

	if (!buf){
		if (pefh){
			pe_free(pefh->pef);
			free(pefh);
			out->user = NULL;
		}
		return false;
	}

	if (!pefh){
		out->user = pefh = malloc(sizeof(struct pefh));
		memset(pefh, '\0', sizeof(struct pefh));
	}

	for (size_t i = 0; i < buf_sz-1; i++){
		if (buf[i] != 'M' || buf[i+1] != 'Z')
			continue;

/* magic bytes found, check if we don't already know about this one
		if (pefh->pef && pos + i == pefh->pos){
			break;
		}
*/

/* if pefh is truncated and we allow buffering and the pos is continuous
 * with amount buffered, append and parse */
		if (pefh->pef)
			pe_free(pefh->pef);

		pefh->pef = pe_parse(buf + i, buf_sz - i);
		if (!pefh->pef)
			continue;

		pefh->pos = pos;
		return draw_pef_state(out, pefh);
	}

	return false;
}

int main(int argc, char* argv[])
{
	enum ARCAN_FLAGS confl = SHMIF_CONNECT_LOOP;
	struct xlt_context* ctx = xlt_open("PE Executable", XLT_DYNSIZE, confl);
	if (!ctx)
		return EXIT_FAILURE;

	xlt_config(ctx, populate, input, over_pop, NULL);
	xlt_wait(ctx);
	xlt_free(&ctx);
	return EXIT_SUCCESS;
}
