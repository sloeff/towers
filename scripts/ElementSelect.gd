extends Panel
## Start-of-run element pick. The player commits to one element and can only
## build that element's towers; more are unlocked later through the elemental
## token economy (DESIGN_DOC.md section 8, not implemented yet).
##
## Cards are generated from ElementTypes.DATA, so adding an element needs no
## scene change - same rule as the HUD's build bar. Each card leaves a fixed
## block of space for the element's pros and cons, which aren't designed yet;
## see the note on ElementTypes.DATA.

signal element_chosen(element: int)

const CARD_SIZE := Vector2(216.0, 344.0)
## Height reserved for the pros/cons block, whether or not it has any lines in
## it yet, so filling them in later doesn't shift the rest of the card.
const NOTES_HEIGHT := 92.0

const CARD_BG := Color(0.11, 0.12, 0.16, 0.96)
const MUTED := Color(0.64, 0.67, 0.73)
const PRO_COLOR := Color(0.45, 0.82, 0.5)
const CON_COLOR := Color(0.9, 0.45, 0.42)

@onready var _cards: HBoxContainer = $Center/Box/Cards
@onready var _title: Label = $Center/Box/TitleLabel
@onready var _subtitle: Label = $Center/Box/SubtitleLabel

const TowerScript := preload("res://scripts/Tower.gd")

## Per-element card widgets we relabel between the start pick and a tier choice.
var _buttons := {}
var _tier_labels := {}
## Per-element {"damage": Label, "fire_rate": Label} - the tier-scaled stat
## values, previewed to the tier a choice would advance the element to.
var _stat_values := {}


func _ready() -> void:
	for element in ElementTypes.ALL:
		_cards.add_child(_build_card(element))


## Re-label the panel for a mid-run tier choice: the heading changes and each
## card shows the element's current tier, with its button offering to unlock a
## new element or advance one you already own to the next tier.
func configure_for_choice() -> void:
	_title.text = "Choose an upgrade"
	_subtitle.text = "Advance an element you own to its next tier, or unlock a new one."
	for element in ElementTypes.ALL:
		var data: Dictionary = ElementTypes.DATA[element]
		var tier: int = GameManager.element_tier(element)
		# The tier this choice would land the element at: the next one if owned,
		# tier 1 if it's a fresh unlock. Preview the stats a tower would then have.
		var resulting_tier: int = tier + 1 if tier > 0 else 1
		_stat_values[element]["damage"].text = "%.0f" % TowerScript.damage_at_tier(data["damage"], resulting_tier)
		_stat_values[element]["fire_rate"].text = "%.1f/s" % TowerScript.fire_rate_at_tier(data["fire_rate"], resulting_tier)
		if tier > 0:
			_buttons[element].text = "Advance to Tier %d" % (tier + 1)
			_tier_labels[element].text = "Owned  ·  Tier %d" % tier
			_tier_labels[element].add_theme_color_override("font_color", ElementTypes.text_color_of(element))
		else:
			_buttons[element].text = "Unlock %s" % data["name"]
			_tier_labels[element].text = "Not owned"
			_tier_labels[element].add_theme_color_override("font_color", MUTED)


func _build_card(element: int) -> Control:
	var data: Dictionary = ElementTypes.DATA[element]
	var color: Color = ElementTypes.text_color_of(element)

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.add_theme_stylebox_override("panel", _card_style(data["color"]))

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	box.add_child(_heading(data["name"], color))

	# Tier status, blank for the start pick and filled by configure_for_choice
	# for a mid-run tier choice. Kept in the layout either way so cards don't jump.
	var tier_label := _body("", MUTED)
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tier_labels[element] = tier_label
	box.add_child(tier_label)

	box.add_child(_body(data["role"], MUTED))
	box.add_child(HSeparator.new())
	box.add_child(_stats(element, data))
	box.add_child(HSeparator.new())
	box.add_child(_notes(data))

	var button := Button.new()
	button.text = "Choose %s" % data["name"]
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.add_theme_color_override("font_color", color)
	button.pressed.connect(_on_card_pressed.bind(element))
	_buttons[element] = button
	box.add_child(button)

	return card


func _on_card_pressed(element: int) -> void:
	element_chosen.emit(element)


func _card_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = Color(color, 0.65)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


func _heading(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _body(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## The basic tower's numbers, plus the elemental matchup - a tower deals 125%
## to its opposite element and 75% to its own (see get_multiplier).
func _stats(element: int, data: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	_stat_row(grid, "Cost", "%d g" % data["cost"])
	# Keep the damage/fire-rate value labels so a tier choice can preview them.
	_stat_values[element] = {
		"damage": _stat_row(grid, "Damage", "%.0f" % data["damage"]),
		"fire_rate": _stat_row(grid, "Fire rate", "%.1f/s" % data["fire_rate"]),
	}
	_stat_row(grid, "Range", "%.0f" % data["range"])
	_stat_row(grid, "Strong vs", ElementTypes.element_name(ElementTypes.OPPOSITES[element]))
	_stat_row(grid, "Weak vs", data["name"])
	return grid


func _stat_row(grid: GridContainer, key: String, value: String) -> Label:
	var key_label := Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override("font_size", 14)
	key_label.add_theme_color_override("font_color", MUTED)
	grid.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(value_label)
	return value_label


## Pros and cons. DATA holds no entries yet, so this is an empty box of a fixed
## height - the space is the point, the lines come later.
func _notes(data: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0.0, NOTES_HEIGHT)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	for text in data["pros"]:
		box.add_child(_body("+ %s" % text, PRO_COLOR))
	for text in data["cons"]:
		box.add_child(_body("- %s" % text, CON_COLOR))
	return box
