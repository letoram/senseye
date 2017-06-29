-- Copyright 2014-2017, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description:
--  Main entry-points for the 'senseye' arcan application.  It passively
--  listens on an external connection key (senseye) for data 'senses' that
--  connect through the senseye ARCAN_CONNPATH and provides UI mappings and
--  type- specific graphical representations for data that these senses
--  deliver.
--
-- The basic flows are these:
--   [SENSOR]
--   1. sensor connects through connection_path + segid (SENSOR)
--   2. main window is spawned (handler_control_window:handler.lua) ->
--      wndshared_setup() which adds window decorations, popup table and
--      bindings based on source/type.
--   3. sensor sends a subsegment request through main window event handler,
--      and it is mapped similarly to 2.
--   4. possible segid+guid specific actions are fetched from sensors/* and
--      merged into the window popup.
--
--   [TRANSLATOR]
--   1. translator connects through connection_path +segid (ENCODER)+ident
--   2. if it doesn't already exist, it is added to the translator path
--   3. [for all data windows] : add translator activation button to the
--      sides.
--
--      [USER CLICKS A TRANSLATOR BUTTON]
--      [    enabled] destroy translator and overlay
--      [not enabled] push feedcopy subsegment to encoder, this means that
--                    whenever datawindow source delivers a frame, a copy
--                    will be sent to the translator.
--
--      1. translator requests a subsegment, this is mapped as a new window
--         with only basic controls and an overlay toggle.
--         [USER ACTIVATES OVERLAY TOGGLE]
--         [   enabled] hide it, send visibility hint
--         [not enabled,     existing] send visibility hint
--         [not enabled, not existing] push subsegment to window
--
--   [INPUT]
--   1. event is delivered into senseye_input and routed through mouse
--      callback listeners for mouse events, otherwise through the priority:
--
--      [has symbol: ] a. (if meta held, wm symbol) -> wnd-symbol ->
--                     wm-symbol.
--      [ no symbol: ] drain or direct to selected window.
--
--   Certain inputs are complicated, motion, zoom and selection activity
--   on the data window as the action may need to be routed to the sensor,
--   to translators and to tools.
--
--   Generic Keybindings are defined as part of the menu system, where
--   !/menu/command triggers menu->command on the currently selected window
--   #/menu/command triggers menu->command from the global menu
--
--   When a popup menu is active, it reroutes and absorbs all input by
--   creating a hidden large "catch all" surface.
--
--   [TOOLS]
--   These are more complicated as there's no strict model about what they
--   provide. The more common action is to hook into the data window and a,
--   get a calctarget on the data itself, register as a link_zoom handler
--   and as a stepping handler.
--
connection_path = "senseye";
wndcnt = 0;
pending_lim = 4;

--
-- global, used in all menus and messages
--
menu_text_fontstr = "\\f,0\\#cccccc ";
MENUS = {};

--
-- customized dispatch handlers based on registered sensor type populated by
-- scanning senses/[name].lua
--
type_handlers = {};
type_helpers = {};

-- primarily used by picture tune and other processes that rely heavily on
-- multiple readbacks in short succession
postframe_handlers = {};

--
-- external clients that register with the segkind 'encoder' + ident will
-- be added to the list of possible translators that can be added to a
-- data window
--
translators = {};

function senseye()
-- basic functions
	system_load("gconf.lua")();
	system_load("apiext.lua")();
	system_defaultfont("default.ttf", 16, 2);

-- input control
	system_load("mouse.lua")();
	mouse_setup(load_image("images/cursor.png"), 65535, 1, true);
	symtable = system_load("symtable.lua")();
	kbd_repeat(gconfig_get("repeat_period"), gconfig_get("repeat_delay"));
	system_load("keybindings.lua")();

-- UI management
	system_load("composition_surface.lua")();
	system_load("popup_menu.lua")();
	system_load("wndshared.lua")();

-- client event dispatch
	system_load("handlers.lua")();

-- specific support / drawing functions
	system_load("hilbert.lua")();
	system_load("shaders.lua")();
	system_load("translators.lua")();
	MENUS["system"] = system_load("menus/system.lua")();

	if (API_VERSION_MAJOR <= 0 and API_VERSION_MINOR < 11) then
		return shutdown("Arcan Lua API version is too old, " ..
			"please upgrade your arcan installation (> 0.5.2)");
	end

	DEFAULT_TIMEOUT = gconfig_get("msg_timeout");

-- create a window manager for the composition surface
	wm = compsurf_create(VRESW, VRESH, {});
	table.insert(wm.handlers.select, focus_window);
	table.insert(wm.handlers.deselect, defocus_window);
	table.insert(wm.handlers.destroy, check_listeners);

-- background image doubles as a mouse-handler for deselecting windows
-- and for the system/global popup menu
	bgimg = load_image("images/background.png");
	image_tracetag(bgimg, "background");
	wm:set_background(bgimg);
	mouse_addlistener({
		name = "bgtbl",
		own = function(ctx, vid) return vid == bgimg; end,
		click = function(vid)
			if (wm.selected) then
				wm.selected:deselect();
			end
		end,
		rclick = function(vid)
			local old = wm.selected;
			if (old) then
				old:deselect();
			end
				spawn_popupmenu(MENUS["system"]);
			if (old and old.select) then
				old:select();
			end
		end,
	}, {"click", "rclick"});

-- disable all filtering by default since pixels represent actual data
-- that we don't want smeared into oblivion
	switch_default_texfilter(FILTER_NONE);

-- map bindings to default UI actions (wndshared.lua + keybindings.lua)
	setup_dispatch(wm.dispatch);

-- setup our 'senseye' listening connection point.
	local lp = target_alloc(connection_path, new_connection);
	if (not valid_vid(lp)) then
		return
			shutdown("couldn't allocate connection_path (" .. connection_path .. ")");
	end
	image_tracetag(lp, connection_path .. "conn_" .. tonumber(wndcnt));
end

function add_window(source, wtype, parent)
	local wnd = wm:add_window(source, {});
	wndshared_setup(wnd, wtype);

-- custom handlers and bindings
	window_shared(wnd, true);
	wnd.fullscreen_disabled = true;
	wnd.ctrl_id = source;
	wnd.zoom_preview = true;
	wnd.highlight = shader_update_range;
	wnd.source_listener = {};
	wnd.shader_group = shaders_2dview;
	target_flags(source, TARGET_VSTORE_SYNCH);
	wnd.shind = 1;
	wnd.pending = 0;
	wnd.popup = controlwnd_menu;
	if (parent) then
		wnd:set_parent(parent, ANCHOR_UR);
	end
	return wnd;
end

local function add_subwindow(parent, id)
	local wnd = add_window(id);
	wnd:set_parent(parent, ANCHOR_UR);
	return wnd;
end

--
-- safeguard against pileups, the stepframe_target can have a steep cost for
-- each sensor and when events accumulate it might block more important ones
-- (switching clocking modes etc.) so make these requests synchronous with
-- delivery.
--
stepframe_target_builtin = stepframe_target;
function stepframe_target(src, id)
	local wnd = wm:find(src);
	if (wnd == nil) then
		return stepframe_target_builtin(src, id);
	end

-- this is deferred from all over the place to not have multiple
-- histogram matching + picture matching colliding
	if (wnd.flip_suspend) then
		wnd.flip_suspend = false;
		if (wnd.suspended) then
			wnd.suspended = false;
			resume_target(src);
		end
	end

	if (wnd.suspended) then
		return nil;
	end

	if (wnd.pending == nil) then
		stepframe_target_builtin(src, id);
		return;
	elseif (wnd.pending < pending_lim) then
		stepframe_target_builtin(src, id);
		wnd.pending = wnd.pending + 1;
	end
end

-- just hooked for now, using this as a means for having UI notifications
-- of future errors.
function error_message(note)
	warning(note);
end

--
-- there might be incentive to only permit windows that registers with the
-- correct subid to remain alive, and have a timeout (i.e. mouse_tick on
-- pending connections) but >currently< we expect the sensor to cooperate.
--
function new_connection(source, status)
-- need to distinguish between a translator (data interpreter)
-- and a sensor (data provider) as they have different usr-int schemes
	if (status.kind == "connected") then
		local vid = target_alloc(status.key, new_connection);

		if (not valid_vid(vid)) then
			warning("connection limit reached, non-auth connections disabled.");
			return;
		end

		wndcnt = wndcnt + 1;
		image_tracetag(vid, connection_path .. "conn_" .. tonumber(wndcnt));
		return;

	elseif (status.kind ~= "registered") then
		delete_image(source);
		warning("connection attempted from uncooperative client." .. status.kind);
	end

	print("registered:", status.segkind, handler_control_window);
-- sensor : used as data control source
	if (status.segkind == "sensor") then
		target_updatehandler(source, handler_control_window);
		local wnd = add_window(source, "sensor");
		wnd:select();

-- encoder : used for translators
	elseif (status.segkind == "encoder") then
		target_updatehandler(source, handler_translate_control);

-- integrators register as both sensors and encoders and we're not interested
-- in any other types
	else
		warning("attempted connection from unsupported type, " .. status.segkind);
		delete_image(source);
	end
end

function senseye_clock_pulse()
	mouse_tick(1);
	wm:tick(1);
end

-- we use the uncommon postframe event hook as a means for synchronizing
-- manually managed readback/calctargets etc.
function senseye_postframe_pulse()
	for k,v in ipairs(postframe_handlers) do
		v();
	end
end

function senseye_shutdown()
	gconfig_shutdown();
end

function senseye_input(iotbl)
-- will do picking and route to vid- registered mouse-handle
	if (iotbl.source == "mouse") then
		mouse_iotbl_input(iotbl);

-- lookup sym and if found, forward as such, otherwise let the wm take raw inp.
	elseif (iotbl.translated and symtable[iotbl.keysym]) then
		wm:input_sym(symtable[iotbl.keysym], iotbl.active, iotbl);
	else
		wm:input(iotbl);
	end
end

-- for when we run as LWA, acknowledge a parent initiated resize, force a
-- relayout of all windows and propagate any updates to density and size.
function VRES_AUTORES(w, h)
	resize_video_canvas(w, h);
	wm:resize(w, h, VPPCM, HPPCM);
end
