-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: Basic UI / Popup Menu / management.
-- Provides default input dispatch routines shared by
-- most windows.
--
-- Exported Functions:
--  focus_window(wnd)   hook to map to window manager
--  defocus_window(wnd) hook to map to window manager
--  check_listeners(wnd)hook to map to window manager for cleanup
--  setup_dispatch(tbl) add basic input dispatch to table
--  window_shared(wnd)  add basic popups etc. to window
--  lookup_motion(wnd)  add overlay that shows agecant hex values on motion
--  merge_menu(m1, m2)  combine two popup menus into one
--  table.remove_match  find one occurence of (tbl, match) and remove
--  repos_window(wnd)   handle for automated positioning
--  copy_surface(vid)   readback and create a new raw surface
--

-- some more complex window setups are kept separately
system_load("histogram.lua")();
system_load("modelwnd.lua")();
system_load("distgram.lua")();
system_load("patfind.lua")();

local function wnd_reset(wnd)
	wnd.zoom_range = 1.0;
	wnd.zoom_ofs[1] = 0.0;
	wnd.zoom_ofs[2] = 0.0;
	wnd.zoom_ofs[3] = 1.0;
	wnd.zoom_ofs[4] = 1.0;
	wnd:update_zoom();
end

local function wnd_gather(wnd)
	local off_x = 0;
	local off_y = 0;

	for i=1, #wm.windows do
		if (wm.windows[i].parent and
			wm.windows[i].parent == wnd) then
			move_image(wm.windows[i].anchor, off_x, off_y);
			off_x = off_x + 10;
			off_y = off_y + 10;
		end
	end

	for i, v in ipairs(wnd.children) do
		if (#v.children > 0) then
			wnd_gather(v);
		end
	end
end

function repos_window(wnd)
	local props = image_surface_resolve_properties(wnd.canvas);
	if (props.x + props.width < 10) then
		nudge_image(wnd.anchor, 0 - props.x, 0);
	end
	if (props.y + props.height < 10) then
		nudge_image(wnd.anchor, 0, 0 - props.y);
	end
	for i, v in ipairs(wnd.children) do
		v:reposition();
	end
end

--
-- needs framestatus events forwarded from subwindow event handler
--
local function spawn_messages(wnd)
end

--
-- Combine and validate the menus supplied in m1 with m2.
-- m2 can override and cancel out menus in m1.
--
function merge_menu(m1, m2)
	local res = {};

-- shallow mapping
	for k,v in ipairs(m1) do
		table.insert(res, v);
	end

-- projection
	for k, v in ipairs(m2) do
		local found = false;
		for j,m in ipairs(res) do
			if (m.label == v.label) then
				res[j] = v;
				found = true;
				break;
			end
		end

		if (not found) then
			table.insert(res, v);
		end
	end

-- filter out "broken"
	local i = 1;
	while i <= #res do
		if (res[i].submenu == nil and
			res[i].value == nil and res[i].handler == nil) then
			table.remove(res, i);
		else
			i = i + 1;
		end
	end

	return res;
end

local function ppot(val)
	val = math.pow(2, math.floor( math.log(val) / math.log(2) ));
	return val < 32 and 32 or val;
end

local function npot(val)
	val = math.pow(2, math.ceil( math.log(val) / math.log(2) ));
	return val < 32 and 32 or val;
end

--
-- Main keybindings and functions for features like zoom and window management
--
function setup_dispatch(dt)
	local point_sz = gconfig_get("point_size");

	shader_pcloud_pointsz(point_sz);

-- just used for recording videos
-- dt["F9"] = function(wm)
--		local ns = null_surface(VRESW, VRESH);
--		image_sharestorage(WORLDID, ns);
--		image_set_txcos_default(ns, 1);
--		show_image(ns);
--		local buf = alloc_surface(VRESW, VRESH);
--		define_recordtarget(buf, "demo.mkv", "vpreset=8:fps=30:noaudio", {ns}, {},
--			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1);
--	end
--

	dt[BINDINGS["POINTSZ_INC"]] = function(wm)
		point_sz = point_sz + 0.5;
		gconfig_set("point_size", point_sz);
		shader_pcloud_pointsz(point_sz);
	end

	dt[BINDINGS["POINTSZ_DEC"]] = function(wm)
		point_sz = point_sz - 0.5;
		point_sz = point_sz < 1.0 and 1.0 or point_sz;
		gconfig_set("point_size", point_sz);
		shader_pcloud_pointsz(point_sz);
	end

	dt[BINDINGS["CANCEL"]] = function(wm)
		if (wm.meta) then
			return shutdown();

		elseif (wm.fullscreen) then
			wm:toggle_fullscreen();

		elseif (wm.selected) then
			wm.selected:deselect();
		end
	end

	dt[BINDINGS["TRANSLATORS"]] = function(wm)
		if (wm.fullscreen or wm.selected == nil) then
			return;
		end

		if (wm.meta and #translator_popup > 0) then
			spawn_popupmenu(wm, translator_popup);
		end
	end

	dt[BINDINGS["RESIZE_X2"]] = function(wm)
		if (wm.fullscreen) then
			return;
		end

		local wnd = wm.selected;
		if (wnd == nil) then
			return;
		end

		if (wm.meta) then
			local basew = ppot(wnd.width - 1);
			local baseh = ppot(wnd.height - 1);
			if (basew / baseh == wnd.width / wnd.height) then
				wnd:resize(basew, baseh);
			end
		else
			local basew = npot(wnd.width + 1);
			local baseh = npot(wnd.height + 1);
			wnd:resize(basew, baseh);
		end

		local x, y = mouse_xy();
		wnd:reposition();
		wnd:motion(wm.selected.canvas, x, y);
	end

	dt[BINDINGS["FULLSCREEN"]] = function(wm)
		wm:toggle_fullscreen();
	end

	dt["BACKSPACE"] = function(wm)
		if (wm.fullscreen) then
			return;
		end

		if (wm.meta) then
			if (wm.selected) then
				wm.selected:destroy();
			end
		end
	end
end

function focus_window(wnd)
	if (wnd.flag_popup == nil) then
		wnd:set_border(2, 192, 192, 192);
	end
end

local function translate_2d(wnd, vid, x, y)
-- figure out surface relative coordinate
	local oprops = image_storage_properties(wnd.canvas);
	local rprops = image_surface_resolve_properties(wnd.canvas);
	x = (x - rprops.x) / rprops.width;
	y = (y - rprops.y) / rprops.height;

-- use the current textured coordinates rather than wnd.zoom_range etc.
-- to get the benefit even if we do non-uniform magnification.
	local txcos = image_get_txcos(wnd.canvas);
	x = txcos[1] + x * (txcos[3] - txcos[1]);
	y = txcos[2] + y * (txcos[6] - txcos[2]);

-- translate into source input dimensions
	x = math.floor(x * oprops.width);
	y = math.floor(y * oprops.height);

	return x, y;
end

--
-- called on delete, make sure to drop the custom event
-- listeners so we don't get dangling vid / table refs.
--
function check_listeners(wnd)
	if (wnd.parent) then
		table.remove_match(wnd.parent.zoomh, wnd);
		table.remove_match(wnd.parent.source_listener, wnd);
	end
end

function defocus_window(wnd, nw)
	if (nw) then
		if (not nw.flag_popup) then
			wnd:set_border(1, 128, 128, 128);
		end
	else
		wnd:set_border(1, 128, 128, 128);
	end
end

local function update_zoom(wnd)
	local s1 = wnd.zoom_ofs[1];
	local t1 = wnd.zoom_ofs[2];
	local s2 = wnd.zoom_ofs[3] + wnd.zoom_ofs[1];
	local t2 = wnd.zoom_ofs[4] + wnd.zoom_ofs[2];

	local txcos = {s1, t1, s2, t1, s2, t2, s1, t2};
	image_set_txcos(wnd.canvas, txcos);
	if (wnd.zoomh == nil) then
		return;
	end

	for i,v in ipairs(wnd.zoomh) do
		if (v.zoom_link) then
			v:zoom_link(wnd, txcos);
		end
	end
end

function table.remove_match(tbl, match)
	if (tbl == nil) then
		return;
	end

	for k,v in ipairs(tbl) do
		if (v == match) then
			table.remove(tbl, k);
			return true;
		end
	end

	return false;
end

function table.remove_vmatch(tbl, match)
	if (tbl == nil) then
		return;
	end

	for k,v in pairs(tbl) do
		if (v == match) then
			tbl[k] = nil;
			return true;
		end
	end
	return false;
end

local function drop_zoom_handler(wnd, zoomh)
	if (wnd.zoomh) then
		table.remove_match(wnd.zoomh, zoomh);
	end
end

local function add_zoom_handler(wnd, zoomh)
	if (wnd.zoomh == nil) then
		wnd.zoomh = {};
	end

	drop_zoom_handler(wnd, zoomh);
	table.insert(wnd.zoomh, zoomh);
	update_zoom(wnd);
end

function lookup_motion(wnd, vid, x, y)
	if (not wnd.wm.meta) then
		return;
	end

-- by default, this is just the window itself (disabled when translation
-- is toggled) but
	if (wnd.message_recv) then
		image_access_storage(wnd.canvas, function(tbl, w, h)
			local props = image_surface_resolve_properties(wnd.canvas);
			local x, y = mouse_xy();
			x = x - props.x;
			y = y - props.y;
		end
		);
	end
end

--
-- sort out position and dimensions for a canvas clipped dynamic selection
--
local function get_positions(dz, maxw, maxh)
	local p1, p2, w, h;

	if (dz[1] < dz[3]) then
		p1 = dz[1];
		w = dz[3] - dz[1];
	else
		p1 = dz[3];
		w = dz[1] - dz[3];
	end

	if (dz[2] < dz[4]) then
		p2 = dz[2];
		h = dz[4] - dz[2];
	else
		p2 = dz[4];
		h = dz[2] - dz[4];
	end

	p1 = p1 <= 0 and 0 or p1;
	p2 = p2 <= 0 and 0 or p2;
	w = p1+w > maxw and maxw - p1 or w;
	h = p2+h > maxh and maxh - p2 or h;
	w = w <= 0 and 1 or w;
	h = h <= 0 and 1 or h;

	return p1, p2, w, h;
end

--
-- hooks and functions that act similarly between main and subwindows
--
function window_shared(wnd)
	wnd.update_zoom = update_zoom;
	wnd.add_zoom_handler = add_zoom_handler;
	wnd.drop_zoom_handler = drop_zoom_handler;

-- chain- override destroy to deregister any zoom handlers
	local destroy = wnd.destroy;
	wnd.destroy = function(wnd)
		if (wnd.parent) then
			wnd.parent:drop_zoom_handler(wnd);
		end
		destroy(wnd);
	end

-- used for hex-lookup etc. can be overridden by a message recv. window
	wnd.message_recv = wnd;
	wnd.msg_w = 4;
	wnd.msg_h = 1;

	wnd.zoom_ofs = {0, 0, 1.0, 1.0};
	wnd.zoom_range = 1.0;
	image_texfilter(wnd.canvas, FILTER_NONE);

	local prev_drag = wnd.drag;
	wnd.drag = function(wnd, vid, x, y)
		if (wnd.wm.meta and not wnd.dz) then
			return prev_drag(wnd, vid, x, y);
		end

-- pan and clamp
		if (wnd.zoom_range > 1.0) then
			local step = 1.0 / wnd.zoom_range;
			local ns = wnd.zoom_ofs[1];
			local nt = wnd.zoom_ofs[2];

			ns = ns + (0.01 * x / wnd.zoom_range);
			nt = nt + (0.01 * y / wnd.zoom_range);

			ns = step + ns > 1.0 and 1.0 - step or ns;
			ns = ns < 0.0 and 0.0 or ns;

			nt = step + nt > 1.0 and 1.0 - step or nt;
			nt = nt < 0.0 and 0.0 or nt;

			wnd.zoom_ofs[1] = ns;
			wnd.zoom_ofs[2] = nt;

			wnd:update_zoom();
		elseif wnd.dynamic_zoom then
			if (wnd.dz) then
				wnd.dz[3] = wnd.dz[3] + x;
				wnd.dz[4] = wnd.dz[4] + y;
				local x, y, w, h = get_positions(wnd.dz, wnd.width, wnd.height);
				move_image(wnd.dzv, x, y);
				resize_image(wnd.dzv, w, h);
			else
				local props = image_surface_resolve_properties(wnd.canvas);
				local mx, my = mouse_xy();
				mx = mx - props.x;
				my = my - props.y;
				wnd.dz = {mx, my, mx+1, my+1};
				wnd.dzv = color_surface(1, 1, 255, 255, 255);
				image_tracetag(wnd.dzv, "wnd_dynamic_zoom");
				link_image(wnd.dzv, wnd.canvas);
				image_inherit_order(wnd.dzv, true);
				order_image(wnd.dzv, 1);
				blend_image(wnd.dzv, 0.8);
				move_image(wnd.dzv, wnd.dz[1], wnd.dz[2]);
			end
		end
	end

	wnd.drop = function(wnd, vid, x, y)
		wnd.zoom_drag = false;

		if (wnd.dynamic_zoom and wnd.dz) then
			if (wnd.zoom_ofs[1] > 0) then
				wnd.zoom_ofs[1] = 0.0;
				wnd.zoom_ofs[2] = 0.0;
				wnd.zoom_ofs[3] = 1.0;
				wnd.zoom_ofs[4] = 1.0;
				wnd:update_zoom();
			else
				local x, y, w, h = get_positions(wnd.dz, wnd.width, wnd.height);
				wnd.zoom_ofs[1] = x / wnd.width;
				wnd.zoom_ofs[2] = y / wnd.height;
				wnd.zoom_ofs[3] = w / wnd.width;
				wnd.zoom_ofs[4] = h / wnd.height;
				wnd:update_zoom();
			end

			delete_image(wnd.dzv);
			wnd.dz = nil;
		end
	end

--
-- safe-guard against parent- relative motion and resizes
-- pushing the window out of reach for the user
--
	wnd.reposition = repos_window;
-- forward non-mapped input to the designated window,
-- NOTE: coordinates does not consider zoom now, should be more difficult
-- than multiplying with scale factor, offset and round
	wnd.input = function(wnd, tbl)
		if (wnd.ctrl_id) then
			target_input(wnd.ctrl_id, tbl);
		end
	end

	wnd.click = function(wnd, tbl, x, y)
		local rprops = image_surface_resolve_properties(wnd.canvas);
		x, y = translate_2d(wnd, BADID, x, y);

		wnd:select();
		if (wnd.wm.meta and wnd.zoomh) then
			for i,v in ipairs(wnd.zoomh) do
				if (v.zoom_position) then
					v:zoom_position(wnd, x, y);
				end
			end
		end
	end

	wnd.rclick = function(wnd, tbl)
		local wm = wnd.wm;
		local popup = wnd.wm.meta and wnd.popup_meta or wnd.popup;
		wnd:select();
		if (popup and #popup > 0) then
			spawn_popupmenu(wm, popup);
		end
	end

	wnd.dispatch[BINDINGS["ZOOM"]] = function(wnd)
		local w = wm.selected;
		if (w == nil or w.update_zoom == nil) then
			return;
		end

-- switch between custom zoom region and uniform
		if (w.zoom_range == 1.0 and (w.zoom_ofs[1] ~= 0.0 or
			w.zoom_ofs[2] ~= 0.0 or w.zoom_ofs[3] ~= 1.0 or
			w.zoom_ofs[4] ~= 1.0)) then
			wnd_reset(wnd);
		end

		if (not wm.meta) then
			wm.selected.zoom_range = wm.selected.zoom_range * 2.0;
		else
			w.zoom_range = w.zoom_range / 2.0;
			w.zoom_range = w.zoom_range < 1.0 and 1.0 or w.zoom_range;
		end
		w.zoom_ofs[3] = (1.0 / wnd.zoom_range);
		w.zoom_ofs[4] = (1.0 / wnd.zoom_range);
		w:update_zoom();
	end

-- use meta + tab to cycle focused window in same group,
-- or if no window, switch to children
	wnd.dispatch[BINDINGS["POPUP"]] = function(wnd)
		local wm = wnd.wm;

		if (wm.fullscreen or wm.selected == nil) then
			return;
		end

		if (wm.meta) then
			local ind = 1;
			for i=1,#wm.windows do
				if (wm.windows[i] == wnd) then
					ind = i;
					break;
				end
			end
			ind = (ind + 1 > #wm.windows) and 1 or (ind + 1);
			wm.windows[ind]:select();
		else
			spawn_popupmenu(wm, wnd.popup);
		end
	end
end

local function wnd_vistog(wnd)
	if (wnd.all_hidden) then
		for i,v in ipairs(wnd.children) do
			v:show();
		end
		wnd.all_hidden = false;
	else
		for i,v in ipairs(wnd.children) do
			v:hide();
		end
		wnd.all_hidden = true;
	end
end

local views_sub = {
	{
		label = "Point Cloud",
		name = "view_pointcloud",
		handler = spawn_pointcloud
	},
	{
		label = "Histogram",
		name = "view_histogram",
		handler = spawn_histogram
	},
	{
		label = "Distance Tracker",
		name = "view_distgram",
		handler = spawn_distgram
	},
	{
		label = "Pattern Finder",
		name = "view_patfind",
		handler = function(wnd)
			spawn_patfind(wnd, copy_surface(wnd.canvas));
		end
	}
};

local wnd_subwin = {
	{
		label = "Gather",
		name = "subwin_gather",
		handler = wnd_gather
	},
	{
		label = "Hide/Show All",
		name = "subwin_vistog",
		handler = wnd_vistog
	}
};

controlwnd_menu = {
	{
		label = "Subwindows...",
		name  = "ctrl_subwin",
		submenu = wnd_subwin
	},
	{
		label = "Reset",
		name = "zoom_reset",
		handler = wnd_reset
	},
};

local function motion_2d(wnd, vid, x, y)
	if (wnd.map) then
		local x, y = translate_2d(wnd, BADID, x, y);
		local img, lines = render_text(menu_text_fontstr .. wnd:map(x, y));
		wnd:set_message(img);
	end
end

local subwnd_toggle = function(wnd)
	if (wnd.motion == motion_2d) then
		wnd.motion = function() end;
		wnd.message_recv = wnd;
	else
		wnd.motion = motion_2d;
		wnd.message_recv = nil;
	end
end

local wnd_xl = {
	{
		label = "Toggle On/Off",
		handler = subwnd_toggle
	},
};

local function gen_dumpname(sens, suffix)
	local testname;
	local attempt = 0;

	repeat
		testname = string.format("dumps/%s_%d%s.%s", sens,
			benchmark_timestamp(1), attempt > 0 and tostring(CLOCK) or "", suffix);
		attempt = attempt + 1;
	until (resource(testname) == nil);

	return testname;
end

local function dump_png(wnd)
	local name = gen_dumpname(wnd.basename, "png");
	save_screenshot(name, FORMAT_PNG_FLIP, wnd.ctrl_id);
	wnd:set_message(render_text(menu_text_fontstr .. name .. " saved"), 100);
end

local function dump_full(wnd)
	local name = gen_dumpname(wnd.basename, "raw");
	save_screenshot(name, FORMAT_RAW32, wnd.ctrl_id);
	wnd:set_message(render_text(menu_text_fontstr .. name .. " saved"), 100);
end

function copy_surface(vid)
	local newimg = BADID;

	image_access_storage(vid, function(tbl, w, h)
		local out = {};
		for y=1,h do
			for x=1,w do
				local r,g, b = tbl:get(x-1, y-1, 3);
				table.insert(out, r);
				table.insert(out, g);
				table.insert(out, b);
			end
		end
		newimg = raw_surface(w, h, 3, out);
	end);

	return newimg;
end

local function dump_noalpha(wnd)
	local name = gen_dumpname(wnd.basename, "raw");
	local fmt = FORMAT_RAW32;

	if wnd.size_cur == 1 then
		fmt = FORMAT_RAW8;
	elseif wnd.size_cur == 3 then
		fmt = FORMAT_RAW24;
	end

	save_screenshot(name, fmt, wnd.ctrl_id);
	wnd:set_message(render_text(menu_text_fontstr .. name .. " saved"), 100);
end

local wnd_dump = {
	{
		label = "PNG",
		handler = dump_png
	},
	{
		label = "Full",
		handler = dump_full
	},
	{
		label = "No Alpha",
		handler = dump_noalpha
	}
};

subwnd_menu = {
	{
		label = "Reset",
		name = "zoom_reset",
		handler = reset_wnd
	},
	{
		label = "Views...",
		submenu = views_sub,
	},
	{
		label = "Translation...",
		submenu = function()
			return data_meta_popup[1].submenu();
		end
	},
	{
		label = "Dump...",
		submenu = wnd_dump
	},
};
