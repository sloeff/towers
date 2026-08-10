extends PanelContainer
## Floating popover for the selected tower: its combat stats, a Sell button, and
## a disabled Upgrade button (the token/gold upgrade economy in DESIGN_DOC
## section 8 isn't built yet). Lives on the HUD CanvasLayer in screen space and
## re-anchors to the tower it describes every frame, so it tracks camera pan and
## zoom. Built in code, matching how the build bar generates its buttons.
##
## Future: an active-buffs section and item slots (the modifier system in
## DESIGN_DOC's "Items") drop into the same vertical stack.

signal sell_pressed(tower: Node2D)
signal close_pressed

## Keep the whole panel this far inside the viewport edges.
const SCREEN_MARGIN := 8.0
## Screen-space nudge from the tower's anchor point to the panel's top-left, so
## the popover sits up and to the right of the tower rather than over it.
const SCREEN_OFFSET := Vector2(18.0, -30.0)
## World-space point on the tower to anchor to - roughly its head.
const TOWER_ANCHOR := Vector2(0.0, -40.0)

var _tower: Node2D = null

var _title: Label
var _damage: Label
var _range: Label
var _fire_rate: Label
var _upgrade_button: Button
var _sell_button: Button


func _ready() -> void:
	visible = false
	# Clicks on the panel must not fall through to the map (which would place a
	# tower or deselect). A STOP-filtered Control on the CanvasLayer consumes
	# them before Main's _unhandled_input ever runs.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.94)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 1.0, 1.0, 0.15)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)

	var close_button := Button.new()
	close_button.text = "x"
	close_button.custom_minimum_size = Vector2(28.0, 28.0)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(close_button)

	_damage = _add_stat(box)
	_range = _add_stat(box)
	_fire_rate = _add_stat(box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)

	_upgrade_button = Button.new()
	_upgrade_button.text = "Upgrade"
	_upgrade_button.disabled = true
	_upgrade_button.tooltip_text = "Coming soon"
	_upgrade_button.focus_mode = Control.FOCUS_NONE
	_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_upgrade_button)

	_sell_button = Button.new()
	_sell_button.focus_mode = Control.FOCUS_NONE
	_sell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_button.pressed.connect(_on_sell_pressed)
	buttons.add_child(_sell_button)


func _add_stat(box: VBoxContainer) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 16)
	box.add_child(label)
	return label


## Populate for `tower` and show. Stats are the tower's current values; with no
## upgrade system yet they never change while the panel is open.
func show_for(tower: Node2D) -> void:
	_tower = tower
	_title.text = "%s Tower" % ElementTypes.element_name(tower.element)
	_title.add_theme_color_override("font_color", ElementTypes.text_color_of(tower.element))
	_damage.text = "Damage: %s" % tower.damage
	_range.text = "Range: %s" % tower.range_radius
	_fire_rate.text = "Fire rate: %s/s" % tower.fire_rate
	_sell_button.text = "Sell  +%dg" % tower.sell_value()
	visible = true
	reset_size()
	_reposition()


func hide_panel() -> void:
	_tower = null
	visible = false


func _on_sell_pressed() -> void:
	if is_instance_valid(_tower):
		sell_pressed.emit(_tower)


func _process(_delta: float) -> void:
	if not visible:
		return
	# The tower can be freed out from under us (sold elsewhere, or a restart).
	if not is_instance_valid(_tower):
		hide_panel()
		return
	_reposition()


## Map the tower's world anchor to screen space via the world canvas transform
## (driven by the Camera2D), then clamp so the whole panel stays on-screen.
func _reposition() -> void:
	var world: Vector2 = _tower.ground_position() + TOWER_ANCHOR
	var screen: Vector2 = get_viewport().get_canvas_transform() * world
	var target := screen + SCREEN_OFFSET
	var bounds: Vector2 = get_viewport_rect().size
	target.x = clampf(target.x, SCREEN_MARGIN, maxf(SCREEN_MARGIN, bounds.x - size.x - SCREEN_MARGIN))
	target.y = clampf(target.y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, bounds.y - size.y - SCREEN_MARGIN))
	position = target
