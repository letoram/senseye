--
-- translator archetype is a bit more complicated as it should be
-- able to crash and reconnect without rebuilding windows without
-- losing too much state, and that it acts as a mediator for
-- instantiating translator sessions and setting up overlays.
--
local tlist = {};

local function add_olay(xlt, wnd)
-- overlay is activated by sending a new segment to the feedtarget
-- it need to be fed information about the zoom-level and the current
-- packaging format, and displayhints as to the dimensions of the
-- data surface.
	local olay = target_alloc(xlt.external,
	function(source, status)
-- don't really care
	end);

	if (not valid_vid(olay)) then
		warning("failed to spawn overlay for translator");
		return;
	end

-- takes care of mapping UI controls, switching / pacifying etc.
	wnd:add_overlay(olay, xlt.external);
end

local function add_xlt(xlt, dst)
	local wnd;

-- feed data from the window to the translator
	local feed = define_feedtarget(xlt.external, dst.external,
		function(source, status) end);

	if (not valid_vid(feed)) then
		warning("translator feedtarget failed");
	end
-- and create a window for it to draw back into
	local vid = target_alloc(xlt.external,
	function(source, status)
		if (status.kind == "resized") then
-- don't really care
		elseif(status.kind == "ident") then
-- we have an overlay available for this one, make it available,
-- need per-data-wnd tracking of acceptable overlays and data source
			wnd.overlay_id = status.message;
			wnd.add_overlay = function() add_olay(wnd, dst); end;
		elseif(status.kind == "terminated") then
			wnd.overlay_id = nil;
			wnd.add_overlay = nil;
		end
	end
	);
	if (not valid_vid(vid)) then
		delete_image(feed);
		warning("translator output failed");
		return;
	end

	dst:inc_synch();
	dst:refresh();

-- link for lifecycle management
	link_image(vid, feed);

-- bind this output to a window, this should be switched to
-- the terminal archetype later so we get clipboard management etc.
	wnd = active_display():add_window(vid);
	wnd.external = feed;
	wnd.scalemode = "stretch";
	wnd.handlers.mouse.canvas.motion = function() end;

	shader_setup(wnd.canvas, "simple", "autocrop");
	wnd:add_handler("resize", senseye_tile_changed);
	rebalance_space(wnd.wm.spaces[wnd.wm.space_ind]);
	table.insert(dst.translators, wnd);
end

function list_translators()
	local res = {};
	for k,v in pairs(tlist) do
		table.insert(res,{
			name = "xlt_" .. k,
			label = v.ident,
			kind = "action",
			handler = function(ctx)
				add_xlt(v, ctx.wm.selected);
			end
		});
	end
	table.sort(res, function(a, b)
		return a.label < b.label;
	end);
	return res;
end

local function xltev(source, status)
	if (status.kind == "ident") then
		tlist[source].ident = status.message;
	elseif (status.kind == "terminated") then
-- mark all translator- related windows as 'pending' in terms
-- of overlay requests, and when we get a reconnect then we sweep
-- these windows and reattach.
	end
end

return {
	dispatch = {
	},
	actions = {},
	labels = {},
	subreq = {},
	atype = "encoder",

-- we break free from the normal extevh
	init = function(self, wnd, source)
		target_updatehandler(source, xltev);
		tlist[source] = wnd;
		wnd.ident = "unknown";
	end,
	props = {}
};
