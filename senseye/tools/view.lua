-- track cursor
-- mangification

local menu = {
{
name = "trackon",
label = "Enable Tracking",
kind = "action",
handler = function(ctx)
end
},
{
name = "magfact",
label = "Set Magnification",
kind = "value",
validator = gen_valid_num(1,10),
handler = function(ctx)
end
}
};

return {
	label = "View",
	name = "view",
	spawn = function(wnd)
		image_framesetsize(wnd.canvas, 2, FRAMESET_MULTITEXTURE);
		shdrmgmt_default_lut(wnd.canvas, 1);
		wnd.cursor_track = false;
	end
};
