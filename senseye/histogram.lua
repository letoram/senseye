-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: Histogram statistics tool. Most of the
-- 'heavy' lifting is done in arcan engine internals as
-- part of the calctarget feature, here we primarily
-- map UI resources and do buffer setup.

local histo_popup = {
	{
		label = "Switch Normalization Mode",
		name = "ph_zoom_norm",
		handler = function(wnd)
			wnd.normalize = not wnd.normalize;
			wnd.pending = 1;
		end
	}
};

function spawn_histogram(wnd)
-- create composition buffer, intermediate buffer and histogram
-- buffer. Setup a calctarget that imposes the histogram unto to
-- histogram buffer (which is used as the window canvas)
	local props = image_storage_properties(wnd.ctrl_id);
	local hgram = fill_surface(256, 1, 0, 0, 0, 256, 1);
	local ibuf = alloc_surface(props.width, props.height);
	local csurf = null_surface(props.width, props.height);
	image_sharestorage(wnd.ctrl_id, csurf);
	show_image(csurf);

--
-- anchor a new window to the data source window, and setup
-- some of the required event handlers (reposition, ...)
--
	local nw = wnd.wm:add_window(hgram, {});
	nw.reposition = repos_window;
	nw:set_parent(wnd, ANCHOR_LR);
	nw:resize(wnd.width, wnd.height);
	local destroy = nw.destroy;
	nw.normalize = true;

	define_calctarget(ibuf, {csurf}, RENDERTARGET_DETACH,
		RENDERTARGET_NOSCALE, 0, function(tbl, w, h)
		tbl:histogram_impose(hgram, HISTOGRAM_MERGE_NOALPHA, nw.normalize);
	end);

--
-- this might seem a bit odd, but since both uploads and
-- readbacks are asynchronous by default (and we don't want
-- the stalls imposed for synchronous transfers) we defer
-- histogram updates and lock them to the logical clock.
--
	nw.pending = 1;
	nw.tick = function()
		if (nw.pending > 0) then
			nw.pending = 0;
			stepframe_target(ibuf);
		end
	end

	nw.source_handler = function(wnd, source, status)
		if (status.kind == "frame") then
			nw.pending = nw.pending + 1;
		end
	end

--
-- highlight cursor that follows mouse motion and indicates
-- the currently selected column (which is scaled and tracked
-- as hgram_slot)
--
	local cursor = color_surface(1, wnd.height, 0, 255, 0);
	blend_image(cursor, 0.8);
	link_image(cursor, nw.canvas);
	image_inherit_order(cursor, true);
	order_image(cursor, 1);
	image_mask_set(cursor, MASK_UNPICKABLE);
	table.insert(nw.autodelete, cursor);
	nw.hgram_lock = false;
	local cursor_label = null_surface(1, 1);

	nw.motion = function(wnd, vid, x, y)
		local rprops = image_surface_resolve_properties(wnd.canvas);
		local newx = (x-rprops.x > wnd.width) and wnd.width or (x-rprops.x);
		move_image(cursor, newx, 0);
		x = (x - rprops.x) / wnd.width;
		nw.hgram_slot = math.floor(x * 255);

		local lockstr = nw.hgram_lock and ", lock: " .. tostring(nw.lockv) or "";

		delete_image(cursor_label);
		cursor_label = render_text(menu_text_fontstr ..
			" " .. tostring(nw.hgram_slot) .. lockstr);
		show_image(cursor_label);
		image_inherit_order(cursor_label, true);
		link_image(cursor_label, cursor);
		move_image(cursor_label, 0, 10);

		if (not nw.hgram_lock and nw.parent.highlight) then
			nw.parent:highlight((nw.hgram_slot-0.5) / 255.0,
				(nw.hgram_slot+0.5) / 255.0);
		end

		resize_image(cursor, 1, rprops.height);
	end

-- overload the default click-handler and use default click for
-- meta but forward highlight- value to parent
	local oldclick = nw.click;
	nw.click = function(wnd, vid, x, y)
		if (wnd.wm.meta) then
			return oldclick(wnd, vid, x, y);
		end

		nw.hgram_lock = not nw.hgram_lock;
		nw.lockv = nw.hgram_slot;

		if (nw.parent.highlight) then
			nw.parent:highlight((nw.hgram_slot-0.5) / 255.0,
				(nw.hgram_slot+0.5) / 255.0);
		end
	end

	nw.zoom_link = function(self, wnd, txcos)
		image_set_txcos(csurf, txcos);
		rendertarget_forceupdate(ibuf);
		stepframe_target(ibuf);
	end

	table.insert(nw.parent.source_listener, nw);
	table.insert(nw.autodelete, ibuf);
	nw.parent:add_zoom_handler(nw);

	nw.popup = histo_popup;
	nw.dispatch[BINDINGS["POPUP"]] = wnd.dispatch[BINDINGS["POPUP"]];

	nw.shader_group = shaders_1dplot;
	nw.shind = 1;
	nw.fullscreen_disabled = true;
	defocus_window(nw);
	switch_shader(nw, nw.canvas, shaders_1dplot[1]);
end
