function spawn_terminal()
	local bc = gconfig_get("term_bgcol");
	local fc = gconfig_get("term_fgcol");
	local cp = gconfig_get("extcon_path");

-- we want the dimensions in beforehand so we can pass them immediately
-- and in that way avoid the cost of a _resize() + signal cycle. To avoid
-- an initial 'flash' before background etc. is applied, we preset one.
	local wnd = durden_prelaunch();
	wnd:set_title("Terminal");

	local ppcm = tostring(active_display(true, true).ppcm);
	local ppcm = string.gsub(ppcm, ',', '.');

	local lstr = string.format(
		"font_hint=%s:font=[ARCAN_FONTPATH]/%s:ppcm=%s:"..
		"font_sz=%d:bgalpha=%d:bgr=%d:bgg=%d:bgb=%d:fgr=%d:fgg=%d:fgb=%d:%s",
		TERM_HINT_RLUT[tonumber(gconfig_get("term_font_hint"))],
		gconfig_get("term_font"),
		ppcm, gconfig_get("term_font_sz"),
		gconfig_get("term_opa") * 255.0 , bc[1], bc[2], bc[3],
		fc[1], fc[2],fc[3], (cp and string.len(cp) > 0) and
			("env=ARCAN_CONNPATH="..cp) or ""
	);

	local fbf = gconfig_get("font_fb");
	if (fbf and resource(fbf, SYS_FONT_RESOURCE)) then
		lstr = lstr .. string.format(":font_fb=[ARCAN_FONTPATH]/%s", fbf);
	end

-- we can't use the effective_w,h fields yet because the scalemode do
-- not apply (chicken and egg problem)
	if (gconfig_get("term_autosz")) then
		neww = wnd.width - wnd.pad_left - wnd.pad_right;
		newh = wnd.height- wnd.pad_top - wnd.pad_bottom;
		lstr = lstr .. string.format(":width=%d:height=%d", neww, newh);
	end

	local vid = launch_avfeed(lstr, "terminal");
	image_tracetag(vid, "terminal");

	if (valid_vid(vid)) then
		durden_launch(vid, "", "terminal", wnd);
		extevh_default(vid, {
			kind = "registered", segkind = "terminal", title = "", guid = 1});
		image_sharestorage(vid, wnd.canvas);
--		hide_image(wnd.border);
--		hide_image(wnd.canvas);
	else
		active_display():message( "Builtin- terminal support broken" );
		wnd:destroy();
	end
end

register_global("spawn_terminal", spawn_terminal);

return {
{
	name = "terminal",
	label = "Terminal",
	kind = "value",
	hint = "(append arguments)",
	default = "",
	eval = function()
		return string.match(FRAMESERVER_MODES, "terminal") ~= nil;
	end,
	handler = function(ctx, val)
		spawn_terminal(cmd);
	end
}
};
