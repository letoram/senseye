return function(wnd, source, status)
	if (status.kind == "terminated") then
		wnd:destroy();
		return;
	end
end
