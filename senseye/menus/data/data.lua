-- need this to calculate position when hilbert mapping is applied
system_load("hilbert.lua")();

local pack_sztbl = {
	4,
	3,
	1
};

-- hack for packing current data state using streaminfo
local function dec_stream(wnd, source, status)
	local base = string.byte("a", 1);
	local upd = "";

	local pack_cur = string.byte(status.lang, 1) - base;
	local map_cur  = string.byte(status.lang, 2) - base;
	local size_cur = string.byte(status.lang, 3) - base;
	local pack_sz  = pack_sztbl[pack_cur+1];

	wnd.ack = {
		pack = pack_cur,
		map = map_cur,
		size = size_cur,
		pack_sz = pack_sz
	};

	for k,v in ipairs(wnd.translators) do
		target_graphmode(v.external, pack_sz);
	end
end

local function translate_2d(vid, x, y)
-- figure out surface relative coordinate
	local oprops = image_storage_properties(vid);
	local rprops = image_surface_resolve_properties(vid);
	x = (x - rprops.x) / rprops.width;
	y = (y - rprops.y) / rprops.height;

	local txcos = image_get_txcos(vid);
	x = txcos[1] + x * (txcos[3] - txcos[1]);
	y = txcos[2] + y * (txcos[6] - txcos[2]);

-- translate into source input dimensions
	x = math.floor(x * oprops.width);
	y = math.floor(y * oprops.height);

	return (x < 0 and 0 or x), (y < 0 and 0 or y);
end

local function recalc_zoom(wnd)
	local s1 = wnd.zoom[1];
	local t1 = wnd.zoom[2];
	local s2 = wnd.zoom[3];
	local t2 = wnd.zoom[4];

	local props = image_storage_properties(wnd.canvas);

	local step_s = 1.0 / props.width;
	local step_t = 1.0 / props.height;

-- align against grid to lessen precision effects in linked windows
	if (false) then
	s1 = s1 - math.fmod(s1, step_s);
	t1 = t1 - math.fmod(t1, step_t);
	s2 = s2 + math.fmod(s2, step_s);
	t2 = t2 + math.fmod(t2, step_t);
	t2 = t2 > 1.0 and 1.0 or t2;
	s2 = s2 > 1.0 and 1.0 or s2;
	end

	wnd.zoom = {s1, t1, s2, t2};
	local txcos = {s1, t1, s2, t1, s2, t2, s1, t2};

	image_set_txcos(wnd.canvas, txcos);
end

local function all_subs(wnd, func, ...)
	for k,v in ipairs(wnd.tools) do
		if (v[func]) then
			v[func](v, ...);
		end
	end
	for k,v in ipairs(wnd.translators) do
		if (v[func]) then
			v[func](v, ...);
		end
	end
end

local function fs_upd(wnd, source, status)
	wnd.offset = status.pts;
	all_subs(wnd, "pupdate", wnd);
	return true;
end

local function fs_stat(wnd, source, status)
	return true;
end

local function list_overlays(ctx)
	local wnd = ctx.wm.selected;
	local res = {};
	for k,v in ipairs(wnd.translators) do
		if (v.overlay_id) then
			table.insert(res,
{
name = "ol_" .. tostring(k),
label = v.overlay_id,
kind = "action",
handler = function()
	v:add_overlay();
end
}
			);
		end
	end
	return res;
end

-- propagate resized dimensions to connected overlays, but only if
-- they are actually active to prevent storms
local function datawnd_resize(wnd)
	wnd:synch_overlays();
end

local function update_txcos(wnd)
	local x1 = wnd.zoom[1] / wnd.base;
	local y1 = wnd.zoom[2] / wnd.base;
	local x2 = wnd.zoom[3] / wnd.base;
	local y2 = wnd.zoom[4] / wnd.base;
	local txcos = {x1, y1, x2, y1, x2, y2, x1, y2};
	image_set_txcos(wnd.canvas, txcos);

	wnd:synch_overlays();
	all_subs(wnd, "on_zoom", wnd.zoom);
end

local function dec_resize(wnd, source, status)
	wnd.base = status.width;
	if (wnd.resize and wnd.translators) then
		for k,v in ipairs(wnd.translators) do
			target_displayhint(v.external, wnd.base, wnd.base);
		end
	end

	if (status.width ~= status.height) then
		warning(string.format("resize(%d,%d) expected pow2 and w=h",
			status.width, status.height));
	end
	stepframe_target(wnd.external, 0);
-- need to cascade to connected translators and overlays too
end

function datawnd_setup(newwnd)
	newwnd.set_packing = function(ctx, pv)
		ctx.pack = pv;
		target_graphmode(ctx.external, 20 + pv);
	end

	newwnd.set_alpha = function(ctx, av)
		ctx.alpha = av;
		target_graphmode(ctx.external, 30 + av);
	end

	newwnd.set_mapping = function(ctx, mv)
		ctx.map = mv;
		target_graphmode(ctx.external, 10 + mv);
	end

	newwnd.set_step = function(ctx, sv)
		ctx.step = sv;
		target_graphmode(ctx.external, 0 + sv);
	end

--  we don't want to operate in synchronous mode unless necessary
	newwnd.inc_synch = function(ctx)
		if (not ctx.synch_ctr) then
			ctx.synch_ctr = 1;
			target_flags(ctx.external, TARGET_VSTORE_SYNCH);
			ctx:refresh();
		else
			ctx.synch_ctr = ctx.synch_ctr + 1;
		end
	end

	newwnd.dec_synch = function(ctx)
		ctx.synch_ctr = ctx.synch_ctr - 1;
		if (ctx.synch_ctr == 0) then
			ctx.synch_ctr = nil;
			target_flags(ctx.external, 0);
		end
	end

	newwnd.set_zoom = function(ctx, x1, y1, x2, y2)
		if (not x1) then
			ctx.zoom = {0.0, 0.0, ctx.base, ctx.base};
			ctx.in_zoom = false;
			image_set_txcos(ctx.canvas, {0, 0, 1, 0, 1, 1, 0, 1});
		else
			local rp = image_surface_resolve_properties(ctx.canvas);
			ctx.in_zoom = true;
-- translate to canvas-relative
			x1 = math.floor((x1 - rp.x) / rp.width * ctx.base);
			y1 = math.floor((y1 - rp.y) / rp.height * ctx.base);
			x2 = math.ceil((x2 - rp.x) / rp.width * ctx.base);
			y2 = math.ceil((y2 - rp.y) / rp.height * ctx.base);

-- and texture coordinates
			ctx.zoom = {x1, y1, x2, y2};
		end
		update_txcos(ctx);
	end

	newwnd.refresh = function(ctx)
		if (ctx.autoplay) then
-- do nothing, tick will refresh
		else
			stepframe_target(ctx.external, 0);
		end
	end

	newwnd.handlers.mouse.canvas.drag = function(ctx, source, dx, dy)
		if (ctx.drag_action == "focus") then
			local mx, my = mouse_xy();
			x,y = translate_2d(ctx.tag.canvas, mx, my);
			all_subs(ctx.tag, "focus_point", x, y);
			return;
-- drag action is pan
		elseif (ctx.in_zoom) then
-- FIXME: depends on zoom-mouse bug, but drag should be implemented
-- as a thresholded delta to zoom[] values, then just run update_txcos
		end
	end

	newwnd.handlers.mouse.canvas.click = function(ctx, source, x, y)
		x, y = translate_2d(ctx.tag.canvas, x, y);
		all_subs(ctx.tag, "focus_point", x, y);
	end

	image_framesetsize(newwnd.external, 2, FRAMESET_MULTITEXTURE);
	shdrmgmt_default_lut(newwnd.external, 1);

-- for histogram shader, we need to pre-get a uniform group
-- in order for the highlight values to be tracked properly without
-- bleeding between sensors

	newwnd.dispatch["streaminfo"] = dec_stream;
	newwnd.dispatch["resized"] = dec_resize;
	newwnd.dispatch["frame"] = fs_upd;
	newwnd.dispatch["framestatus"] = fs_stat;

	target_verbose(newwnd.external);
	newwnd:set_packing(gconfig_get("data_pack"));
	newwnd:set_alpha(gconfig_get("data_alpha"));
	newwnd:set_mapping(gconfig_get("data_map"));
	newwnd:set_step(gconfig_get("data_step"));
	newwnd:add_handler("resize", datawnd_resize);
	shader_setup(newwnd.wm.selected.canvas, "color", "normal");

	newwnd.base = image_storage_properties(newwnd.canvas).width;
	newwnd.offset = 0;
	newwnd.zoom = {0, 0, newwnd.base, newwnd.base};
	newwnd:refresh();
end

local step_lut = {};
step_lut["Byte"] = "STEP_BYTE";
step_lut["Pixel"] = "STEP_PIXEL";
step_lut["Row"] = "STEP_ROW";
step_lut["Halfpage"] = "STEP_HALFPAGE";
step_lut["Page"] = "STEP_PAGE";
step_lut["Align-512"] = "STEP_ALIGN_512";

local step_act = {
{
name = "platog",
kind = "action",
label = "Play/Pause",
handler = function(ctx)
	ctx.wm.selected.autoplay_step = 1;
	ctx.wm.selected.autoplay = not ctx.wm.selected.autoplay;
end
},
{
name = "platog_fast",
kind = "action",
label = "Play/Pause",
invisible = true,
handler = function(ctx)
	ctx.wm.selected.autoplay_step = 2;
	ctx.wm.selected.autoplay = not ctx.wm.selected.autoplay;
end
},
{
name = "stepping",
kind = "value",
label = "Size",
set = {"Byte", "Pixel", "Row", "Halfpage", "Page"},
handler = function(ctx, val)
	local ind = table.find_i(ctx.set, val);
	target_input(ctx.wm.selected.external, {kind = "digital",
		active = true, label = step_lut[val]});
end
},
{
name = "align",
kind = "value",
label = "Back Align",
set = {"2", "16", "32", "64", "512", "1024", "2048", "4096"},
eval = function(ctx)
	return not ctx.wm.selected.seek_disable;
end,
handler = function(ctx, val)
	target_input(ctx.wm.selected.external, {kind = "digital",
		active = true, label = "STEP_ALIGN_" .. val});
end,
},
{
name = "seek",
label = "Seek",
kind = "value",
initial = function(ctx)
	local pv = ctx.wm.selected.offset and ctx.wm.selected.offset or 1;
	return string.format("%d(0x%x)", pv, pv);
end,
validator = function(val)
	return tonumber(val) ~= nil;
end,
eval = function(ctx)
	return not ctx.wm.selected.seek_disable;
end,
handler = function(ctx, val)
	target_seek(ctx.wm.selected.external, tonumber(val));
end,
},
{
name = "forward",
kind = "action",
label = "Forward",
handler = function(ctx)
	if (not ctx) then
		print(debug.traceback());
	end
	stepframe_target(ctx.wm.selected.external, 1);
end
},
{
name = "fwd_big",
kind = "action",
label = "Forward (Large)",
handler = function(ctx)
	stepframe_target(ctx.wm.selected.external, 2);
end
},
{
name = "reverse",
kind = "action",
label = "Reverse",
handler = function(ctx)
	stepframe_target(ctx.wm.selected.external, -1);
end,
},
{
name = "rev_big",
kind = "action",
label = "Reverse (Large)",
handler = function(ctx)
	stepframe_target(ctx.wm.selected.external, -2);
end
}
};

local corrupt_menu = {
{
name = "hex",
label = "Hex",
kind = "value",
validator = function(val)
	val = string.trim(val);
	local elems = string.split(val, " ");
	if (not elems or #elems == nil) then
		return false;
	end
	for k,v in ipairs(elems) do
		if (tonumber("0x" .. v) == nil or tonumber("0x" .. v) > 255) then
			return false;
		end
	end
	return true;
end,
handler = function(ctx, val)
	local mx, my = mouse_xy();
	mx, my = translate_2d(ctx.wm.selected.canvas, mx, my);
	local bbuf = string.format("%d,%d,-1\n", mx, my);
	local elems = string.split(string.trim(val), " ");

	local outl = {};
	for k,v in ipairs(elems) do
		table.insert(outl, string.char(tonumber("0x" .. v)));
	end

	local msg = util.to_base64(bbuf .. table.concat(outl, ""));
	target_input(ctx.wm.selected.external, msg);
end
},
{
name = "asm",
label = "Assembly",
kind = "action",
submenu = true,
eval = function() return
	keystone_architectures ~= nil and #keystone_architectures() > 0; end,
handler = function(ctx, val)
	return gen_keystone_menu(ctx);
end
}
};


DATA_ACTIONS = {
{
name = "size",
kind = "value",
label = "Base Size",
set = {"16", "32", "64", "128", "256", "512", "1024", "2048", "4096"},
handler = function(ctx, val)
	val = tonumber(val);
	target_displayhint(ctx.wm.selected.external, val, val);
	ctx.wm.selected:refresh();
end
},
{
label = "Data Packing",
name = "packing",
kind = "value",
initial = function(ctx)
	return tostring(ctx.wm.selected.packing);
end,
set = {"1 byte", "4 bytes", "3 bytes+meta"},
handler = function(ctx, val)
	ctx.wm.selected:set_packing(table.find_i(ctx.set, val) - 1);
	ctx.wm.selected:refresh();
end,
},
{
name = "map",
label = "Mapping",
kind = "value",
set = {"Wrap", "Bigram", "Bigram-Ack", "Hilbert"},
handler = function(ctx, val)
	ctx.wm.selected:set_mapping(table.find_i(ctx.set, val) - 1);
	ctx.wm.selected:refresh();
end
},
{
name = "cyclemap",
label = "Cycle Mapping",
kind = "action",
invisible = true,
handler = function(ctx, val)
	local ind = ctx.wm.selected.map;
	ind = (ind and ind + 1 or 0) % 4;
	ctx.wm.selected:set_mapping(ind);
end
},
{
label = "Alpha Channel",
name = "alpha",
kind = "value",
set = {"Ignore", "Pattern", "Delta", "Entropy-base", "Entrop-4b",
	"Entropy-8b", "Entropy-16b", "Entropy-32b", "Entropy-64b"},
handler = function(ctx, val)
	ctx.wm.selected:set_alpha(table.find_i(ctx.set, val) - 1);
	ctx.wm.selected:refresh();
end
},
{
name = "step",
kind = "action",
label = "Position",
submenu = true,
handler = step_act,
},
{
name = "color",
kind = "value",
label = "Color Map",
set = function() return shader_list({"color"}); end,
handler = function(ctx, val)
	local key, dom = shader_getkey(val, {"color"});
	if (key ~= nil) then
		shader_setup(ctx.wm.selected.canvas, dom, key);
	end
end
},
{
name = "color_lut",
kind = "value",
label = "Lookup-Texture",
set = function() return glob_resource("color_lut/*.png"); end,
handler = function(ctx, val)
	local img = load_image("color_lut/" .. val);
	if (valid_vid(img)) then
		set_image_as_frame(ctx.wm.selected.canvas, img, 1);
		delete_image(img);
	end
end
},
-- generate a list of valid tools. These are scanned separately
-- and should cover (alphamap, histogram, image-search, image-tune,
-- point cloud, distance-tracker)
{
name = "tools",
kind = "action",
label = "Tools",
submenu = true,
handler = function(ctx)
	if (not ctx) then print(debug.traceback()); end
	return list_tools(ctx.wm.selected);
end
},
{
name = "corrupt",
kind = "action",
label = "Corrupt",
submenu = true,
handler = corrupt_menu
},
-- generate a list of available overlays, requires connected translators
{
name = "overlay",
kind = "action",
label = "Overlays",
submenu = true,
eval = function(ctx) return #list_overlays(ctx) > 0; end,
handler = list_overlays
},
-- generate a list of available translators
{
name = "translator",
kind = "action",
label = "Translators",
submenu = true,
eval = function() return #list_translators() > 0; end,
handler = list_translators
},
-- generate a list of active overlays
{
name = "overlays",
kind = "action",
label = "Active Overlays",
submenu = true,
eval = function(ctx) return #ctx.wm.selected.overlays > 0; end,
handler = active_overlays
},
{
name = "zoom",
label = "Zoom",
kind = "action",
handler = function(ctx)
	if (ctx.wm.selected.in_zoom) then
		ctx.wm.selected:set_zoom();
	else
		suppl_region_select(255, 255, 255,
			function(x1, y1, x2, y2)
				ctx.wm.selected:set_zoom(x1, y1, x2, y2);
			end, ctx.wm.selected.canvas);
	end
end
}
};
