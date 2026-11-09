shader_type canvas_item;
// Tints the sprite toward flash_color by flash_amount (hit feedback). Alpha is kept.
// Task 3f (owner 2026-11-09): a status tint under the flash: the colours go toward tint_color by tint_amount,
// keeping the sprite's light and shade (tint_color scaled by the pixel's brightness), so a burning monster reads
// red-orange and a frozen one ice-blue.
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 t = mix(c.rgb, min(tint_color.rgb * (0.7 + l), vec3(1.0)), tint_amount);
	COLOR = vec4(mix(t, flash_color.rgb, flash_amount), c.a);
}
