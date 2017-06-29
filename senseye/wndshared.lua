-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description:
-- The functions in here deal with window management, window creation
-- and adding type- specific features when it comes to mouse actions on
-- the window surface.
--
-- system_load("histogram.lua")();
-- system_load("modelwnd.lua")();
-- system_load("distgram.lua")();
-- system_load("patfind.lua")();
-- system_load("alphamap.lua")();
-- system_load("pictune.lua")();

local function wnd_reset(wnd)
	wnd.zoom_range = 1.0;
	wnd.zoom_ofs[1] = 0.0;
	wnd.zoom_ofs[2] = 0.0;
	wnd.zoom_ofs[3] = 1.0;
	wnd.zoom_ofs[4] = 1.0;
	wnd:update_zoom();
end

-- setup bars, scrollhandlers, input handlers etc. based on type
-- control : windows spawned from here are treated as data
-- data (overlays, top and bottom, possible scroll-areas,
-- view (data views)
-- generic (used for mapping in normal clients like terminal)
function wndshared_setup(wnd, wndtype)
	local fontfn = function() return "\\f,0"; end
-- default buttons
	local tb = wnd:set_bar("t", 18);
	tb:add_button("right", "DEFAULT", "DEFAULT", "X", 0, fontfn, 16, 16,
		{
			click = function()
				wnd:destroy();
			end
		}
	);
	tb:add_button("center", "DEFAULT", "DEFAULT", "", 0, fontfn, 16, 16,
		{
			drag = function(ctx, vid, dx, dy)
				nudge_image(wnd.anchor, dx, dy);
			end
		}
	);
	local bb = wnd:set_bar("b", 18);
	bb:add_button("right", "DEFAULT", "DEFAULT", "Z", 0, fontfn, 15, 15,
		{
			drag = function() print("drag zoom"); end,
			rclick = function() print("popup"); end
		}
	);
	bb:add_button("center", "DEFAULT", "DEFAULT", "defuq", 0, fontfn, 16, 16);
end

local function zoom_position(wnd, x, y, click)
	wnd:select();

	if (wnd.zoomh) then
		for i,v in ipairs(wnd.zoomh) do
			if (v.zoom_position) then
				local r, g, b, a;
				image_access_storage(wnd.canvas, function(tbl, w, h)
					if (x < w and y < h) then
						r, g, b, a = tbl:get(x, y, 4);
					end
				end);
				v:zoom_position(wnd, x, y, r, g, b, a, click);
			end
		end
	end
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

local function drop_rmeta(wnd)
	if (wnd.wm.meta_detail) then
		wnd:set_message();
		if (valid_vid(wnd.wm.meta_zoom)) then
			delete_image(wnd.wm.meta_zoom);
			wnd.wm.meta_zoom = BADID;
		end
	end
end

--
-- Main keybindings and functions for features like zoom and window management
--
function setup_dispatch(dt)
	dt[BINDINGS["POPUP"]] =
	function(wm)
		spawn_popupmenu(wm, (wm.selected and wm.selected.popup) and
			wm.selected.popup or MENUS["system"]);
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
end

function focus_window(wnd)
	if (wnd.flag_popup == nil) then
		wnd:set_border(2, unpack(wnd.focus_color));
	end
end

function translate_2d(wnd, vid, x, y)
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

	return (x < 0 and 0 or x), (y < 0 and 0 or y);
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
			wnd:set_border(1, unpack(wnd.normal_color));
		end
	else
		wnd:set_border(1, unpack(wnd.normal_color));
	end
end

local function update_zoom(wnd, nalign)
	local s1 = wnd.zoom_ofs[1];
	local t1 = wnd.zoom_ofs[2];
	local s2 = wnd.zoom_ofs[3];
	local t2 = wnd.zoom_ofs[4];

	local props = image_storage_properties(wnd.canvas);

	local step_s = 1.0 / props.width;
	local step_t = 1.0 / props.height;

-- align against grid to lessen precision effects in linked windows
	if (not nalign) then
		s1 = s1 - math.fmod(s1, step_s);
		t1 = t1 - math.fmod(t1, step_t);
		s2 = s2 + math.fmod(s2, step_s);
		t2 = t2 + math.fmod(t2, step_t);
		t2 = t2 > 1.0 and 1.0 or t2;
		s2 = s2 > 1.0 and 1.0 or s2;
	end

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

local function clamp_zoom(wnd)
	local zs = 1.0 / wnd.zoom_range;
	if (wnd.zoom_ofs[3] > 1.0) then
		wnd.zoom_ofs[1] = 1.0 - zs;
		wnd.zoom_ofs[3] = 1.0;
	end
	if (wnd.zoom_ofs[4] > 1.0) then
		wnd.zoom_ofs[2] = 1.0 - zs;
		wnd.zoom_ofs[4] = 1.0;
	end
end

local function resize_zone(wnd)
	local props = image_surface_resolve_properties(wnd.canvas);
	local mx, my = mouse_xy();
	local lx = mx - props.x;
	local ly = my - props.y;
	return (wnd.width < 32 or wnd.height < 32) or
		(lx > wnd.width * 0.6667 and ly > wnd.height * 0.6667);
end

local function update_zoom_preview(wnd, x, y)
	if (not wnd.zoom_preview or wnd.in_zoom) then
		return;
	end

	if (not valid_vid(wnd.wm.meta_zoom)) then
		local ms = null_surface(80, 80);
		image_sharestorage(wnd.canvas, ms);
		link_image(ms, wnd.canvas);
		show_image(ms);
		image_inherit_order(ms, true);
		order_image(ms, 2);
		image_mask_set(ms, MASK_UNPICKABLE);
		force_image_blend(ms, BLEND_NONE);
		wnd.wm.meta_zoom = ms;
	end

	local lx, ly = translate_2d(wnd, BADID, x, y);
	local props = image_storage_properties(wnd.canvas);
	local ss = 1.0 / props.width;
	local st = 1.0 / props.height;
	local txcos = {
		(lx-3)*ss, (ly-3)*st, (lx+4)*ss, (ly-3)*st,
		(lx+4)*ss, (ly+4)*st, (lx-3)*ss, (ly+4)*st
	};
	image_set_txcos(wnd.wm.meta_zoom, txcos);
	props = image_surface_resolve_properties(wnd.canvas);
	move_image(wnd.wm.meta_zoom, x - props.x - 40, y - props.y - 40);
	image_shader(wnd.wm.meta_zoom, "preview_zoom");
end

local function motion_2d(wnd, vid, x, y)
	if (wnd.wm.meta_detail and wnd.wm.selected == wnd and not wnd.dz) then
		local lx, ly = translate_2d(wnd, BADID, x, y);
		zoom_position(wnd, lx, ly);
		update_zoom_preview(wnd, x, y);
		if (wnd.map) then
			local img, lines = render_text({menu_text_fontstr, wnd:map(lx, ly)});
			wnd:set_message(img, -1);
		end
	end
end

--
-- order 2 points that form a square so we get a texel-aligned, surface
-- normalized square that accounts for a zoom-level
--
local function get_positions(dz, maxw, maxh)
	local x1, y1, x2, y2;

-- clamp and reorder
	if (dz[1] < dz[3]) then
		x1 = dz[1];
		x2 = dz[3];
	else
		x1 = dz[3];
		x2 = dz[1];
	end

	if (dz[2] < dz[4]) then
		y1 = dz[2];
		y2 = dz[4];
	else
		y1 = dz[4];
		y2 = dz[2];
	end

	y2 = y2 > maxh and maxh or y2;
	x2 = x2 > maxw and maxw or x2;
	x1 = x1 < 0 and 0 or x1;
	y1 = y1 < 0 and 0 or y1;
	x2 = x2 == x1 and x1 + 1 or x2;
	y2 = y2 == y1 and y1 + 1 or y2;

	return {x1, y1, x2, y2};
end

local function pos_to_surface(inp, maxw, maxh, srfw, srfh, zoom)
-- from window- space to surface relative
	local pos = {};
	pos[1] = inp[1] / maxw;
	pos[2] = inp[2] / maxh;
	pos[3] = inp[3] / maxw;
	pos[4] = inp[4] / maxh;

	local step_s = 1.0 / srfw;
	local step_t = 1.0 / srfh;

-- account for zoom
	local sfx = (zoom[3] - zoom[1]);
	local sfy = (zoom[4] - zoom[2]);

	pos[1] = zoom[1] + sfx * pos[1];
	pos[2] = zoom[2] + sfy * pos[2];
	pos[3] = zoom[1] + sfx * pos[3];
	pos[4] = zoom[2] + sfy * pos[4];

-- align to grid
	pos[1] = pos[1] - math.fmod(pos[1], step_s);
	pos[2] = pos[2] - math.fmod(pos[2], step_t);
	pos[3] = pos[3] + math.fmod(pos[3], step_s);
	pos[4] = pos[4] + math.fmod(pos[4], step_t);

	return pos;
end

local function wnd_resize(wnd, vid, x, y)
	local neww = wnd.width + x;
	local newh = wnd.height + y;
	neww = neww <= 0 and 1 or neww;
	newh = newh <= 0 and 1 or newh;
	if (neww ~= wnd.width or newh ~= wnd.height) then
		wnd:resize(neww, newh);
	end
end

--
-- two ways of zooming, uniform (which permits drag->pan)
-- and custom which is reset when repeated
--
local function wnd_drag(wnd, vid, x, y)
	if (wnd.wm.meta_detail) then
		local mx, my = mouse_xy();
		update_zoom_preview(wnd, mx, my);
	end

	if (wnd.dragmode) then
		return wnd:dragmode(vid, x, y);
	end

-- pan and clamp
	if (wnd.zoom_range > 1.0) then
		local zs = 1.0 / wnd.zoom_range;
		local step_s = zs / wnd.width;
		local step_t = zs / wnd.height;
		wnd.zoom_ofs[1] = wnd.zoom_ofs[1] + x * step_s;
		wnd.zoom_ofs[2] = wnd.zoom_ofs[2] + y * step_t;
		wnd.zoom_ofs[1] = wnd.zoom_ofs[1] < 0.0 and 0.0 or wnd.zoom_ofs[1];
		wnd.zoom_ofs[2] = wnd.zoom_ofs[2] < 0.0 and 0.0 or wnd.zoom_ofs[2];
		wnd.zoom_ofs[3] = wnd.zoom_ofs[1] + zs;
		wnd.zoom_ofs[4] = wnd.zoom_ofs[2] + zs;
		wnd:clamp_zoom(wnd);
		wnd:update_zoom();
	elseif wnd.dynamic_zoom then
		if (wnd.dz) then
			wnd.dz[3] = wnd.dz[3] + x;
			wnd.dz[4] = wnd.dz[4] + y;
			local pos = get_positions(wnd.dz, wnd.width, wnd.height);
			move_image(wnd.dzv, pos[1], pos[2]);
			if (wnd.zoom_popup) then
				image_color(wnd.dzv, 255, 0, 0);
			else
				image_color(wnd.dzv, 255, 255, 255);
			end
			resize_image(wnd.dzv, pos[3] - pos[1], pos[4] - pos[2]);
		else
			local props = image_surface_resolve_properties(wnd.canvas);
			local mx = mouse_state().press_x;
			local my = mouse_state().press_y;
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

--
-- hooks and functions that act similarly between main and subwindows
--
function window_shared(wnd)
	wnd.update_zoom = update_zoom;
	wnd.add_zoom_handler = add_zoom_handler;
	wnd.drop_zoom_handler = drop_zoom_handler;
	wnd.clamp_zoom = clamp_zoom;

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

	wnd.out = function()
		drop_rmeta(wnd);
		mouse_switch_cursor();
	end
	wnd.motion = motion_2d;

	wnd.prev_drag = wnd.drag;
	wnd.drag = wnd_drag;
	wnd.drop = function(wnd, vid, x, y)
		wnd.dragmode = nil;
		if (wnd.dynamic_zoom and wnd.dz) then
			if (wnd.zoom_popup and wnd.zoom_meta_popup) then
				local inp = get_positions(wnd.dz, wnd.width, wnd.height);
				local sp = image_storage_properties(wnd.canvas);
				local pos = pos_to_surface(inp,
					wnd.width, wnd.height, sp.width, sp.height, wnd.zoom_ofs);

				wnd.corrupt = {
					math.floor(pos[1] * sp.width),
					math.floor(pos[2] * sp.height),
					math.ceil(pos[3] * sp.width),
					math.ceil(pos[4] * sp.height)
				};
				wnd.zoom_popup = not wnd.zoom_popup;
				table.insert(
					spawn_popupmenu(wm, wnd.zoom_meta_popup).autodelete, wnd.dzv);
			elseif (wnd.in_zoom) then
				wnd.zoom_ofs[1] = 0.0;
				wnd.zoom_ofs[2] = 0.0;
				wnd.zoom_ofs[3] = 1.0;
				wnd.zoom_ofs[4] = 1.0;
				wnd:update_zoom();
				wnd.in_zoom = false;
				delete_image(wnd.dzv);
			else
				local pos = get_positions(wnd.dz, wnd.width, wnd.height);
				local sp = image_storage_properties(wnd.canvas);
				wnd.zoom_ofs = pos_to_surface(pos,
					wnd.width, wnd.height, sp.width, sp.height, {0.0, 0.0, 1.0, 1.0});
				wnd.in_zoom = true;
				wnd:update_zoom();
				delete_image(wnd.dzv);
			end

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
		zoom_position(wnd, x, y, true);
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

		local zs = 1.0 / wnd.zoom_range;
		wnd.zoom_ofs[3] = wnd.zoom_ofs[1] + zs;
		wnd.zoom_ofs[4] = wnd.zoom_ofs[2] + zs;
		clamp_zoom(wnd);
		w:update_zoom();
	end

-- use meta + tab to cycle focused window in same group,
-- or if no window, switch to children
	wnd.dispatch[BINDINGS["POPUP"]] = function(wnd)
		local wm = wnd.wm;
		if (wnd.dz) then
			wnd.zoom_popup = not wnd.zoom_popup;
			local x, y = mouse_xy();
			wnd_drag(wnd, wm.selected.canvas, 0, 0);
			return;
		end

		if (wm.fullscreen or wm.selected == nil) then
			return;
		end

		if (wm.meta) then
			wm:step_selected(wnd);
		else
			spawn_popupmenu(wm, wnd.popup);
		end
	end
end


