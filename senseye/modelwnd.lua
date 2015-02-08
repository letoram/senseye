-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: Basic UI for three dimensional representations
--
-- Exported Functions:
-- spawn_pointcloud(wnd) -- create a subwindow attached to wnd
--

-- prepare a window suitable for showing / navigating one model
local function modelwnd(wnd, model, shader)
-- 1. share the storage from the original model (note, should we
--    add an update hook for zoom and do a corresponding txco- mapping?)
	image_sharestorage(wnd.canvas, model);

-- 2. create an offscreen rendertarget for our 3d pipeline, and add a camera
	local rtgt = alloc_surface(VRESW, VRESH);
	define_rendertarget(rtgt, {model}, RENDERTARGET_DETACH,
		RENDERTARGET_NOSCALE, RENDERTARGET_FULL);

	local camera = null_surface(1, 1);
	rendertarget_attach(rtgt, camera, RENDERTARGET_DETACH);
	camtag_model(camera, 0.01, 100.0, 45.0, 1.33);
	scale3d_model(camera, 1.0, -1.0, 1.0);
	forward3d_model(camera, -4.0);
	image_tracetag(camera, "camera");

	switch_shader(wnd, model, shader);
	show_image({camera, rtgt, model});

-- 3. take the rendertarget and set as the window canvas
	local nw = wnd.wm:add_window(rtgt, {});

	nw:set_parent(wnd, ANCHOR_UR);
	defocus_window(nw)
	nw.camera = camera;
	nw.zang = 0.0;
	nw.xang = 0.0;
	nw.yang = 5.0;
	nw.rendertarget = rtgt;
	nw.model = model;
	nw.mmode = "rotate";
	nw.spinning = false;

	rotate3d_model(model, nw.xang, nw.yang, nw.zang);

-- grab the shared window handlers, but replace / extend
	window_shared(nw);

	nw.fullscreen_input = function(wnd, iotbl)
	end

	nw.fullscreen_input_sym = function(wnd, sym)
		if ((sym == BINDINGS["PSENSE_STEP_FRAME"] or
			sym == BINDINGS["PSENSE_STEP_BACKWARD"]) and
			wnd.parent.dispatch[sym] ~= nil) then
			wnd.parent.dispatch[sym](wnd.parent);
		end
	end

	nw.tick = function(wnd, step)
		if (wnd.spinning) then
			wnd.zang = math.abs(wnd.zang + 0.5 * step, 360.0);
			rotate3d_model(wnd.model, wnd.xang, wnd.yang, wnd.zang);
		end
	end

	local def_drag = nw.drag;
	nw.drag = function(ctx, vid, dx, dy)
		if (nw.wm.meta) then
			return def_drag(nw, vid, dx, dy);
		end

		if (nw.mmode == "rotate") then
			nw.yang = nw.yang + dy;
			nw.zang = nw.zang + dx;
			rotate3d_model(nw.model, nw.xang, nw.yang, nw.zang);
		else
			forward3d_model(nw.camera, -0.1 * dy);
			strafe3d_model(nw.camera, 0.1 * dx);
		end
	end

	nw.fullscreen_mouse = {
		drag = nw.drag
	};

	nw.dispatch[BINDINGS["ZOOM"]] = function(wnd)
	end

	nw.dispatch[BINDINGS["STEP_FORWARD"]] = function(wnd)
		forward3d_model(wnd.camera, 0.2);
	end

	nw.dispatch[BINDINGS["STEP_BACKWARD"]] = function(wnd)
		forward3d_model(wnd.camera, -0.2);
	end

	nw.dispatch[BINDINGS["STRAFE_LEFT"]] = function(wnd)
		strafe3d_model(wnd.camera, -0.2);
	end

	nw.dispatch[BINDINGS["STRAFE_RIGHT"]] = function(wnd)
		strafe3d_model(wnd.camera, 0.2);
	end

	nw.dispatch[BINDINGS["TOGGLE_3DMOUSE"]] = function(wnd)
		wnd.mmode = wnd.mmode == "rotate" and "move" or "rotate";
	end

	nw.dispatch[BINDINGS["CYCLE_SHADER"]] = function(wnd)
		wnd.shind = (wnd.shind + 1 > #shaders_3dview_pcloud and 1 or
			wnd.shind + 1);
		switch_shader(wnd, wnd.model, shaders_3dview_pcloud[wnd.shind]);
	end

	nw.dispatch[BINDINGS["TOGGLE_3DSPIN"]] = function(wnd)
		wnd.spinning = not wnd.spinning;
	end
	nw.shind = 1;

	return nw;
end

--
-- The scaletarget indirection is needed for linking sampling
-- coordinate buffers to the parent. It creates a null surface
-- with a shared storage to which the zoom- texture coordinates
-- are applied.
--

local function drop_scaletarget(wnd)
	if (valid_vid(wnd.scaletarget)) then
		for k,v in ipairs(wnd.autodelete) do
			if (v == wnd.scaletarget) then
				table.remove(wnd.autodelete, k);
				break;
			end
		end
		delete_image(wnd.scaletarget);
	end
end

local function setup_scaletarget(wnd, vid)
	drop_scaletarget(wnd);
	local props = image_storage_properties(vid);
	wnd.scaletarget = alloc_surface(props.width, props.height);
	wnd.scalebuf = null_surface(props.width, props.height);

	image_texfilter(wnd.scalebuf, FILTER_NONE);
	image_texfilter(wnd.scaletarget, FILTER_NONE);

	switch_shader(wnd, wnd.scalebuf, shaders_2dview[1]);

	show_image(wnd.scalebuf);
	image_sharestorage(vid, wnd.scalebuf);
	define_rendertarget(wnd.scaletarget, {wnd.scalebuf},
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	table.insert(wnd.autodelete, wnd.scaletarget);
	rendertarget_forceupdate(wnd.scaletarget);
	return buf;
end

local function deactivate_link(wnd)
	wnd.zoom_link = nil;
	drop_scaletarget(wnd);
	wnd.parent:drop_zoom_handler(wnd);

	wnd.update_zoom = wnd.parent_zoom;
	image_sharestorage(wnd.parent.canvas, wnd.model);
	wnd.scaletarget = nil;
	wnd.parent_zoom = nil;

	local img, lines = render_text(menu_text_fontstr .. "link disabled");
	wnd:set_message(img);
end

local function activate_link(wnd)
	wnd.zoom_link = function(wnd, parent, txcos)
		image_set_txcos(wnd.scalebuf, txcos);
		rendertarget_forceupdate(wnd.scaletarget);
		rendertarget_forceupdate(wnd.rendertarget);
	end

	setup_scaletarget(wnd, wnd.parent.canvas);
	image_sharestorage(wnd.scaletarget, wnd.model);

	wnd.parent:add_zoom_handler(wnd);
	local img, lines = render_text(menu_text_fontstr .. "link enabled");
	wnd:set_message(img);
end

local link_menu = {
	{
			label = "Toggle",
			name = "link_toggle",
			handler = function(wnd)
				if (wnd.zoom_link) then
					deactivate_link(wnd);
				else
					activate_link(wnd);
				end
			end
	}
};

local pc_menu = {
-- rebuild needed to manually support rebuilding the internal representation
-- if the underlying storage changes from the user specifying different
-- packing schemes
	{
		label = "Rebuild",
		name = "pc_submenu_rebuild",
		handler = function(wnd)
			local props = image_storage_properties(wnd.parent.canvas);
			delete_image(wnd.model);
			local pc = build_pointcloud(props.width * props.height);
			image_sharestorage(wnd.parent.canvas, pc);
			show_image(pc);
			wnd.model = pc;
			rendertarget_attach(wnd.rendertarget, pc, RENDERTARGET_DETACH);
			switch_shader(wnd, wnd.model, shaders_3dview_pcloud[wnd.shind]);
		end
	},
--
-- one might want to change the sample- set (texture coordinates) in
-- the parent window and have them reflected
--
	{
		label = "Point Mapping...",
		name = "pc_submenu_mapping",
		submenu = function()
			return shader_menu(shaders_3dview_pcloud, "model");
		end
	},
};

local model_menu = {
	{
		label = "Reset",
		name = "model_reset",
		handler = function(wnd)
			wnd.xang = 0.0;
			wnd.yang = 5.0;
			wnd.zang = 0.0;
			rotate3d_model(wnd.model, wnd.xang, wnd.yang, wnd.zang);
			move3d_model(wnd.camera, 0.0, 0.0, 0.0);
			forward3d_model(wnd.camera, -4.0);
			wnd.spinning = nil;
		end
	},
	{
		label = "Sample Coordinates...",
		name = "model_link",
		submenu = link_menu
	},
};

local plane_menu = {
-- rebuild needed to manually support rebuilding the internal representation
-- if the underlying storage changes from the user specifying different
-- packing schemes
	{
		label = "Rebuild",
		name = "plane_submenu_rebuild",
		handler = function(wnd)
			local props = image_storage_properties(wnd.canvas);
			delete_image(wnd.model);
			local plane = build_3dplane(-1.0, -1.0, 1.0,
				1.0, -1.0, 1.0 / base, 1.0 / base, 1);
			image_sharestorage(wnd.parent.canvas, plane);
			show_image(plane);
			wnd.model = plane;
			rendertarget_attach(wnd.rendertarget, plane, RENDERTARGET_DETACH);
			switch_shader(wnd, wnd.model, shaders_3dview_plane[wnd.shind]);
		end
	},
--
-- one might want to change the sample- set (texture coordinates) in
-- the parent window and have them reflected
--
	{
		label = "Plane Mapping...",
		name = "pc_submenu_mapping",
		submenu = function()
			return shader_menu(shaders_3dview_plane, "model");
		end
	},
};

function spawn_pointcloud(wnd)
	local props = image_storage_properties(wnd.canvas);
	local pc = build_pointcloud(props.width * props.height);
	local new = modelwnd(wnd, pc, shaders_3dview_pcloud[1]);
	new.shader_group = shaders_3dview_pcloud;
	new.popup = merge_menu(pc_menu, model_menu);
	new.name = new.name .. "_pointcloud";
	new.shind = 1;
end

local function spawn_plane(wnd)
	local props = image_storage_properties(wnd.canvas);
	local base = props.width / 2.0;
	local plane = build_3dplane(-1.0, -1.0, 1.0,
		1.0, -1.0, 1.0 / base, 1.0 / base, 1);
	local new = modelwnd(wnd, plane, shaders_3dview_plane[1]);
	new.shader_group = shaders_3dview_plane;
	new.popup = merge_menu(plane_menu, model_menu);
	new.name = new.name .. "_plane";
	new.shind = 1;
end
