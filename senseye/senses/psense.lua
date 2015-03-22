--
-- fd-sense single channel
--

local disp = {};

disp[BINDINGS["PSENSE_STEP_FRAME"]] = function(wnd)
	wnd.flip_suspend = true;
	stepframe_target(wnd.ctrl_id, 1);
end

disp[BINDINGS["PSENSE_PLAY_TOGGLE"]] = function(wnd)
	wnd.flip_suspend = true;

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
		label = "Intensity (1b/pixel)",
		name  = "pack_default",
		value = 0
	},
	{
		label = "Tight (4b/pixel)",
		name  = "pack_default",
		value = 1
	},
	{
		label = "Meta (3b+meta/pixel)",
		name = "pack_default",
		value = 2
	}
};

local pack_sztbl = {
	4,
	3,
	1
};

local alpha_sub = {
	{
		label = "Full (no data)",
		name  = "alpha_default",
		value = 0
	},
	{
		label = "Pattern Signal",
		name  = "alpha_default",
		value = 1
	},
	{
		label = "Entropy (base width)",
		name  = "alpha_default",
		value = 2
	},
	{
		label = "Entropy (8 bytes)",
		name = "alpha_default",
		value = 5,
	},
	{
		label = "Entropy (16 bytes)",
		name = "alpha_default",
		value = 6,
	},
	{
		label = "Entropy (32 bytes)",
		name = "alpha_default",
		value = 7,
	},
	{
		label = "Entropy (64 bytes)",
		name = "alpha_default",
		value = 8,
	},
};

alpha_sub.handler = function(wnd, value, rv)
	target_graphmode(wnd.ctrl_id, 30 + value);
	if (rv) then
		gconfig_set("alpha_default", 30 + value);
	end
end

dpack_sub.handler = function(wnd, value, rv)
	target_graphmode(wnd.ctrl_id, 20 + value);
	stepframe_target(wnd.ctrl_id, 0);
	if (rv) then
		gconfig_set("pack_default", 20 + value);
	end
end

local space_sub = {
	{
		label = "Wrap",
		name  = "map_default",
		value = 0
	},
	{
		label = "Tuple",
		name  = "map_default",
		value = 1
	},
	{
		label = "Hilbert",
		name  = "map_default",
		value = 2
	}
};

space_sub.handler = function(wnd, value, rv)
	target_graphmode(wnd.ctrl_id, 10 + value);
	if (rv) then
		gconfig_set("map_default", 10 + value);
	end
end

local clock_sub = {
	{
		label = "Buffer Limit",
		name  = "clock_default",
		value = 0
	},
	{
		label = "Sliding Window",
		name  = "clock_default",
		value = 1
	}
};

clock_sub.handler = function(wnd, value, rv)
	target_graphmode(wnd.ctrl_id, 0 + value);
	if (rv) then
		gconfig_set("clock_default", 10 + value);
	end
end

function color_sub()
	return shader_menu(shaders_2dview, "canvas");
end

local sample_sub = {};
for i=6,10 do
	table.insert(sample_sub, {
		label = tostring(math.pow(2, i)),
		value = math.pow(2, i),
		name = "sample_default",
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

	elseif (wnd.map_cur == 2) then
		local hofs = hilbert_lookup(wnd.base, x, y);
		local hofs = hofs and hofs or 0;
		msg = string.format("ofs@0x%x+%d", wnd.ofs+hofs, wnd.size_cur);

-- with tuple we lose information, can't reverse
	elseif (wnd.map_cur == 1) then
		msg = string.format("transfer@0x%x %d bytes/pixel",
			wnd.ofs, wnd.size_cur);
	else
		msg = "unknown";
	end

	return msg;
end

function psense_decode_streaminfo(wnd, status)
	local base = string.byte("0", 1);
	wnd.pack_cur = string.byte(status.lang, 1) - base;
	wnd.map_cur  = string.byte(status.lang, 2) - base;
	wnd.size_cur = string.byte(status.lang, 3) - base;
	wnd.pack_sz  = pack_sztbl[wnd.pack_cur+1];

	if (wnd.pack_sz == nil) then
		wnd:message("Warning: received broken streaminfo");
	end
end

local fsrv_ev = {
	framestatus = function(wnd, source, status)
		wnd.ofs = status.frame;
	end,
	streaminfo = function(wnd, source, status)
		psense_decode_streaminfo(wnd, status);
	end,
	resized = function(wnd, source, status)
		wnd.base = status.width;
		if (status.width ~= status.height) then
			warning(string.format("psense:resize(%d,%d) expected pow2 and w=h",
				status.width, status.height));
		end

		local torem = {};
		for k,v in ipairs(wnd.children) do
			table.insert(torem, v);
		end
		for k, v in ipairs(torem) do
			v:destroy();
		end
	end
};

local pop = {{
	label = "Data Packing...",
	submenu = dpack_sub }, {
	label = "Metadata...",
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
	popup_sub = pop, -- sensor specific popup,
	init = function(wnd)
		wnd.ofs = 0;
		wnd.seek = function() end
		wnd.size_cur = 3; -- default packing mode is 2
		target_flags(wnd.ctrl_id, TARGET_VSTORE_SYNCH);
		wnd.dynamic_zoom = true;
		target_graphmode(wnd.ctrl_id, gconfig_get("map_default"));
		target_graphmode(wnd.ctrl_id, gconfig_get("pack_default"));
		target_graphmode(wnd.ctrl_id, gconfig_get("alpha_default"));

	end -- hook to set members before data comes
};
