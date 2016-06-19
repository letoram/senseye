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

local mfiledatawnd = {
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
	wnd.pts = 0;

	wnd:add_handler("resize", function(wnd, neww, newh)
		target_displayhint(wnd.external, neww, newh);
	end);

	wnd:ws_attach();
end

local mfilenavwnd = {
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
	guid = "HgoAAAAAAAAAAAAAAAAAAA==",
	init = navwnd_init
};

mfilenavwnd.subreq[tostring(0xa1e)] = mfiledatawnd;

return mfilenavwnd;
