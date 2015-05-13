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

-- similar to psense with some things added that didn't
-- belong to the main window before
local slisth = {
	framestatus = function(wnd, source, status)
		wnd.cells = status.pts;
		wnd.ofs = status.frame;
		if (wnd.pending > 0) then
			wnd.pending = wnd.pending - 1;
		end
	end,
	streaminfo = function(wnd, source, status)
		local msg = psense_decode_streaminfo(wnd, status);
		wnd:set_message(msg, DEFAULT_TIMEOUT);
	end,
-- we delete everything except our special diff child
	resized = function(wnd, source, status)
		local torem = {};
		for k,v in ipairs(wnd.children) do
			if (v.mfsense_diff) then
				table.insert(torem, v);
			end
		end
		for k,v in ipairs(torem) do
			v:destroy();
		end
	end,
	frame = function(wnd, source, status)
		print("got frame:", wnd.ofs);
	end
};

-- menu items for tile sizes, should remove:
-- "menu_metadata", "menu_map"
--
-- and add a 'tile-size' and a 'delta toggle'
--
local rtbl = {
	name = "mfsense",
	dispatch_sub = disp,
	popup_sub = merge_menu(subwnd_menu, pop),
	source_listener = slisth,
	init = function(wnd)
		wnd.ofs = 0;
		target_flags(wnd.ctrl_id, TARGET_VSTORE_SYNCH);
		wnd.dynamic_zoom = true;

		for i=#wnd.popup,1,-1 do
			if (wnd.popup[i].name == "menu_map" or
				wnd.popup[i].name == "menu_metadata" or
				wnd.popup[i].name == "menu_bufsz") then
				table.remove(wnd.popup, i);
			end
		end

		wnd.seek = function(wnd, ofs)
			target_seek(wnd.ctrl_id, ofs);
		end
	end
};

return rtbl;
