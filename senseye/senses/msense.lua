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

--
-- need to create a copy of popup and add things
--
local pop = {};

local refresh_sub = {
	{
		label = "Off",
		name = "refresh_off",
		value = 0,
	},
};

for i=1,10 do
	table.insert(refresh_sub, {
		label = string.format("%d ms", CLOCKRATE * i),
		name = "refresh" .. tonumber(i),
		value = i
	});
end

refresh_sub.handler = function(wnd, value)
	wnd.tick_rate = value;
	wnd.tick_value = value;
end

for k,v in ipairs(rtbl.popup_sub) do
	pop[k] = v;
end

table.insert(pop, {
	label = "Refresh Clock...",
	submenu = refresh_sub
});

rtbl.popup_sub = pop;

--
-- wee bit messy, chain init and chain tick, count down and trigger
-- current-page reset of tick rate has been set from refresh clock menu
--
local oldinit = rtbl.init;
rtbl.init = function(wnd)
	oldinit(wnd);
	wnd.tick_rate = 0;
	local oldtick = wnd.tick;
	wnd.tick = function()
		if (oldtick) then
			oldtick(wnd);
		end
		if (wnd.tick_rate > 0) then
			wnd.tick_value = wnd.tick_value - 1;
			if (wnd.tick_value <= 0) then
				stepframe_target(wnd.ctrl_id, 0);
				wnd.tick_value = wnd.tick_rate;
			end
		end
	end
end

rtbl.name = "msense";
return rtbl;
