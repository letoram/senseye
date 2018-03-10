-- figure out where the rest of the scripts are
local prefix = "";
if (resource("tools/senseye.lua")) then
	prefix = "tools/"
end

-- figure out if we have the normal durden debug-message setup or
-- just fallback to standard warnings
local error_function = warning
if (type(active_display) == "function") then
--		error_function = function(...) active_display():message(...); end
end

-- NOTE: probably better to just glob the folder..
local tools = {
	"histogram.lua"
};

-- each tool returns its own menu entr(ies, y)
local tools_list = {};
local function scan()
	for _,v in ipairs(tools) do
		local fun = system_load(prefix .. "senseye/histogram.lua", false);
		if not fun then
			error_function("failed to open/parse " .. v);
		else
			local okstate, msg = pcall(fun);
			print(okstate, msg, type(okstate));
			if (not okstate) then
				error_function(
							string.format("runtime error loading tool %s : %s", v, msg)
				);
			elseif type(msg) == "table" then
				local st, err = suppl_menu_validate(msg);
				if (not st) then
					error_function("tool " .. v .. "menu error: " .. err);
				else
					table.insert(tools_list, msg);
				end
			else
				error_function("tool " .. v .. " didn't return a table");
			end
		end
	end
end

scan();

local function senseye_menu()
	local res = {};

	for i,v in ipairs(tools_list) do
		table.insert(res, v);
	end

	table.insert(res, {
		name = "reload",
		label = "Reload",
		description = "Scan / reload all tool scripts",
		handler = function()
			tools_list = {};
			scan();
		end
	});

	return res;
end

shared_menu_register("",
{
	name = "senseye",
	label = "Senseye",
	description = "Senseye data analysis toolsuite and sensor integration",
	kind = "action",
	submenu = true,
	handler = senseye_menu
}
);
