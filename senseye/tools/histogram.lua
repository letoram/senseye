--
-- Histogram tools
-- Features missing:
--  * pattern- clicking / highlight
--  * accumulated view (add histogram into row for a historical view)
--  * hybrid, a shader that takes the bottom portion and shows as the
--    current view, and the upper portion as accumulated
--  * dumping search- match log to file
--  * dumping profile to file, loading profile from file
--
local function bhattacharyya(h1, h2)
	local bcf = 0;
	local sum_1 = 0;
	local sum_2 = 0;

	for i=0,255 do
		bcf = bcf + math.sqrt(h1[i] * h2[i]);
		sum_1 = sum_1 + h1[i];
		sum_2 = sum_2 + h2[i];
	end

	local rnd = math.floor(sum_1 + 0.5);
	local bcf = bcf > rnd and rnd or bcf;

	return 1.0 - math.sqrt(rnd - bcf);
end

local function intersection(h1, h2)
	local sum = 0;
	for i=0,255 do
		sum = sum + (h1[i] > h2[i] and h2[i] or h1[i]);
	end
	return sum;
end

local match_func = {
{
	label = "Bhattacharyya",
	name = "bhatt",
	kind = "action",
	handler = function(ctx)
		ctx.wm.selected.matchfunc = bhattacharyya;
	end
},
{
	label = "Intersection",
	name = "match_intersect",
	kind = "action",
	handler = function(ctx)
		ctx.wm.selected.matchfunc = intersection;
	end,
	handler = function(wnd)
		wnd.match_fun = intersection;
		wnd.parent:set_message("Intersection matching", DEFAULT_TIMEOUT);
	end,
}
};

local histo_menu = {
	{
		label = "Match Function",
		name = "match",
		kind = "submenu",
		handler = match_func
	},
	{
		label = "Set Matching",
		name = "match_ref",
		kind = "submenu",
		handler = match_ref
	},
	{
		label = "Match Rate (>= x%)",
		name = "match_rate",
		kind = "value",
		validator = gen_valid_num(1,100);
		handler = function(ctx, val)
			ctx.wm.selected.matchrate = tonumber(val);
		end
	},
	{
		label = "Auto-pause",
		name = "match_pause",
		kind = "action",
		handler = function(ctx)
			ctx.wm.selected.autopause = false;
		end
	},
	{
		label = "Stop Matching",
		name = "match_stop",
		kind = "action",
		eval = function(ctx)
			return ctx.wm.selected.hgram_ref ~= nil;
		end,
	}
};

-- just run access_storage and generate histogram from there

local function parent_click(wnd, parent, x, y, pos)
	print("got click");
end

local function parent_update(wnd, parent)
-- generate a histogram from the currently synched parent storage
-- and update the canvas of our own window
	image_access_storage(parent.external,
	function(tbl, w, h)
		tbl:histogram_impose(wnd.canvas, HISTOGRAM_MERGE_NOALPHA, true);
		if (not wnd.hgram_ref or not wnd.matchfunc) then
			return;
		end

-- if a reference is set and we are matching, run a comparison
		local ctbl = {};
		pop_htable(tbl, ctbl);
		local rate = wnd.matchfunc(wnd.hgram_ref, ctbl) * 100;

		if (rate < wnd.matchrate) then
			wnd.in_signal = false;
			return;
		end

-- match and we did not know about it before? log and possibly pause
		if (not wnd.in_signal) then
			wnd.in_signal = true;
			table.insert(wnd.signal_pos, {parent.ofs, rate, ctbl});
			if (wnd.autopause) then
				wnd:alert();
				parent:set_pause();
			end
		end
	end
	);
end

-- window is in ctx. tag
local function on_motion(ctx, vid, x, y)

end

local function on_button(ctx, vid, ind, active, x, y)
end

local hshader = build_shader(
	nil,
[[
	uniform sampler2D map_tu0;
	varying vec2 texco;

	void main()
	{
		vec2 uv = vec2(texco.s, 1.0 - texco.t);
		vec4 col = texture2D(map_tu0, uv);

		float rv = float(col.r > uv.y);
		float gv = float(col.g > uv.y);
		float bv = float(col.b > uv.y);

		gl_FragColor = vec4(rv, gv, bv, 1.0);
	}
]], "histogram");

return {
	label = "Histogram",
	name = "hgram",
	spawn = function(wnd, parent)
		wnd.signal_pos = {};
		wnd.handlers.mouse.canvas.motion = on_motion;
		wnd.handlers.mouse.canvas.button = on_button;
		wnd.hptn = {};
		wnd.pupdate = parent_update;
		wnd:add_handler("destroy", function()
			parent:dec_synch();
		end);
		local hgram = fill_surface(256, 1, 0, 0, 0, 256, 1);
		image_sharestorage(hgram, wnd.canvas);
		delete_image(hgram);
		image_shader(wnd.canvas, hshader);
		parent:inc_synch();
		parent_update(wnd, parent);
	end
};
