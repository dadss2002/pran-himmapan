shader_type canvas_item;
// M5b Task 8 review (owner 2026-11-11, "ย้อมสีประกายตีแทน"): recolours a sprite to one colour by brightness, so the
// orange hit spark reads red (ศรกระหายเลือด) or dark purple (ศรราหูอมจันทร์). The spark's brightest palette colour
// (#ffc23d, luminance ~0.77) maps to about the tint; darker pixels to a darker tint. Alpha is kept. COLOR on entry is
// already the texture × the vertex colour / modulate (Godot 4), so it is read once and replaced.
// Used by ComboFx.recolor (one material per tint).
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 c = COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(tint.rgb * min(l / 0.8, 1.0), c.a);
}
