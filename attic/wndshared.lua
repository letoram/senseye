-- Copyright 2014-2017, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description:
-- The functions in here deal with window management, window creation
-- and adding type- specific features when it comes to mouse actions on
-- the window surface. Most of the actual features are implemented as
-- part of menu/type for the trigger-function methods and as window/type
-- for more advanced UI interaction. The code here, along with
-- composition_surface should be reusable in other contexts, while the
-- other functions are more specialized (of course).
--
-- The basic use is rather trivial, at system load time, run wndshared_init(wm)
-- to add the basic keybindings etc.
-- Then, whenever a window is created via the wnd = wm:add_window() function
-- to get a window table. Push this table through wndshared_setup(wnd, type);
--
-- wndshared_setup : menus/typename.lua -> tbl (set as popup)
--                 : windows/typename.lua(wnd) -> manipulates wnd
--                 : handlers/typename.lua(wnd) -> function(wnd,source,status)
--
-- wndshared_init(wm)
--

local window_manager;
local consumers_pending;

-- setup bars, scrollhandlers, input handlers etc. based on type
-- control : windows spawned from here are treated as data
-- data (overlays, top and bottom, possible scroll-areas,
-- view (data views)
-- generic (used for mapping in normal clients like terminal)
function wndshared_setup(wnd, wndtype)
	if (not window_manager) then
		warning("wndshared_setup, no WM - use wmshared_setup");
		return;
	end

	local fontfn = function() return "\\f,0\\#ffffff"; end

-- window- management keybindings
	wnd.labels = {};
	wnd.dispatch[BINDINGS["POPUP"]] = function()
		spawn_popupmenu(window_manager, wnd.popup and wnd.popup or MENUS["system"]);
	end

-- default buttons and decorations
	wnd:set_border(1, {255, 255, 255}, {128, 128, 128});
	local tb = wnd:set_bar("t", 18);
	tb:add_button("right", "bar_button", "bar_label", "X", 0, fontfn, 16, 16,
		{
			click = function()
				wnd:destroy();
			end
		}
	);
	tb:add_button("center", "bar_button", "bar_label", "", 0, fontfn, 16, 16,
		{
			drag = function(ctx, vid, dx, dy)
				nudge_image(wnd.anchor, dx, dy);
			end,
			press = function(ctx, vid, dx, dy)
				wnd:select();
			end
		}
	);
	local bb = wnd:set_bar("b", 18);
	bb:add_button("right", "bar_button", "bar_label", "Z", 0, fontfn, 15, 15,
		{
			drag = function(ctx, vid, dx, dy)
				wnd:resize(wnd.width + dx, wnd.height + dy);
			end,
			press = function(ctx, vid, dx, dy)
				wnd:select();
			end,
			drop = function()
			end,
			rclick = function()
				spawn_popupmenu(window_manager, MENUS["RESIZE"]);
			end
		}
	);
	bb:add_button("center", "bar_button", "bar_label", "defuq", 0, fontfn, 16, 16);

-- first try and load the type specific menus
	local basename = wndtype .. ".lua";
	local got_menu = false;
	if (resource("menus/" .. basename)) then
		local pc = system_load("menus/" .. basename, false);
		if (pc) then
			local status, res = pcall(pc, wnd);
			if (status) then
				tb:add_button("left", "bar_button", "bar_label", "M", 0, fontfn, 16, 16,
					{click = function() spawn_popupmenu(window_manager, wnd.popup) end});
				wnd.popup = res;
				table.insert(wnd.popup, {
					name = "global",
					label = "Global",
					submenu = MENUS["system"]
				});
				table.insert(wnd.popup, {
					name = "input",
					label = "Inputs",
					eval = function()
						return #wnd.labels > 0;
					end,
					submenu = wnd.labels
				});
				got_menu = true;
			else
				warning("error loading menu: " .. wndtype .. " : " .. res);
			end
		end
	end

-- then load the type specific windows
	local got_window = false;
	if (resource("windows/" .. basename)) then
		local ui = system_load("windows/" .. basename , 0);
		if (ui) then
			local status, res = pcall(ui);
			if (status and type(res) == "function") then
				local status, res = pcall(res, wnd);
				if (not status) then
					warning("error executing window handler: " .. wndtype .. " : " ..res);
				else
					got_window = true;
				end
			else
				warning("error loading window: " .. wndtype .. " : " .. res);
			end
		end
	end

-- and external event handlers
	local got_handler = false;
	if (valid_vid(wnd.canvas, TYPE_FRAMESERVER)
		and resource("handlers/" .. basename)) then
		wnd.control_id = wnd.canvas;
		local handler = system_load("handlers/" .. basename, 0);
		if (handler) then
			local status, res = pcall(handler, wnd);
			if (status) then
				target_updatehandler(wnd.control_id,
				function(source, status)
					res(wnd, source, status);
				end);
				got_handler = true;
			end
		end
	end

	if (not window_manager.selected or window_manager.selected == wnd) then
		wnd:select();
	end

	return got_base, got_window, got_handler;
end

local function wnd_gather(wnd)
	local off_x = 0;
	local off_y = 0;

	for i=1, #window_manager.windows do
		if (window_manager.windows[i].parent and
			window_manager.windows[i].parent == wnd) then
			move_image(window_manager.windows[i].anchor, off_x, off_y);
			off_x = off_x + 10;
			off_y = off_y + 10;
		end
	end

	for i, v in ipairs(wnd.children) do
		if (#v.children > 0) then
			wnd_gather(v);
		end
	end
end

local function repos_window(wnd)
	local props = image_surface_resolve_properties(wnd.canvas);
	if (props.x + props.width < 10) then
		nudge_image(wnd.anchor, 0 - props.x, 0);
	end
	if (props.y + props.height < 10) then
		nudge_image(wnd.anchor, 0, 0 - props.y);
	end
	for i, v in ipairs(wnd.children) do
		v:reposition();
	end
end

--
-- shared handler for coreopts and for inputs
--
function wndshared_defhandler(wnd, source, status)
-- initial: iotbl.keysym handler
-- modifiers: goes with initial
-- labelhint:
-- description: user-readable
-- datatype
	if (status.kind == "input_label") then
		if (status.datatype ~= "digital") then
			return;
		end

-- map the input binding if it's not used for something else
		local sym = symtable[status.initial];
		if (sym and status.initial ~= 0 and wnd.dispatch[sym] == nil) then
			wnd.dispatch[sym] = function()
				target_input(wnd.control_id, {
					devid = 0, subid = 0,
					digital = true, active = true, label = status.labelhint});
			end
		end

-- add to the popup menu as well
		table.insert(wnd.labels,
			{
				name = "label_" .. tostring(#wnd.labels),
				label = status.labelhint,
				handler = function()
					target_input(wnd.control_id, {
						devid = 0, subid = 0,
						digital = true, active = true, label = status.labelhint});
				end
			});

	elseif (status.kind == "coreopt") then
	end
end

--
-- enable zoom, window positioning, stepping management etc.
--
function wndshared_init(wm)
	window_manager = wm;
	wm.dispatch[BINDINGS["POPUP"]] =
	function(wm)
		spawn_popupmenu(wm, (wm.selected and wm.selected.popup) and
			wm.selected.popup or MENUS["system"]);
	end

	wm.dispatch[BINDINGS["CANCEL"]] = function(wm)
		if (wm.meta) then
			return shutdown();

		elseif (wm.fullscreen) then
			wm:toggle_fullscreen();

		elseif (wm.selected) then
			wm.selected:deselect();
		end
	end
end
