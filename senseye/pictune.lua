-- Copyright 2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description:
-- Picture Tuner is a set of tools and heuristics
-- for finding packing parameters to unencoded images
-- without header support.
--
-- Flow:
--  [ colorspace unpacker:rendertarget] -> [tuner] -> autotune ?
--  [tile_readback_buffer] -> [eval] -> [auto adjust tuner] ->
--  [auto ofset]
--
-- Details:
-- Color space unpack works on the assumption that though the
-- input data has been provided as RGBA, it may itself contain
-- more odd packed color formats and tries to generate a new
-- output buffer based on this.
--
-- Auto- adjust tuner works by placing evaluation tiles that
-- use a certain heuristic to evaluate if the current assumed
-- pitch is good or not (spatial relationships typically), then
-- adjust pitch and tries again until satisfied.
--
-- Lastly, auto-ofset uses edge detection to try and align any
-- hard edges that were found (which is typically screen borders
-- or the sharp discontinuity that happens when the starting
-- ofset is bad.
--
-- Limitations:
--
--  This is a heuristic driven algorithm that is prone to
--  both false-positives and false negatives.
--
--  There is no support for planar images, only interleaved as we
--  don't know if we have the full image buffer or not in the active
--  sample window.
--
--  Input buffer size in relation to the width evaluated is
--  also important (as the sample window dimensions effectively
--  limit the maximum detectable width).
--
--  The auto- steps are effective for cases where you have a sample
--  window that is smaller than the images you want to detect, which
--  is typically the case.
--
-- Improvements:
--
--  * Support many more color and tile- formats in unpacking
--  stage, possibly also add color formats to the auto-tuning
--  process.
--
--  * Switch between "all in one run" and "one evaluation
--  per frame", default could possibly be set using
--  the command-line synchronization strategy.
--
--  * For "autostepping", look for a vertical edge to determine
--  when to use or autotuning based on sharp breaks in histogram
--  on a per row basis.
--
--  * Use edge-detection to find and isolate blocks of text,
--  then OCR to automatically extract strings
--
--  * Propagate detected dimensions to rwstat(in sensor sampling support)
--  in order to set a step size that would allow you to pan around inside
--  the buffer
--
--  * Detect starting row and height by rewinding (requires the step-size
--  change), looking for sharp histogram changes per row.
--
--  * When the 'favorites' feature is added, auto-add newly detected
--  images with their assumed stride and offset
--
-- This solution could also be broken out to a separate tool that
-- uses most of the same IPC / setup as senseye, but works automatically
-- (i.e. no UI, just headless).
--

local function build_unpacker(unpack, srcid)
	local props = image_storage_properties(srcid);
	local neww = props.width * unpack.sfx;
	local newh = props.height * unpack.sfy;

	local newrt = alloc_surface(neww, newh);
	local interm = null_surface(neww, newh);
	image_sharestorage(srcid, interm);

	define_rendertarget(newrt, {interm},
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, 0);

	show_image({interm, newrt});

	if (type(unpack.frag) == "string") then
		unpack.frag = build_shader(nil,
			unpack.frag, "unpack_" .. unpack.label);
	end

	image_shader(interm, unpack.frag);
	rendertarget_forceupdate(newrt);

	return newrt;
end

local unpackers = {
	{
		label = "RGBA->RGBx",
		frag =
[[
uniform sampler2D map_tu0;
varying vec2 texco;
void main()
{
	gl_FragColor = vec4(texture2D(map_tu0, texco).rgb, 1.0);
}
]];
		sfx = 1.0,
		sfy = 1.0,
		handler = function(wnd, source)
		end
	}
};

local tuners = {
	{
		frag = [[
uniform sampler2D map_tu0;
varying vec2 texco;

uniform vec2 obj_input_sz;
uniform vec2 obj_storage_sz;
uniform float tune_x;
uniform float ofs_s;

void main()
{
	float step_s = obj_input_sz.x;
	float step_t = obj_input_sz.y;
	float tx = tune_x < obj_storage_sz.x ? obj_storage_sz.x : tune_x;

/* align against grid to lessen sampling artifacts */
	float new_s = floor(texco.s / obj_input_sz.x) * obj_input_sz.x;
	float new_t = floor(texco.t / obj_input_sz.y) * obj_input_sz.y;

/* calculate the offset shift for each row */
	float lpr = (tx - obj_storage_sz.x) * obj_input_sz.x;
	new_s = new_s + new_t / step_t * lpr + (ofs_s * step_s);

/* adjust s/t accordingly */
	float ts = ceil(new_s) - 1.0;
	if (ts > 0.0){
		new_s = new_s - ts;
		new_t = new_t + ts * step_t;
	}

/* clamp to show the reduced effective area */
	if (new_s > 1.0 || new_t > 1.0)
		gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
	else
		gl_FragColor = vec4(texture2D(map_tu0, vec2(new_s, new_t)).rgb, 1.0);
}
]],
		label = "Horizontal Pitch"
	}
};

local function set_width(wnd, neww, newofs)
	local props = image_storage_properties(wnd.canvas);
	local tbl = {};

	wnd.split_w = neww;
	wnd.ofs_s = newofs;
	shader_uniform(wnd.shid, "tune_x", "f", PERSIST, neww);
	shader_uniform(wnd.shid, "ofs_s", "f", PERSIST, newofs);
	wnd:set_message(string.format("width (%d), ofs (%d)", neww, newofs));

	if (wnd.cascade) then
		for k,v in ipairs(wnd.cascade) do
			rendertarget_forceupdate(v);
			stepframe_target_builtin(v, 1, true);
		end
	end
end

--
-- used for autotuning, take a set of cords (x,y,x2,y2, ...)
-- and a base (x,y,x+base,y+base), generate null surfaces that
-- are part of a calctarget readback into calc.
--
-- x, y [+base] should be within the assumed "max" testing
-- width relative to the input source so that there is enough
-- data to work with.
--
-- returns a reference to the calc/rendertarget and the set of tiles
--
local function gen_tiles(source, coords, base, calc)
	local props = image_storage_properties(source);
	local ntiles = #coords / 2;

	local tset = {};
	local ss = base / props.width;
	local st = base / props.height;

	for i=1,ntiles do
		local x = coords[i*2-1];
		local y = coords[i*2-0];

		local tile = null_surface(base, base);
		image_sharestorage(source, tile);
		move_image(tile, base * (i-1), 0);
		show_image(tile);
		local s1 = x * (1.0 / props.width);
		local t1 = y * (1.0 / props.height);
		local s2 = s1 + ss;
		local t2 = t1 + st;

		local txcos = {s1, t1, s2, t1, s2, t2, s1, t2};
		image_set_txcos(tile, txcos);
		table.insert(tset, tile);
	end

	local rt = alloc_surface(ntiles * base, base);
	if (calc) then
		define_calctarget(rt, tset,
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, 0, calc);
	else
		define_rendertarget(rt, tset, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, 0);
	end
	return rt, tset;
end

local unpacking_popup = {
};

local tuning_popup = {
	-- reset, autoscan, # tiles, tile-size
};

local picture_popup = {
	{
		label = "Unpacking...",
		name = "pt_unpack_menu",
		submenu = unpackers
	},
	{
		label = "Tuning...",
		name = "pt_tune_menu",
		submenu = tuners
	}
};

local function vcont(wnd, tbl, base, w, h)
	local tilec = w / base;

-- just compare euclid distance between rows (vertical continuity)
	local function tile_score(ofs)
		local score = 0;
		for x=0,base-1 do
			local last_pos = 0;
			for y=0,base-1 do
				local r,g,b = tbl:get(x+ofs, y, 3);
				local dist = math.sqrt(r * r + g * g + b * b);
				if (math.abs(dist - last_pos) < 0.01) then
					score = score + 1;
				else
					last_pos = dist;
				end
			end
		end
		return score;
	end

-- punish tiles that are close to perfect?
	local sum = 0.0001;
	for i=0,tilec-1 do
		sum = sum + tile_score(i*base);
	end
	return sum / tilec;
end

function spawn_pictune(wnd)
	local props = image_storage_properties(wnd.ctrl_id);
	if (wnd.pack_sz == 1) then
		wnd:set_message(
			"Only 3/4bpp packing input formats supported", DEFAULT_TIMEOUT);
		return;
	end

	local rt = build_unpacker(unpackers[1], wnd.ctrl_id);
	local nw = wnd.wm:add_window(rt, {});

	nw:set_parent(wnd, ANCHOR_LL);
	nw.copy = copy;
	nw.mode = 0;
	nw.split_w = props.width;
	nw.ofs_t = 0.0;
	nw.dynamic_zoom = false;
	nw:select();

	window_shared(nw);
	local old_drag = nw.drag;
	nw.drag = function(wnd, vid, x, y)
		if (not wnd.wm.meta and not wnd.wm.meta_detail) then
			if (nw.mode == 0) then
				set_width(wnd, wnd.split_w + 0.5 * x, wnd.ofs_s);
			else
				set_width(wnd, wnd.split_w, wnd.ofs_s + 0.5 * y);
			end
		else
			old_drag(wnd, vid, x, y);
		end
	end

	nw.dispatch["LEFT"] = function()
		if (nw.mode == 0) then
			nw.split_w = nw.split_w - (nw.wm.meta and 10 or 1);
		else
			nw.ofs_t = nw.ofs_t - (nw.wm.meta and 10 or 1);
		end
		set_width(nw, nw.split_w, nw.ofs_t);
	end

	nw.dispatch["a"] = function()
		local tiles = {0, 4, 20, 4, 80, 4, 120, 4};
-- for the tiles we also need an intermediate rendertarget
-- as the tuning shader is built on buffer dimensions
		local props = image_storage_properties(nw.canvas);
		local im = alloc_surface(props.width, props.height);
		local ns = null_surface(props.width, props.height);
		image_sharestorage(nw.canvas, ns);
		show_image(ns);
		define_rendertarget(im, {ns}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, 0);
		image_shader(ns, nw.shid);
		rendertarget_forceupdate(im);
		show_image(im);

		local scores = {};
		local rt, tiles = gen_tiles(im, tiles, 20,
			function(tbl, w, h)
				scores[nw.split_w] = vcont(nw, tbl, 20, w, h);
			end
		);
		nw.cascade = {im, rt};

-- possible detected tile depend on base size and highest sampled y val,
-- we can calculate "lost height" based on assumed width vs. tested width
		for i=props.width+1,props.width * 5 do
			set_width(nw, i, 0);
		end

		local highest = 0;
		local highest_ind = 1;

		for k,v in pairs(scores) do
			if (v > highest) then
				highest = v;
				highest_ind = k;
			end
		end
		delete_image(im);
		delete_image(rt);
		nw.cascade = nil;
		set_width(nw, highest_ind, 0);
	end

	nw.dispatch[BINDINGS["PLAYPAUSE"]] = function()
		local iotbl = {};
		if (nw.paused) then
			iotbl = {kind = "digital", active = true, label = "STEP_SIZE_ROW"};
			wnd:set_message("Pictune set step to row", DEFAULT_TIMEOUT);
			nw.paused = nil;
		else
			iotbl = {kind = "digital", active = true, label = ""};
			iotbl.label = string.format("CSTEP_%d", nw.split_w * wnd.pack_sz);
			wnd:set_message(string.format("Pictune set step to %d bytes",
				nw.split_w * wnd.pack_sz), DEFAULT_TIMEOUT);
			nw.paused = true;
		end
		target_input(wnd.ctrl_id, iotbl);
	end

	nw.source_handler = function(wnd, source, status)
-- for this to work, we need to know how many bytes we have moved and judge
-- if this is enough for a new row and if so, adjust offset accordingly
		if (status.kind == "frame") then
			rendertarget_forceupdate(nw.canvas);
-- should have some tracking here to determine if we've had a "sharp switch",
-- possibly using a combination of histogram and our eval- regions
		end
	end
	table.insert(nw.parent.source_listener, nw);

	nw.dispatch["RIGHT"] = function()
		if (nw.mode == 0) then
			nw.split_w = nw.split_w + (nw.wm.meta and 10 or 1);
		else
			nw.ofs_t = nw.ofs_t + (nw.wm.meta and 10 or 1);
		end
		set_width(nw, nw.split_w, nw.ofs_t);
end

	nw.dispatch[BINDINGS["MODE_TOGGLE"]] = function()
		nw.mode = nw.mode == 0 and 1 or 0;
		nw:set_message("Mode switched to " .. (nw.mode == 0 and "(width)" or "(ofset)"));
	end

	nw.shid = build_shader(nil, tuners[1].frag, tostring(nw.name));
	image_shader(nw.canvas, nw.shid);
	set_width(nw, props.width, 0);

	muppet = alloc_surface(props.width, props.height);
	int = null_surface(props.width, props.height);
	image_sharestorage(nw.canvas, int);

	table.insert(nw.autodelete, copy);
end
