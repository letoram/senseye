--
-- Senseye tool- script mapper
--
-- This script registers a handler into the target- part of the
-- durden menu system. This handler, when activated on a window
-- with the GUID of senseye data window, enables the tools from
-- the senseye/ subdirectory
--
-- It also provides support functions for translators, sampling
-- stepping and related data controls.
--
-- system_load("tools/senseye/histogram.lua")();
-- system_load("tools/senseye/pointcloud.lua")();
-- system_load("tools/senseye/disttracker.lua")();
-- system_load("tools/senseye/tuner.lua")();
-- system_load("tools/senseye/colormapper.lua")();
--

local at = extevh_archetype("sensor");
if (at) then
-- add special tracking, e.g.
-- dispatch on [framestatus] and get bytes from framenumber,
-- and total from framestatus
--
-- extract pack (subtract 'a') from langid[1], map from [2] and sz from [3]
else
	warning("senseye - couldn't attach to sensor archetype");
end

local senseye_menu = {
{
	kind = "action",
	name = "histogram",
	label = "Histogram",
	description = "Histogram of the active window canvas region",
	kind = "action",
	handler = function()
	end
}
};

shared_menu_register("",
{
	kind = "action",
	name = "senseye",
	label = "Senseye",
	description = "Senseye- specific data processing tools",
	kind = "action",
	submenu = true,
	eval = function()
		return active_display().selected.guid and
			active_display().selected.guid == "U3T4NvRYtjFoFyuolXUWBQ==";
	end,
	handler = senseye_menu
});
