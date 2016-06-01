local exit_query = {
{
	name = "no",
	label = "No",
	kind = "action",
	handler = function() end
},
{
	name = "yes",
	label = "Yes",
	kind = "action",
	dangerous = true,
	handler = function() shutdown(); end
}
};

local system_menu = {
	{
		name = "shutdown",
		label = "Shutdown",
		kind = "action",
		submenu = true,
		handler = exit_query
	}
};

return system_menu;
