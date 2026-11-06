class_name DamageNumber
extends Label
## Floating damage text: rises 20 px and fades over 0.6 s. Crits are gold with "!".

const CRIT_COLOR := Color("#ffd36a")
const HURT_COLOR := Color("#ff8a7a")
const RISE := 20.0
const LIFE := 0.6

static func make(amount: int, crit: bool, hurt := false) -> DamageNumber:
	var d := DamageNumber.new()
	d.text = str(amount) + ("!" if crit else "")
	var c := CRIT_COLOR if crit else (HURT_COLOR if hurt else Color.WHITE)
	d.add_theme_color_override("font_color", c)
	d.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	d.add_theme_constant_override("outline_size", 3)
	d.add_theme_font_size_override("font_size", 15 if crit else 12)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.size = Vector2(40, 16)
	d.z_index = 50
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

func _ready() -> void:
	position -= Vector2(20, 8)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "position:y", position.y - RISE, LIFE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, LIFE).set_delay(LIFE * 0.4)
	t.chain().tween_callback(queue_free)
