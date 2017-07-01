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
					connection_path), "terminal", function() end);
			if (valid_vid(vid)) then
				local wnd = wm:add_window(vid, {});
				if (wnd) then
					wndshared_setup(wnd, "cli");
					wnd:hide();
				else
					delete_image(vid);
				end
			end
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
