-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: Histogram statistics tool. Most of the
-- 'heavy' lifting is done in arcan engine internals as
-- part of the calctarget feature, here we primarily
-- map UI resources and do buffer setup.

local function bhattacharyya(h1, h2)
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

local function intersection(h1, h2)
	local sum = 0;
	for i=0,255 do
		sum = sum + (h1[i] > h2[i] and h2[i] or h1[i]);
	end
	return sum;
end

local match_func = {
	{
		label = "Bhattacharyya",
		name = "match_bhatt",
		handler = function(wnd)
			wnd.match_fun = bhattacharyya;
			wnd.parent:set_message("Bhattacharyya matching", DEFAULT_TIMEOUT);
		end
	},
	{
		label = "Intersection",
		name = "match_intersect",
		handler = function(wnd)
			wnd.match_fun = intersection;
			wnd.parent:set_message("Intersection matching", DEFAULT_TIMEOUT);
		end,
	}
};

local match_val = {};

for k,v in ipairs({99, 98, 95, 90, 80, 70, 60}) do
	table.insert(match_val, {
		label = string.format("%d %%", v),
		value = v,
		name = "match_thresh"
	});
end

match_val.handler = function(wnd, value, rv)
	value = value < 1 and 1 or value;
	value = value > 100 and 100 or value;
	wnd.thresh = value;
	wnd.parent:set_message(string.format(
		"Trigger tolerance at %d%% deviation", value), DEFAULT_TIMEOUT);
	if (rv) then
		gconfig_set("match_default", value);
	end
end

-- need to track and toggle synchronous matching behavior
-- to reduce the risk of race conditions at the expense
-- of being vulnerable to clients stalling us.
local histo_popup = {
	{
		label = "Toggle Matching...",
		name = "ph_ptn_find",
		handler = function(wnd)
			if (wnd.ref_histo == nil) then
				wnd.log_histo = true;
				if (wnd.scanners ~= nil) then
					wnd.scanners = wnd.scanners + 1;
				else
					wnd.scanners = 1;
					target_synchronous(wnd.parent.ctrl_id, 1);
				end
				wnd.thresh = gconfig_get("hmatch_pct");
				wnd.parent:set_message(string.format(
					"Matching > (%d%%)", wnd.thresh), gconfig_get("msg_timeout"));
			else
				wnd.parent:set_message("Matching disabled", DEFAULT_TIMEOUT);
				wnd.ref_histo = nil;
				wnd.scanners = wnd.scanners - 1;
				if (wnd.scanners == 0) then
					target_synchronous(wnd.parent.ctrl_id, 0);
				end
			end
		end
	},
	{
		label = "Matching Function...",
		name = "ph_ptn_match",
		submenu = match_func
	},
	{
		label = "Trigger Deviation...",
		name = "ph_ptn_trig",
		submenu = match_val
	}
};

local function goto_position(nw, slot)
	slot = slot < 0 and 0 or slot;
	slot = slot > 255 and 255 or slot;
	nw.hgram_slot = slot;

	local sz = nw.width > 256 and nw.width / 256 or 1;
	resize_image(nw.cursor, sz, nw.height);
	move_image(nw.cursor, slot * nw.width / 255, 0);

	local slotstr = string.format("(0x%.2x) - ", slot);

	if (nw.lockv) then
		for i=1,#nw.lockv do
			slotstr = slotstr .. ":" .. string.format("0x%.2x", nw.lockv[i]);
		end
	end

	nw.parent:highlight((slot-0.1)/255, (slot+1)/255);
	nw:set_message(slotstr, -1);
end

-- just extract the values, scale and normalize to 1
local function pop_htable(tbl, dst)
	local sum = 0;
	for i=0, 255 do
		dst[i] = tbl:frequency(i, HISTOGRAM_MERGE_NOLPHA, false);
		sum = sum + dst[i];
	end

	if (sum > 0) then
		for i=0,255 do
			dst[i] = dst[i] / sum;
		end
	end
end

local function force_update(nw)
	rendertarget_forceupdate(nw.calc_target);
	stepframe_target(nw.calc_target);
end

-- missing, comparison function. Possible candidates:
-- chisquare (perfect, 0.0, total: relative to hgram size), sum((h1[n]-h2[n])^2/(h1[n]+h2[n])),
-- correl (-1 .. 1), sum( hp1[n] * hp1[n] ) / sqrt( sum(hp1^2 * hp2^2) ) and
-- hp is h[n] - (1/256)*sum(h[n])
-- intersect ( 0.. 1) sum(min(h1[n], h2[n]))

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

-- anchor a new window to the data source window, and setup
-- some of the required event handlers (reposition, ...)
	local nw = wnd.wm:add_window(hgram, {});
	nw.reposition = repos_window;
	nw:set_parent(wnd, ANCHOR_LR);
	nw:resize(wnd.width, wnd.height);
	window_shared(nw);
	local destroy = nw.destroy;

	local old_resize = nw.resize;

	nw.resize = function(wnd, neww, newh)
		old_resize(wnd, neww, newh);
		goto_position(nw, nw.hgram_slot);
	end

	force_image_blend(csurf, BLEND_NONE);

	define_calctarget(ibuf, {csurf}, RENDERTARGET_DETACH,
		RENDERTARGET_NOSCALE, 0, function(tbl, w, h)
		tbl:histogram_impose(hgram, HISTOGRAM_MERGE_NOALPHA, true);
-- same as in patfind.lua, only alert when going out->in
		if (nw.ref_histo ~= nil) then
			local ctbl = {};
			pop_htable(tbl, ctbl);
			local pct = 100 * nw.match_fun(nw.ref_histo, ctbl);
			if (pct >= nw.thresh) then
				nw:set_border(2, 0, 255 - (100-nw.thresh)/255*(pct - nw.thresh), 0);
				if (not nw.in_signal) then
					nw.in_signal = true;
					nw.signal_pos = nw.parent.ofs;
					nw:set_border(2, 0, 255 - (100-nw.thresh)/255*(pct - nw.thresh), 0);
					nw.parent:alert("histogram", nw.parent.ctrl_id, nw.signal_pos);
				end
			else
				nw:set_border(2, 255 - ((nw.thresh-pct)/nw.thresh)*255, 0, 0);
				nw.in_signal = false;
			end

		elseif (nw.log_histo == true) then
			nw.ref_histo = {};
			pop_htable(tbl, nw.ref_histo);
			nw.log_histo = false;
			nw.in_signal = true;
			nw:set_border(2, 0, 255, 0);
		end
	end);

-- this might seem a bit odd, but since both uploads and
-- readbacks are asynchronous by default (and we don't want
-- the stalls imposed for synchronous transfers) we defer
-- histogram updates and lock them to the logical clock.
	nw.source_handler = function(wnd, source, status)
		if (status.kind == "frame") then
			rendertarget_forceupdate(ibuf);
			stepframe_target(ibuf);
		end
	end

-- highlight cursor that follows mouse motion and indicates
-- the currently selected column (which is scaled and tracked
-- as hgram_slot)
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
	nw.match_fun = bhattacharyya;

	local old_motion = nw.motion;
	nw.motion = function(wnd, vid, x, y)
		old_motion(wnd, vid, x, y);
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
		wnd:select();

		if (wnd.wm.meta) then
			nw.lockv = nil;
			update_highlight_shader({});
			goto_position(nw, nw.hgram_slot);
		else
			spawn_popupmenu(wnd.wm, wnd.popup);
		end
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

	nw.dispatch["RIGHT"] = function()
		if (nw.ref_histo ~= nil) then
			match_val.handler(nw, nw.thresh - 1);
			nw:force_update();
		else
			goto_position(nw, nw.hgram_slot + (nw.wm.meta and 10 or (
				nw.wm.meta_detail and 30 or 1)));
		end
	end

	nw.dispatch[BINDINGS["SELECT"]] = function()
		nw:click(wnd.canvas, x, y);
	end

	nw.dispatch["LEFT"] = function()
		if (nw.ref_histo ~= nil) then
			match_val.handler(nw, nw.thresh + 1);
			nw:force_update();
		else
			goto_position(nw, nw.hgram_slot + (nw.wm.meta_detail and -10 or (
				nw.wm.meta_detail and -30 or -1)));
		end
	end

	nw.zoom_link = function(self, wnd, txcos)
		image_set_txcos(csurf, txcos);
		nw:force_update();
	end

	table.insert(nw.parent.source_listener, nw);
	table.insert(nw.autodelete, ibuf);

	nw.calc_target = ibuf;
	nw.force_update = force_update;
	nw.parent:add_zoom_handler(nw);
	nw.popup = histo_popup;
	nw.dispatch[BINDINGS["POPUP"]] = wnd.dispatch[BINDINGS["POPUP"]];

	nw.shader_group = shaders_1dplot;
	nw.shind = 1;
	nw.fullscreen_disabled = true;
	defocus_window(nw);
	switch_shader(nw, nw.canvas, shaders_1dplot[1]);
end
