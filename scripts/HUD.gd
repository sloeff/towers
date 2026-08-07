extends CanvasLayer
## Gold/lives/wave readout, the element build bar, and the end-of-run panel.
## Element buttons are generated from ElementTypes.DATA so adding an element
## doesn't need a scene change.

signal element_selected(element: int)
signal next_wave_requested
signal restart_requested

const MESSAGE_SECONDS := 1.5

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

var _spawner: Node = null
var _message_timeout: float = 0.0
var _buttons := {}


func _ready() -> void:
	_build_element_buttons()
	next_wave_button.pressed.connect(func() -> void: next_wave_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())

	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.lives_changed.connect(_on_lives_changed)
	GameManager.wave_changed.connect(_on_wave_changed)
	_on_gold_changed(GameManager.gold)
	_on_lives_changed(GameManager.lives)
	_on_wave_changed(GameManager.wave_number)
	_select(ElementTypes.Element.FIRE)


func set_spawner(spawner: Node) -> void:
	_spawner = spawner


func _build_element_buttons() -> void:
	for element in ElementTypes.ALL:
		var data: Dictionary = ElementTypes.DATA[element]
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(120.0, 44.0)
		button.text = "%s\n%d g" % [data["name"], data["cost"]]
		button.add_theme_color_override("font_color", data["color"])
		button.pressed.connect(_select.bind(element))
		element_buttons.add_child(button)
		_buttons[element] = button


func _select(element: int) -> void:
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
