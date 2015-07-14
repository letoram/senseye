-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description:
--  Main entry-points for the 'senseye' arcan application.  It passively
--  listens on an external connection key (senseye) for data 'senses' that
--  connect through the senseye ARCAN_CONNPATH and provides UI mappings and
--  type- specific graphical representations for data that these senses
--  deliver.
--
connection_path = "senseye";
wndcnt = 0;
pending_lim = 4;

--
-- enable 'demo mode' with recording (if correct frameserver is built in) and
-- key overlay
--
demo_mode = false;

--
-- global, used in all menus and messages
--
menu_fontsz = 16;
menu_text_fontstr = string.format("\\fdefault.ttf,%d\\#cccccc ", menu_fontsz);

--
-- customized dispatch handlers based on registered sensor type populated by
-- scanning senses/[name].lua
--
type_handlers = {};
type_helpers = {};

-- primarily used by picture tune and other processes that rely heavily on
-- multiple readbacks in short succession
postframe_handlers = {};

translators = {};
data_meta_popup = {
	{
		label = "Activate Translator...",
		submenu = function()
			return #translator_popup > 0 and translator_popup or {
				{
				label = "No Translators Connected",
				handler = function() end
				}
			};
		end
	}
};

function senseye()
	system_load("mouse.lua")();
	symtable = system_load("symtable.lua")();
	system_load("keybindings.lua")();
	system_load("stringext.lua")();
	system_load("composition_surface.lua")();
	system_load("popup_menu.lua")();
	system_load("gconf.lua")();
	system_load("wndshared.lua")();
	system_load("hilbert.lua")();
	system_load("shaders.lua")();
	system_load("translators.lua")();

	if (API_VERSION_MAJOR <= 0 and API_VERSION_MINOR < 9) then
		return shutdown("Arcan Lua API version is too old, " ..
			"please upgrade your arcan installation");
	end

	DEFAULT_TIMEOUT = gconfig_get("msg_timeout");

--
-- load sense- specific user interfaces (name matches the identification string
-- that the connected frameserver sensor segment provides, it does not define
-- any additional trust barriers, only user interface semantics.
--
	local res = glob_resource("senses/*.lua", APPL_RESOURCE);
	if (res) then
		for i,v in ipairs(res) do
			base, ext = string.extension(v);
			if (ext ~= nil and ext == "lua") then
				local tbl = system_load("senses/" .. v, 0);
				if (tbl ~= nil) then
					tbl = tbl();
				else
					warning("could not load sensor handler ( " ..
						v .. " ), parsing errors likely.");
				end

				if (tbl ~= nil) then
					type_handlers[base] = tbl;
					if (tbl.help) then
						table.insert(type_helpers, tbl.help);
					end

				end
			end
		end
	end

-- uncomment for non-native cursor (would be visible in video recording)
-- mouse_setup(load_image("cursor.png"), 1000, 1, true);
	mouse_setup_native(load_image("cursor.png"), 1, 1);
	mouse_add_cursor("move", load_image("cursor_move.png"), 13, 13);
	mouse_add_cursor("scale", load_image("cursor_scale.png"), 13, 13);

--
-- create a window manager for the composition surface
--
	wm = compsurf_create(VRESW, VRESH, {});
	table.insert(wm.handlers.select, focus_window);
	table.insert(wm.handlers.deselect, defocus_window);
	table.insert(wm.handlers.destroy, check_listeners);

	local bgimg = load_image("background.png");
	image_tracetag(bgimg, "background");
	wm:set_background(bgimg);

	switch_default_texfilter(FILTER_NONE); -- barely anything should be filtered

--
-- map bindings to default UI actions (wndshared.lua + keybindings.lua)
--
	setup_dispatch(wm.dispatch);

	local lp = target_alloc(connection_path, new_connection);
	if (not valid_vid(lp)) then
		return
			shutdown("couldn't allocate connection_path (" .. connection_path .. ")");
	end
	image_tracetag(lp, connection_path .. "conn_" .. tonumber(wndcnt));

	local statusid = null_surface(2,2);
	statusbar = wm:add_window(statusid, {
		ontop = true, fixed = true, block_select = true,
		width = VRESW, height = menu_fontsz + 4,
		name = "status"
	});
	statusbar.select = function() end
	statusbar:move(0, VRESH - menu_fontsz - 4);

	if (gconfig_get("show_help") == 1) then
		show_help();
	end
end

function add_window(source)
	local wnd = wm:add_window(source, {});
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
	return wnd;
end

local function add_subwindow(parent, id)
	local wnd = add_window(id);
	wnd:set_parent(parent, ANCHOR_UR);
	nudge_image(wnd.anchor, 2, 0);
	image_shader(wnd.canvas, shaders_2dview[1].shid);
	return wnd;
end

function show_help()
	if (valid_vid(help_anchor)) then
		blend_image(help_anchor, 0.0, 10);
		expire_image(help_anchor, 10);
		help_anchor = nil;
		return;
	end

	local msg = string.format([[
\fdefault.ttf,%d\#ffffffQuick Help\#ffff00\n\r
Toggle Help\n\r
Meta 1 (move, resize)\n\r
Meta 2 (zoom, synch)\n\r
Screenshot\n\r
\#ffffffAll Windows\n\r\#ffff00\n\r
Cycle Focus\n\r
Zoom-Area\n\r
Show Popup\n\r
Delete Window\n\r
Grow/Shrink x2\n\r
\#ffffffData Window\#ffff00\n\r
Toggle Play/Pause\n\r
Cycle Mapping\n\r
Mode Toggle\n\r
Step Forward\n\r
Step Backwards\n\r]], 16);

	local lookup = function(sym)
		if BINDINGS[sym] ~= nil then
			if BINDINGS[sym] == " " then
				return "SPACE";
			end
			return BINDINGS[sym];
		else
			return "";
		end
	end

	local data = string.format([[
 \#00ff00\n\r
%s\n\r
%s\n\r
%s\n\r
%s\n\r
 \n\r\n\r
(meta1) %s\n\r
lclick+drag\n\r
%s\n\r
%s\n\r
(meta) %s\n\r
 \n\r\n\r
%s\n\r
%s\n\r
%s\n\r
%s\n\r
%s\n\r
]],
	lookup("HELP"), lookup("META"), lookup("META_DETAIL"),
	lookup("SCREENSHOT"), lookup("POPUP"), lookup("POPUP"),
	lookup("DESTROY"), lookup("RESIZE_X2"),
	lookup("PLAYPAUSE"), lookup("CYCLE_MAPPING"),
	lookup("MODE_TOGGLE"), lookup("PSENSE_STEP_FRAME"),
	lookup("FSENSE_STEP_BACKWARD")
);

	for k,v in ipairs(type_helpers) do
		msg = msg .. [[\n\r]] .. v;
	end

	local help_text = render_text(msg);
	local help_bind = render_text(data);
	local props = image_surface_properties(help_text);
	props.width = props.width + image_surface_properties(help_bind).width + 20;
	link_image(help_bind, help_text, ANCHOR_UR);
	nudge_image(help_bind, 20, 0);
	help_anchor = color_surface(props.width+20, props.height+20, 0, 0, 0);
	link_image(help_text, help_anchor);
	show_image({help_text, help_anchor, help_bind});
	move_image(help_anchor, VRESW,
		math.floor( 0.5 * (VRESH - props.height) ));
	nudge_image(help_anchor, -1 * (props.width + 20), 0, 50, INTERP_EXPOUT);
	move_image(help_text, 10, 10);
	order_image(help_anchor, 1000);
	image_inherit_order(help_text, true);
	image_inherit_order(help_bind, true);
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

--
-- just hooked for now, using this as a means for having UI notifications of
-- future errors.
--
function error_message(note)
	warning(note);
end

local function def_sourceh(wnd, source, status)
	if (wnd.handler_tbl[status.kind]) then
		wnd.handler_tbl[status.kind](wnd, source, status);
	end
end

--
-- switch a window to expose one set of UI functions in favor of another. Only
-- really performed when a segment sends an identity update.
--
function convert_type(wnd, th, basemenu)
	if (th == nil) then
		return;
	end

	local tbl = th.dispatch_sub;
	for k,v in pairs(tbl) do
		wnd.dispatch[k] = v;
	end

	wnd.popup = merge_menu(basemenu, th.popup_sub);
	wnd.basename = th.name;
	wnd.name = wnd.name .. "_" .. th.name;
	wnd.map = th.map;

-- this function can be intercepted in order to add additional
-- handlers, e.g. taking note of interesting positions
	wnd.alert = function(wnd, source_str, source_id, pos)
		wnd:set_message(string.format(
			"%s alert @ %x", source_str, pos), DEFAULT_TIMEOUT);
		wnd:seek(pos);
		wnd.tick = nil;
		wnd.pending = 0;
		wnd.suspended = true; -- will require user-input to wake
	end

	if (th.source_listener) then
		wnd.source_handler = def_sourceh;
		wnd.handler_tbl = th.source_listener;
		table.insert(wnd.source_listener, wnd);
	end

	th.init(wnd);

	if (wm.selected == wnd) then
		focus_window(wnd);
	else
		defocus_window(wnd);
	end
end

--
-- this is the minimized default subwindow handle, it works as such until the
-- point where we receive an ident message with the suggested UI type.
--
function subid_handle(source, status)
	local wnd = wm:find(source);

	if (wnd.pending > 0 and status.kind == "framestatus") then
		wnd.pending = wnd.pending - 1;
	end

	if (status.kind == "resized") then
		wnd:resize(status.width, status.height);

	elseif (status.kind == "ident") then
		convert_type(wnd, type_handlers[status.message], subwnd_menu);
	else
	end

	for i,v in ipairs(wnd.source_listener) do
		v:source_handler(source, status);
	end
end

--
-- Default handle for the control- segment (main window) to the sensor, other
-- data components will be provided as subsegments.
--
function default_wh(source, status)
	local wnd = wm:find(source);

	if (status.kind == "resized" and wnd ~= nil) then
		wnd:resize(status.width, status.height);
--
-- currently permitting infinite subsegments (allocated from main one) in more
-- sensitive settings, this may be a bad idea (malicious process just spamming
-- requests) if that is a concern, rate-limit and kill.
--
	elseif (status.kind == "segment_request") then
		local id = accept_target();
		target_verbose(id);
		local subwnd = add_subwindow(wnd, id);
		subwnd.ctrl_id = id;
		local prop = image_surface_properties(id);
		subwnd:resize(status.width, status.height);
		subwnd:select();
		target_updatehandler(id, subid_handle);

	elseif (status.kind == "ident") then
		convert_type(wnd, type_handlers[status.message], {});
	end

	for k,v in ipairs(wnd.source_listener) do
		v:source_handler(source, status);
	end
end

--
-- note: translators are initially considered to be on the same privilege level
-- as the main senseye process, it is only individual sessions that are deemed
-- tainted.  Thus we assume that status.message is reasonable.
--
function translate_wh(source, status)
	if (status.kind == "ident") then
		if (translators[status.message] ~= nil) then
			warning("translator for that type already exists, terminating.");
			delete_image(source);
			return;
		else
			translators[status.message] = source;
			translators[source] = status.message;
			local lbl = string.gsub(status.message, "\\", "\\\\");

			table.insert(translator_popup, {
				value = {source, lbl},
				label = lbl
			});
			statusbar:set_message("Translator connected: " .. lbl, DEFAULT_TIMEOUT);

			for i,v in ipairs(wm.windows) do
				if (v.translator_name == status.message and not valid_vid(
					v.ctrl_id, TYPE_FRAMESERVER)) then
					activate_translator(v.parent, {source, lbl}, 0, v);
					v.normal_color = {128, 128, 128};
					v.focus_color = {192, 192, 192};
				end
			end
		end
	elseif (status.kind == "terminated") then
		local xlt_res = nil;
		for k,v in ipairs(translator_popup) do
			if (v.value[1] == source) then
				xlt_res = v;
				table.remove(translator_popup, k);
				statusbar:set_message("Lost translator: " ..
					tostring(v.label), DEFAULT_TIMEOUT);
				break;
			end
		end

		for k,v in ipairs(wm.windows) do
			if (xlt_res and v.translator_name == xlt_res.label) then
				v.normal_color = {128, 0, 0};
				v.focus_color = {255, 0, 0};
				v:set_border(v.borderw, unpack(wm.selected == v
					and v.focus_color or v.normal_color));
			end
		end
		table.remove_vmatch(translators, source);
	end
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
	end

	if (status.kind ~= "registered") then
		delete_image(source);
		warning("connection attempted from uncooperative client." .. status.kind);

	else
		if (status.segkind == "sensor") then
			target_updatehandler(source, default_wh);
			local wnd = add_window(source);
			wnd:select();
			default_wh(source, status);

		elseif (status.segkind == "encoder") then
			target_updatehandler(source, translate_wh);

		else
			warning("attempted connection from unsupported type, " .. status.segkind);
			delete_image(source);
		end
	end
end

function senseye_clock_pulse()
	mouse_tick(1);
	wm:tick(1);
end

function senseye_postframe_pulse()
	for k,v in ipairs(postframe_handlers) do
		v();
	end
end

function senseye_shutdown()
	gconfig_shutdown();
end

local function update_symstatus(sym, active, meta, meta_detail)
	local lbl = sym;
	local tbl = {};
	local sym_meta = false;

	for k,v in pairs(BINDINGS) do
		if (v == sym and (k == "META" or k == "META_DETAIL")) then
			lbl = k;
			sym_meta = true;
			break;
		end

		if (v == sym) then
			table.insert(tbl, k);
		end
	end

	if #tbl > 0 then
		lbl = lbl .. " (" .. table.concat(tbl, ", ") .. " )";
	end

	if (sym_meta and not active) then
		statusbar:set_message();
	else
		statusbar:set_message(string.format("%s%s%s%s",
			(meta and not sym_meta) and "META + " or "",
			(meta_detail and not sym_meta) and "META_DETAIL + " or "",
			lbl,
			active and " Pressed" or " Released"), active and -1 or 100);
	end
end

--
-- the mid-c flip-flop buffer is a common workaround for the issue of
-- mouse devices reporting data on multiple axis (design flaw that
-- won't really be fixed), so we wait for two events and forward
-- when we have a tuple.
--
mid_c = 0;
mid_v = {0, 0};
function senseye_input(iotbl)
	if (iotbl.source == "mouse") then
		if (iotbl.kind == "digital") then
			if (demo_mode) then
				update_symstatus(iotbl.subid == 1 and "Left Mouse" or "Right Mouse",
					iotbl.active, wm.meta, wm.meta_detail);
			end

			mouse_button_input(iotbl.subid, iotbl.active);
		else
			mid_v[iotbl.subid+1] = iotbl.samples[1];
			mid_c = mid_c + 1;

			if (mid_c == 2) then
				mouse_absinput(mid_v[1], mid_v[2]);
				mid_c = 0;
			end
		end

	elseif (iotbl.translated) then
		local sym = symtable[ iotbl.keysym ];

-- propagate meta-key state (for resize / drag / etc.)
		if (sym == BINDINGS["META"]) then
			wm.meta = iotbl.active and true or nil;
			if (not iotbl.active) then
				mouse_switch_cursor();
			end

		elseif (sym == BINDINGS["META_DETAIL"]) then
			wm.meta_detail = iotbl.active and true or nil;
			mouse_switch_cursor();

			if (iotbl.active == false and wm.selected) then
				wm.selected:set_message(nil);
				if (valid_vid(wm.meta_zoom)) then
					delete_image(wm.meta_zoom);
					wm.meta_zoom = BADID;
				end
			end
		end

-- wm input takes care of other management as well, i.e.
-- data routing, locking etc. so just forward
		if (demo_mode) then
			update_symstatus(sym, iotbl.active, wm.meta, wm.meta_detail);
		end
		wm:input_sym(sym, iotbl.active);

	else
		wm:input(iotbl);
	end
end
