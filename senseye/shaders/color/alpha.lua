return {
	label = "Alpha",
	version = 1,
	frag =
[[
	uniform sampler2D map_tu0;
	varying vec2 texco;

	void main()
	{
		float col = texture2D(map_tu0, texco).a;
		gl_FragColor = vec4(0, col, 0, 1.0);
	}
]],
	uniforms = {
	}
};
