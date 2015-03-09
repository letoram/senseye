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

local function goto_position(nw, slot)
	slot = slot < 0 and 0 or slot;
	slot = slot > 255 and 255 or slot;
	nw.hgram_slot = slot;

	local sz = nw.width > 256 and nw.width / 256 or 1;
	resize_image(nw.cursor, sz, nw.height);
	move_image(nw.cursor, slot * math.floor(nw.width / 256), 0);

	local slotstr = string.format("(0x%.2x) - ", slot);

	if (nw.lockv) then
		for i=1,#nw.lockv do
			slotstr = slotstr .. ":" .. string.format("0x%.2x", nw.lockv[i]);
		end
	end

	nw.parent:highlight((slot-0.1)/255, (slot+1)/255);
	nw:set_message(slotstr);
end

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
	nw.cursor_label = null_surface(1, 1);
	nw.cursor = cursor;

	nw.motion = function(wnd, vid, x, y)
		local rprops = image_surface_resolve_properties(wnd.canvas);
		local newx = (x-rprops.x > wnd.width) and wnd.width or (x-rprops.x);
		x = (x - rprops.x) / wnd.width;
		goto_position(wnd, math.floor(x * 255), y - rprops.y);
	end

-- left-click builds a list of clicked values, rclick resets it.
-- used with highlight- shader to find byte sequences visually.
	local oldclick = nw.click;
	nw.click = function(wnd, vid, x, y)
		if (wnd.wm.meta) then
			return oldclick(wnd, vid, x, y);
		end

		nw.hgram_lock = not nw.hgram_lock;
		if (nw.lockv) then
			local found = false;
			for i=1,#nw.lockv do
				if (nw.lockv[i] == nw.hgram_slot) then
					found = true;
					break;
				end
			end
			if (not found) then
				table.insert(nw.lockv, nw.hgram_slot);
			end
		else
			nw.lockv = {nw.hgram_slot};
		end
		update_highlight_shader(nw.lockv);

		if (nw.parent.highlight) then
			nw.parent:highlight((nw.hgram_slot-0.5) / 255.0,
				(nw.hgram_slot+0.5) / 255.0);
		end
	end

	nw.rclick = function(wnd, vid, x, y)
		nw.lockv = nil;
		update_highlight_shader({});
		goto_position(nw, nw.hgram_slot);
	end

	nw.zoom_position = function(self, wnd, x, y, r, g, b, a, click)
		local pos = 1;
		if (wnd.pack_sz == 1) then
			pos = r;
		elseif (wnd.pack_sz == 3) then
			pos = math.floor((r + g + b) / 3.0);
		elseif (wnd.pack_sz == 4) then
			pos = math.floor((r + g + b + a) / 4.0);
		end
		goto_position(nw, pos);

-- forward click so highlight stack works
		if (click and wnd.wm.meta_detail) then
			nw.click(wnd, wnd.canvas, x, y);
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
