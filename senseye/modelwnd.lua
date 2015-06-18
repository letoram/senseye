-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: Basic UI for three dimensional representations
--
-- Exported Functions:
-- spawn_pointcloud(wnd) -- create a subwindow attached to wnd
--

-- prepare a window suitable for showing / navigating one model
function create_model_window(wnd, model, shader, nozoom)
-- 1. render the zoomed view to a texture that we use as LUT
	local props, isurf, csurf;

	if (not nozoom) then
		props = image_storage_properties(wnd.ctrl_id);
		isurf = alloc_surface(props.width, props.height);
		csurf = null_surface(props.width, props.height);
		force_image_blend(csurf, BLEND_NONE);
		force_image_blend(isurf, BLEND_NONE);
		image_sharestorage(wnd.ctrl_id, csurf);
		show_image(csurf);
		define_rendertarget(isurf, {csurf},
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, 0);
		rendertarget_forceupdate(isurf);
		image_sharestorage(isurf, model);
	end

-- 2. create an offscreen rendertarget for our 3d pipeline, and add a camera
	local rtgt = alloc_surface(VRESW, VRESH);
	define_rendertarget(rtgt, {model}, RENDERTARGET_DETACH,
		RENDERTARGET_NOSCALE, -1, RENDERTARGET_FULL);

	local camera = null_surface(1, 1);
	rendertarget_attach(rtgt, camera, RENDERTARGET_DETACH);
	camtag_model(camera, 0.01, 100.0, 45.0, 1.33);
	scale3d_model(camera, 1.0, -1.0, 1.0);
	forward3d_model(camera, -4.0);
	image_tracetag(camera, "camera");
	show_image({camera, rtgt, model});

-- 3. take the rendertarget and set as the window canvas
	local nw = wnd.wm:add_window(rtgt, {});
	if (shader) then
		switch_shader(nw, model, shader);
	end

	if (not nozoom) then
		nw.zoom_link = function(self, wnd, txcos)
			image_set_txcos(csurf, txcos);
			rendertarget_forceupdate(isurf);
		end

		wnd.zoom_link = function(wnd, parent, txcos)
			image_set_txcos(model, txcos);
		end

		nw.source_handler = function(wnd, source, status)
			if (status.kind == "frame") then
				rendertarget_forceupdate(isurf);
			end
		end

		wnd:add_zoom_handler(nw);
		table.insert(wnd.source_listener, nw);
	end

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
	nw:resize(wnd.width, wnd.height);
	table.insert(nw.autodelete, isurf);
	table.insert(nw.autodelete, rtgt);

	nw.rotate_set = {model};
	nw.rotate = function(wnd)
		for i,v in ipairs(nw.rotate_set) do
			rotate3d_model(v, nw.xang, nw.yang, nw.zang);
		end
	end

-- grab the shared window handlers, but replace / extend
	window_shared(nw);

	nw.fullscreen_input = function(wnd, iotbl)
	end

--	wnd.parent:add_zoom_handler(wnd);

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
			wnd:rotate();
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
			nw:rotate();
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

	nw.dispatch[BINDINGS["MODE_TOGGLE"]] = function(wnd)
		wnd.shind = (wnd.shind + 1 > #shaders_3dview_pcloud and 1 or
			wnd.shind + 1);
		if (shader) then
			switch_shader(wnd, wnd.model, shaders_3dview_pcloud[wnd.shind]);
		end
	end

	nw.dispatch[BINDINGS["TOGGLE_3DSPIN"]] = function(wnd)
		wnd.spinning = not wnd.spinning;
	end
	nw.shind = 1;

	return nw;
end

local pc_menu = {
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
			wnd:rotate();
			move3d_model(wnd.camera, 0.0, 0.0, 0.0);
			forward3d_model(wnd.camera, -4.0);
			wnd.spinning = nil;
		end
	}
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
	local pc = build_pointcloud(props.width * props.height, 2);
	force_image_blend(pc, BLEND_ADD);

	local new = create_model_window(wnd, pc, shaders_3dview_pcloud[1]);
	new.shader_group = shaders_3dview_pcloud;
	new.popup = merge_menu(pc_menu, model_menu);
	new.name = new.name .. "_pointcloud";
	new.shind = 1;

-- 2. attach a marker that is usually hidden but can be used to show
-- parent window selection
	local box = build_3dbox(0.0001, 0.0001, 0.0001, 0.0001);
	local text = fill_surface(2, 2, 255, 255, 255);
	image_sharestorage(text, box);
	delete_image(text);
--	show_image(box);
--	rotate3d_model(box, 45, 45, 45, 1000);
	rendertarget_attach(new.rendertarget, box, RENDERTARGET_DETACH);
end

local function spawn_plane(wnd)
	local props = image_storage_properties(wnd.canvas);
	local base = props.width / 2.0;
	local plane = build_3dplane(-1.0, -1.0, 1.0,
		1.0, -1.0, 1.0 / base, 1.0 / base, 1);
	local new = create_model_window(wnd, plane, shaders_3dview_plane[1]);
	new.shader_group = shaders_3dview_plane;
	new.popup = merge_menu(plane_menu, model_menu);
	new.name = new.name .. "_plane";
	new.shind = 1;
end
