return {
	label = "Red-Green Split",
	version = 1,
	frag =
[[
	uniform sampler2D map_tu0;
	varying vec2 texco;

	void main()
	{
		vec3 col = texture2D(map_tu0, texco).rgb;
		float intens = (col.r + col.g + col.b) / 3.0;
		gl_FragColor = vec4(intens * 2.0, (intens - 0.5) * 2.0, 0.0, 1.0);
	}
]],
	uniforms = {
	}
};
