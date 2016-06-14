--
-- necessary fields for sense_*:
-- atype :- "sensor" [matches primary segment kind]
--  guid :- match the first 'registered', identifies 'file', 'mem' and
--          links binary build version against script version
--
-- workspaces are tightly coupled to a sensor to make it a lot easier
-- to handle sub-tool relationships, stepping control, event notification
-- and so on.
--
-- every sensor is expected to present a nav-area [space.children[1]]
-- and a data area [space.children[2]. The data area is the most complex
-- area to manage UI wise, with drag-region zoom/reset, coloring shader,
-- overlays, slice, etc. For first release, this is limited to one.
--
-- the default subsegment requests match against subreq[num] and is
-- expected to return a similar window table as this one.
--
-- dispatch[kind](wnd, source, status)
--
local defprop_tbl = {
	scalemode = "stretch",
	autocrop = false,
	font_block = true,
	filtermode = FILTER_NONE
};

local function data_ev(wnd, source, ev)
	print(ev.kind);
end

local file_datawnd = {
	dispatch = {},
	labels = {},
-- actions should map to normal data window
	reqh = data_ev,
	props = defprop_tbl
};

local file_navwnd = {
	props = defprop_tbl;
	dispatch = {},
	subreq = {},
	actions = {},
	labels = {},
	guid = "rQ8AAAAAAAAAAAAAAAAAAA==",
};

file_navwnd.subreq[tostring(0xfad)] = file_datawnd;

return file_navwnd;
