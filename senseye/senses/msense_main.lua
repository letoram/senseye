-- Copyright 2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: UI mapping for the process memory specific sensor

-- Most of the unique properties of this sensor is implemented
-- in msense.lua rather than main. This is only used for input
-- translation as the local cursor (selected row) is drawn in
-- the sensor, not in the UI.

local main_ev = {
};

local disp = {};
disp[BINDINGS["MSENSE_MAIN_UP"]] = function(wnd)
	local iotbl = {kind = "digital", active = true, label = "UP"};
	target_input(wnd.ctrl_id, iotbl);
end

disp[BINDINGS["MSENSE_MAIN_DOWN"]] = function(wnd)
	local iotbl = {kind = "digital", active = true, label = "DOWN"};
	target_input(wnd.ctrl_id, iotbl);
end

disp[BINDINGS["MSENSE_MAIN_LEFT"]] = function(wnd)
	local iotbl = {kind = "digital", active = true, label = "LEFT"};
	target_input(wnd.ctrl_id, iotbl);
end

disp[BINDINGS["MSENSE_MAIN_RIGHT"]] = function(wnd)
	local iotbl = {kind = "digital", active = true, label = "RIGHT"};
	target_input(wnd.ctrl_id, iotbl);
end

disp[BINDINGS["MSENSE_MAIN_SELECT"]] = function(wnd)
	local iotbl = {kind = "digital", active = true, label = "SELECT"};
	target_input(wnd.ctrl_id, iotbl);
end

local rtbl = {
	name = "msense_main",
	source_listener = main_ev,
	dispatch_sub = disp,
	popup_sub = {},
	init = function(wnd)
		print("msense_main init");
	end
};

return rtbl;
