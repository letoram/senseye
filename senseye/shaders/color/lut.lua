return {
	label = "Lookup-Texture",
	version = 1,
	frag =
[[
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
	uniforms = {
	}
};
