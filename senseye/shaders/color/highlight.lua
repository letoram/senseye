return {
	label = "Highlight",
	version = 1,
	frag =
[[
	uniform sampler2D map_tu0;
	uniform sampler2D map_tu1;
	uniform vec2 highlight_range;
	uniform mat4 lut;

	varying vec2 texco;

	void main()
	{
		vec4 col = texture2D(map_tu0, texco);
		float intens = (col.r + col.g + col.b) / 3.0;
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
			else
				gl_FragColor = vevc4(0.0, 1.0, 0.0, 1.0);
	}
]],
	uniforms = {
		lut = {
			typev = "ffffffffffffffff",
			values = {-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}
		};
	}
};
