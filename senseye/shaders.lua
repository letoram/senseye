-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: Basic selection of shaders for some sensor windows
-- ordered by type shaders_(2dview, 3dview_plane, 3dview_pcloud, 1dplot)
-- that are exposed in the global namespaces as integer indexed tables
--
-- use function switch_shader(wnd, target, shtbl) to change shader on
-- the canvas of an active window.
--
-- use function shader_menu(group, target) to impose the list of available
-- shaders in a subgroup to a popup menu.
--
-- The system used here is too rigid and is in the process of being reworked.

-- we generate the default color lookup table programatically,
-- just a a gradient with some signal colors for the first 16 slots
-- others can be loaded as images

local default_lut = {
	0xff, 0xff, 0xff,
	0xff, 0x00, 0x00,
--	0x00, 0xff, 0x00 used for highlight so exclude here
	0xff, 0xff, 0x00,
	0x00, 0x00, 0xff,
	0xff, 0x00, 0xff,
	0x00, 0xff, 0xff,
	0x99, 0x99, 0x99,
	0x99, 0x00, 0x00,
	0x00, 0x99, 0x00,
	0x99, 0x99, 0x00,
	0x00, 0x00, 0x99,
	0x99, 0x00, 0x99,
	0x00, 0x99, 0x99,
	0x40, 0x40, 0x40,
	0x40, 0x00, 0x00,
	0x40, 0x40, 0x00,
};

for i=49,768,3 do
	default_lut[i+0] = 0;
	default_lut[i+1] = i-1;
	default_lut[i+2] = 0;
end

local global_lookup = load_image("color_lut/ascii.png");

if (not valid_vid(global_lookup)) then
	global_lookup = raw_surface(256, 1, 3, default_lut);
end
default_lut = raw_surface(256, 1, 3, default_lut);

--
-- get x, y, z coordinates that match the tranformation done by the
-- vertex shader, needed in order to get correlation between marker
-- and point-cloud view
--
local function pc_xl_disp(x, y, r, g, b, a)

end

shaders_2dview = {
	{
		name = "Normal",
		fragment = [[
			uniform sampler2D map_tu0;
			varying vec2 texco;

			void main()
			{
				vec4 col = texture2D(map_tu0, texco);
				float intens = (col.r + col.g + col.b) / 3.0;
				gl_FragColor = vec4(col.r, col.g, col.b, 1.0);
			}
		]],
		vertex = nil
	},
-- assumed histogram is [2] for update_highlight_shader function
	{
		name = "Histogram Highlight",
		vertex = nil,
		fragment = [[
			uniform sampler2D map_tu0;
			uniform sampler2D map_tu1;

			uniform vec2 highlight_range;
			uniform mat4 lut;

			varying vec2 texco;

			void main()
			{
				vec4 col = texture2D(map_tu0, texco);
				float intens = (col.r + col.g + col.b) / 3.0;
				gl_FragColor = vec4(0.2*intens,0.2*intens,0.2*intens,1.0);

/* matrix packed with values to highlight */
				if (intens < highlight_range.x || intens > highlight_range.y){
					for (int i = 0; i < 4; i++)
						for (int j = 0; j < 4; j++){
							if (lut[i][j] == -1.0)
								return;

							if (abs(lut[i][j]/255.0 - intens) < 0.001){
								gl_FragColor = texture2D(map_tu1, vec2(float(i*4+j)/256.0, 0));
								return;
							}
						}
				}
/* range takes priority */
				else
					gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0);
			}
		]],
		uniforms = {
			lut = {
				typev = "ffffffffffffffff",
				values = {-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}
			};
		},
		lookup = default_lut
	},
	{
		name = "Red/Green Split",
		description = "split intensity into upper intensity R/G",
		vertex = nil,
		fragment = [[
			uniform sampler2D map_tu0;
			varying vec2 texco;

			void main()
			{
				vec4 col = texture2D(map_tu0, texco);
				float intens = (col.r + col.g + col.b) / 3.0;
				gl_FragColor = vec4(intens * 2.0, (intens - 0.5) * 2.0, 0.0, 1.0);
			}
		]],
	},
	{
		name = "Luma Lookup Table",
		description = "Byte value determines color",
		vertex = nil,
		fragment = [[
			uniform sampler2D map_tu0;
			uniform sampler2D map_tu1;
			varying vec2 texco;
			void main()
			{
				vec3 col = texture2D(map_tu0, texco).rgb;
				float luma = (col.r + col.g + col.b) / 3.0;
				col = texture2D(map_tu1, vec2(luma, 0)).rgb;
				gl_FragColor = vec4(col.rgb, 1.0);
			}
		]],
		lookup = true
	}
};

shaders_3dview_plane = {
	{
	name = "Displace",
	description = "Displace y value with intensity",
	vertex = [[
	uniform mat4 modelview;
	uniform mat4 projection;
	uniform sampler2D map_tu0;

	attribute vec2 texcoord;
	attribute vec4 vertex;

	varying vec2 texco;

	void main(){
		vec4 dv   = texture2D(map_tu0, texcoord);
		vec4 vert = vertex;
		vert.y    = (dv.r + dv.g + dv.b) / 3.0;
		gl_Position = (projection * modelview) * vert;
		texco = texcoord;
	}
	]],
	fragment = [[
		uniform sampler2D map_tu0;
		varying vec2 texco;

		void main(){
			vec4 col = texture2D(map_tu0, texco);
			gl_FragColor = vec4(col.r, col.g, col.b, 1.0);
		}
	]]
	}
};

local pc_triple_v = [[
	uniform sampler2D map_tu0;
	uniform sampler2D map_tu1;

	uniform mat4 modelview;
	uniform mat4 projection;
	uniform float point_sz;

	attribute vec2 texcoord;
	attribute vec4 vertex;

	varying vec2 texco;
	varying float intens;

	void main(){
		vec4 dv   = texture2D(map_tu0, texcoord);
		vec4 vert = vertex;
		intens = (dv.r + dv.g + dv.b) / 3.0;
		vert.x    = 2.0 * dv.r - 1.0;
		vert.y    = 2.0 * dv.g - 1.0;
		vert.z    = 2.0 * dv.b - 1.0;
		gl_Position = (projection * modelview) * vert;
		gl_PointSize = point_sz;
		texco = texcoord;
	}
]];

local pc_lut_f = [[
	uniform sampler2D map_tu0;
	uniform sampler2D map_tu1;

	varying vec2 texco;
	varying float intens;

	void main(){
		vec4 col = texture2D(map_tu1, vec2(intens, 0.0));
		gl_FragColor = vec4(col.rgb, 1.0);
	}
]];

local pc_disp_v = [[
	uniform mat4 modelview;
	uniform mat4 projection;
	uniform sampler2D map_tu0;
	uniform float point_sz;

	attribute vec2 texcoord;
	attribute vec4 vertex;

	varying vec2 texco;
	varying float intens;

	void main(){
		vec4 dv   = texture2D(map_tu0, texcoord);
		vec4 vert = vertex;
		intens = (dv.r + dv.g + dv.b) / 3.0;
		vert.x    = 2.0 * texcoord.s - 1.0;
		vert.y    = 2.0 * texcoord.t - 1.0;
		vert.z    = 2.0 * intens - 1.0;
		gl_Position = (projection * modelview) * vert;
		gl_PointSize = point_sz;
		texco = texcoord;
	}
]];

shaders_3dview_pcloud = {
	{
	name = "Z Displace",
	description = [[displacement, intensity determines z- val]],
	fragment = pc_lut_f,
	vertex = pc_disp_v,
	translate = pc_xl_disp,
	lookup = true,
	},
	{
	name = "triple",
	description = [[triple, first byte x, second y, third z]],
	vertex = pc_triple_v,
	translate = pc_xl_triple,
	fragment = pc_lut_f,
	lookup = true,
	}
};

shaders_1dplot = {
	{
	name = "histo_plot",
	description = "simple b/w histogram",
	vertex = nil,
	fragment = [[
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
	]];
	}
};

shader_groups = {
	shaders_2dview,
	shaders_3dview_plane,
	shaders_3dview_pcloud,
	shaders_1dplot
};

--
-- precompile all
--
for k,v in ipairs(shader_groups) do
	for j,m in ipairs(v) do
		m.shid = build_shader(m.vertex, m.fragment, m.name);
		shader_uniform(m.shid, "highlight_range", "ff", NOPERSIST, -1.0, -1.0);
	end
end

build_shader(nil, [[
	uniform sampler2D map_tu0;
	varying vec2 texco;

	void main(){
		vec4 col = texture2D(map_tu0, texco);
		gl_FragColor = vec4(col.r, 1.0 - col.g, col.b, 1.0);
	}

]], "invert_green");

function shader_pcloud_pointsz(val)
	for k,v in ipairs(shaders_3dview_pcloud) do
		shader_uniform(v.shid, "point_sz", "f", PERSIST, val);
	end
end

function shader_update_range(wnd, low, high)
	low = low < 0.0 and 0.0 or low;
	high = high > 1.0 and 1.0 or high;

	for k,v in ipairs(shader_groups) do
		for j,j in ipairs(v) do
			shader_uniform(j.shid, "highlight_range", "ff", NOPERSIST, low, high);
		end
	end
end

function switch_shader(wnd, target, shtbl)
	if (shtbl == nil) then
		shtbl = wnd.shtbl;
	end

	if (target == nil) then
		target = wnd.model ~= nil and wnd.model or wnd.canvas;
	end

	image_shader(target, shtbl.shid);

-- always drop current frameset
	image_framesetsize(target, 1);
	wnd.shtbl = shtbl;

	if (shtbl.lookup) then
		local dst = global_lookup;

		if (type(shtbl.lookup) == "string") then
			shtbl.lookup = load_image_asych(shtbl.lookup);
		end

		if (type(shtbl.lookup) == "number") then
			dst = shtbl.lookup;
		end

		image_framesetsize(target, 2, FRAMESET_MULTITEXTURE);
		set_image_as_frame(target, dst, 1);
		wnd.active_lut = dst;
	end

	if (shtbl.uniforms) then
		for k,v in pairs(shtbl.uniforms) do
			shader_uniform(shtbl.shid, k, v.typev, NOPERSIST, unpack(v.values));
		end
	end

	local msg = render_text(menu_text_fontstr .. "Shader: " .. shtbl.name);
	wnd:set_message(msg, DEFAULT_TIMEOUT);

-- repeat the process if there is a fullscreen window and that the
-- window does not have a 3d model (as the shader is applied to the model
-- when drawing the FBO)
	if (wnd.wm.fullscreen == wnd and wnd.wm.fullscreen.model == nil) then
		image_shader(wnd.wm.fullscreen_vid, shtbl.shid);
		image_framesetsize(wnd.wm.fullscreen_vid, 1);

		if (shtbl.lookup) then
			image_framesetsize(wnd.wm.fullscreen_vid, 2, FRAMESET_MULTITEXTURE);
			set_image_as_frame(wnd.wm.fullscreen_vid, global_lookup, 1);
		end
	end
end

function update_highlight_shader(values)
	local vtbl = {};
	for i=1,16 do
		vtbl[i] = values[i] ~= nil and values[i] or -1;
	end

	shaders_2dview[2].uniforms.lut.values = vtbl;
	shader_uniform(shaders_2dview[2].shid, "lut",
		shaders_2dview[2].uniforms.lut.typev, NOPERSIST, unpack(vtbl));
end

local function load_new_lut(wnd, val, id)
	local newimg = load_image(val, asynch);

	if (valid_vid(newimg) and valid_vid(global_lookup)) then
		delete_image(global_lookup);
		global_lookup = newimg;
	end

	switch_shader(wnd);
end

function shader_menu(group, target)
	local rt = {
	{
		label = "Lookup Texture...",
		submenu = function()
			local res = glob_resource("color_lut/*.png");
			if (res == nil or #res == 0) then
				return {
					label = "No results matching: color_lut/*.png",
					handler = function() end
				};
			else
				local rt = {};
				for k,v in ipairs(res) do
					table.insert(rt, {
						label = v,
						value = "color_lut/" .. v
					});
					rt.handler = load_new_lut;
				end
				return rt;
			end
		end
	}
	};

	for k, v in ipairs(group) do
		table.insert(rt, {
			label = v.name,
			name = v.name,
			value = v.shid
		});
	end

	rt.handler = function(wnd, value)
		image_shader(wnd[target], value);
	end

	return rt;
end
