extends PanelContainer
## Floating "Build here" confirm shown while a tower placement is pending (after
## the player clicks/taps a buildable tile, before it's committed). Like
## TowerDetailPanel, it lives on the HUD CanvasLayer and re-anchors to the target
## tile every frame via the world canvas transform, so it tracks pan and zoom.

signal confirmed
signal cancelled

const SCREEN_MARGIN := 8.0
## Screen-space nudge from the tile's world point to the panel's top-left.
const SCREEN_OFFSET := Vector2(18.0, -18.0)

var _world_pos: Vector2 = Vector2.ZERO
var _build_button: Button


func _ready() -> void:
	visible = false
	# Consume clicks/taps on the prompt so they don't fall through to the map.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.94)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 1.0, 1.0, 0.15)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	# Tall enough for a finger (>= 44px tap target).
	_build_button = Button.new()
	_build_button.focus_mode = Control.FOCUS_NONE
	_build_button.custom_minimum_size = Vector2(0.0, 44.0)
	_build_button.pressed.connect(func() -> void: confirmed.emit())
	row.add_child(_build_button)

	var cancel := Button.new()
	cancel.text = "x"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(44.0, 44.0)
	cancel.pressed.connect(func() -> void: cancelled.emit())
	row.add_child(cancel)


func show_at(world_pos: Vector2, cost: int) -> void:
	_world_pos = world_pos
	_build_button.text = "Build  %d g" % cost
	visible = true
	reset_size()
	_reposition()


func hide_prompt() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible:
		_reposition()


func _reposition() -> void:
	var screen: Vector2 = get_viewport().get_canvas_transform() * _world_pos
	var target := screen + SCREEN_OFFSET
	var bounds: Vector2 = get_viewport_rect().size
	target.x = clampf(target.x, SCREEN_MARGIN, maxf(SCREEN_MARGIN, bounds.x - size.x - SCREEN_MARGIN))
	target.y = clampf(target.y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, bounds.y - size.y - SCREEN_MARGIN))
	position = target
