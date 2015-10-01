/*
 * Copyright 2014-2015, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://senseye.arcan-fe.com
 * Description: Basic pattern matching / transfer statistics / block
 * or sliding data transfers across the arcan shared memory interface.
 */

static const int rwstat_row_ch = 6;

/*
 * Determines when a channel should build and synchronize output
 */
enum rwstat_clock {
	RW_CLK_BLOCK  = 0, /* Full block by block (base-squared) */
	RW_CLK_SLIDE  = 1  /* On every new write- flush          */
};

/*
 * different options for what should be packed into the alpha channel
 */
enum rwstat_alpha {
	RW_ALPHA_FULL    = 0, /* 0xff, opaque                                 */
 	RW_ALPHA_PTN     = 1, /* 0xff or signal ID (defined by each pattern)  */
	RW_ALPHA_DELTA   = 2, /* value distance changed from last frame       */
	RW_ALPHA_ENTBASE = 3, /* entropy encoded, channel base determines wnd */
};

/*
 * control which byte offset map to which coordinates
 */
enum rwstat_mapping {
	MAP_WRAP    = 0, /* increment y, reset x after filled row          */
	MAP_TUPLE   = 1, /* first, second bytes (X, Y) + n bytes color     */
	MAP_TUPLE_ACC = 2, /* first ,second bytes (X, Y) + accumulate      */
	MAP_HILBERT = 3, /* use a hilbert space filling curve              */
};

/*
 * control how each channel is mapped, changes to this
 * table should be reflected in pack_sizes in rwstat.c
 */
enum rwstat_pack {
	PACK_TIGHT    = 0, /* first byte R, second G, third B, fourth A */
	PACK_TNOALPHA = 1, /* first byte R, second G, third B, - full a */
	PACK_INTENS   = 2, /* full alpha, same byte in R, G, B - full a */
};

enum ptn_flags {
	FLAG_EVENT = 1, /* if set, event will be fired when detected during synch */
	FLAG_STATE = 2  /* if set, alpha value will be used until next state- ptn */
};

struct rwstat_ch {
	void (*free)(struct rwstat_ch**);

/*
 * feed this function with data, will return number of bytes consumed
 * (so can be used for short-write tests as well) and set *fs to number
 * of frames synched (likely only 1 or 0).
 */
	size_t (*data)(struct rwstat_ch*, uint8_t* buf, size_t buf_sz, int* fs);

/* get the number of bytes left until a full frame is filled given the
 * current packing / mapping sizes */
	size_t (*left)(struct rwstat_ch*);
	size_t (*row_size)(struct rwstat_ch*);
	size_t (*pack_sz)(struct rwstat_ch*);

/* force a transfer step even though parts of buffer state may be incomplete */
	void (*tick)(struct rwstat_ch*);

/* define a new desired base size and new entropy block size */
	void (*resize)(struct rwstat_ch*, size_t base);

/* enqeue an event to propagate upwards */
	void (*event)(struct rwstat_ch*, arcan_event*);

/* all rw-stat sources can handle damage, but we can also forward to the
 * underlying sensor - if it is set to support such operations by overwriting
 * this member.
 *
 * mode = implementation defined, rand = user requested randomization,
 * ofs  = last known base offset (where applicable),
 * rows = number of injection sequences
 * skip = bytes between each injection sequence.
 *
 * the rows / skip fields are needed to map from user 2D to 1D data source,
 * seek(ofs), for rows: write n bytes, seek forward skip;
 *
 * when done, signal the need for repopulating the input buffer.
 */
	void (*damage)(struct rwstat_ch*,
		uint8_t mode, bool rand, uint64_t ofs,
		size_t bytes, size_t rows, size_t skip
	);

	void* damage_tag;
/*
 * Add a byte sequence to look for. Alpha indicates the value to write
 * to the corresponding alpha channel in the output buffer, if  _TYPE
 * alpha mode is set. Id is the value to use in the event that is queued
 * when sequence is detected (along with offset).
 *
 * Stateful only affects _PTN alpha mode. If set, all subsequent bytes
 * (until a new pattern is triggered) will have the specified alpha
 * value set. If not set, only the bytes that triggered the pattern will
 * have the slot alpha value.
 */
	bool (*add_pattern)(struct rwstat_ch*, uint8_t alpha, uint32_t id,
		enum ptn_flags, void* buf, size_t sz);

/* change the offset counter that is propagated in parent communication */
	void (*wind_ofs)(struct rwstat_ch*, off_t val);

/* switch how each byte value is mapped into color channels,
 * using the enumerators defined above */
	void (*switch_packing)(struct rwstat_ch*, enum rwstat_pack);
	void (*switch_mapping)(struct rwstat_ch*, enum rwstat_mapping);
	void (*switch_clock)(struct rwstat_ch*, enum rwstat_clock);
	void (*switch_alpha)(struct rwstat_ch*, enum rwstat_alpha);

	struct arcan_shmif_cont* (*context)(struct rwstat_ch*);
	struct rwstat_ch_priv* priv;
};

/*
 * Create a new channel and assign the specified segment to it.
 */
struct rwstat_ch* rwstat_addch(enum rwstat_clock clock,
	enum rwstat_mapping map, enum rwstat_pack pack,
	size_t base, struct arcan_shmif_cont*
);

/*
 * See if an incoming arcan- style event contains data that
 * should be mapped to the rwstat. This is to re-se more of
 * the same boiler plate code between sensors.
 *
 * Returns true if the event was consumed (i.e. some action
 * that modifies ch was taken), otherwise false.
 */
bool rwstat_consume_event(struct rwstat_ch*, struct arcan_event*);

/*
 * take an arg_arr packed struct and parse it to extract
 * command-line specified patterns and map them into the
 * rwstat channel.
 */
void rwstat_addpatterns(struct rwstat_ch*, struct arg_arr*);
