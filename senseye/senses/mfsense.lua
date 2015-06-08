-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: UI mapping for the multiple- file sensor
-- Notes: We derive most controls from the fsense (that in turn derive
-- from the psense) though some menu features and mappings (resize,
-- mapping etc.) has been dropped.
--
local rtbl = system_load("senses/fsense.lua")();

local disp = rtbl.dispatch_sub;
local pop = rtbl.popup_sub;
disp[BINDINGS["CYCLE_MAPPING"]] = function(wnd)
	wnd.labelofs = not wnd.labelofs;
	if (not wnd.labelofs) then
		wnd:set_message();
	else
		wnd:set_message("Offset: " .. tostring(wnd.ofs));
	end
end;

--
-- by default, these bindings are occupied by things like FSENSE
-- stepping, generator functions that check for meta and zoom
--
for i=1,10 do
	local old = disp[tostring(i)];
	disp[tostring(i)] = function(wnd)
		if (wnd.wm.meta) then
			wnd:zoom_to(i);
		elseif (old ~= nil) then
			old(wnd);
		end
	end
end

table.insert(pop, {
	label = "Tile Size...",
	name = "mfsense_tilesz_sub",
	submenu = function()
		local res = {};
		local i = 8;

		while i <= 512 do
			table.insert(res, {label = tostring(i), value = i});
			i = i*2;
		end

		res.handler = function(wnd, value)
			target_displayhint(wnd.ctrl_id, value, value);
		end

		return res;
	end
});

table.insert(pop, {
	label = "Zoom...",
	name = "mfsense_tilezoom_sub",
	submenu = function(wnd, a, b)
		if (wnd.tile_count == nil) then
			return;
		end

		local res = {};
		for i=1,wnd.tile_count do
			res[i] = {label = tostring(i), value = i};
		end

		res.handler = function(wnd, value)
			wnd:zoom_to(value);
		end

		return res;
	end
});

local function spawn_mfsense_pc(wnd)
	local res = {};
	local p = image_storage_properties(wnd.ctrl_id);
	local x = 0;
	local t = 0;
	local w = wnd.base / p.width;
	local h = wnd.base / p.height;

	for i=1,wnd_tile_count do
		res[i] = {x>0 and x/p.width or 0, y > 0 and y/p.height or y};
		res[i][3] = res[i][1] + w;
		res[i][4] = res[i][2] + h;
		x = x + wnd.base + wnd.tile_border;
		if (x > p.width) then
			x = 0;
			y = y + wnd.base + wnd.tile_border;
		end
	end
	spawn_pointcloud_multi(wnd, set);
end

table.insert(pop, {
	label = "Comparison Model",
	name = "mfsense_pointcloud",
	handler = spawn_mfsense_pc
});

-- similar to psense with some things added that didn't
-- belong to the main window before
local slisth = {
	framestatus = function(wnd, source, status)
-- might want to assert that this match possible legal values
		wnd.base = status.pts;
		wnd.ofs = status.frame;
		if (wnd.pending > 0) then
			wnd.pending = wnd.pending - 1;
		end

		if (wnd.labelofs) then
			wnd:set_message("Offset: " .. tostring(wnd.ofs));
		end
	end,
	streaminfo = function(wnd, source, status)
-- streamid: n, langid: n, datakind[0] : border, [1] = size
		local base = string.byte("0", 1);
		wnd.pack_sz = string.byte(status.lang, 2) - base;
		wnd.tile_count = tonumber(status.streamid);
		wnd.tile_border = string.byte(status.lang, 1) - base;
		wnd:set_message(msg, DEFAULT_TIMEOUT);
	end,

-- we delete everything except our special diff child this is race condition
-- prone for the first resize as it might have not yet registered when this
-- happens, so ignore the first one
	resized = function(wnd, source, status)
		local torem = {};
		if (not wnd.first_resize) then
			wnd.first_resize = true;
			return;
		end

		for k,v in ipairs(wnd.children) do
			if (not v.mfsense_diff) then
				table.insert(torem, v);
			end
		end
		for k,v in ipairs(torem) do
			v:destroy();
		end
	end,
	frame = function(wnd, source, status)
	end
};

local function zoom_ofs(wnd, ofs)
	if (wnd.in_zoom) then
		wnd.zoom_ofs[1] = 0.0; wnd.zoom_ofs[2] = 0.0;
		wnd.zoom_ofs[3] = 1.0; wnd.zoom_ofs[4] = 1.0;
		wnd.in_zoom = false;
		wnd:update_zoom();
		return;
	end

	ofs = ofs - 1;
	if (ofs >= wnd.tile_count) then
		return;
	end

	local y = 0;
	local x = 0;
	local p = image_storage_properties(wnd.ctrl_id);

	for i=0,ofs-1 do
		x = x + wnd.base + wnd.tile_border;
		if (x > p.width) then
			x = 0;
			y = y + wnd.base + wnd.tile_border;
		end
	end

	wnd.zoom_ofs[1] = x > 0 and x / p.width or 0;
	wnd.zoom_ofs[2] = y > 0 and y / p.height or 0;
	wnd.zoom_ofs[3] = wnd.zoom_ofs[1] + wnd.base / p.width;
	wnd.zoom_ofs[4] = wnd.zoom_ofs[2] + wnd.base / p.height;
	wnd.in_zoom = true;
	wnd:update_zoom();
end

-- menu items for tile sizes, should remove:
-- "menu_metadata", "menu_map"
--
-- and add a 'tile-size' and a 'delta toggle'
--
local rtbl = {
	name = "mfsense",
	dispatch_sub = disp,
	popup_sub = merge_menu(subwnd_menu, pop),
	source_listener = slisth,
	init = function(wnd)
		wnd.ofs = 0;
		wnd.dynamic_zoom = true;

		wnd.dblclick = function()
			local x, y = translate_2d(wnd, BADID, mouse_xy());
			local col = (x > 0) and math.floor(x/(wnd.base + wnd.tile_border)) or 0;
			local row = (y > 0) and math.floor(y/(wnd.base + wnd.tile_border)) or 0;
			local cpr = math.floor(image_storage_properties(
				wnd.ctrl_id).width / wnd.base);
			local iotbl = {kind = "digital", active = true,
				label = "FOCUS_" .. tostring(row * cpr + col)};
			target_input(wnd.ctrl_id, iotbl);
		end

-- probably a cute formula to this but the odd # border misalign
-- makes it somewhat irritating, just replicate the drawing formulae
		wnd.zoom_to = zoom_ofs;

		for i=#wnd.popup,1,-1 do
			if (wnd.popup[i].name == "menu_map" or
				wnd.popup[i].name == "menu_metadata" or
				wnd.popup[i].name == "menu_bufsz") then
				table.remove(wnd.popup, i);
			end
		end

		wnd.seek = function(wnd, ofs)
			target_seek(wnd.ctrl_id, ofs);
		end
	end
};

return rtbl;
