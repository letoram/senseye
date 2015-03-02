-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: UI mapping for the file-specific sensor
-- Notes:
--  * The preview window suffers from undersampling issues
--    when working with large files, see fsense.c for details
--
local rtbl = system_load("senses/psense.lua")();

rtbl.dispatch_sub[BINDINGS["PSENSE_STEP_FRAME"]] = function(wnd)
	stepframe_target(wnd.ctrl_id, wnd.wm.meta and 2 or 1);
end

rtbl.dispatch_sub[BINDINGS["FSENSE_STEP_BACKWARD"]] = function(wnd)
	stepframe_target(wnd.ctrl_id, wnd.wm.meta and -2 or -1);
end

rtbl.dispatch_sub[BINDINGS["PSENSE_PLAY_TOGGLE"]] = function(wnd)
	local meta = wnd.wm.meta;
	if (wnd.tick) then
		wnd.tick = nil;
	else
		wnd.tick = function(wnd, n)
			stepframe_target(wnd.ctrl_id, meta and 2 or 1);
		end
	end
end

--
-- remove specific menu entries from the psense popup table
--
for k,v in ipairs(rtbl.popup_sub) do
	if (v.label == "Transfer Clock...") then
		v.submenu = nil;
	end
end

local old_init = rtbl.init;

rtbl.init = function(wnd)
	old_init(wnd);

-- unpickable overlay that estimated the position of the
-- currently presented datablock. This is based on an approximation
-- of how many bytes each line in the preview window covers
	local pview = color_surface(1, 1, 255, 255, 255);
	image_mask_set(pview, MASK_UNPICKABLE);
	blend_image(pview, 0.5);
	link_image(pview, wnd.parent.canvas);
	image_inherit_order(pview, 1);
	image_clip_on(pview, CLIP_SHALLOW);
	order_image(pview, 1);

-- add a click handler that attemts to seek to a specific row,
-- this is also bound to the number of bytes per row granularity
	wnd.parent.click = function(wnd, vid, x, y)
		local props = image_storage_properties(wnd.canvas);
		local sfy = wnd.height / props.height;
		y = (y - wnd.y);
		y = y > 0 and y / sfy or 0;
		target_seek(wnd.ctrl_id, y);
	end

	local last_pts = 1;
	local last_frame = 1;

	wnd.parent.update_preview = function(wnd)
		local props = image_storage_properties(wnd.canvas);
		local sfx = wnd.width / props.width;
		local sfy = wnd.height / props.height;
		resize_image(pview, wnd.width, (last_pts <= 0 and 1 or last_pts) * sfy);
		move_image(pview, 0, last_frame * sfy);
	end

-- subscribe to updates on the last pushed block and use that
-- to draw the preview box
	table.insert(wnd.parent.source_listener, wnd.parent);
	wnd.parent.source_handler =
		function(wnd, source, status)
			if (status.kind == "framestatus") then
				last_pts = status.pts;
				last_frame = status.frame;
				wnd:update_preview();
			end
		end

-- need to override the default resize behavior to account
-- for the preview box being shaped differently
	local wnd_old_rz = wnd.parent.resize;
	wnd.parent.resize = function(wnd, neww, newh)
		wnd_old_rz(wnd, neww, newh);
		wnd:update_preview();
	end
end

rtbl.name = "fsense";
return rtbl;
