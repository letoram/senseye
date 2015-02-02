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
--  setup_dispatch(tbl) add basic input dispatch to table
--  window_shared(wnd)  add basic popups etc. to window
--  lookup_motion(wnd)  add overlay that shows agecant hex values on motion
--  merge_menu(m1, m2)  combine two popup menus into one
--

-- some more complex window setups are kept separately
system_load("histogram.lua")();
system_load("modelwnd.lua")();

local function wnd_reset(wnd)
	wnd.zoom_range = 1.0;
	wnd.zoom_ofs[1] = 0.0;
	wnd.zoom_ofs[2] = 0.0;
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

function ppot(val)
	val = math.pow(2, math.floor( math.log(val) / math.log(2) ));
	return val < 32 and 32 or val;
end

function npot(val)
	val = math.pow(2, math.ceil( math.log(val) / math.log(2) ));
	return val < 32 and 32 or val;
end

--
-- Main keybindings and functions for features like zoom and window management
--
function setup_dispatch(dt)
	local point_sz = gconfig_get("point_size");

	shader_pcloud_pointsz(point_sz);

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

	dt[BINDINGS["RESIZE_X2"]] = function(wm)
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
	local s2 = (1.0 / wnd.zoom_range) + wnd.zoom_ofs[1];
	local t1 =  wnd.zoom_ofs[2];
	local t2 = (1.0 / wnd.zoom_range) + wnd.zoom_ofs[2];
	local txcos = {s1, t1, s2, t1, s2, t2, s1, t2};
	image_set_txcos(wnd.canvas, txcos);
	if (wnd.zoomh == nil) then
		return;
	end

	for i,v in ipairs(wnd.zoomh) do
		v:zoom_link(wnd, txcos);
	end
end

local function drop_zoom_handler(wnd, zoomh)
	if (wnd.zoomh) then
		for k,v in ipairs(wnd.zoomh) do
			if (v == zoomh) then
				table.remove(wnd.zoomh, k);
				return;
			end
		end
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

-- sample n pixels in a clamped square around around into overlay string,
-- x, y is the primary value and should be highlighted as such
-- then (clamped) +- sw, +- sh taking packing into account
local function get_hexstr(tbl, w, h, x, y, sw, sh, pack)
--		local r, g, b, a = tbl:get(x, y, 3);
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
--			wnd.message_recv:set_message( get_hexstr(tbl,
--				w, h, x, y, wnd.message_recv.msg_w * 2,
--				wnd.message_recv.msg_h, wnd.pack_sz )
--			);
		end
		);
	end
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

	wnd.zoom_ofs = {0, 0};
	wnd.zoom_range = 1.0;
	image_texfilter(wnd.canvas, FILTER_NONE);

	local prev_drag = wnd.drag;
	wnd.drag = function(wnd, vid, x, y)
		if (wnd.wm.meta) then
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

	wnd.click = function(wnd, tbl)
		wnd:select();
	end

	wnd.rclick = function(wnd, tbl)
		local wm = wnd.wm;
		wnd:select();
		if (wnd.popup and #wnd.popup > 0) then
			spawn_popupmenu(wm, wnd.popup);
		end
	end

	wnd.dispatch[BINDINGS["ZOOM"]] = function(wnd)
		local w = wm.selected;
		if (w == nil or w.update_zoom == nil) then
			return;
		end

		if (not wm.meta) then
			wm.selected.zoom_range = wm.selected.zoom_range * 2.0;
		else
			w.zoom_range = w.zoom_range / 2.0;
			w.zoom_range = w.zoom_range < 1.0 and 1.0 or w.zoom_range;
		end
		w:update_zoom();
	end

-- use meta + tab to cycle focused window in same group,
-- or if no window, switch to children
	wnd.dispatch[BINDINGS["POPUP"]] = function(wnd)
		local wm = wnd.wm;

		if (wm.fullscreen) then
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

-- forward to the sensor that can translate into a source-
-- relative offset (text representation)
	if (wnd.map) then
		local img, lines = render_text(menu_text_fontstr .. wnd:map(x, y));
		wnd:set_message(img);
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

local subwnd_toggle = function(wnd)
	if (wnd.motion == translate_2d) then
		wnd.motion = function() end;
		wnd.message_recv = wnd;
	else
		wnd.motion = translate_2d;
		wnd.message_recv = nil;
	end
end

local wnd_xl = {
	{
		label = "Toggle On/Off",
		handler = subwnd_toggle
	},
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
		submenu = wnd_xl
	},
};
