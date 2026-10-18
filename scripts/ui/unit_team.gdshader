shader_type canvas_item;
uniform vec4 team_color : source_color;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float shade = max(max(tex.r, tex.g), tex.b);
	COLOR = vec4(team_color.rgb * (0.55 + 0.45 * shade), tex.a);
}
