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
			if (tbl.guid) then
				archetypes[tbl.guid] = tbl;
			elseif (tbl.atype and archetypes[tbl.atype] == nil) then
				archetypes[tbl.atype] = tbl;
			else
				print("broken archetype : ", v);
			end
		end
	end
end
load_archetypes();

local function default_reqh(wnd, source, ev)
	local at = wnd.astate and wnd.astate.subreq[tostring(ev.reqid)];
-- we use the sensor here to assume navigation window + 1..n data windows
	if (ev.segkind == "sensor" and at and at.reqh and not wnd.data) then
		local subid = accept_target();

-- we'll get back the appropriate container for subid
		local subwnd = senseye_launch(wnd, subid, "data", at);
		extevh_register_window(subid, subwnd);
	else
		warning(string.format("ignore unknown sensor: %s, %s",
			ev.segkind, tostring(ev.reqid)));
	end
end

function extevh_merge(wnd, evh)
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
	local atbl = archetypes[stat.guid]
		and archetypes[stat.guid] or archetypes[stat.segkind];

	if (not atbl) then
		warning(string.format("register from unknown %s:%s\n",
			stat.segkind, stat.guid));
		wnd:destroy();
		return;
	end

-- project / overlay archetype specific toggles and settings
	wnd.actions = atbl.actions;
	if (atbl.props) then
		for k,v in pairs(atbl.props) do
			wnd[k] = v;
		end
	end

	wnd.bindings = atbl.bindings;
	wnd.dispatch = merge_dispatch(shared_dispatch(), atbl.dispatch);
	wnd.labels = atbl.labels and atbl.labels or {};
	wnd.source_audio = stat.source_audio;
	wnd.atype = atbl.atype;
	wnd.astate = atbl;

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

-- it is init that is responsible for promoting to visible type
	if (atbl.init) then
		atbl:init(wnd, source);
	end
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
	elseif (stat.segkind == "sensor") then
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

	if (not wnd or (not wnd.space and stat.kind ~= "registered")) then
		warning("event on missing window");
		return;
	end

-- window handler has priority
	if (wnd.dispatch[stat.kind]) then
-- and only forward if the window handler accepts
		local ack = false;
		if (type(wnd.dispatch[stat.kind]) == "table") then
			for k,v in ipairs(wnd.dispatch[stat.kind]) do
				ack = v(wnd, source, stat) and true or ack;
			end
		else
			ack = wnd.dispatch[stat.kind](wnd, source, stat);
		end
		if (ack) then
			return true;
		end
	end

	if (defhtbl[stat.kind]) then
		defhtbl[stat.kind](wnd, source, stat);
	end
end
