shader_type canvas_item;
// Sharp upscale for pixel art at a non-whole scale (owner 2026-11-07: "ภาพยังเหมือนไม่ชัด"):
// inside each source pixel the colour is flat, and only the one-screen-pixel seam between two
// source pixels is blended, so every pixel looks the same size with no blur. Needs linear filtering.
uniform vec2 src_size = vec2(180.0, 384.0);

void fragment() {
	vec2 tex = UV * src_size;
	vec2 seam = floor(tex + 0.5);
	vec2 dudv = max(fwidth(tex), vec2(1e-5));
	tex = seam + clamp((tex - seam) / dudv, -0.5, 0.5);
	COLOR = texture(TEXTURE, tex / src_size);
}
