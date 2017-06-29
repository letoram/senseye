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

--
-- Zoom:
-- Dive (Q1, Q2, Q3, Q4)
-- Rise
--

return {
	{
		label = "Views...",
		name = views,
		submenu = views_sub,
	},
	{
		label = "Dump...",
		submenu = dump,
		name = "dump"
	}
};
