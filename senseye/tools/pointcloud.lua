
local pc_menu = {
	{
		label = "Shader",
		name = "pc_shader",
		kind = "action",
		submenu = true,
		handler = list_shaders
	},
	{
		label = "Set LUT",
		name = "lut",
	},
	{
		label = "Zoom Link(ON)",
		name = "zoom_on",
		kind = "action",
	}
};

-- window is in ctx. tag
local function on_drag(ctx, vid, dx, dy)
	if (ctx.cam_nav) then
		forward3d_model(ctx.tag.camera, -0.1 * dy);
		strafe3d_model(ctx.tag.camera, 0.1 * dx);
	else
		ctx.tag.yang = ctx.tag.yang + dy;
		ctx.tag.zang = ctx.tag.zang + dx;
		ctx.tag:rotate();
	end
end

local function on_zoom(ctx, txcos)
	image_set_txcos(ctx.model, txcos);
	rendertarget_forceupdate(ctx.canvas);
end

local function build_pc_rt(wnd)
	local rtgt = alloc_surface(VRESW, VRESH);
	define_rendertarget(rtgt, {wnd.model}, RENDERTARGET_DETACH,
		RENDERTARGET_NOSCALE, -1, RENDERTARGET_FULL);
	image_sharestorage(wnd.canvas, wnd.model);
	image_sharestorage(rtgt, wnd.canvas);

	local camera = null_surface(1, 1);
	rendertarget_attach(rtgt, camera, RENDERTARGET_DETACH);
	camtag_model(camera, 0.01, 100.0, 45.0, 1.33);
	scale3d_model(camera, 1.0, -1.0, 1.0);
	forward3d_model(camera, -4.0);
	image_tracetag(camera, "camera");
	show_image({camera, wnd.model});
	link_image(rtgt, wnd.canvas);

	wnd.rtgt = rtgt;
	wnd.cam = cam;
	wnd.zang = 0.0;
	wnd.xang = 0.0;
	wnd.yang = 5.0;
	wnd.spinning = false;

	wnd.tick = function(wnd)
		if (wnd.spinning) then
			wnd.zang = math.abs(wnd.zang + 0.5 * step, 360.0);
			wnd:rotate();
		end
	end

	wnd.rotate = function(wnd)
		rotate3d_model(wnd.model, wnd.xang, wnd.yang, wnd.zang);
	end
end

return {
	label = "Point Cloud",
	name = "pcloud",
	spawn = function(wnd, parent)
		wnd.rebuild_model = function(wnd, base_sz)
			if (valid_vid(wnd.model)) then
				delete_image(wnd.model);
			end
			local p = image_storage_properties(parent.canvas);
			wnd.model = build_pointcloud(p.width * p.height, 2);
			force_image_blend(wnd.model, BLEND_ADD);
			if (valid_vid(wnd.rtgt)) then
				rendertarget_attach(wnd.rtgt, wnd.model, RENDERTARGET_DETACH);
			end
			shader_setup(wnd.model, "pcloud", "trigram");
		end
		wnd:rebuild_model();

		wnd.handlers.mouse.canvas.drag = on_drag;
		build_pc_rt(wnd);
	end
};
