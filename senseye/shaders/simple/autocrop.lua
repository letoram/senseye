local bgc = gconfig_get("term_bgcol");

return {
	version = 1,
	label = "Autocrop",
	filter = "none",
-- needed to have txcos that is relative to orig. size
	uniforms = {
		color = {
			label = "Color",
			utype = "ffff",
			default = {bgc[1], bgc[2], bgc[3], gconfig_get("term_opa")}
		},
	},
	frag =
[[
uniform sampler2D map_tu0;
uniform float obj_opacity;
uniform vec4 color;
varying vec2 texco;

uniform vec2 obj_input_sz;
uniform vec2 obj_output_sz;

void main()
{
	vec2 scalef = obj_output_sz / obj_input_sz;
	vec2 sco = texco * scalef;

	if (sco.s > 1.0 || sco.t > 1.0)
		gl_FragColor = vec4(color.r, color.g, color.b,
			color.a * obj_opacity);
	else{
		vec4 col = texture2D(map_tu0, sco);
		gl_FragColor = vec4(
			col.r, col.g, col.b, obj_opacity * col.a);
	}
}
]]
};
