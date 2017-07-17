return function(wnd, source, status)
	if (status.kind == "terminated") then
		wnd:destroy();
		return;
	elseif (status.kind == "framestatus") then
		for k,v in pairs(status) do print(k, v); end
	elseif (status.kind == "frame") then
		for k,v in pairs(status) do print(k, v); end
	else
		wndshared_defhandler(wnd, source, status);
	end
end
