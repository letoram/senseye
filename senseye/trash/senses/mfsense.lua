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
	local shid = shader_ugroup(
		shaders_3dview_pcloud_multi[1].shid
	);

	local pcs = {};
	local p = image_storage_properties(wnd.ctrl_id);
	local x = 0;
	local y = 0;
	local w = wnd.base / p.width;
	local h = wnd.base / p.height;
	shader_uniform(shid, "txshift", "ffff", 0, 0, w, h);
	shader_uniform(shid, "match", "b", 1);

	local wh, fr = math.modf(p.width / (wnd.base + wnd.tile_border));

-- 1. need to subtract borders
	for i=1,wnd.tile_count do
		local msh = shader_ugroup(shid);
		local s1 = x > 0 and x/p.width or 0;
		local t1 = y > 0 and y/p.height or 0;

-- account for precision issues
		if (t1 / h ~= 0) then
			t1 = t1 + math.fmod(t1, h);
		end

		shader_uniform(msh, "txshift", "ffff", s1, t1, w, h);
		shader_uniform(msh, "match", "b", 1);
		x = x + wnd.base + wnd.tile_border;
		if (x >= p.width) then
			x = 0;
			y = y + wnd.base + wnd.tile_border;
		end
		pcs[i] = build_pointcloud(wnd.base * wnd.base, 2);
		image_sharestorage(wnd.ctrl_id, pcs[i]);
		image_shader(pcs[i], msh);
	end

	local new = create_model_window(wnd, pcs[1],
		shaders_3dview_pcloud_multi[1], true);

-- need to repeat as create_model overrides
	image_sharestorage(wnd.ctrl_id, pcs[1]);
	image_shader(pcs[1], shid);

	new.name = new.name .. "_pointcloud_multi";
	local ystep = 1.0 / #pcs;
	for i=2,#pcs do
		move3d_model(pcs[i], 0.0, ystep * (i-1), 0.0);
		blend_image(pcs[i], 0.9);
		table.insert(new.rotate_set, pcs[i]);
		rendertarget_attach(new.rendertarget, pcs[i], RENDERTARGET_DETACH);
	end

	new.set_pointsz = function(sz)
		new.point_sz = sz;
		for k,v in ipairs(new.rotate_set) do
			shader_uniform(image_shader(v), "point_sz", "f", new.point_sz);
		end
		shader_uniform(image_shader(new.model), "point_sz", "f", new.point_sz);
	end

	new.set_pointsz(gconfig_get("point_size"));

	new.dispatch[BINDINGS["POINTSZ_INC"]] = function()
		new.set_pointsz(new.point_sz + 0.5);
	end

	new.dispatch[BINDINGS["POINTSZ_DEC"]] = function()
		new.set_pointsz(new.point_sz < 1.5 and 1.0 or new.point_sz - 0.5);
	end

	new.match = 1;
	new.dispatch[BINDINGS["MODE_TOGGLE"]] = function()
		new.match = not new.match;
		for k,v in ipairs(new.rotate_set) do
			shader_uniform(image_shader(v), "match", "b", new.match and 1 or 0);
		end
		shader_uniform(image_shader(new.model), "match", "b",
			new.match and 1 or 0);
		new:set_message("Compare: " .. (new.match and "Match" or "Mismatch"));
	end

	print(new, new.dispatch[BINDINGS["POINTSZ_INC"]]);
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
		x = x + wnd.base + wnd.tile_border + 1;
		if (x >= p.width) then
			x = 0;
			y = y + wnd.base + wnd.tile_border;
		end
	end

	wnd.zoom_ofs[1] = x > 0 and x / p.width or 0;
	wnd.zoom_ofs[2] = y > 0 and y / p.height or 0;
	wnd.zoom_ofs[3] = wnd.zoom_ofs[1] + (wnd.base-1) / p.width;
	wnd.zoom_ofs[4] = wnd.zoom_ofs[2] + (wnd.base-1) / p.height;
	wnd.in_zoom = true;
	wnd:update_zoom(true);
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
		target_verbose(wnd.ctrl_id);

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
