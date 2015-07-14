-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: Translators are separate processes (see xlt_ascii)
-- that provide higher-level representations of sampled data. This
-- is done by a rather complex operation in the sense that we define
-- a record target (on-GPU composited buffer that is read down into
-- a shmpage accessible by the target).

--
-- we'll use a buffer that matches the size of the initial window
-- (destroy / rebuild if the dimensions are stored) then we hint/blit
-- the active subset on window
--

local function overlay_cb(source, status)
	if (status.kind == "terminated") then
		delete_image(source);

		warning("dropping overlay");
		for i=1, #wm.windows do
			if (wm.windows[i].xlt_overlay == source) then
				wm.windows[i].xlt_overlay = nil;
				table.remove_match(wm.windows[i].autodelete, source);
				return;
			end
		end
-- overlay allocated but nothing assigned
	end
end

--
-- performance consideration / tradeoff, overlays does not have to have
-- a size that matches input or output data windows.
--
-- note: overlay is not reset on translator reconnect after crash,
-- and there seem to be an issue with uniform zooming?
--
local function toggle_overlay(wnd, state)
	local pp = image_storage_properties(wnd.parent.canvas);
	if (not valid_vid(wnd.xlt_overlay)) then
		wnd.xlt_overlay = target_alloc(wnd.translator_out, overlay_cb);
		wnd:zoom_link(wnd.parent, image_get_txcos(wnd.parent.canvas));
		wnd.overlay_pause = false;
		table.insert(wnd.autodelete, wnd.xlt_overlay);
		wnd.parent:set_overlay(wnd.xlt_overlay, function()
			target_displayhint(wnd.xlt_overlay, wnd.parent.width, wnd.parent.height);
		end);

		blend_image(wnd.parent.overlay, wnd.overlay_opa and wnd.overlay_opa or 0.5);

	else
		wnd.overlay_pause = (state ~= nil) and state or (not wnd.overlay_pause);
		if (wnd.overlay_pause) then
			suspend_target(wnd.xlt_overlay);
		else
			target_displayhint(wnd.xlt_overlay, wnd.parent.width, wnd.parent.height);
			resume_target(wnd.xlt_overlay);
		end
	end

	if (not wnd.overlay_pause) then
		target_displayhint(wnd.xlt_overlay, wnd.parent.width, wnd.parent.height);
	end
end

-- wnd : parent
-- vtbl : {source, label} paired in table due to popupwnd restriction
-- srcwnd : if set, means don't create window but replace canvas
function activate_translator(wnd, vtbl, ign, srcwnd)
	local value = vtbl[1];

-- possibility of translator becoming invalid while menu is active
	if (not valid_vid(value)) then
		return;
	end

	local props = image_storage_properties(wnd.ctrl_id);
	local interim = null_surface(props.width, props.height);

	if (interim == BADID) then
		warning("buffer limit saturated, could not create translator buffers");
		return;
	end

	image_tracetag(interim, string.format("translator:%d - interim", value));

	local neww = nil;
	local tgt = define_feedtarget(value, wnd.ctrl_id, function(s, st)
	end);

	if (tgt == BADID) then
		warning("couldn't map feedtarget to translator");
		delete_image(interim);
		return;
	end

-- then the output that's connected to the new window
	local vid = target_alloc(value, function(source, status)
		if (status.kind == "resized" and neww.dragmode == nil) then
			neww:resize(status.width, status.height, true)
			neww:drag(source, 0, 0);

		elseif (status.kind == "ident") then
			neww.overlay_support = source;
			neww.activate_overlay = toggle_overlay;

		elseif (status.kind == "message") then
			neww:set_message(
				string.gsub(status.message, "\\", "\\\\"), DEFAULT_TIMEOUT);
		end
-- will transmit the current zoom-range and cause a refresh of the overlay
	end, wnd.size_cur
	);

	if (vid == BADID) then
		warning("couldn't push new subsegment to translator");
		delete_image(interim);
		delete_image(tgt);
		return;
	end

-- hook the output to a new window, and make sure the output buffer
-- gets tracked and deleted properly as well
	if (srcwnd) then
		neww = srcwnd;
		delete_image(neww.canvas);
		neww.canvas = vid;
		show_image(neww.canvas);
		image_inherit_order(neww.canvas, true);
		link_image(neww.canvas, neww.anchor);
		resize_image(neww.canvas, srcwnd.width, srcwnd.height);
		--target_displayhint(tgt, srcwnd.width, srcwnd.height);
	else
		neww = wnd.wm:add_window(vid, {});
		window_shared(neww);
		target_displayhint(tgt, 256, 256);
	end

	neww.name = neww.name .. "_translator_" .. tostring(value);
	neww.translator_name = vtbl[2];
	neww.fullscreen_disabled = true;
	neww:set_parent(wnd, ANCHOR_LL);
	neww.reposition = repos_window;
	neww.translator_out = tgt;
	neww.ctrl_id = vid;
	neww:select();

	--scale_image(vid, 1.0, 1.0);
	image_tracetag(vid, string.format("translator:%d - output", value));

	neww.source_handler = function(wnd, source, status)
		if (status.kind == "streaminfo") then
			psense_decode_streaminfo(wnd, status);
			target_graphmode(tgt, wnd.pack_sz);
		end
	end

	neww.input_sym = function(self, sym)
		local iotbl = {
			kind = "digital",
			active = "true",
			label = sym;
		};
		target_input(tgt, iotbl);
	end

-- need this to protect from I/O storms where high-samplerate
-- devices fill the queue in the target
	neww.tick = function()
		if (neww.input_queue ~= nil) then
			target_input(tgt, neww.input_queue);
			neww.input_queue = nil;
		end
	end

	local old_drop = neww.drop;
	local old_resize = neww.resize;

	neww.resize = function(wnd, w, h, from_handler)
		if (from_handler) then
			return old_resize(wnd, w, h);
		end

		if (wnd.dragmode == nil) then
			return;
		else
			return old_resize(wnd, w, h);
		end
	end

-- temporary workaround to the feedback loop problem we have
-- with the buggy arcan -> resizefeed not updating scaling factors
-- correctly
	neww.old_drop = neww.drop;
	neww.drop = function(wnd, vid, x, y)
		if (wnd.dragmode ~= nil) then
			target_displayhint(tgt, wnd.width, wnd.height);
		end
		old_drop(wnd, vid, x, y);
	end

-- we treat these as "click" events in that the set the base
-- buffer ofset in the output segment
	neww.zoom_position = function(self, wnd, px, py)
		local iotbl = {
			kind = "touch",
			devid = 0,
			subid = 0,
			x = px,
			y = py,
			pressure = 1,
			size = 1
		};
		neww.input_queue = iotbl;
	end

-- translate zoom texture coordinates back to their aligned sample points
	neww.zoom_link = function(self, wnd, txcos)
		local iotbl = {
			kind = "analog",
			devid = 0,
			subid = 0,
			samples = {}
		};

		local props = image_storage_properties(neww.parent.canvas);
		iotbl.samples[1] = math.floor(props.width * txcos[1]);
		iotbl.samples[2] = math.floor(props.height * txcos[2]);
		iotbl.samples[3] = math.ceil(props.width * txcos[5]);
		iotbl.samples[4] = math.ceil(props.height * txcos[6]);

		target_input(tgt, iotbl);
	end

	wnd:add_zoom_handler(neww);
	table.insert(wnd.source_listener, neww);
	table.insert(neww.autodelete, tgt);
end

translator_popup = {
	handler = activate_translator;
};
