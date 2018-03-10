local def_pmr = 90;

local patfind_menu = {
	{
		name = "set_reference",
		label = "Reference",
		description = "Specify a reference image to match against",
		handler = function()
-- browse, set reference in slot
		end
	},
	{
		name = "match_rate",
		kind = "value",
		validator = gen_valid_num(1, 100),
		initial = function()
			local wnd = active_display():selected;
			local pmr = wnd.pattern_match_threshold;
			return pmr and pmr or def_pmr;
		end,
		handler = function(ctx, val)
			local wnd = active_display().selected;
			wnd.
		end
	},
	{
		name = "drop_reference",
		label = "Drop Reference",
		eval = function()
			return active_display().selected.patfind;
		end,
		submenu = true,
		handler = function()
			local res = {};
			for i,v in ipairs(active_display().selected.patfind) do
				table.insert(res, {
				});
			end
		end
	}
};

return {
	name = "pattern_find",
	label = "Pattern Finder",
	kind = "action",
	description = "Compare the contents of the current window to a reference image",
	submenu = true,
	handler = patfind_menu
};
