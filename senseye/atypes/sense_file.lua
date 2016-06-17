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
	if (wnd.dispatch[ev.kind]) then
		wnd.dispatch[ev.kind](wnd, ev);
	else
		print("unhandled event", ev.kind);
	end
end

local function update_preview(wnd)
	local props = image_storage_properties(wnd.canvas);
	local sfx = wnd.width / props.width;
	local sfy = wnd.height / props.height;
	resize_image(wnd.pview, wnd.width, (wnd.pts <= 0 and 1 or wnd.pts) * sfy);
	move_image(wnd.pview, 0, wnd.frame * sfy);
end

local file_datawnd = {
	dispatch = {
		framestatus = function(wnd,src,ev)
			wnd.ofs = ev.pts;
		end,
		frame = function(wnd,src,ev)
			wnd.ofs = ev.pts;
		end
	},
	labels = {
		LEFT = function(wnd)
			stepframe_target(wnd.external, -1);
		end,
		lshift_LEFT = function(wnd)
			stepframe_target(wnd.external, -2);
		end,
		RIGHT = function(wnd)
			stepframe_target(wnd.external, 1);
		end,
		lshift_RIGHT = function(wnd)
			stepframe_target(wnd.external, 2);
		end,
	},
-- actions should map to normal data window
	reqh = data_ev,
	props = defprop_tbl
};

local function navwnd_init(tbl, wnd, src)
-- unpickable overlay that estimated the position of the
-- currently presented datablock. This is based on an approximation
-- of how many bytes each line in the preview window covers
	wnd.pview = color_surface(1, 1, 255, 255, 255);
	image_mask_set(wnd.pview, MASK_UNPICKABLE);
	blend_image(wnd.pview, 0.5);
	link_image(wnd.pview, wnd.canvas);
	image_inherit_order(wnd.pview, true);
	image_clip_on(wnd.pview, CLIP_SHALLOW);
	order_image(wnd.pview, 1);
	wnd.pts = 1;
-- seek here is based on figuring out which original row we are clicking on,
-- hence sensor preview row width determines offset
	wnd.handlers.mouse.canvas["button"] = function(hnd, ctx, ind, active, x, y)
		if (ind == 1 and active) then
			local props = image_storage_properties(wnd.canvas);
			local sfy = wnd.height / props.height;
			y = (y - wnd.y);
			y = y > 0 and y / sfy or 0;

			target_seek(wnd.external, y);
		end
	end

	wnd:add_handler("resize", function(wnd, neww, newh)
	end);

	wnd:ws_attach();
end

local file_navwnd = {
	props = defprop_tbl;
	dispatch = {
		framestatus = function(wnd, src, ev)
			wnd.pts = ev.pts;
			wnd.frame = ev.frame;
			update_preview(wnd);
		end
	},
	subreq = {},
	actions = {},
	labels = {},
	guid = "rQ8AAAAAAAAAAAAAAAAAAA==",
	init = navwnd_init
};

file_navwnd.subreq[tostring(0xfad)] = file_datawnd;

return file_navwnd;
