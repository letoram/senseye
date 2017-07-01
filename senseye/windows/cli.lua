return function(wnd)
	wnd.bottom_bar.buttons.right[1].drag = function(ctx, vid, dx, dy)
		if (not wnd.drag_start_x) then
			wnd.drag_start_x, wnd.drag_start_y = mouse_xy();
			wnd.drag_w = wnd.width;
			wnd.drag_h = wnd.height;
			wnd.last_hint = CLOCK;
		end

-- rate limit drag events so we won't get murdered
		local mx, my = mouse_xy();
		if CLOCK - wnd.last_hint >= 1 then
			local neww = wnd.drag_w + (mx - wnd.drag_start_x);
			local newh = wnd.drag_h + (my - wnd.drag_start_y);
			if (neww > 0 and newh > 0) then
				target_displayhint(wnd.control_id, neww, newh);
			end
		end
	end
	wnd.bottom_bar.buttons.right[1].drop = function(ctx, vid)
		wnd.drag_start_x = nil;
		wnd.drag_start_y = nil;
	end

	local oldsel = wnd.select;
	local olddesel = wnd.deselect;
	wnd.disp_mask = TD_HINT_UNFOCUSED;

	wnd.select = function(wnd)
		wnd.disp_mask = bit.band(wnd.disp_mask,
			bit.bnot(wnd.disp_mask, TD_HINT_UNFOCUSED));
		target_displayhint(wnd.control_id, 0, 0, wnd.disp_mask);
		oldsel(wnd);
	end

	wnd.deselect = function(wnd)
		wnd.disp_mask = bit.bor(wnd.disp_mask, TD_HINT_UNFOCUSED);
		target_displayhint(wnd.control_id, 0, 0, wnd.disp_mask);
		olddesel(wnd);
	end
end
