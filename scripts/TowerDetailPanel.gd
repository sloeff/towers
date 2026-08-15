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
signal upgrade_pressed(tower: Node2D)
signal transform_pressed(tower: Node2D, combo_id: int)
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
var _tier: Label
var _level: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _damage: Label
var _range: Label
var _fire_rate: Label
var _kills: Label
## One Transform button per available combo, rebuilt only when the set of
## available combos changes (a tower can have several owned partners). Keyed by
## combo_id so prices refresh each frame without recreating buttons.
var _transform_box: VBoxContainer
var _transform_buttons: Dictionary = {}
var _transform_combo_ids: Array[int] = []
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
	close_button.custom_minimum_size = Vector2(40.0, 40.0)  # finger-sized tap target
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(close_button)

	# Tier (the paid upgrade axis) sits above the XP level row, which is the
	# automatic axis - two separate progressions, kept visually distinct.
	_tier = _add_stat(box)

	_build_potion_effects(box)

	_build_xp_row(box)

	_damage = _add_stat(box)
	_range = _add_stat(box)
	_fire_rate = _add_stat(box)
	_kills = _add_stat(box)

	_build_item_slots(box)

	# Transform is a promoted, distinct action (a placed basic tower becoming its
	# combo). Each available combo gets its own full-width button, stacked in this
	# box above Upgrade/Sell and rebuilt on demand in _refresh_transform_buttons.
	_transform_box = VBoxContainer.new()
	_transform_box.add_theme_constant_override("separation", 6)
	box.add_child(_transform_box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)

	_upgrade_button = Button.new()
	_upgrade_button.text = "Upgrade"
	_upgrade_button.focus_mode = Control.FOCUS_NONE
	_upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	buttons.add_child(_upgrade_button)

	_sell_button = Button.new()
	_sell_button.focus_mode = Control.FOCUS_NONE
	_sell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_button.pressed.connect(_on_sell_pressed)
	buttons.add_child(_sell_button)


## Active potion effects applied to the tower, shown as coloured badges just
## below the name. These are dummy placeholders - the potion/modifier system in
## DESIGN_DOC's "Potions" isn't built yet, so a fixed sample is drawn for layout.
func _build_potion_effects(box: VBoxContainer) -> void:
	var effects := [
		{"label": "GF", "color": Color(0.85, 0.68, 0.18), "name": "Gold Find"},
		{"label": "DMG", "color": Color(0.82, 0.29, 0.22), "name": "Damage Up"},
		{"label": "SLW", "color": Color(0.27, 0.53, 0.83), "name": "Slow"},
	]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	for effect in effects:
		var color: Color = effect["color"]
		var badge := Panel.new()
		badge.custom_minimum_size = Vector2(34.0, 34.0)
		badge.tooltip_text = "%s (placeholder)" % effect["name"]

		var style := StyleBoxFlat.new()
		style.bg_color = color.darkened(0.15)
		style.set_border_width_all(1)
		style.border_color = color.lightened(0.3)
		style.set_corner_radius_all(3)
		badge.add_theme_stylebox_override("panel", style)

		var text := Label.new()
		text.text = effect["label"]
		text.add_theme_font_size_override("font_size", 11)
		text.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.add_child(text)

		row.add_child(badge)


## Level readout + progress toward the next level, just below the name. Empty
## until the leveling system fills it in (see Tower's XP placeholder).
func _build_xp_row(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	_level = Label.new()
	_level.add_theme_font_size_override("font_size", 14)
	row.add_child(_level)

	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	# Tall enough to hold the XP text drawn inside it.
	_xp_bar.custom_minimum_size = Vector2(0.0, 18.0)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Outline the bar so the empty track reads as a bar, not a gap.
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.05, 0.06, 0.08, 0.9)
	bar_bg.set_border_width_all(1)
	bar_bg.border_color = Color(1.0, 1.0, 1.0, 0.5)
	bar_bg.set_corner_radius_all(2)
	_xp_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.42, 0.78, 1.0, 0.95)
	bar_fill.set_corner_radius_all(2)
	_xp_bar.add_theme_stylebox_override("fill", bar_fill)

	row.add_child(_xp_bar)

	# Draw the "N / M XP" text centred inside the bar rather than below it.
	_xp_label = Label.new()
	_xp_label.add_theme_font_size_override("font_size", 11)
	_xp_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xp_bar.add_child(_xp_label)


## Three greyed-out placeholder item slots. Wiring them up is future work (the
## equippable items in DESIGN_DOC's "Items"); for now they just mark the space.
func _build_item_slots(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(0.16, 0.17, 0.2, 0.9)
	slot_style.set_border_width_all(1)
	slot_style.border_color = Color(1.0, 1.0, 1.0, 0.18)
	slot_style.set_corner_radius_all(3)

	for i in 3:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(30.0, 30.0)
		slot.tooltip_text = "Item slot (coming soon)"
		slot.add_theme_stylebox_override("panel", slot_style)
		slot.modulate = Color(1.0, 1.0, 1.0, 0.5)
		row.add_child(slot)


func _add_stat(box: VBoxContainer) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 16)
	box.add_child(label)
	return label


## Populate for `tower` and show. The fixed bits (name, range, sell value) are
## set once here; the level-scaled bits refresh every frame in _refresh_dynamic.
func show_for(tower: Node2D) -> void:
	_tower = tower
	_title.text = tower.display_name() if tower.is_combo else "%s Tower" % ElementTypes.element_name(tower.element)
	_title.add_theme_color_override("font_color",
		tower.display_color() if tower.is_combo else ElementTypes.text_color_of(tower.element))
	_range.text = "Range: %s" % tower.range_radius
	_sell_button.text = "Sell  +%dg" % tower.sell_value()
	_refresh_dynamic()
	visible = true
	reset_size()
	_reposition()


## Level, XP bar and the level-scaled stats - refreshed each frame so the panel
## tracks XP gained and level-ups live while it's open.
func _refresh_dynamic() -> void:
	_tier.text = "Tier %d" % _tower.tier
	_level.text = "Lv %d" % _tower.level
	# An aura tower (Quicksand) has no per-shot damage or fire rate; it deals a
	# continuous tick, so it reads its aura's damage-per-second instead of 0.0.
	if _tower.is_combo and Combos.DATA[_tower.combo_id].get("firing_mode", "projectile") == "aura":
		# _tower.damage is aura_dps scaled by tier and XP, so this tracks upgrades.
		_damage.text = "Damage: %.1f/s (aura)" % _tower.damage
		_fire_rate.text = "Slow: %d%%" % int(round((1.0 - Combos.DATA[_tower.combo_id].get("slow_factor", 1.0)) * 100.0))
	else:
		_damage.text = "Damage: %.1f" % _tower.damage
		_fire_rate.text = "Fire rate: %.2f/s" % _tower.fire_rate
	_kills.text = "Kills: %d" % _tower.kills
	_refresh_upgrade_button()
	_refresh_transform_buttons()
	if _tower.is_at_max_level():
		_xp_bar.max_value = 1.0
		_xp_bar.value = 1.0
		_xp_label.text = "MAX"
	else:
		var needed: int = _tower.experience_to_next_level()
		_xp_bar.max_value = needed
		_xp_bar.value = _tower.experience
		_xp_label.text = "%d / %d XP" % [_tower.experience, needed]


## The Upgrade button offers the next tier only when the tower's element has
## been advanced past it (via the every-5-rounds choice). It goes disabled - but
## still shows the price - when the player can't afford it, and reads as maxed
## when the tower already matches its element's tier.
func _refresh_upgrade_button() -> void:
	var element_tier: int = GameManager.available_tier(_tower)
	if _tower.tier < element_tier:
		var upgrade_cost: int = _tower.upgrade_cost()
		var affordable: bool = GameManager.gold >= upgrade_cost
		_upgrade_button.text = "Upgrade → T%d  -%dg" % [_tower.tier + 1, upgrade_cost]
		_upgrade_button.disabled = not affordable
		_upgrade_button.tooltip_text = "" if affordable else "Not enough gold"
	else:
		_upgrade_button.text = "Tier %d (max)" % _tower.tier
		_upgrade_button.disabled = true
		_upgrade_button.tooltip_text = "Advance this element's tier to upgrade further"


## Offer a "Transform → [Combo]" button for each combo a basic tower can form
## (one per owned partner element); each is priced-but-disabled when the player
## can't afford it. Nothing shows for a combo, which never re-transforms. The
## buttons are rebuilt only when the available set changes; prices refresh here
## every frame.
func _refresh_transform_buttons() -> void:
	var combos: Array[int] = GameManager.available_combos_for(_tower)
	if combos != _transform_combo_ids:
		_rebuild_transform_buttons(combos)
	for combo_id in _transform_combo_ids:
		var transform_cost: int = Combos.DATA[combo_id]["transform_cost"]
		var affordable: bool = GameManager.gold >= transform_cost
		var button: Button = _transform_buttons[combo_id]
		button.text = "Transform → %s  −%dg" % [Combos.name_of(combo_id), transform_cost]
		button.disabled = not affordable
		button.tooltip_text = "" if affordable else "Not enough gold"


func _rebuild_transform_buttons(combos: Array[int]) -> void:
	for child in _transform_box.get_children():
		child.queue_free()
	_transform_buttons.clear()
	# available_combos_for returns a fresh array each call and we never mutate it,
	# so hold the reference directly (no duplicate needed).
	_transform_combo_ids = combos
	for combo_id in combos:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_transform_pressed.bind(combo_id))
		_transform_box.add_child(button)
		_transform_buttons[combo_id] = button


func hide_panel() -> void:
	_tower = null
	visible = false


func _on_sell_pressed() -> void:
	if is_instance_valid(_tower):
		sell_pressed.emit(_tower)


func _on_upgrade_pressed() -> void:
	if is_instance_valid(_tower):
		upgrade_pressed.emit(_tower)


func _on_transform_pressed(combo_id: int) -> void:
	if is_instance_valid(_tower):
		transform_pressed.emit(_tower, combo_id)


func _process(_delta: float) -> void:
	if not visible:
		return
	# The tower can be freed out from under us (sold elsewhere, or a restart).
	if not is_instance_valid(_tower):
		hide_panel()
		return
	_refresh_dynamic()
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
