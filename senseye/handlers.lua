--
-- event dispatch handlers for all external connections
--

--
-- Default handle for the control- segment (main window) to the sensor
-- other data components will be provided as subsegments.
--
function handler_control_window(source, status)
	local wnd = wm:find(source);
	if (not wnd) then
		warning(string.format("couldn't find handler for (%d), killing", source));
		delete_image(source);
		return;
	end

	if (status.kind == "resized") then
		wnd:resize(status.width, status.height);
--
-- currently permitting infinite subsegments (allocated from main one) in more
-- sensitive settings, this may be a bad idea (malicious process just spamming
-- requests) if that is a concern, rate-limit and kill.
--
	elseif (status.kind == "segment_request") then
		local id = accept_target();

-- we want frame-delivery reports etc. to present state about the data window
		target_verbose(id);

-- create a child window, tie it to the control window and build a chain-cb
		local child = add_window(id, "data", wnd);
		child:resize(status.width, status.height);
		child:select();
		target_updatehandler(id,
			function(source, status)
				handler_data_window(child, source, status);
			end
		);

	elseif (status.kind == "terminated") then
		wnd:destroy();
--
-- control windows can provide their base identity ONCE, which allows sensor-
-- unique controls to apply.
--
	elseif (status.kind == "ident") then
--		convert_type(wnd, type_handlers[status.message], {});
	else
		for k,v in ipairs(wnd.source_listener) do
			v:source_handler(source, status);
		end
	end
end

function handler_data_window(wnd, source, status)
	if (status.kind == "terminated") then
		wnd:destroy();
		return;
	end
end

-- windowless, we only track the presence and type, so that we can update
-- the controls for all data windows.
function handler_translate_control(source, status)
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

			for i,v in ipairs(wm.windows) do
				if (v.translator_name == status.message and not valid_vid(
					v.ctrl_id, TYPE_FRAMESERVER)) then
					activate_translator(v.parent, {source, lbl}, 0, v);
					v.normal_color = {128, 128, 128};
					v.focus_color = {192, 192, 192};
					v:set_border(v.borderw, unpack(wm.selected == v
						and v.focus_color or v.normal_color));
				end
			end
		end
	elseif (status.kind == "terminated") then
		local xlt_res = nil;
		for k,v in ipairs(translator_popup) do
			if (v.value[1] == source) then
				xlt_res = v;
				table.remove(translator_popup, k);
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

function handler_translate_overlay_window(source, status)
end
