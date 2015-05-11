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
disp[BINDINGS["CYCLE_MAPPING"]] = nil;

-- menu items for tile sizes, should remove:
-- "menu_metadata", "menu_map"
--
-- and add a 'tile-size' and a 'delta toggle'
--
local rtbl = {
	name = "mfsense",
	dispatch_sub = disp,
	popup_sub = pop,
	init = function(wnd)
		wnd.ofs = 0;
		target_flags(wnd.ctrl_id, TARGET_VSTORE_SYNCH);
		wnd.dynamic_zoom = true;

		wnd.seek = function(wnd, ofs)
			target_seek(wnd.ctrl_id, ofs);
		end
	end
};

return rtbl;
