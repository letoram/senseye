return function(wnd, source, status)
	if (status.kind == "resized") then
		wnd:resize(status.width, status.height);
--
-- currently permitting infinite subsegments (allocated from main one) in more
-- sensitive settings, this may be a bad idea (malicious process just spamming
-- requests) if that is a concern, rate-limit and kill.
--
	elseif (status.kind == "segment_request") then
		local id = accept_target();
		if (not valid_vid(id, TYPE_FRAMESERVER)) then
			warning("control window handler, couldn't spawn subsegment");
			return;
		end

-- we want frame-delivery reports etc. to present state about the data window
		target_verbose(id);

-- create a child window, tie it to the control window and build a chain-cb
		local child = wnd.wm:add_window(id, {});
		if (not child) then
			delete_image(id);
			warning("couldn't bind data window to wm");
			return;
		end

		image_tracetag(id, image_tracetag(source) .. "_data");
		wndshared_setup(child, "data");
		child:set_parent(wnd, ANCHOR_UR);
		child:resize(status.width, status.height);
		child:select();
	elseif (status.kind == "terminated") then
		wnd:destroy();

	elseif (status.kind == "framestatus") then
		if (wnd.pending > 0) then
			wnd.pending = wnd.pending - 1;
		end

		if (wnd.pending == 0 and wnd.autostep) then
			target_stepframe(wnd.control_id, wnd.autostep);
		end

	elseif (status.kind == "ident") then
	-- wnd.top_bar:update("fill", 1, status
		print(status.message);
	else
		wndshared_defhandler(wnd, source, status);
	end
end
