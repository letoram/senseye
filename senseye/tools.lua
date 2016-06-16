local tools = {};

local list = glob_resource("tools/*.lua", APPL_RESOURCE);
for k,v in ipairs(list) do
	local res = system_load("tools/" .. v, 0);
	if (not res) then
		warning(string.format("couldn't parse tool: %s", v));
	else
		local okstate, msg = pcall(res);
		if (not okstate) then
			warning(string.format("runtime error loading tool: %s", v));
		else
			table.insert(tools, msg);
		end
	end
end

-- generate a menu suitable for activating tools against a data window
function list_tools(dwnd)
	local res = {};

	for k,v in ipairs(tools) do
		table.insert(res,	{
			name = v.name,
			label = v.label,
			kind = "action",
			handler =

-- spawn window and forward to tool
function(ctx)
	local nsrf = null_surface(1, 1);
	image_sharestorage(dwnd.canvas, nsrf);
	local wnd = durden_launch(nsrf);
	wnd:set_title(v.label);
	v.spawn(wnd, dwnd);
	wnd.scalemode = "stretch";
-- auto-cleanup so we don't get more after death
	wnd:add_handler("destroy", function()
		for i,v in ipairs(ctx.tools) do
			if (v == wnd) then
				table.remove(ctx.tools, i);
				return;
			end
		end
	end);

	table.insert(ctx.tools, wnd);
end
		});
	end
	return res;
end
