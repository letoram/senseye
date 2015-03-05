-- Copyright 2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: Pattern finder, creates a copy of the
-- data window on launch, and can then be instructed to
-- trigger when this pattern occurs again.
--

local match_bfrag = [[
	uniform sampler2D map_tu0;
	uniform sampler2D map_tu1;
	varying vec2 texco;

	void main()
	{
		vec3 c1 = texture2D(map_tu0, texco).rgb;
		vec3 c2 = texture2D(map_tu1, texco).rgb;

		bool b1 = any(greaterThan(c1, vec3(0.0)));
		bool b2 = any(greaterThan(c2, vec3(0.0)));

		if (b1 == b2)
			gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
		else
			gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);
	}
]];

local match_frag = [[
	uniform sampler2D map_tu0;
	uniform sampler2D map_tu1;
	varying vec2 texco;

	void main()
	{
		vec3 c1 = texture2D(map_tu0, texco).rgb;
		vec3 c2 = texture2D(map_tu1, texco).rgb;
		vec3 diff = clamp(abs(c1 - c2), 0.0, 1.0);
		gl_FragColor = vec4(diff.rgb, 1.0);
	}
]];

local bfrag_shid = build_shader(nil, match_bfrag, "pat_bdelta");
local frag_shid = build_shader(nil, match_frag, "pat_delta");
local ptind = 1;

local shtbl = {
	bfrag_shid, frag_shid
};

local function update_threshold(wnd, val)
	val = val < 1 and 1 or val;
	val = val > 99 and 99 or val;
	wnd.thresh = val;
	wnd.parent:set_message(
		string.format( "Pattern: trigger > %d %%", wnd.thresh ));
end

local function set_calc(nw, abuf, canv)
	define_calctarget(abuf, {canv}, RENDERTARGET_DETACH,
		RENDERTARGET_NOSCALE, 0, function(tbl, w, h)
		local sum = 0;
		for y=1,h do
			for x=1,w do
				local r, g, b = tbl:get(x, y, 3);
				sum = sum + r + g + b;
			end
		end
		local pct = math.ceil(((1.0 - sum / (w * h * 255 * 3)) * 100));
		if (pct >= nw.thresh) then
			nw:set_border(2, 0, 255 - (100-nw.thresh)/255*(pct - nw.thresh), 0);

			if (nw.in_signal) then
			else
				nw.in_signal = true;
				nw.signal_pos = nw.parent.ofs;
				nw:set_border(2, 0, 255 - (100-nw.thresh)/255*(pct - nw.thresh), 0);
				nw.parent:alert(string.format("pattern %d match", nw.ptind));
			end
		else
				nw:set_border(2, 255 - ((nw.thresh-pct)/nw.thresh)*255, 0, 0);

			if (nw.in_signal and nw.parent.ofs ~= nw.signal_ofs) then
				nw.in_signal = false;
			end
		end

-- #in pattern and not already in? set border to green and in
-- and pause (and possibly notepad trigger).
-- out pattern and in pattern? set border to red

	end);
end

--
-- New window that shares the same storage as the data window
-- + a manual copy at creation that will be used as reference
-- match_frag shader provides the delta comparison, wrap these
-- in a calctarget and on step, add deviances and compare against
-- set trigger. If the match is sufficient, signal / show that
-- we have a match and pause the parent.
--
function spawn_patfind(wnd, refimg)
	local props = image_storage_properties(wnd.canvas);

	if (not valid_vid(refimg)) then
		warning("pattern finder - couldn't clone surface");
		return;
	end

	local canv = null_surface(props.width, props.height);
	if (not valid_vid(canv)) then
		warning("pattern finder - couldn't create intermediate buffer.");
		delete_image(refimg);
		return;
	end

	image_sharestorage(wnd.canvas, canv);
	image_framesetsize(canv, 2, FRAMESET_MULTITEXTURE);
	set_image_as_frame(canv, refimg, 1);
	image_shader(canv, shtbl[1]);
	delete_image(refimg);

	local abuf = alloc_surface(props.width, props.height);
	if (not valid_vid(abuf)) then
		warning("pattern finder - couldn't create renderbuffer.");
		delete_image(canv);
		return;
	end

	show_image({abuf, canv});

	local nw = wnd.wm:add_window(abuf, {});
	set_calc(nw, abuf, canv);

	nw.reposition = repos_window;
	nw:resize(64, 64);
	nw:set_parent(wnd, ANCHOR_UL);
	nw.in_signal = true;
	nw.signal_pos = nw.parent.ofs;
	move_image(nw.anchor, 0, -64);
	nw.fullscreen_disabled = true;
	nw.shid = 1;
	nw.ptind = ptind;
	ptind = ptind + 1;

	nw.source_handler = function(wnd, source, status)
		if (status.kind == "frame") then
			rendertarget_forceupdate(abuf);
			stepframe_target(abuf);
		end
	end

	table.insert(nw.parent.source_listener, nw);
	table.insert(nw.autodelete, abuf);

	nw.thresh = 95;

	nw.dispatch[BINDINGS["CYCLE_SHADER"]] = function(wnd)
		nw.shid = (nw.shid + 1) > #shtbl and 1 or nw.shid+1;
		image_shader(canv, nw.shid);
	end

	nw.dispatch[BINDINGS["PFIND_INC"]] = function(wnd)
		update_threshold(nw, nw.thresh + (wnd.wm.meta and 1 or 10));
	end

	nw.dispatch[BINDINGS["PFIND_DEC"]] = function(wnd)
		update_threshold(nw, nw.thresh - (wnd.wm.meta and 1 or 10));
	end

	defocus_window(nw);
end
