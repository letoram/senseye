-- Copyright: 2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://durden.arcan-fe.com
-- Description: Main event-handlers for different external connections
-- and their respective subsegments. Handles registering new windows,
-- hinting default sizes, update timers etc.

-- Every connection can get a set of additional commands and configurations
-- based on what type it has. Supported ones are registered into this table.
-- init, bindings, settings, commands
local archetypes = {};

-- source-id-to-window-mapping
local swm = {};

local function load_archetypes()
-- load custom special subwindow handlers
	local res = glob_resource("atypes/*.lua", APPL_RESOURCE);
	if (res ~= nil) then
		for k,v in ipairs(res) do
			local tbl = system_load("atypes/" .. v, false);
			tbl = tbl and tbl() or nil;
			if (tbl and tbl.atype) then
				archetypes[tbl.atype] = tbl;
			end
		end
	end
end
load_archetypes();

local function cursor_handler(wnd, source, status)
-- for cursor layer, we reuse some events to indicate hotspot
-- and implement local warping..
end

local function default_handler(sourcewnd, athandler, status)
	for k,v in pairs(status) do
		print(k, v);
	end
end

local function default_reqh(wnd, source, ev)
	local at = archetypes[tostring(ev.reqid)];

-- we use the sensor here to assume navigation window + 1..n data windows
	if (ev.segkind == "sensor" and at) then
		local subid = accept_target();

-- we'll get back the appropriate container for subid
		local subwnd = senseye_launch(wnd, subid, at.subtitle);

-- default handler merely forwards to one that fit the archetype
		target_updatehandler(subid, function(source, status)
			default_handler(subwnd, at.subhandler, status) end);
	else
		warning(string.format("ignore unknown sensor: %s, %s",
			ev.segkind, tostring(ev.id)));
	end
end

function extevh_clipboard(wnd, source, status)
	if (status.kind == "terminated") then
		delete_image(source);
		if (wnd) then
			wnd.clipboard = nil;
		end
	elseif (status.kind == "message") then
-- got clipboard message, if it is multipart, buffer up to a threshold (?)
		CLIPBOARD:add(source, status.message, status.multipart);
	end
end

local defhtbl = {};

defhtbl["framestatus"] =
function(wnd, source, stat)
-- don't do any state / performance tracking right now
end

defhtbl["alert"] =
function(wnd, source, stat)
-- FIXME: need multipart concatenation of message
end

defhtbl["cursorhint"] =
function(wnd, source, stat)
	wnd.cursor = stat.cursor;
end

defhtbl["viewport"] =
function(wnd, source, stat)
-- need different behavior for popup here (invisible, parent, ...),
-- FIXME:	wnd:custom_border(ev->viewport.border);
end

defhtbl["resized"] =
function(wnd, source, stat)
	wnd.space:resize();
	wnd.source_audio = stat.source_audio;
	audio_gain(stat.source_audio, (gconfig_get("global_mute") and 0 or 1) *
		gconfig_get("global_gain") * wnd.gain);

	if (wnd.space.mode == "float") then
		wnd:resize_effective(stat.width, stat.height);
	end
	wnd.origo_ll = stat.origo_ll;
	image_set_txcos_default(wnd.canvas, stat.origo_ll == true);
end

defhtbl["message"] =
function(wnd, source, stat)
-- FIXME: no multipart concatenation
	wnd:set_message(stat.message, gconfig_get("msg_timeout"));
end

defhtbl["ident"] =
function(wnd, source, stat)
--	print("ident", source, stat);
-- FIXME: update window title unless custom titlebar?
end

defhtbl["terminated"] =
function(wnd, source, stat)
	EVENT_SYNCH[wnd.canvas] = nil;

-- if the target menu is active on the same window that is being
-- destroyed, cancel it so we don't risk a tiny race
	local ictx = active_display().input_ctx;
	if (active_display().selected == wnd and ictx and ictx.destroy and
		LAST_ACTIVE_MENU == grab_shared_function("target_actions")) then
		ictx:destroy();
	end
	wnd:destroy();
end

defhtbl["registered"] =
function(wnd, source, stat)
	local atbl = archetypes[stat.segkind];
	print("registered"); for k,v in pairs(stat) do print(k,v); end
	if (atbl == nil or wnd.atype ~= nil) then
		return;
	end

-- project / overlay archetype specific toggles and settings
	wnd.actions = atbl.actions;
	if (atbl.props) then
		for k,v in pairs(atbl.props) do
			wnd[k] = v;
		end
	end

-- can either be table [tgt, cfg] or [guid]
	if (not wnd.config_tgt) then
		wnd.config_tgt = stat.guid;
	end

	wnd.bindings = atbl.bindings;
	wnd.dispatch = merge_dispatch(shared_dispatch(), atbl.dispatch);
	wnd.labels = atbl.labels and atbl.labels or {};
	wnd.source_audio = stat.source_audio;
	wnd.atype = atbl.atype;

-- should always be true but ..
	if (active_display().selected == wnd) then
		if (atbl.props.kbd_period) then
			iostatem_repeat(atbl.props.kbd_period);
		end

		if (atbl.props.kbd_delay) then
			iostatem_repeat(nil, atbl.props.kbd_delay);
		end
	end

-- specify default shader by properties (e.g. no-alpha, fft) or explicit name
	if (atbl.default_shader) then
		shader_setup(wnd.canvas, unpack(atbl.default_shader));
	end

	if (atbl.init) then
		atbl:init(wnd, source);
	end

	if (stat.title and string.len(stat.title) > 0) then
		wnd:set_title(stat.title, true);
	end
end

defhtbl["state_size"] =
function(wnd, source, stat)
end

defhtbl["coreopt"] =
function(wnd, source, stat)
end

defhtbl["clock"] =
function(wnd, source, stat)
end

defhtbl["content_state"] =
function(wnd, source, stat)
end

defhtbl["segment_request"] =
function(wnd, source, stat)
-- eval based on requested subtype etc. if needed
	if (stat.segkind == "clipboard") then
		if (wnd.clipboard ~= nil) then
			delete_image(wnd.clipboard)
		end
		wnd.clipboard = accept_target();
		target_updatehandler(wnd.clipboard,
			function(source, status)
				extevh_clipboard(wnd, source, status)
			end
		);
	else
		default_reqh(wnd, source, stat);
	end
end

function extevh_register_window(source, wnd)
	if (not valid_vid(source, TYPE_FRAMESERVER)) then
		return;
	end
	swm[source] = wnd;

	target_updatehandler(source, extevh_default);
	wnd:add_handler("destroy",
	function()
		extevh_unregister_window(source);
		CLIPBOARD:lost(source);
	end);
end

function extevh_unregister_window(source)
	swm[source] = nil;
end

function extevh_get_window(source)
	return swm[source];
end

function extevh_default(source, stat)
	local wnd = swm[source];

	if (not wnd) then
		warning("event on missing window");
		return;
	end

	if (DEBUGLEVEL > 0 and active_display().debug_console) then
		active_display().debug_console:target_event(wnd, source, stat);
	end

-- window handler has priority
	if (wnd.dispatch[stat.kind]) then
		if (DEBUGLEVEL > 0 and active_display().debug_console) then
			active_display().debug_console:event_dispatch(wnd, stat.kind, stat);
		end

-- and only forward if the window handler accepts
		if (wnd.dispatch[stat.kind](wnd, source, stat)) then
			return;
		end
	end

	if (defhtbl[stat.kind]) then
		defhtbl[stat.kind](wnd, source, stat);
	else
	end
end
