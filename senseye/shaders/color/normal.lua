return {
	label = "Normal",
	version = 1,
	frag =
[[
	uniform sampler2D map_tu0;
	varying vec2 texco;

	void main()
	{
		vec3 col = texture2D(map_tu0, texco).rgb;
		gl_FragColor = vec4(col.rgb, 1.0);
	}
]],
	uniforms = {
	}
};
