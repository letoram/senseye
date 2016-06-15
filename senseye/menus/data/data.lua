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
end

local function fs_upd(wnd, source, status)
	wnd.offset = status.pts;
	return true;
end

local function fs_stat(wnd, source, status)
	return true;
end

local function dec_resize(wnd, source, status)
	wnd.base = status.width;
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

	newwnd.refresh = function(ctx)
		if (ctx.autoplay) then
-- do nothing, tick will refresh
		else
			stepframe_target(ctx.external, 0);
		end
	end

	image_framesetsize(newwnd.external, 2, FRAMESET_MULTITEXTURE);
	shdrmgmt_default_lut(newwnd.external, 1);

-- for histogram shader, we need to pre-get a uniform group
-- in order for the highlight values to be tracked properly without
-- bleeding between sensors

	newwnd.dispatch["streaminfo"] = dec_stream;
	newwnd.dispatch["resized"] = dec_rzev;
	newwnd.dispatch["frame"] = fs_upd;
	newwnd.dispatch["framestatus"] = fs_stat;

	target_verbose(newwnd.external);
	newwnd:set_packing(gconfig_get("data_pack"));
	newwnd:set_alpha(gconfig_get("data_alpha"));
	newwnd:set_mapping(gconfig_get("data_map"));
	newwnd:set_step(gconfig_get("data_step"));
	newwnd.offset = 0;
	newwnd:refresh();
end

local step_act = {
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

DATA_ACTIONS = {
{
name = "platog",
kind = "action",
label = "Play/Pause",
handler = function(ctx)
	ctx.wm.selected.autoplay = not ctx.wm.selected.autoplay;
end
},
{
name = "zoom",
kind = "action",
label = "Zoom",
handler = function(ctx)
-- lock mouse, do region select, calculate window 'zoom' coordinates
-- propagate coordinates to overlays and tools
end
},
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
hint = "number of bytes to map into color channels",
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
name = "step_act",
kind = "action",
label = "Step",
submenu = true,
handler = step_act,
},
{
name = "stepping",
kind = "value",
label = "Step Size",
set = {"Byte", "Pixel", "Row", "Halfpage", "Page", "Align-512"},
handler = function(ctx, val)
	local ind = table.find_i(ctx.set, val);
	ctx.wm.selected:set_stepping(table.find_i(ctx.set, val) - 1);
end
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
eval = function() return false; end,
handler = list_tools
},
-- generate a list of available overlays, requires connected translators
{
name = "overlay",
kind = "action",
label = "Overlays",
submenu = true,
eval = function() return false; end,
handler = list_overlays
},
-- generate a list of available translators
{
name = "translator",
kind = "action",
label = "Translators",
submenu = true,
eval = function() return false; end,
handler = list_translators
},
-- generate a list of active overlays
{
name = "overlays",
kind = "action",
label = "Active Overlays",
submenu = true,
eval = function() return false; end,
handler = active_overlays
},
};
