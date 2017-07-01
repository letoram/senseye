-- cut and paste junk of functions to save and re-add during refact.

local function ppot(val)
	val = math.pow(2, math.floor( math.log(val) / math.log(2) ));
	return val < 32 and 32 or val;
end

local function npot(val)
	val = math.pow(2, math.ceil( math.log(val) / math.log(2) ));
	return val < 32 and 32 or val;
end

zoom_2x:
		if (wm.fullscreen) then
			return;
		end

		local wnd = wm.selected;
		if (wnd == nil) then
			return;
		end

		if (wm.meta) then
			local basew = ppot(wnd.width - 1);
			local baseh = ppot(wnd.height - 1);
			if (basew / baseh == wnd.width / wnd.height) then
				wnd:resize(basew, baseh);
			end
		else
			local basew = npot(wnd.width + 1);
			local baseh = npot(wnd.height + 1);
			wnd:resize(basew, baseh);
		end

		local x, y = mouse_xy();
		wnd:reposition();
		wnd:motion(wm.selected.canvas, x, y);


local function gen_dumpname(sens, suffix)
	local testname;
	local attempt = 0;

	repeat
		testname = string.format("dumps/%s_%d%s.%s", sens,
			benchmark_timestamp(1), attempt > 0 and tostring(CLOCK) or "", suffix);
		attempt = attempt + 1;
	until (resource(testname) == nil);

	return testname;
end

local function gen_dumpid(wnd)
	local s1 = wnd.zoom_ofs[1];
	local t1 = wnd.zoom_ofs[2];
	local s2 = wnd.zoom_ofs[3];
	local t2 = wnd.zoom_ofs[4];

	local did = valid_vid(wnd.ctrl_id) and wnd.ctrl_id or wnd.canvas;

-- zoomed case, create an intermediate recipient that has the dimensions
-- of the zoomed range but uses the source buffer and copies into a
-- temporary calctarget
	local res = image_storage_properties(did);
	local x1 = s1 * res.width;
	local y1 = t1 * res.height;
	local x2 = s2 * res.width;
	local y2 = t2 * res.height;
	local interim = alloc_surface(x2-x1, y2-y1);
	local csurf = null_surface(x2-x1, y2-t1);
	image_sharestorage(did, csurf);
	show_image({interim, csurf});
	local txcos = {s1, t1, s2, t1, s2, t2, s1, t2};
	image_set_txcos(csurf, txcos);
	force_image_blend(csurf, BLEND_NONE);

	if (wnd.shtbl) then
		switch_shader(wnd, csurf);
	end

	define_calctarget(interim, {csurf}, RENDERTARGET_DETACH,
		RENDERTARGET_NOSCALE, 0, function() end);
	rendertarget_forceupdate(interim);

	return interim;
end

local function dump_png(wnd)
	local name = gen_dumpname(wnd.basename, "png");
	local img = gen_dumpid(wnd);
	save_screenshot(name, FORMAT_PNG, img);
	delete_image(img);
	wnd:set_message(render_text(
		{menu_text_fontstr, name .. " saved"}), DEFAULT_TIMEOUT);
end

local views_sub = {
	{
		label = "Point Cloud",
		name = "view_pointcloud",
		handler = spawn_pointcloud
	},
	{
		label = "Alpha Map",
		name = "view_alpa",
		handler = spawn_alphamap
	},
	{
		label = "Histogram",
		name = "view_histogram",
		handler = spawn_histogram
	},
	{
		label = "Distance Tracker",
		name = "view_distgram",
		handler = spawn_distgram
	},
	{
		label = "Picture Tuner",
		name = "pictune",
		handler = spawn_pictune
	},
	{
		label = "Pattern Finder",
		name = "view_patfind",
		handler = function(wnd)
			spawn_patfind(wnd, copy_surface(wnd.canvas));
		end
	}
};

local function dump_full(wnd)
	local name = gen_dumpname(wnd.basename, "raw");
	local img = gen_dumpid(wnd);
	save_screenshot(name, FORMAT_RAW32, wnd.ctrl_id);
	delete_image(img);
	wnd:set_message(render_text({menu_text_fontstr,
		name .. " saved"}), DEFAULT_TIMEOUT);
end

local function dump_noalpha(wnd)
	local name = gen_dumpname(wnd.basename, "raw");
	local fmt = FORMAT_RAW32;

	if wnd.size_cur == 1 then
		fmt = FORMAT_RAW8;
	elseif wnd.size_cur == 3 then
		fmt = FORMAT_RAW24;
	end

	local img = gen_dumpid(wnd);
	save_screenshot(name, fmt, img);
	delete_image(img);
	wnd:set_message(render_text({
		menu_text_fontstr, name .. " saved"}), DEFAULT_TIMEOUT);
end

function copy_surface(vid)
	local newimg = BADID;

	image_access_storage(vid, function(tbl, w, h)
		local out = {};
		for y=1,h do
			for x=1,w do
				local r,g, b = tbl:get(x-1, y-1, 3);
				table.insert(out, r);
				table.insert(out, g);
				table.insert(out, b);
			end
		end
		newimg = raw_surface(w, h, 3, out);
	end);

	return newimg;
end

--
-- This only affects the visuals of the overlay, not its status
--
local function overlay_opa(wnd)
	local mnu = {};
	for i=0, 10, 2 do
		table.insert(mnu, {label = tostring(i*10) .. "%", value=i*10});
	end
	mnu.handler = function(wnd, value)
		wnd.overlay_opa = value / 100;
		blend_image(wnd.overlay, value / 100);
	end
	return mnu;
end

local function overlay_popup(wnd)
	local olist = {
		{
			label = "Opacity...",
			submenu = overlay_opa
		}
	};

	for i=1,#wnd.children do
		if (wnd.children[i].overlay_support) then
			table.insert(olist, {
				label = wnd.children[i].translator_name,
				handler = function()
					wnd.children[i]:activate_overlay();
				end
			});
		end
	end

	if (#olist > 0) then
		return olist;
	else
		return {{
			label = "No Overlays Available",
			handler = function() end
		}};
	end
end

local function wnd_vistog(wnd)
	if (wnd.all_hidden) then
		for i,v in ipairs(wnd.children) do
			v:show();
		end
		wnd.all_hidden = false;
	else
		for i,v in ipairs(wnd.children) do
			v:hide();
		end
		wnd.all_hidden = true;
	end
end
