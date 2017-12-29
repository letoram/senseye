return function(wnd, source, status)
	if (status.kind == "preroll") then
-- override all input management
		wnd.input = function(ctx, iotbl)
			target_input(source, iotbl);
		end
		wnd.input_sym = function(ctx, sym, active, iotbl)
			target_input(source, iotbl);
		end
	elseif (status.kind == "message") then
-- tui tells us of the width/height but we don't really care

-- resize management is accumulated- and client defined
	elseif (status.kind == "resized") then
		if (not wnd.initialized) then
			wnd.initialized = true;
			wnd:show();
		end
		wnd:resize(status.width, status.height);
	elseif (status.kind == "terminated") then
		delete_image(source);
		termwnd[source] = nil;
	else
		wndshared_defhandler(wnd, source, status);
	end
end
