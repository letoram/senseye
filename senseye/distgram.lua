-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description:
-- Distance- Table is visually similar to a histogram,
-- but works from a base position and tracks the distance
-- to the nearest byte for each possible value (if found).
--

local function update_distwnd(wnd, dist, maxd)
	local tbl = {};

	for i=0,255 do
		tbl[i+1] = (dist[i] ~= nil and dist[i] or 0) / maxd * 255;
	end

	wnd.distances = dist;
	local dv = raw_surface(256, 1, 1, tbl);
	image_sharestorage(dv, wnd.canvas);
	delete_image(dv);
end

--
-- We need to have one of these for each packing configuration.
-- Algorithm:
--  starting at x,y - for each remaining pixel (or all 256 possible
--  values has been found), sample the pixel and if no distance
--  has been recorded, store the distance found.
--
--  then normalize the table against the max possible distance
--  and convert to a textured backing store that is rendered like
--  any other histogram.
--
local function update_distance(tbl, value, dist, max, count)
	if (tbl[value] == nil) then
		tbl[value] = dist;
		max = dist > max and dist or max;
		count = count + 1;
	end
	return max, count;
end

local function gen_distimg_pack1(wnd, dst, src, x, y)
	local dist = {};
	local count = 0;
	local maxd = 0;

	image_access_storage(src, function(tbl, w, h)
		local base = y * w + x;

		for row=y,h-1 do
			for col=x,w-1 do
				local v = tbl:get(row, col, 1);
				maxd, count = update_distance(dist, v, (row*w+col)-base, maxd, count);
				if (count == 255) then
					return;
				end
			end
		end
	end);

	update_distwnd(wnd, dist, maxd);
end

local function gen_distimg_pack3(wnd, dst, src, x, y)
	local dist = {};
	local count = 0;
	local maxd = 0;

	image_access_storage(src, function(tbl, w, h)
		local base = (y * w + x) * 3;

		for row=y,h-1 do
			for col=x,w-1 do
				local r,g,b = tbl:get(row, col, 3);
				local bp = (row * w + col) * 3;
				maxd, count = update_distance(dist, r, bp-base+0, maxd, count);
				maxd, count = update_distance(dist, g, bp-base+1, maxd, count);
				maxd, count = update_distance(dist, b, bp-base+2, maxd, count);
				if (count >= 255) then
					return;
				end
			end
		end
	end);

	update_distwnd(wnd, dist, maxd);
end

local function gen_distimg_pack4(wnd, dst, src, x, y)
	local dist = {};
	local count = 0;
	local maxd = 0;

	image_access_storage(src, function(tbl, w, h)
		local base = (y * w + x) * 4;

		for row=y,h-1 do
			for col=x,w-1 do
				local r,g,b,a = tbl:get(row, col, 4);
				local bp = (row * w + col) * 4;
				maxd, count = update_distance(dist, r, bp-base+0, maxd, count);
				maxd, count = update_distance(dist, g, bp-base+1, maxd, count);
				maxd, count = update_distance(dist, b, bp-base+2, maxd, count);
				maxd, count = update_distance(dist, a, bp-base+3, maxd, count);
				if (count >= 255) then
					return;
				end
			end
		end
	end);

	update_distwnd(wnd, dist, maxd);
end

--
-- there's no sane "2-byte per pixel" packing format
--
local gen_lut = {
	gen_distimg_pack1,
	nil,
	gen_distimg_pack3,
	gen_distimg_pack4
};

local function disttbl_motion(wnd, vid, x, y)
	local rprops = image_surface_resolve_properties(wnd.canvas);
	local newx = (x-rprops.x > wnd.width) and wnd.width or (x-rprops.x);
	move_image(wnd.cursor, newx, 0);
	resize_image(wnd.cursor, 1, rprops.height);
	x = (x - rprops.x) / wnd.width;
	local slot = math.floor(x * 255);

	local labelstr = string.format("%sbyte(%d) - %s", menu_text_fontstr,
		slot, (wnd.distances == nil or wnd.distances[slot] == nil)
		and "not found" or (tostring(wnd.distances[slot] .. " bytes")));

	local msg = render_text(labelstr);
	wnd:set_message(msg);
end

function spawn_distgram(wnd)
	local props = image_storage_properties(wnd.ctrl_id);
	local distances = {};
	for i = 1, 256 do
		distances[i] = 0;
	end
	local surf = raw_surface(256, 1, 1, distances);
	local nw = wnd.wm:add_window(surf, {});
	nw:set_parent(wnd, ANCHOR_LR);
	nw.fullscreen_disabled = true;
	nw.sample_x = 0;
	nw.sample_y = 0;
	nw.shader_group = shaders_1dplot;
	nw.shind = 1;
	nw.reposition = repos_window;
	defocus_window(nw);
	switch_shader(nw, nw.canvas, shaders_1dplot[1]);
	nw.motion = disttbl_motion;
	nw:resize(wnd.width, wnd.height);

	local cursor = color_surface(1, wnd.height, 0, 255, 0);
	blend_image(cursor, 0.8);
	link_image(cursor, nw.canvas);
	image_inherit_order(cursor, true);
	order_image(cursor, 1);
	image_mask_set(cursor, MASK_UNPICKABLE);
	table.insert(nw.autodelete, cursor);
	nw.cursor = cursor;

	nw.update_disttbl = function()
		if (gen_lut[wnd.pack_sz]) then
			gen_lut[wnd.pack_sz](nw, nw.canvas,
				wnd.canvas, nw.sample_x, nw.sample_y);
		end
	end

	nw.source_handler = function(nw, source, status)
		if (status.kind == "frame") then
			nw.sample_x = 0;
			nw.sample_y = 0;
			nw:update_disttbl();
		end
	end

	nw.zoom_position = function(self, wnd, px, py)
		nw.sample_x = px;
		nw.sample_y = py;
		nw:update_disttbl();
	end

	nw.parent:add_zoom_handler(nw);
	table.insert(wnd.source_listener, nw);
	nw:update_disttbl();
end
