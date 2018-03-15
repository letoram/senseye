local function match_bhat(h1, h2)
	local bcf = 0;
	local sum_1 = 0;
	local sum_2 = 0;

	for i=0,255 do
		bcf = bcf + math.sqrt(h1[i] * h2[i]);
		sum_1 = sum_1 + h1[i];
		sum_2 = sum_2 + h2[i];
	end

	local rnd = math.floor(sum_1 + 0.5);
	local bcf = bcf > rnd and rnd or bcf;

	return 1.0 - math.sqrt(rnd - bcf);
end

local function match_intersect(h1, h2)
	local sum = 0;
	for i=0,255 do
		sum = sum + (h1[i] > h2[i] and h2[i] or h1[i]);
	end
	return sum;
end

local match_functions = {
	bhattacharyya = match_bhat,
	intersection = match_intersect
};

local match_actions = {
};

local histwnd_menu = {
{
	name = "channel",
	label = "Channel",
	set = {"merged", "split"},
	description = "Select if the ",
	kind = "value",
	handler = function(ctx, val)
	end
}
};

local
function build_histogram(wnd)
	print("build new histogram");
	if (valid_vid(wnd.external, TYPE_FRAMESERVER)) then
		target_verbose(wnd.external, true);
	end

	local vid = null_surface(1, 1);
	image_sharestorage(wnd.canvas, vid);
	local props = image_storage_properties(vid);
	local ibuf = alloc_surface(props.width, props.height);

-- hgram will be used for the data-store where we impose the histogram
	local hgram = fill_surface(256, 1, 0, 0, 0, 256, 1);

-- 1. resize handler that synchs storage and texture coordinates
	local synch = function()
		local nprops = image_storage_properties(vid);
		local rprops = image_surface_resolve(wnd.canvas);
		local csz = image_storage_properties(ibuf);

		local dw = math.min(nprops.width, rprops.width);
		local dh = math.min(nprops.height, rprops.height);

-- optimization, since there are many possible scalemodes and other options,
-- pick whatever is smallest, the size of the window or the size of the storage
		if (dw ~= csz.width or dh ~= csz.height) then
			image_resize_storage(ibuf, dw, dh);
			resize_image(vid, dw, dh);
			active_display():message(string.format("resized to %d %d", dw, dh));
		end
		local txcos = image_get_txcos(wnd.canvas);
		image_set_txcos(vid, txcos);
		rendertarget_forceupdate(ibuf);
		stepframe_target(ibuf);
	end

-- 2. synch updates to when the provider receives a frame
	local update = function()
		rendertarget_forceupdate(ibuf);
		stepframe_target(ibuf);
	end

-- bind that histogram to a new window and make sure the source calctarget
-- is destroyed when the window is tied to the life of the window
-- also make sure to drop any resize handler on the main window as they
-- can be deleted independently
	local hwnd = active_display():add_window(hgram, {scalemode = "stretch"});
	hwnd:add_handler("destroy", function()
		if (wnd.drop_handler) then
			wnd:drop_handler("resize", synch);
			wnd:drop_dispatch("frame", update);
		end
	end);
	hwnd.hgram = {
		limit_w = MAX_SURFACEW,
		limit_h = MAX_SURFACEH,
		method = HISTOGRAM_MERGE_NOALPHA,
		synch = synch,
		update = update
	};
	hwnd.clipboard_block = true;
	hwnd.menu_state_disabled = true;
	hwnd.actions = histwnd_menu;

	wnd:add_handler("resize", synch);
	wnd:add_dispatch("frame", update);

-- finally set up the offscreen readback process that also calculates the hgram
	define_calctarget(ibuf, {vid},
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, 0,
		function(tbl, w, h)
			tbl:histogram_impose(hgram, hwnd.hgram.method, true);
-- FIXME: it is here we can match against reference histograms and notify
-- which distributions that actually match
		end
	);
	show_image({vid});
end

return {
	name = "histogram",
	label = "Histogram",
	description = "Histogram based statistics of window contents",
	kind = "action",
	handler = function()
		return build_histogram(active_display().selected);
	end
};
