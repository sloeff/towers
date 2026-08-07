extends Node2D
## A short-lived number that drifts upward and fades out - the gold reward shown
## over an enemy as it dies. Spawned into Entities by whoever it belongs to,
## because the source usually frees itself in the same frame.
##
## It rides above the y-sorted map on its own z_index instead of taking part in
## the depth sort, so terrain in front of the kill can never swallow it. That
## also means the node never moves: the rise is drawn as an offset, so there is
## no sort key to keep in step with the pixels (compare Enemy, where there is).

## Seconds the number stays on screen. Exported so it can be tuned here or in
## the inspector; setup() takes an override for a one-off.
@export var lifetime: float = 0.5
## How far the number drifts up over its lifetime, in pixels.
@export var rise_pixels: float = 26.0
@export var font_size: int = 16

const GOLD_COLOR := Color(1.0, 0.84, 0.35)
const Z_ABOVE_MAP := 100
## Fraction of the lifetime spent at full opacity before the fade starts.
const HOLD_FRACTION := 0.4

var text: String = ""
var color: Color = GOLD_COLOR

var _elapsed: float = 0.0


func _ready() -> void:
	z_index = Z_ABOVE_MAP


## Call after adding to the tree and positioning, like Tower does its
## projectiles. `seconds` overrides `lifetime` when positive.
func setup(popup_text: String, popup_color: Color = GOLD_COLOR, seconds: float = 0.0) -> void:
	text = popup_text
	color = popup_color
	if seconds > 0.0:
		lifetime = seconds
	queue_redraw()


func _process(delta: float) -> void:
	if lifetime <= 0.0:
		queue_free()
		return
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_elapsed / lifetime, 0.0, 1.0)
	# Ease out: the number leaps away from the kill, then settles as it fades.
	var rise := rise_pixels * (1.0 - pow(1.0 - t, 2.0))
	var alpha := 1.0
	if t > HOLD_FRACTION:
		alpha = 1.0 - (t - HOLD_FRACTION) / (1.0 - HOLD_FRACTION)

	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(-width * 0.5, -rise)
	# Outlined, because the map runs from pale sand to dark cliff face.
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4,
		Color(0.0, 0.0, 0.0, alpha * 0.7))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(color, alpha))
