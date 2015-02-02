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
-- The system used here is too rigid and should be reworked / redesigned.
-- The actual shader code should be dynamically generated and let the
-- user specify certain parameters:
--  . data mapping function (vertex stage)
--  . coloring function (fragment stage)
--  . optional lookup table (fragment stage)
--  . highlight value / range (fragment stage)
--
-- then cache common combinations and build those on launch (to lessen
-- the embarassing stalls imposed by shader compilation on some drivers).
--
shaders_2dview = {
	{
		name = "Normal",
		fragment = [[
			uniform sampler2D map_tu0;
			uniform vec3 col_highlight;
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
	{
		name = "Histogram Highlight",
		vertex = nil,
		fragment = [[
			uniform sampler2D map_tu0;
			uniform vec2 highlight_range;
			varying vec2 texco;

			void main()
			{
				vec4 col = texture2D(map_tu0, texco);
				float intens = (col.r + col.g + col.b) / 3.0;
				if (highlight_range.x < 0.0 || intens < highlight_range.x ||
					intens > highlight_range.y)
					gl_FragColor = vec4(0.5 * intens, 0.5 * intens, 0.5 * intens, 1.0);
				else
					gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0);
			}
		]],
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
		name = "Alpha Lookup Table",
		description = "Lookup Table and Alpha value determines color",
		vertex = nil,
		fragment = [[
			uniform sampler2D map_tu0;
			uniform sampler2D map_tu1;

			varying vec2 texco;

			void main()
			{
				float av = texture2D(map_tu0, texco).a;
	 			vec3 col = texture2D(map_tu1, vec2(av, 0.0)).rgb;
				gl_FragColor = vec4(col.r, col.g, col.b, 1.0);
			}
		]],
		lookup = "palettes/gradients.png"
	},
	{
		name = "Alpha Gradient",
		description = "Green Alpha Channel",
		vertex = nil,
		fragment = [[
		uniform sampler2D map_tu0;
		varying vec2 texco;
		void main()
		{
			float av = texture2D(map_tu0, texco).a;
			gl_FragColor = vec4(0, av, 0, 1.0);
		}
		]]
	},
	{
		name = "Red Entropy, Green Intensity",
		description = "maps intensity into green channel, alpha into red",
		vertex = nil,
		fragment = [[
		uniform sampler2D map_tu0;
		varying vec2 texco;

		void main()
		{
			vec4 col = texture2D(map_tu0, texco);
			float intens = (col.r + col.g + col.b) / 3.0;
			gl_FragColor = vec4(col.a, intens, 0.0, 1.0);
		}
	]]}
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
	uniform mat4 modelview;
	uniform mat4 projection;
	uniform float point_sz;

	attribute vec2 texcoord;
	attribute vec4 vertex;

	varying vec2 texco;

	void main(){
		vec4 dv   = texture2D(map_tu0, texcoord);
		vec4 vert = vertex;
		vert.x    = 2.0 * dv.r - 1.0;
		vert.y    = 2.0 * dv.g - 1.0;
		vert.z    = 2.0 * dv.b - 1.0;
		gl_Position = (projection * modelview) * vert;
		gl_PointSize = point_sz;
		texco = texcoord;
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

	void main(){
		vec4 dv   = texture2D(map_tu0, texcoord);
		vec4 vert = vertex;
		vert.x    = (2.0 * texcoord.s) - 1.0;
		vert.y    = (2.0 * texcoord.t) - 1.0;
		vert.z    = (2.0 * (dv.r + dv.g + dv.b) / 3.0) - 1.0;
		gl_Position = (projection * modelview) * vert;
		gl_PointSize = point_sz;
		texco = texcoord;
	}
]];

shaders_3dview_pcloud = {
	{
	name = "Z Displace",
	description = [[displacement, intensity determines z- val]],
	fragment = [[
		uniform sampler2D map_tu0;
		varying vec2 texco;
		void main(){
			vec4 col = texture2D(map_tu0, texco);
			float intens = (col.r + col.g + col.b) / 3.0;
			gl_FragColor = vec4(col.a, 0.0, intens, 1.0);
		}
	]],
	vertex = pc_disp_v
	},
	{
	name = "Z Displace LUT",
	description = [[displacement, alpha LUT sets color]],
	fragment = [[
		uniform sampler2D map_tu0;
		uniform sampler2D map_tu1;
		varying vec2 texco;
		void main(){
			float av = texture2D(map_tu0, texco).a;
 			vec3 col = texture2D(map_tu1, vec2(av, 0.0)).rgb;
			gl_FragColor = vec4(col.r, col.g, col.b, 1.0);
		}
	]],
	lookup = "palettes/gradients.png",
	vertex = pc_disp_v
	},
	{
	name = "triple",
	description = [[triple, first byte x, second y, third z]],
	vertex = pc_triple_v,
	fragment = [[
		uniform sampler2D map_tu0;
		varying vec2 texco;

		void main(){
			vec4 col = texture2D(map_tu0, texco);
			float intens = (col.r + col.g + col.b) / 3.0;
			gl_FragColor = vec4(intens, col.a, 0.0, 1.0);
		}
	]],
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
		if (m.lookup) then
			local n = m.lookup;
			m.lookup = load_image(m.lookup);
			image_texfilter(m.lookup, FILTER_NONE);
			image_tracetag(m.lookup, "LUT:" .. n);
		end
	end
end

function shader_pcloud_pointsz(val)
	for k,v in ipairs(shaders_3dview_pcloud) do
		shader_uniform(v.shid, "point_sz", "f", PERSIST, val);
	end
end

function shader_update_range(wnd, low, high)
	for k,v in ipairs(shader_groups) do
		for j,j in ipairs(v) do
			shader_uniform(j.shid, "highlight_range", "ff", NOPERSIST, low, high);
		end
	end
end

function switch_shader(wnd, target, shtbl)
	image_shader(target, shtbl.shid);

-- always drop current frameset
	image_framesetsize(target, 1);

	if (shtbl.lookup) then
		image_framesetsize(target, 2, FRAMESET_MULTITEXTURE);
		set_image_as_frame(target, shtbl.lookup, 1);
	end

	local msg = render_text(menu_text_fontstr .. "Shader: " .. shtbl.name);
	wnd:set_message(msg, 100);

-- repeat the process if there is a fullscreen window and that the
-- window does not have a 3d model (as the shader is applied to the model
-- when drawing the FBO)
	if (wnd.wm.fullscreen == wnd and wnd.wm.fullscreen.model == nil) then
		image_shader(wnd.wm.fullscreen_vid, shtbl.shid);
		image_framesetsize(wnd.wm.fullscreen_vid, 1);

		if (shtbl.lookup) then
			image_framesetsize(wnd.wm.fullscreen_vid, 2, FRAMESET_MULTITEXTURE);
			set_image_as_frame(wnd.wm.fullscreen_vid, shtbl.lookup, 1);
		end
	end
end

function shader_menu(group, target)
	local rt = {
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
