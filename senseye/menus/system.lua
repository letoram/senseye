local system_submenu = {
	{
		name = "shutdown",
		label = "Shutdown",
		handler = function() shutdown(); end
	}
};

local input_submenu = {
	{
		name = "grab",
		label = "Toggle Grab",
		handler = function() toggle_mouse_grab(); end
	}
};

local share_submenu = {
--		if (wm.meta and wm.selected) then
--			local name = gen_dumpname("screenshot", "png");
--			local img = gen_dumpid(wm.selected);
--			save_screenshot(name, FORMAT_PNG, img);
--			statusbar:set_message("Window saved as " .. name, DEFAULT_TIMEOUT);
--			delete_image(img);
--		else
--			local name = gen_dumpname("screenshot", "png");
--			save_screenshot(name, FORMAT_PNG_FLIP);
--			statusbar:set_message("Screen saved as " .. name, DEFAULT_TIMEOUT);
--		end
};

local termwnd = {};
local function terminal_handler(source, status)
	if (status.kind == "resized") then
		if (termwnd[source]) then
			termwnd[source]:resize(status.width, status.height);
		else
			termwnd[source] = wm:add_window(source, {});
			termwnd[source]:resize(status.width, status.height);
			termwnd[source].input = function(ctx, iotbl)
				target_input(source, iotbl);
			end
			termwnd[source].input_sym = function(ctx, sym, active, iotbl)
				target_input(source, iotbl);
			end
			wndshared_setup(termwnd[source], "generic");
		end
	elseif (status.kind == "terminated") then
		delete_image(source);
		termwnd[source] = nil;
	end
end

return {
	{
		name = "input",
		label = "Input",
		submenu = function()
			return input_submenu;
		end,
	},
	{
		name = "terminal",
		label = "Terminal",
		handler = function()
			local vid = launch_avfeed(
				string.format("force_bitmap:env=ARCAN_CONNPATH=%s",
					connection_path), "terminal", terminal_handler);
		end,
	},
	{
		name = "system",
		label = "System",
		submenu = function()
			return system_submenu;
		end
	}
};
