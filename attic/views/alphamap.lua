-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
--
-- Description: A clone of the main data window that only
-- shows the alpha, either as a translucent window that can
-- be lockedor as a separate. The rationale for doing it here
-- rather than in the shader for the datawindow is to easier
-- combine with other coloring approaches without things
-- getting too 'noisy'.
--

local ashid = build_shader(nil, [[
uniform sampler2D map_tu0;
varying vec2 texco;

void main()
{
	vec4 col = texture2D(map_tu0, texco);
	gl_FragColor = vec4(0.0, col.a, 0.0, 1.0);
}
]], "alpha_tor");

function spawn_alphamap(wnd)
	local canv = null_surface(wnd.width, wnd.height);
	image_sharestorage(wnd.canvas, canv);
	local nw = wnd.wm:add_window(canv, {});
	nw.reposition = repos_window;
	nw:set_parent(wnd, ANCHOR_LR);
	nw:resize(wnd.width, wnd.height);
	nw.fullscreen_disabled = true;

	nw.zoom_link = function(self, wnd, txcos)
		image_set_txcos(self.canvas, txcos);
	end

	defocus_window(nw);
	wnd:add_zoom_handler(nw);
	image_shader(canv, ashid);
	window_shared(nw);

	return nw;
end
