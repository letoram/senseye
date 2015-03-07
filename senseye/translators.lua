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
function activate_translator(wnd, value)
	local props = image_storage_properties(wnd.ctrl_id);
	local interim = null_surface(props.width, props.height);

	if (interim == BADID) then
		warning("buffer limit saturated, could not create translator buffers");
		return;
	end

	image_tracetag(interim, string.format("translator:%d - interim", value));

	local neww = nil;
	local tgt = define_feedtarget(value, wnd.ctrl_id, function() end);

	if (tgt == BADID) then
		warning("couldn't map feedtarget to translator");
		delete_image(interim);
		return;
	end

-- then the output that's connected to the new window
	local vid = target_alloc(value, function(source, status)
		neww.in_handler = true;

		if (status.kind == "resized") then
			neww:resize(status.width, status.height)
		end

		neww.in_handler = false;
	end, wnd.size_cur
	);

	if (vid == BADID) then
		warning("couldn't push new subsegment to translator");
		delete_image(interim);
		delete_image(tgt);
		return;
	end

	target_displayhint(tgt, props.width, props.height);

-- hook the output to a new window, and make sure the output buffer
-- gets tracked and deleted properly as well
	neww = wnd.wm:add_window(vid, {});
	neww.name = neww.name .. "_translator_" .. tostring(value);
	neww.fullscreen_disabled = true;
	neww:set_parent(wnd, ANCHOR_LL);
	neww.reposition = repos_window;
	neww.translator_out = tgt;
	neww.ctrl_id = vid;
	neww:select();
	neww.old_resize = neww.resize;
	neww.resize = function(wnd, w, h, interm)
		if (neww.in_handler) then --feedback loop protection
			neww:old_resize(w, h);
			return;
		end
		target_displayhint(tgt, w, h);
	end

	scale_image(vid, 1.0, 1.0);
	image_tracetag(vid, string.format("translator:%d - output", value));

	neww.source_handler = function(wnd, source, status)
		if (status.kind == "streaminfo") then
			psense_decode_streaminfo(wnd, status);
			target_graphmode(tgt, wnd.size_cur);
		end
	end

	neww.input_sym = function(self, sym)
		if (sym ~= "LEFT" and sym ~= "RIGHT" and sym ~= "UP"
			and sym ~= "DOWN" and sym ~= "TAB") then
			return;
		end

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

	wnd:add_zoom_handler(neww);
	table.insert(wnd.source_listener, neww);
	table.insert(neww.autodelete, tgt);
end

translator_popup = {
	handler = activate_translator;
};
