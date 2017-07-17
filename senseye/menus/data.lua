local dump = {
	{
		label = "PNG",
		handler = dump_png
	},
	{
		label = "Full",
		handler = dump_full
	},
	{
		label = "No Alpha",
		handler = dump_noalpha
	}
};

local base_sz = {
	{
		label = "256",
		name = "sz_256",
		handler = function(wnd)
			target_displayhint(wnd.control_id, 256, 256);
		end,
	},
	{
		label = "512",
		name = "sz_512",
		handler = function(wnd)
			target_displayhint(wnd.control_id, 512, 512);
		end,
	},
	{
		label = "1024",
		name = "sz_1024",
		handler = function(wnd)
			target_displayhint(wnd.control_id, 1024, 1024);
		end,
	},
	{
		label = "2048",
		name = "sz_2048",
		handler = function(wnd)
			target_displayhint(wnd.control_id, 2048, 2048);
		end,
	}
};

--
-- Zoom:
-- Dive (Q1, Q2, Q3, Q4)
-- Rise
--

return {
	{
		label = "Views",
		name = views,
		submenu = views_sub,
	},
	{
		label = "Base Size",
		name = base_sz,
		submenu = base_sz,
	},
	{
		label = "Dump",
		submenu = dump,
		name = "dump"
	}
};
