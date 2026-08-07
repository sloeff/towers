extends Node2D
## Level root: owns camera control and tower placement, and wires the HUD to
## GameManager / WaveSpawner.

const TOWER_SCENE := preload("res://scenes/Tower.tscn")

const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const KEYBOARD_PAN_SPEED := 600.0

@onready var camera: Camera2D = $Camera2D
@onready var map: Node2D = $Map
@onready var entities: Node2D = $Entities
@onready var spawner: Node2D = $WaveSpawner
@onready var hud: CanvasLayer = $HUD

var selected_element: int = ElementTypes.Element.FIRE

var _towers_by_cell := {}
var _panning := false


func _ready() -> void:
	GameManager.new_game()
	GameManager.game_over.connect(_on_game_over)
	GameManager.victory.connect(_on_victory)
	hud.element_selected.connect(_on_element_selected)
	hud.next_wave_requested.connect(spawner.start_next_wave_early)
	hud.restart_requested.connect(_restart)
	hud.set_spawner(spawner)
	_center_camera()


func _center_camera() -> void:
	var corner_a := GridManager.cell_to_world(Vector2i.ZERO)
	var corner_b := GridManager.cell_to_world(GridManager.GRID_SIZE - Vector2i.ONE)
	camera.position = (corner_a + corner_b) * 0.5


func _process(delta: float) -> void:
	var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if pan != Vector2.ZERO:
		camera.position += pan * KEYBOARD_PAN_SPEED * delta / camera.zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _panning:
			camera.position -= event.relative / camera.zoom.x
		_update_hover()
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_by(1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_by(1.0 / 1.1)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_try_place_tower()


func _zoom_by(factor: float) -> void:
	var level := clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(level, level)


func _update_hover() -> void:
	var cell := GridManager.world_to_cell(get_global_mouse_position())
	map.hover_cell = cell
	map.hover_valid = GridManager.can_build(cell) and GameManager.gold >= _selected_cost()
	var tower: Node2D = _towers_by_cell.get(cell)
	for placed in _towers_by_cell.values():
		placed.show_range = placed == tower


func _selected_cost() -> int:
	return ElementTypes.DATA[selected_element]["cost"]


func _try_place_tower() -> void:
	if GameManager.is_over:
		return
	var cell := GridManager.world_to_cell(get_global_mouse_position())
	if not GridManager.can_build(cell):
		hud.flash_message("Can't build there")
		return
	if not GameManager.spend_gold(_selected_cost()):
		hud.flash_message("Not enough gold")
		return

	var tower := TOWER_SCENE.instantiate()
	tower.configure(selected_element)
	tower.cell = cell
	entities.add_child(tower)
	tower.global_position = GridManager.cell_to_world(cell)
	GridManager.set_occupied(cell, true)
	_towers_by_cell[cell] = tower
	_update_hover()


func _on_element_selected(element: int) -> void:
	selected_element = element
	_update_hover()


func _on_game_over() -> void:
	get_tree().paused = true
	var waves := GameManager.wave_number
	hud.show_result("Game Over", "You survived %d wave%s." % [waves, "" if waves == 1 else "s"])


func _on_victory() -> void:
	get_tree().paused = true
	hud.show_result("Victory!", "You cleared all %d waves." % GameManager.MAX_WAVES)


func _restart() -> void:
	get_tree().paused = false
	GridManager.occupied_cells.clear()
	get_tree().reload_current_scene()
