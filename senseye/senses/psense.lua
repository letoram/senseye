--
-- fd-sense single channel
--

local disp = {};

disp[BINDINGS["PSENSE_STEP_FRAME"]] = function(wnd)
	stepframe_target(wnd.ctrl_id, 1);
end

disp[BINDINGS["PSENSE_PLAY_TOGGLE"]] = function(wnd)
	if (wnd.tick) then
		wnd.tick = nil;
	else
		wnd.tick = function(wnd, n) stepframe_target(wnd.ctrl_id, n); end
	end
end

disp[BINDINGS["CYCLE_SHADER"]] = function(wnd)
	wnd.shind = wnd.shind == nil and 0 or wnd.shind;
	wnd.shind = (wnd.shind + 1 > #shaders_2dview and 1 or wnd.shind + 1);
	switch_shader(wnd, wnd.canvas, shaders_2dview[wnd.shind]);
end

local dpack_sub = {
	{
		label = "Intensity",
		name  = "pack_intens",
		value = 0
	},
	{
		label = "Histogram Intensity",
		name  = "pack_histo",
		value = 1
	},
	{
		label = "Tight (alpha)",
		name  = "pack_tight",
		value = 2
	},
	{
		label = "Tight (no-alpha)",
		name = "pack_tight_alpha",
		value = 3
	}
};

local alpha_sub = {
	{
		label = "Full (no data)",
		name  = "map_alpha_full",
		value = 0
	},
	{
		label = "Shannon Entropy",
		name  = "map_alpha_entropy",
		value = 2
	},
	{
		label = "Pattern Signal",
		name  = "map_alpha_signal",
		value = 1
	}
};

alpha_sub.handler = function(wnd, value)
	target_graphmode(wnd.ctrl_id, 30 + value);
end

dpack_sub.handler = function(wnd, value)
	target_graphmode(wnd.ctrl_id, 20 + value);
end

local space_sub = {
	{
		label = "Wrap",
		name  = "map_wrap",
		value = 0
	},
	{
		label = "Tuple",
		name  = "map_tuple",
		value = 1
	},
	{
		label = "Hilbert",
		name  = "map_hilbert",
		value = 2
	}
};

space_sub.handler = function(wnd, value)
	target_graphmode(wnd.ctrl_id, 10 + value);
end

local clock_sub = {
	{
		label = "Buffer Limit",
		name  = "clk_blk",
		value = 0
	},
	{
		label = "Sliding Window",
		name  = "clk_slide",
		value = 1
	}
};

clock_sub.handler = function(wnd, value)
	target_graphmode(wnd.ctrl_id, 0 + value);
end

function color_sub()
	return shader_menu(shaders_2dview, "canvas");
end

local sample_sub = {};
for i=6,10 do
	table.insert(sample_sub, {
		label = tostring(math.pow(2, i)),
		value = math.pow(2, i);
	});
end
sample_sub.handler = function(wnd, value)
	target_displayhint(wnd.ctrl_id, value, value);
end

clock_sub.handler = function(wnd, value)
	target_graphmode(wnd.ctrl_id, value);
end

--
-- Resolve a specific window- coordinate space to the one used locally.
--
local function coord_map(wnd, x, y)
	if (wnd.base == nil) then
		wnd.base = image_storage_properties(wnd.canvas).width;
	end

	local msg;

	if (wnd.map_cur == 0) then
		local bofs = (y * wnd.base + x) * wnd.size_cur + wnd.ofs;
		msg = string.format("ofs@0x%x+%d", bofs, wnd.size_cur);

 -- map_tuple, not enough data to map
	elseif (wnd.map_cur == 1 or wnd.map_cur == 2) then
		msg = string.format("transfer@0x%x %d bytes/pixel",
			wnd.ofs, wnd.size_cur);

	else
		msg = "unknown";
	end

	return msg;
end

local fsrv_ev = {
	framestatus = function(wnd, source, status)
		wnd.ofs = status.frame;
		return true; -- don't forward
	end,
	streaminfo = function(wnd, source, status)
		local base = string.byte("0", 1);
		wnd.pack_cur = string.byte(status.lang, 1) - base;
		wnd.map_cur  = string.byte(status.lang, 2) - base;
		wnd.size_cur = string.byte(status.lang, 3) - base;
	end,
	resized = function(wnd, source, status)
		wnd.base = status.width;
		if (status.width ~= status.height) then
			warning(string.format("psense:resize(%d,%d) expected pow2 and w=h",
				status.width, status.height));
		end
		return false; -- forward
	end
};

--
-- attach to framestatus events, extract and show in a new window
--
local function statwnd(wnd, table)
	print("spawn stats- window");
end

local pop = {{
	label = "Data Packing...",
	submenu = dpack_sub }, {
	label = "Alpha Channel...",
	submenu = alpha_sub }, {
	label = "Transfer Clock...",
	submenu = clock_sub }, {
	label = "Space Mapping...",
	submenu = space_sub }, {
	label = "Sample Buffer Size...",
	submenu = sample_sub }, {
	label = "Coloring...",
	submenu = color_sub }
};

return {
	name = "psense", -- identifier in tracetags for debugging
	source_listener = fsrv_ev, -- need to listen to some events to track stream
	map = coord_map, -- translate from position in window to stream
	dispatch_sub = disp, -- sensor specific keybindings
	popup_sub = pop, -- sensor specific popup
	init = function(wnd) wnd.ofs = 0; end -- hook to set members before data comes
};
