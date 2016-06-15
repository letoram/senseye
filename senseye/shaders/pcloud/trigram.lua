return {
	label = "Trigram",
	version = 1,
	vert =
[[
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
]],
	frag =
[[
	uniform sampler2D map_tu0;
	uniform sampler2D map_tu1;

	varying vec2 texco;
	varying float intens;

	void main(){
		vec4 col = texture2D(map_tu1, vec2(intens, 0.0));
		gl_FragColor = vec4(col.rgb, 1.0);
	}
]],
	uniforms = {
	}
};
