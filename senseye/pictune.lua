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
--  and a final "auto-ofs" step that uses an edge detector and
--  looks for an edge that covers the whole vertical span
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
--  There is no support for planar images, only interleaved.
--  Input buffer size in relation to the width evaluated is
--  also important (as the sample window dimensions effectively
--  limit the maximum detectable width).
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

/* align against grid to lessen sampling artifacts */
	float new_s = floor(texco.s / obj_input_sz.x) * obj_input_sz.x;
	float new_t = floor(texco.t / obj_input_sz.y) * obj_input_sz.y;

/* calculate the offset shift for each row */
	float lpr = (tune_x - obj_storage_sz.x) * obj_input_sz.x;
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
end

--
-- used for autotuning, take a table of {.x, .y} tables and a base
-- width (to avoid bin packing problem) and pack into a rendertarget
--
local function gen_tiles(source, tilelist, base, calc)
	local props = image_storage_properties(source);
	local htiles = math.ceil(math.sqrt(#tilelist));
	local ofs = 1;
	local row = 1;
	local tset = {};
	local ss = base / props.width;
	local st = base / props.height;

	while row <= htiles and ofs <= #tilelist do
		for col=1,htiles do
			local tile = null_surface(base, base);
			local s1 = tilelist[ofs].x > 0 and tilelist[ofs].x / props.width or 0;
			local t1 = tilelist[ofs].y > 0 and tilelist[ofs].y / props.height or 0;
			local s2 = s1 + ss;
			local t2 = t1 + st;
			move_image(tile, (row - 1) * base, (col - 1) * base);
			image_sharestorage(source, tile);
			local txcos = {s1, t1, s2, t1, s2, t2, s1, t2};
			image_set_txcos(tile, txcos);
			tset[ofs] = tile;
			ofs = ofs + 1;
		end
		row = row + 1;
	end

	local rt = null_surface(htiles * base, htiles * base);
	if (calc) then
		return define_calctarget(rt,
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, 0, calc);
	else
		return define_rendertarget(rt,
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, 0);
	end
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

function spawn_pictune(wnd)
	local props = image_storage_properties(wnd.ctrl_id);
	if (wnd.pack_sz == 1) then
		wnd:set_message(
			"Only 3/4bpp packing input formats supported", DEFAULT_TIMEOUT);
		return;
	end

	local rt = build_unpacker(unpackers[1], wnd.ctrl_id);
	local nw = wnd.wm:add_window(rt, {});

	window_shared(nw);
	nw:set_parent(wnd, ANCHOR_LL);
	nw.basew = props.width;
	nw.copy = copy;
	nw.mode = 0;
	nw.splitw = 0.0;
	nw.ofs_t = 0.0;
	nw:select();

	nw.dispatch["LEFT"] = function()
		if (nw.mode == 0) then
			nw.split_w = nw.split_w - (nw.wm.meta and 10 or 1);
		else
			nw.ofs_t = nw.ofs_t - (nw.wm.meta and 10 or 1);
		end
		set_width(nw, nw.split_w, nw.ofs_t);
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
	set_width(nw, 533, 0);

	muppet = alloc_surface(props.width, props.height);
	int = null_surface(props.width, props.height);
	image_sharestorage(nw.canvas, int);

	nw.sh_drag = nw.drag;
	nw.motion = function() end;
	nw.drag = function(wnd, vid, x, y)
		if (wm.meta_detail) then
			if (nw.mode == 0) then
				set_width(wnd, wnd.split_w + 0.5 * x, wnd.ofs_s);
			else
				set_width(wnd, wnd.split_w, wnd.ofs_s + 0.5 * y);
			end
		else
			return wnd:sh_drag(vid, x, y);
		end
	end

	table.insert(nw.autodelete, copy);
end
