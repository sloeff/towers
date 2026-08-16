extends PanelContainer
## Floating popover for the selected tower: its combat stats, the loot applied to
## it, and the Upgrade / Transform / Sell actions. Lives on the HUD CanvasLayer
## in screen space and re-anchors to the tower it describes every frame, so it
## tracks camera pan and zoom. Built in code, matching how the build bar
## generates its buttons.
##
## Loot (DESIGN_DOC section 6) is applied from here, not from the bag: the
## player picks a tower first, then a potion or an item for it. This panel only
## emits the intent - Main performs it and moves the loot in or out of the
## Inventory.

signal sell_pressed(tower: Node2D)
signal upgrade_pressed(tower: Node2D)
signal transform_pressed(tower: Node2D, combo_id: int)
signal use_potion_pressed(tower: Node2D)
signal equip_item_pressed(tower: Node2D)
signal unequip_item_pressed(tower: Node2D, slot: int)
signal close_pressed

## Keep the whole panel this far inside the viewport edges.
const SCREEN_MARGIN := 8.0
## Screen-space nudge from the tower's anchor point to the panel's top-left, so
## the popover sits up and to the right of the tower rather than over it.
const SCREEN_OFFSET := Vector2(18.0, -30.0)
## World-space point on the tower to anchor to - roughly its head.
const TOWER_ANCHOR := Vector2(0.0, -40.0)
## Tint of an item slot with nothing in it.
const EMPTY_SLOT_COLOR := Color(0.55, 0.57, 0.62)

const TowerScript := preload("res://scripts/Tower.gd")

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
var _gold_find: Label
## One Transform button per available combo, rebuilt only when the set of
## available combos changes (a tower can have several owned partners). Keyed by
## combo_id so prices refresh each frame without recreating buttons.
var _transform_box: VBoxContainer
var _transform_buttons: Dictionary = {}
var _transform_combo_ids: Array[int] = []
var _upgrade_button: Button
var _sell_button: Button

## Loot widgets. The potion badges are rebuilt only when the tower's drunk-potion
## list changes, the item slots only when their contents change - both are
## refreshed every frame otherwise, so the cheap comparison guards the rebuild.
var _potion_row: HBoxContainer
var _potion_badge_ids: Array[int] = []
var _potion_button: Button
var _item_row: HBoxContainer
var _item_slots: Array[Button] = []
var _item_slot_ids: Array[int] = []


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
	_gold_find = _add_stat(box)
	_gold_find.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))

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


## Potions drunk by this tower, one badge each, plus the button that opens the
## bag filtered to potions. A potion is permanent, so a badge is a record, not a
## control - only the button is clickable.
func _build_potion_effects(box: VBoxContainer) -> void:
	_potion_row = HBoxContainer.new()
	_potion_row.add_theme_constant_override("separation", 6)
	box.add_child(_potion_row)

	_potion_button = Button.new()
	_potion_button.focus_mode = Control.FOCUS_NONE
	_potion_button.custom_minimum_size = Vector2(0.0, 36.0)
	_potion_button.pressed.connect(_on_use_potion_pressed)
	box.add_child(_potion_button)


## Rebuild the badge row when the tower's drunk potions change (and on a switch
## to a different tower). Repeats of the same potion collapse into one badge with
## a count, so a heavily dosed tower doesn't overflow the panel.
func _refresh_potion_badges() -> void:
	if _tower.potions_taken != _potion_badge_ids:
		_potion_badge_ids = _tower.potions_taken.duplicate()
		# Detach before freeing: queue_free lands at the end of the frame, so the
		# old badges would sit alongside the new ones until then.
		for child in _potion_row.get_children():
			_potion_row.remove_child(child)
			child.queue_free()
		var counts: Dictionary = {}
		for id in _potion_badge_ids:
			counts[id] = counts.get(id, 0) + 1
		for id in counts:
			_potion_row.add_child(_potion_badge(id, counts[id]))
	var held: int = Inventory.ids_of_kind(Loot.Kind.POTION).size()
	_potion_button.text = "Use potion" if held > 0 else "No potions"
	_potion_button.disabled = held == 0
	_potion_button.tooltip_text = "" if held > 0 else "Kill enemies to find potions"


func _potion_badge(id: int, count: int) -> Control:
	var color: Color = Loot.color_of(id)
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(34.0, 34.0)
	badge.tooltip_text = "%s%s - %s" % [
		Loot.name_of(id), "" if count == 1 else " x%d" % count, Loot.describe(id)]
	badge.add_theme_stylebox_override("panel", _slot_style(color))

	var text := Label.new()
	text.text = Loot.badge_of(id) if count == 1 else "%s%d" % [Loot.badge_of(id), count]
	text.add_theme_font_size_override("font_size", 11)
	text.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(text)
	return badge


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


## The tower's item slots (DESIGN_DOC's "Items"). Each is a button: empty opens
## the bag filtered to items, filled takes the item back off and returns it to
## the bag. Buttons rather than plain panels so a tap lands on something
## finger-sized and Godot handles the press states.
func _build_item_slots(box: VBoxContainer) -> void:
	_item_row = HBoxContainer.new()
	_item_row.add_theme_constant_override("separation", 6)
	box.add_child(_item_row)

	for i in TowerScript.MAX_ITEM_SLOTS:
		var slot := Button.new()
		slot.focus_mode = Control.FOCUS_NONE
		slot.custom_minimum_size = Vector2(40.0, 40.0)
		slot.add_theme_font_size_override("font_size", 12)
		slot.pressed.connect(_on_item_slot_pressed.bind(i))
		_item_row.add_child(slot)
		_item_slots.append(slot)


## Repaint the slots when their contents change. `_item_slot_ids` mirrors what is
## currently drawn (-1 = empty), so the common case costs one array compare.
func _refresh_item_slots() -> void:
	var current: Array[int] = []
	for i in TowerScript.MAX_ITEM_SLOTS:
		current.append(_tower.items[i] if i < _tower.items.size() else -1)
	var held: int = Inventory.ids_of_kind(Loot.Kind.ITEM).size()
	for i in TowerScript.MAX_ITEM_SLOTS:
		var slot: Button = _item_slots[i]
		# An empty slot is only useful when there is something to put in it, so it
		# goes disabled (but visible) with an empty bag - same rule as Use potion.
		slot.disabled = current[i] < 0 and held == 0
		# The tooltip tracks the bag, not just the slot's contents, so it refreshes
		# even when the styling below is skipped as unchanged.
		if current[i] < 0:
			slot.tooltip_text = "Equip an item" if held > 0 else "Kill enemies to find items"
		else:
			slot.tooltip_text = "%s - %s\nClick to unequip" % [
				Loot.name_of(current[i]), Loot.describe(current[i])]
		if current[i] == _item_slot_ids_at(i):
			continue
		if current[i] < 0:
			slot.text = "+"
			slot.add_theme_stylebox_override("normal", _slot_style(EMPTY_SLOT_COLOR))
			slot.add_theme_color_override("font_color", EMPTY_SLOT_COLOR)
		else:
			slot.text = Loot.badge_of(current[i])
			slot.add_theme_stylebox_override("normal", _slot_style(Loot.color_of(current[i])))
			slot.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	_item_slot_ids = current


## What slot `i` is currently drawn as, or -1 before the first refresh.
func _item_slot_ids_at(i: int) -> int:
	return _item_slot_ids[i] if i < _item_slot_ids.size() else -2


## Shared square style for potion badges and item slots, tinted by rarity (or
## grey for an empty slot) so the same loot reads the same everywhere.
func _slot_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.6)
	style.set_border_width_all(1)
	style.border_color = Color(color, 0.8)
	style.set_corner_radius_all(3)
	return style


func _on_use_potion_pressed() -> void:
	if is_instance_valid(_tower):
		use_potion_pressed.emit(_tower)


func _on_item_slot_pressed(slot: int) -> void:
	if not is_instance_valid(_tower):
		return
	if slot < _tower.items.size():
		unequip_item_pressed.emit(_tower, slot)
	else:
		equip_item_pressed.emit(_tower)


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
	# Range moves with loot (Farsight, Eagle Lens), so it refreshes here rather
	# than being set once in show_for.
	_range.text = "Range: %.0f" % _tower.range_radius
	_kills.text = "Kills: %d" % _tower.kills
	# Only worth a line once the tower actually has Gold Find on it.
	var gold_find: int = _tower.gold_find_bonus()
	_gold_find.visible = gold_find > 0
	_gold_find.text = "Gold find: +%dg per kill" % gold_find
	_refresh_potion_badges()
	_refresh_item_slots()
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
