-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
--
-- Description: UI mapping for each segement in the memory
-- specific sensor. This is similar to psense and fsense
-- (and derives most behavior from there) with the addition
-- of needing to refresh the current page/offset and that
-- the page may die (be unmapped) at any time.
--
-- Possible improvements include:
--  Periodic refresh, popup menu to control tick and
--  have it emit REFRESH_ commands periodically
--

local rtbl = system_load("senses/psense.lua")();

--
-- remove specific menu entries from the psense popup table
--
for k,v in ipairs(rtbl.popup_sub) do
	if (v.label == "Transfer Clock...") then
		v.submenu = nil;
	end
end

rtbl.dispatch_sub[BINDINGS["MSENSE_REFRESH"]] = function(wnd)
	stepframe_target(wnd.ctrl_id, 0);
end

rtbl.dispatch_sub[BINDINGS["PSENSE_STEP_FRAME"]] = function(wnd)
	stepframe_target(wnd.ctrl_id, wnd.wm.meta and 2 or 1);
end

rtbl.dispatch_sub[BINDINGS["FSENSE_STEP_BACKWARD"]] = function(wnd)
	stepframe_target(wnd.ctrl_id, wnd.wm.meta and -2 or -1);
end

return rtbl;
