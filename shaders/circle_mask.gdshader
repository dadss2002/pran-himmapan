shader_type canvas_item;
// Shows only the inscribed circle of the texture (round ROV-style buttons).
uniform float dim : hint_range(0.0, 1.0) = 0.0;   // 0 = normal, 1 = fully greyed

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	if (distance(UV, vec2(0.5)) > 0.5) discard;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114)) * 0.55;
	COLOR = vec4(mix(c.rgb, vec3(g), dim), c.a * 0.92);
}
