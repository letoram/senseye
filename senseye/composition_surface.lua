--
-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD.
-- Reference: http://arcan-fe.com
--

--
-- Composition Surface
--
-- Utility script / interface for managing windows
-- connected to external processes / frameservers.
--
-- The use for this is both traditional window management but also for nested
-- window managing purposes, like recording, remote desktop etc.
--
-- compiled shaders, indexed by both type and by width
-- (so uniform state is combined with shader identifier)
--

local default_width = 1;

system_load("uiprim.lua")();

local function compsurf_find(ctx, name)
	if (type(name) == "string") then
		for k, v in ipairs(ctx.windows) do
			if (v.name == name) then
				return v;
			end
		end

	elseif(type(name) == "number") then
		return ctx.src_lut[name];
	end
end

local function wnd_ind(tbl, wnd)
	for k,v in ipairs(tbl) do
		if (v == wnd) then
			return k;
		end
	end
end

local function broadcast(group, wnd, wnd2)
	for k,v in ipairs(group) do
		v(wnd, wnd2);
	end
end

local function compsurf_wnd_deselect(wnd)
	if (wnd.wm.selected == wnd) then
		broadcast(wnd.wm.handlers.deselect, wnd);
		wnd.wm.selected = nil;
	end
end

local function forward_children(wm, wnd)
	if (wnd.children) then
		for k,v in ipairs(wnd.children) do
			local ind = wnd_ind(wm.windows, v);
			table.remove(wm.windows, ind);
			table.insert(wm.windows, v);
			if (v.children) then
				forward_children(wm, v);
			end
		end
	end
end

-- visual queue that the window is not currently used,
-- primarily for popup purposes
local function compsurf_wnd_activate(wnd)
end

local function compsurf_wnd_deactivate(wnd)
end

local function compsurf_wnd_select(wnd)
	if (wnd.wm.selected == wnd) then
		return;
	end
	local wm = wnd.wm;

-- update visual state, trigger external event listeners
	if (wm.selected) then
		wm.selected:deactivate();
		broadcast(wm.handlers.deselect, wm.selected, wnd);
		order_image(wm.selected.anchor, wm.selected.deselorder);
	end

	wm.selected = wnd;
	wnd:activate();
	broadcast(wm.handlers.select, wnd);

-- we use the flat windows list to determine drawing order
	forward_children(wm, wnd);
	local ind = wnd_ind(wm.windows, wnd);
	table.remove(wm.windows, ind);
	table.insert(wm.windows, wnd);

-- handle "always on top" windows by always sorting last
	local tmp = {};
	for i=#wnd.wm.windows,1,-1 do
		if (wnd.wm.windows[i].ontop) then
			table.insert(tmp, wnd.wm.windows[i]);
			table.remove(wnd.wm.windows, i);
		end
	end

	for i,v in ipairs(tmp) do
		table.insert(wnd.wm.windows, v);
	end

-- 10 order slots per window should be enough for everyone
	for i, v in ipairs(wnd.wm.windows) do
		order_image(v.anchor, 1 + i * 10);
	end
end

local function compsurf_wnd_destroy(wnd, cascade)
-- drop connection to mouse handler, zero out table members
-- and optionally cascade upwards
	local wm = wnd.wm;

	mouse_droplistener(wnd);

	if (wnd.wm.selected == wnd) then
		wnd.wm.selected = nil;
	end

-- need to copy the children list as the recursive destroy
-- deregisters itself (!)
	local list = {};
	for i,v in ipairs(wnd.children) do
		list[i] = v;
	end
	for i,v in ipairs(list) do
		v:destroy();
	end

	for i,v in ipairs(wnd.autodelete) do
		delete_image(v);
	end

-- make sure we can't LUT anymore
	wnd.wm.src_lut[wnd.canvas] = nil;

-- notify all listeners that this windows is about to disappear
	broadcast(wnd.wm.handlers.destroy, wnd);

-- drop from list, delete anchor (which will cascade
-- to all linked surfaces), deregister
	local wi = wnd_ind(wnd.wm.windows, wnd);
	table.remove(wnd.wm.windows, wi);
	local oi = wnd_ind(wnd.wm.wnd_order, wnd);
	if (oi ~= nil) then
		table.remove(wnd.wm.wnd_order, oi);
	end

	delete_image(wnd.anchor);

	local p = wnd.parent;
	for k,v in pairs(wnd) do
		wnd[k] = nil;
	end
	wnd.destroyed = true;

	if (p) then
		for i,v in ipairs(p.children) do
			if (v == wnd) then
				table.remove(p.children, i);
				break;
			end
		end

-- cascade to possible parents
		if (cascade) then
			p:destroy(cascade);
		end
	end
end

local function compsurf_wnd_own(wnd, vid)
	if (not valid_vid(vid)) then
		return;
	end

	if (not valid_vid(wnd.canvas)) then
		mouse_droplistener(wnd);
		return;
	end

	return (vid == wnd.canvas or image_children(wnd.canvas, vid));
end

local function compsurf_wnd_click(wnd)
end

local function compsurf_wnd_rclick(wnd)
end

local function compsurf_wnd_dblclick(wnd)
end

-- set prerendered msg vid in message slot
local function compsurf_wnd_message(ctx, msg, expiration)
	if (not ctx.bottom_bar) then
		return;
	end
	ctx.bottom_bar:update("center", 1, msg, expiration);
end

local function resolve_abs_xy(wnd, newx, newy)
	local tmp = wnd.parent;
	local desx = newx;
	local desy = newy;

	while (tmp ~= nil) do
		desx = tmp.x - desx;
		desy = tmp.y - desy;
		tmp = tmp.parent;
	end

	return newx, newy;
end

local function compsurf_wnd_repos(wnd)
-- limit to managed surface area
	local dx, dy = resolve_abs_xy(wnd, wnd.x, wnd.y);

	if ((wnd.x - wnd.pad_left) +
		wnd.pad_right + wnd.width > wnd.wm.max_w) then
		dx = wnd.wm.max_w - wnd.width - wnd.pad_left - wnd.pad_right;
	end

	if ((wnd.x - wnd.pad_left) < 0) then
		dx = wnd.pad_left;
	end

	if ((wnd.y - wnd.pad_top) < 0) then
		dy = wnd.pad_top;
	end

	if ((wnd.y - wnd.pad_top) +
		wnd.pad_bottom + wnd.height > wnd.wm.max_h) then
		dy = wnd.wm.max_h - wnd.height - wnd.pad_top - wnd.pad_bottom;
	end

	if (dx ~= wnd.x or dy ~= wnd.y) then
		move_image(wnd.anchor, dx, dy);
		wnd.x = dx;
		wnd.y = dy;
	end
end

local function compsurf_wnd_move(wnd, newx, newy, repos)
	local tmp = wnd.parent;
	local desx = newx;
	local desy = newy;

	while (tmp ~= nil) do
		desx = tmp.x - desx;
		desy = tmp.y - desy;
		tmp = tmp.parent;
	end

	move_image(wnd.anchor, desx, desy);
	wnd.x = desx;
	wnd.y = desy;

	if (repos) then
		compsurf_wnd_repos(wnd);
	end
end

--
-- interm marks that we will likely receive additional
-- events close to this one, more important when we
-- forward to a frameserver
--
local function compsurf_wnd_resize(wnd, neww, newh, interm)
	neww = neww < wnd.wm.min_w and wnd.wm.min_w or neww;
	newh = newh < wnd.wm.min_h and wnd.wm.min_h or newh;

	resize_image(wnd.canvas, neww, newh);
	resize_image(wnd.overlay, neww, newh);
	resize_image(wnd.anchor, neww, newh);
	if (wnd.top_bar) then
		wnd.top_bar:resize(neww, wnd.top_bar.height);
	end
	if (wnd.bottom_bar) then
		wnd.bottom_bar:resize(neww, wnd.top_bar.height);
	end

	wnd.width = neww;
	wnd.height = newh;

	if (wnd.overlay_resize) then
		wnd:overlay_resize(wnd.width, wnd.height);
	end

	compsurf_wnd_repos(wnd);
end

local function compsurf_wnd_drag(wnd, vid, x, y)
	if (wnd.wm.meta == nil) then
		return;
	end

	wnd.dragging = true;

	local mx, my = mouse_xy();
	nudge_image(wnd.anchor, x, y);
	wnd.x = wnd.x + x;
	wnd.y = wnd.y + y;
--	compsurf_wnd_repos(wnd);
end

local function compsurf_wnd_drop(wnd)
	wnd.dragging = nil;
end

local function compsurf_wnd_over(wnd)
end

local function compsurf_wnd_press(wnd)
	wnd:select();
end

local function compsurf_wnd_release(wnd)
end

local function compsurf_wnd_out(wnd)
end

local function compsurf_wnd_motion(wnd, vid, x, y)
	if (wnd.dragging or wnd.meta) then
		return;
	end
end

local function compsurf_wnd_hover(wnd)
end

local function compsurf_wnd_bar(wnd, dir, thickness)
	if (dir == "t") then
		if (wnd.top_bar) then
			wnd.top_bar:destroy();
			wnd.top_bar = nil;
		end
		wnd.top_bar = uiprim_bar(
			wnd.canvas, ANCHOR_UL, wnd.width, thickness, nil);
		move_image(wnd.top_bar.anchor, 0, -thickness);
		wnd.pad_top = thickness;
		compsurf_wnd_repos(wnd);
		return wnd.top_bar;
-- add titlebar action handler for drag etc.
	elseif (dir == "b") then
		if (wnd.bottom_bar) then
			wnd.bottom_bar:destroy();
			wnd.bottom_bar = nil;
		end
		wnd.bottom_bar = uiprim_bar(
			wnd.canvas, ANCHOR_LL, wnd.width, thickness, nil);
		wnd.pad_bottom = thickness;
		compsurf_wnd_repos(wnd);
	return wnd.bottom_bar;
	else
		warning("add_bar(dir), unsupported direction, only 't' and 'b' allowed");
		return;
	end
end

local function compsurf_wnd_parent(ctx, wnd, relative)
	link_image(ctx.anchor, wnd.anchor, relative);

-- reparent
	if (ctx.parent) then
		for i,v in ipairs(ctx.parent.children) do
			if (v == ctx) then
				table.remove(ctx.parent.children, i);
				break;
			end
		end
	end

	ctx.parent = wnd;
	table.insert(ctx.parent.children, ctx);

	if (relative == nil) then
		return;
	end

	move_image(ctx.anchor, 0, 0);
end

local wseq = 1;

local function input_stub(iotbl)
end

local function input_dispatch(wnd, sym, active, srctbl)
	if (wnd.wm.meta and wnd.parent and
		wnd.dispatch[sym] == nil and wnd.parent.dispatch[sym]) then
		wnd = wnd.parent;
	end

	if (wnd.dispatch[sym] ~= nil) then
		wnd.dispatch[sym](wnd);
	end
end

local function compsurf_wnd_activate(wnd)
end

local function compsurf_wnd_inactivate(wnd)
end

local function compsurf_wnd_hide(wnd)
	hide_image(wnd.anchor);
end

local function compsurf_wnd_show(wnd)
	show_image(wnd.anchor);
end

local function compsurf_next_window(ctx, wnd)
	local oi = 1;

	if (wnd ~= nil) then
		oi = wnd_ind(ctx.wnd_order, wnd);
		if (oi ~= nil) then
			oi = (oi + 1) > #ctx.wnd_order and 1 or (oi + 1);
		end
	end

	if (oi ~= nil and ctx.wnd_order[oi]	~= nil) then
		ctx.wnd_order[oi]:select();
	end
end

local function compsurf_wnd_overlay(ctx, source, rzhandle)
	image_sharestorage(source, ctx.overlay);
	force_image_blend(ctx.overlay, BLEND_FORCE);
	ctx.overlay_resize = rzhandle;
end

local function compsurf_add_window(ctx, surf, opts)
	local w = opts.width ~= nil and opts.width or ctx.def_ww;
	local h = opts.height ~= nil and opts.height or ctx.def_wh;

	local wnd = {
		anchor = null_surface(w, h),
		name = opts.name and opts.name or
			string.format("%s_wnd_%d", ctx.name, wseq),
		wm = ctx,
		canvas = surf,
		children = {},
		autodelete = {},
		focus_color = {192, 192, 192},
		normal_color = {128, 128, 128},
		overlay = null_surface(w, h),
		deselect = compsurf_wnd_deselect,
		select = compsurf_wnd_select,
		destroy = compsurf_wnd_destroy,
		resize = compsurf_wnd_resize,
		move = compsurf_wnd_move,
		hide = compsurf_wnd_hide,
		show = compsurf_wnd_show,
		deactivate = compsurf_wnd_deactivate,
		activate = compsurf_wnd_activate,
		abs_xy = resolve_abs_xy,
		set_overlay = compsurf_wnd_overlay,
		set_parent = compsurf_wnd_parent,
		set_bar = compsurf_wnd_bar,
		set_border = function() print("border missing"); end,
		set_message = compsurf_wnd_message,

-- account for additional "tacked-on" surfaces (border, bars, ...)
		pad_left = 0,
		pad_right = 0,
		pad_top = 0,
		pad_bottom = 0,

-- track position / dimensions here to cut down on _properties calls
		x = 0,
		y = 0,
		width = w,
		height = h,
		last_border_color = {255, 255, 255, 255},

-- background "only" objects can fix the orderv.
		selorder = opts.selorder ~= nil and opts.selorder or ctx.selorder,
		deselorder = opts.deselorder ~= nil and opts.deselorder or ctx.deselorder,

-- stub symbol, replace with eg. target_input(source, iotbl)
		dispatch = {},
		input = input_stub,
		input_sym = input_dispatch,

-- always on top => re-order on new window
		ontop = opts.ontop,

-- default mouse handlers
		own = compsurf_wnd_own,
		click = compsurf_wnd_click,
		rclick = compsurf_wnd_rclick,
		dblclick = compsurf_wnd_dblclick,
		rclick = compsurf_wnd_click,
		press = compsurf_wnd_press,
		release = compsurf_wnd_release,
		drag = compsurf_wnd_drag,
		drop = compsurf_wnd_drop,
		over = compsurf_wnd_over,
		out = compsurf_wnd_out,
		motion = compsurf_wnd_motion,
		hover = compsurf_wnd_hover,
	};

--	image_mask_set(wnd.anchor, MASK_UNPICKABLE);
	image_mask_set(wnd.overlay, MASK_UNPICKABLE);
	image_tracetag(wnd.anchor, wnd.name .. "_anchor");
	image_tracetag(wnd.canvas, wnd.name .. "_canvas");

	link_image(wnd.canvas, wnd.anchor);
	link_image(wnd.anchor, ctx.canvas);
	link_image(wnd.overlay, wnd.canvas);

	image_inherit_order(wnd.canvas, true);
	image_inherit_order(wnd.overlay, true);
	order_image(wnd.overlay, 1);

	resize_image(wnd.canvas, wnd.width, wnd.height);
	show_image({wnd.canvas, wnd.anchor});

	if (not opts.fixed) then
		mouse_addlistener(wnd, {"click", "rclick", "drag", "drop",
			"dblclick", "over", "out", "press", "release",
			"hover", "motion"}
		);
	end

	wseq = wseq + 1;

	table.insert(ctx.windows, wnd);
	if (not opts.block_select) then
		table.insert(ctx.wnd_order, wnd);
	end

	ctx.src_lut[wnd.canvas] = wnd;

	if (not ctx.selected and not opts.fixed) then
		wnd:select();
	end

	return wnd;
end

local seq = 1;

local function compsurf_background(ctx, bg)
	if (valid_vid(ctx.background_id)) then
		delete_image(ctx.background_id);
	end

	image_tracetag(bg, "compsurf_background");
	link_image(bg, ctx.canvas);
	show_image(bg);
	move_image(bg, 0, 0);
	resize_image(bg, ctx.max_w, ctx.max_h);

	ctx.background_id = bg;
end

local function compsurf_input(ctx, iotbl)
	if (ctx.inp_lock) then
		ctx.inp_lock(iotbl);
		return;
	end

	if (ctx.fullscreen) then
		if (ctx.fullscreen.fullscreen_input) then
			ctx.fullscreen:fullscreen_input(iotbl, ctx.fullscreen_vid);
		end
		return;
	end

	if (ctx.selected) then
		ctx.selected:input(iotbl);
	end
end

local function compsurf_input_sym(ctx, sym, active, tbl)
	if (not active) then
		sym = "r" .. sym;
	end

	if (ctx.inp_lock) then
		ctx.inp_lock(sym, active, tbl);
		return;
	end

	if (ctx.meta and ctx.dispatch[sym]) then
		return ctx.dispatch[sym](ctx, sym, active, tbl);
	end

	if (ctx.fullscreen) then
		if (ctx.fullscreen.fullscreen_input_sym) then
			ctx.fullscreen:fullscreen_input_sym(sym, ctx.fullscreen_vid, active, tbl);
		end
		return;
	end

	if (ctx.selected) then
		ctx.selected:input_sym(sym, active, tbl);

	elseif (ctx.dispatch[sym]) then
		ctx.dispatch[sym](ctx, sym, active, tbl);
	end
end

--
-- fullscreen is rather complex as it involved input routing, possible
-- specialized input modes, shaders, being overridden by various keypresses
-- etc. Add to that 'fullscreen' actually means "filling the composition
-- surface" as we can have nested composition etc.
--
local function compsurf_fullscreen(ctx)
	if (ctx.selected == nil or
		ctx.selected.fullscreen_disabled) then
		return;
	end

	if (ctx.fullscreen_vid) then
		delete_image(ctx.fullscreen_vid);
		ctx.fullscreen = nil;
		ctx.fullscreen_vid = nil;
		for i,v in ipairs(ctx.windows) do
			v:show();
		end
		if (ctx.fullscreen_mouse) then
			mouse_droplistener(ctx.fullscreen_mouse);
			ctx.fullscreen_mouse = nil;
		end
		return;
	end

	for i,v in ipairs(ctx.windows) do
		v:hide();
	end

	ctx.fullscreen_vid = null_surface(ctx.max_w, ctx.max_h);

	if (ctx.selected.fullscreen_mouse) then
		ctx.fullscreen_mouse = ctx.selected.fullscreen_mouse;
		ctx.fullscreen_mouse.own = function(src, vid)
			return vid == ctx.fullscreen_vid;
		end
		ctx.fullscreen_mouse.name = ctx.name .. "_fullscreen";
		mouse_addlistener(ctx.selected.fullscreen_mouse,
		{"click", "drag", "drop",	"motion", "dblclick", "rclick"});
	end

	show_image(ctx.fullscreen_vid);
	image_tracetag(ctx.fullscreen_vid, "fullscreen");
	image_sharestorage(ctx.selected.canvas, ctx.fullscreen_vid);
	order_image(ctx.fullscreen_vid, ctx:max_order());
	ctx.fullscreen = ctx.selected;

--
-- reset the shader for the specific window so that any hooks
-- and tracking gets updated as well
--
	if (ctx.fullscreen.model == nil) then
		switch_shader(ctx.fullscreen, ctx.fullscreen.canvas,
			ctx.fullscreen.shader_group[ctx.fullscreen.shind]);
	end
end

--
-- split even clustered ticks, should possibly do this
-- following the preset hierarchy dfs or bfs rather than
-- insertion order.
--
local function compsurf_tick_windows(ctx, tc)
	for k,v in ipairs(ctx.windows) do
		if (v.tick) then
			v:tick(tc);
		end
	end
end

--
-- need to track this in order to not interfere with the
-- software defined mouse cursor and other compsurfaces
--
local function compsurf_maxorder(ctx)
	return 10 + (#ctx.windows * 10) + 1;
end

--
-- disable or enable (set to nil/false) specific groups or
-- devices from being processed
--
local function compsurf_input_lock(ctx, hand)
	ctx.inp_lock = hand;
end

local function compsurf_resize(ctx, w, h)
	local oldw = ctx.max_w;
	local oldh = ctx.max_h;
	ctx.max_w = w;
	ctx.max_h = h;

	if (ctx.background_id) then
		resize_image(ctx.background_id, w, h);
	end

	if (w < oldw or h < oldh) then
		for i, v in ipairs(ctx.windows) do
			compsurf_wnd_repos(v);
		end
	end
end

function compsurf_create(width, height, opts)
	local restbl = {
-- 'private' properties
		canvas = null_surface(width, height),
		windows = {},
		wnd_order = {},
		src_lut = {},
		max_w = width,
		max_h = height,
		min_w = 32,
		min_h = 32,
		def_ww = opts.def_ww ~= nil and opts.def_ww or math.floor(width * 0.3),
		def_wh = opts.def_wh ~= nil and opts.def_wh or math.floor(height * 0.3),
		name = opts.name ~= nil and opts.name or ("compsurf_" .. tostring(seq)),
		selorder = opts.selorder ~= nil and opts.selorder or 10,
		deselorder = opts.selorder ~= nil and opts.deselorder or 1,
		resize = compsurf_resize,

-- user directed window functions
		find = compsurf_find,
		add_window = compsurf_add_window,
		set_background = compsurf_background,
		toggle_fullscreen = compsurf_fullscreen,
		max_order = compsurf_maxorder,
		step_selected = compsurf_next_window,

-- explicitly hint what state the cursor should be in
		cursor_normal = function() end,
		cursor_resize = function() end,
		cursor_move = function() end,

-- timing events
		tick = compsurf_tick_windows,

-- input management
		dispatch = {},
		input = compsurf_input,
		input_sym = compsurf_input_sym,
		lock_input = compsurf_input_lock,

-- listen to major state changes
		handlers = {
			select = {},
			deselect = {},
			resize = {},
			destroy = {},
		},
	};

	image_tracetag(restbl.canvas, "compsurf_canvas");
	image_mask_set(restbl.canvas, MASK_UNPICKABLE);
	show_image(restbl.canvas);
	seq = seq + 1;
	return restbl;
end

--
-- precompile the default shader types and
-- hope that the driver is "competent" enough to cache
--
if (defw == nil) then
	defw = 2;
end

default_width = defw;
