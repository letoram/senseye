-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: UI mapping for the multiple- file sensor diff window
--
-- menu items for tile sizes, should remove:
-- "menu_metadata", "menu_map"
--
-- and add a 'tile-size' and a 'delta toggle'
--

local disp = {};
disp[BINDINGS["MODE_TOGGLE"]] = function(wnd)
	wnd.inv = not wnd.inv;
	if (wnd.inv) then
		wnd:set_message("Highlight match", DEFAULT_TIMEOUT);
		image_shader(wnd.canvas, "invert_green");
	else
		wnd:set_message("Highlight mismatch", DEFAULT_TIMEOUT);
		image_shader(wnd.canvas, "DEFAULT");
	end
end

local rtbl = {
	name = "mfsense_diff",
	dispatch_sub = disp,
	popup_sub = {},
	init = function(wnd)
		wnd.inv = false;
		wnd.popup = {};
		wnd.mfsense_diff = true;
	end
};

return rtbl;
