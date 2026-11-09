shader_type canvas_item;
// Tints the sprite toward flash_color by flash_amount (hit feedback). Alpha is kept.
// Task 3f (owner 2026-11-09): a status tint under the flash: the colours go toward tint_color by tint_amount,
// keeping the sprite's light and shade (tint_color scaled by TINT_BASE + TINT_GAIN x the texel's brightness), so a
// burning monster reads red-orange and a frozen one ice-blue, the dark ones (boar) too. Dark outlines are kept: the
// tint is weighted by smoothstep(OUTLINE_LO, OUTLINE_HI, texel luma), so pixels darker than OUTLINE_LO are untouched.
// B23 (fixed, owner 2026-11-09 "แก้เป็นสีจริง"): in Godot 4 COLOR here already holds texture(TEXTURE, UV) x the vertex
// colour (modulate); this shader used to multiply by the texture again, drawing colour and alpha squared. It reads
// COLOR alone now, so sprites show their true PixelLab colours.
// Wolf.tint_preview mirrors this on the CPU with the same numbers and formula (tests/test_pixelfx.gd checks the consts
// and this fragment() body; tests/screenshots_m5a_pixelfx.gd compares the GPU result with the mirror).
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;

const float TINT_BASE = 0.65;
const float TINT_GAIN = 0.8;
const float OUTLINE_LO = 0.06;
const float OUTLINE_HI = 0.16;

void fragment() {
	vec4 c = COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float k = tint_amount * smoothstep(OUTLINE_LO, OUTLINE_HI, l);
	vec3 t = mix(c.rgb, min(tint_color.rgb * (TINT_BASE + TINT_GAIN * l), vec3(1.0)), k);
	COLOR = vec4(mix(t, flash_color.rgb, flash_amount), c.a);
}
