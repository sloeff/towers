extends CanvasLayer
## Gold/lives/wave readout, the element build bar, and the end-of-run panel.
## Element buttons are generated from ElementTypes.DATA so adding an element
## doesn't need a scene change.

signal element_selected(element: int)
signal starting_element_chosen(element: int)
signal next_wave_requested
signal restart_requested
signal tower_sell_requested(tower: Node2D)
signal tower_detail_closed
signal build_confirmed
signal build_cancelled

const MESSAGE_SECONDS := 1.5

## HUD scaling: a device whose short side matches this (points) renders the HUD
## at 1x; smaller-feeling screens scale up so text and touch targets stay
## readable, capped so a huge screen doesn't get comically large chrome.
const UI_REFERENCE := 720.0
const UI_SCALE_MIN := 1.0
const UI_SCALE_MAX := 2.5
const BASE_FONT_SIZE := 16
const BASE_BUTTON_HEIGHT := 44.0

@onready var gold_label: Label = $TopBar/Row/GoldLabel
@onready var lives_label: Label = $TopBar/Row/LivesLabel
@onready var wave_label: Label = $TopBar/Row/WaveLabel
@onready var timer_label: Label = $TopBar/Row/TimerLabel
@onready var message_label: Label = $MessageLabel
@onready var element_buttons: HBoxContainer = $BuildBar/ElementButtons
@onready var next_wave_button: Button = $BuildBar/NextWaveButton
@onready var result_panel: Panel = $ResultPanel
@onready var result_title: Label = $ResultPanel/Center/Box/TitleLabel
@onready var result_detail: Label = $ResultPanel/Center/Box/DetailLabel
@onready var restart_button: Button = $ResultPanel/Center/Box/RestartButton
@onready var element_select: Panel = $ElementSelectPanel
@onready var tower_detail: PanelContainer = $TowerDetailPanel
@onready var build_prompt: PanelContainer = $BuildPrompt
@onready var rotate_hint: Panel = $RotateHint

var _spawner: Node = null
var _message_timeout: float = 0.0
var _buttons := {}
var _ui_theme: Theme = null


## Larger on small/high-DPI screens, 1x on a desktop-sized viewport, capped at
## the top. Under the "expand" stretch, a portrait phone's logical short side is
## the (constrained) width, which is well above the reference, so it scales up.
static func compute_ui_scale(viewport_size: Vector2) -> float:
	var short_side := minf(viewport_size.x, viewport_size.y)
	return clampf(short_side / UI_REFERENCE, UI_SCALE_MIN, UI_SCALE_MAX)


## Grow HUD text and touch targets to match the screen. A shared theme carries
## the font size to every control (anchoring is preserved because we scale the
## theme, not a transform); buttons also get a taller minimum tap height.
func apply_ui_scale(viewport_size: Vector2) -> void:
	var scale := compute_ui_scale(viewport_size)
	if _ui_theme == null:
		_ui_theme = Theme.new()
	_ui_theme.default_font_size = int(round(BASE_FONT_SIZE * scale))
	for child in get_children():
		if child is Control:
			(child as Control).theme = _ui_theme
	next_wave_button.custom_minimum_size.y = roundf(BASE_BUTTON_HEIGHT * scale)


## Full-screen "rotate to landscape" cover, shown when a phone is held upright
## (the board is landscape-shaped, so portrait is unplayable). Drawn on top of
## the rest of the HUD and set to process while paused.
func show_rotate_hint(visible: bool) -> void:
	rotate_hint.visible = visible


func _ready() -> void:
	_build_element_buttons()
	next_wave_button.pressed.connect(func() -> void: next_wave_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	element_select.element_chosen.connect(_on_starting_element_chosen)
	tower_detail.sell_pressed.connect(func(tower: Node2D) -> void: tower_sell_requested.emit(tower))
	tower_detail.close_pressed.connect(func() -> void: tower_detail_closed.emit())
	build_prompt.confirmed.connect(func() -> void: build_confirmed.emit())
	build_prompt.cancelled.connect(func() -> void: build_cancelled.emit())

	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.lives_changed.connect(_on_lives_changed)
	GameManager.wave_changed.connect(_on_wave_changed)
	GameManager.elements_changed.connect(_refresh_element_buttons)
	_on_gold_changed(GameManager.gold)
	_on_lives_changed(GameManager.lives)
	_on_wave_changed(GameManager.wave_number)
	_refresh_element_buttons()


func set_spawner(spawner: Node) -> void:
	_spawner = spawner


func show_element_select() -> void:
	element_select.visible = true


func show_tower_detail(tower: Node2D) -> void:
	tower_detail.show_for(tower)


func hide_tower_detail() -> void:
	tower_detail.hide_panel()


func show_build_prompt(world_pos: Vector2, cost: int) -> void:
	build_prompt.show_at(world_pos, cost)


func hide_build_prompt() -> void:
	build_prompt.hide_prompt()


func _on_starting_element_chosen(element: int) -> void:
	element_select.visible = false
	starting_element_chosen.emit(element)


func _build_element_buttons() -> void:
	for element in ElementTypes.ALL:
		var data: Dictionary = ElementTypes.DATA[element]
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(120.0, 44.0)
		button.text = "%s\n%d g" % [data["name"], data["cost"]]
		button.add_theme_color_override("font_color", ElementTypes.text_color_of(element))
		button.pressed.connect(select_element.bind(element))
		element_buttons.add_child(button)
		_buttons[element] = button


## The bar only shows elements the player has unlocked - before the start-of-run
## pick that's none of them, and the pick panel is covering the bar anyway.
func _refresh_element_buttons() -> void:
	for element in _buttons:
		var button: Button = _buttons[element]
		var unlocked: bool = GameManager.is_element_unlocked(element)
		button.visible = unlocked
		if not unlocked:
			button.button_pressed = false


## Pick which element the next tower will be. Locked elements are ignored - they
## have no button, but the guard also covers callers outside the bar.
func select_element(element: int) -> void:
	if not GameManager.is_element_unlocked(element):
		_refresh_element_buttons()
		return
	for key in _buttons:
		_buttons[key].button_pressed = key == element
	element_selected.emit(element)


func _process(delta: float) -> void:
	if _spawner != null:
		timer_label.text = "Next wave: %ds" % ceili(maxf(_spawner.time_until_next_wave, 0.0))
	if _message_timeout > 0.0:
		_message_timeout -= delta
		if _message_timeout <= 0.0:
			message_label.text = ""


func flash_message(text: String) -> void:
	message_label.text = text
	_message_timeout = MESSAGE_SECONDS


func show_result(title: String, detail: String) -> void:
	result_title.text = title
	result_detail.text = detail
	result_panel.visible = true


func _on_gold_changed(new_amount: int) -> void:
	gold_label.text = "Gold: %d" % new_amount


func _on_lives_changed(new_amount: int) -> void:
	lives_label.text = "Lives: %d" % new_amount


func _on_wave_changed(new_wave: int) -> void:
	wave_label.text = "Wave: %d / %d" % [new_wave, GameManager.MAX_WAVES]
