extends Panel
## The bag: every potion and item dropped this run (DESIGN_DOC section 6). Opens
## full-screen over the board, like the element-select panel, because on a phone
## a floating list would be unreadable.
##
## Two modes:
##   BROWSE - opened from the HUD's Bag button. Read-only; loot is applied from a
##            tower, so the browse view just tells the player what they're
##            holding and points them at a tower.
##   PICK   - opened from the tower detail panel with a Loot.Kind filter. Picking
##            a row emits loot_picked and the caller (Main) applies it to the
##            tower it opened this for.
##
## Rows are generated from Inventory + Loot.DATA, so a new potion or item shows
## up here with no change to this file.

signal loot_picked(loot_id: int)
signal closed

enum Mode { BROWSE, PICK }

const CARD_BG := Color(0.11, 0.12, 0.16, 0.96)
const MUTED := Color(0.64, 0.67, 0.73)
const ROW_HEIGHT := 58.0
const BADGE_SIZE := 40.0
## The list scrolls past this height rather than pushing the close button off a
## short screen (set on the Scroll node in HUD.tscn).
const LIST_MAX_HEIGHT := 380.0

@onready var _title: Label = $Center/Box/TitleLabel
@onready var _subtitle: Label = $Center/Box/SubtitleLabel
@onready var _list: VBoxContainer = $Center/Box/Scroll/List
@onready var _close_button: Button = $Center/Box/CloseButton

var _mode: int = Mode.BROWSE
## Loot.Kind this view is limited to, or -1 for everything.
var _filter_kind: int = -1


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(_on_close_pressed)
	# Keep the list in step with drops landing while the bag is open, and with
	# the pick that just emptied a stack.
	Inventory.inventory_changed.connect(_on_inventory_changed)


## Read-only view of everything held.
func show_browse() -> void:
	_mode = Mode.BROWSE
	_filter_kind = -1
	_title.text = "Bag"
	_subtitle.text = "Select a tower, then use a potion or fill an item slot."
	_rebuild()
	visible = true


## Choose one piece of loot of `kind` to apply to the tower that opened this.
func show_pick(kind: int) -> void:
	_mode = Mode.PICK
	_filter_kind = kind
	if kind == Loot.Kind.POTION:
		_title.text = "Use a potion"
		_subtitle.text = "A potion is drunk once and can't be taken back off."
	else:
		_title.text = "Equip an item"
		_subtitle.text = "An item can be unequipped again from the tower's slot."
	_rebuild()
	visible = true


func hide_panel() -> void:
	visible = false


func _on_close_pressed() -> void:
	visible = false
	closed.emit()


func _on_inventory_changed() -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	# remove_child before queue_free: freeing is deferred to the end of the frame,
	# so leaving the old rows in would show the list doubled for one frame.
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var ids: Array[int] = Inventory.ids() if _filter_kind < 0 else Inventory.ids_of_kind(_filter_kind)
	if ids.is_empty():
		_list.add_child(_empty_notice())
		return
	for id in ids:
		_list.add_child(_build_row(id))


func _empty_notice() -> Control:
	var label := Label.new()
	label.text = "Nothing here yet - enemies drop loot when they die." if _filter_kind < 0 \
		else "No %s in the bag." % ("potions" if _filter_kind == Loot.Kind.POTION else "items")
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## One stack: rarity badge, name + effect, count, and (in pick mode) the button
## that spends it.
func _build_row(id: int) -> Control:
	var color: Color = Loot.color_of(id)

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.add_theme_stylebox_override("panel", _row_style(color))

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	row.add_child(margin)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	margin.add_child(line)

	line.add_child(_badge(id, color))

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 2)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text_box)

	var name_label := Label.new()
	name_label.text = "%s  x%d" % [Loot.name_of(id), Inventory.count(id)]
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", color)
	text_box.add_child(name_label)

	var effect_label := Label.new()
	effect_label.text = "%s  ·  %s" % [Loot.rarity_name(id), Loot.describe(id)]
	effect_label.add_theme_font_size_override("font_size", 13)
	effect_label.add_theme_color_override("font_color", MUTED)
	text_box.add_child(effect_label)

	if _mode == Mode.PICK:
		var button := Button.new()
		button.text = "Use" if Loot.is_potion(id) else "Equip"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(88.0, 40.0)  # finger-sized
		button.pressed.connect(_on_row_pressed.bind(id))
		line.add_child(button)

	return row


func _on_row_pressed(id: int) -> void:
	loot_picked.emit(id)


## The same square badge the tower detail panel draws, so a potion reads as the
## same object in the bag and on the tower.
func _badge(id: int, color: Color) -> Control:
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.55)
	style.set_border_width_all(1)
	style.border_color = color
	style.set_corner_radius_all(3)
	badge.add_theme_stylebox_override("panel", style)

	var text := Label.new()
	text.text = Loot.badge_of(id)
	text.add_theme_font_size_override("font_size", 12)
	text.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(text)

	return badge


func _row_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = Color(color, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style
