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

## -1 until the player picks their starting element.
var selected_element: int = -1

var _towers_by_cell := {}
var _panning := false

## The tower whose detail panel is open, or null. It keeps its range ring shown
## while selected, independent of hover.
var _selected_tower: Node2D = null


func _ready() -> void:
	GameManager.new_game()
	GameManager.game_over.connect(_on_game_over)
	GameManager.victory.connect(_on_victory)
	hud.element_selected.connect(_on_element_selected)
	hud.starting_element_chosen.connect(_on_starting_element_chosen)
	hud.next_wave_requested.connect(spawner.start_next_wave_early)
	hud.restart_requested.connect(_restart)
	hud.tower_sell_requested.connect(_on_tower_sell_requested)
	hud.tower_detail_closed.connect(_deselect_tower)
	hud.set_spawner(spawner)
	_center_camera()
	_begin_element_select()


## The run doesn't start until the player commits to an element. Pausing holds
## the wave timer and everything else behind the panel, which has
## process_mode = Always so its buttons still respond - same trick as the
## end-of-run ResultPanel.
func _begin_element_select() -> void:
	get_tree().paused = true
	hud.show_element_select()


func _on_starting_element_chosen(element: int) -> void:
	GameManager.unlock_element(element)
	hud.select_element(element)
	get_tree().paused = false


func _center_camera() -> void:
	var corner_a := GridManager.cell_to_world(Vector2i.ZERO)
	var corner_b := GridManager.cell_to_world(GridManager.GRID_SIZE - Vector2i.ONE)
	camera.position = (corner_a + corner_b) * 0.5


func _process(delta: float) -> void:
	var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if pan != Vector2.ZERO:
		camera.position += pan * KEYBOARD_PAN_SPEED * delta / camera.zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_deselect_tower()
		return
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
					_on_left_click()


func _zoom_by(factor: float) -> void:
	var level := clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(level, level)


func _update_hover() -> void:
	var cell := GridManager.world_to_cell(get_global_mouse_position())
	map.hover_cell = cell
	map.hover_valid = selected_element != -1 and GridManager.can_build(cell) \
		and GameManager.gold >= _selected_cost()
	var hovered: Node2D = _towers_by_cell.get(cell)
	for placed in _towers_by_cell.values():
		placed.show_range = placed == hovered or placed == _selected_tower


func _selected_cost() -> int:
	return ElementTypes.DATA[selected_element]["cost"]


## Left-click either selects a tower (opening its detail panel) or, on empty
## ground, deselects and attempts a build. Clicks on the panel itself never
## reach here - the panel Control consumes them first.
func _on_left_click() -> void:
	if GameManager.is_over:
		return
	var cell := GridManager.world_to_cell(get_global_mouse_position())
	var tower: Node2D = _towers_by_cell.get(cell)
	if tower != null:
		_select_tower(tower)
		return
	_deselect_tower()
	_try_place_tower(cell)


func _select_tower(tower: Node2D) -> void:
	_selected_tower = tower
	hud.show_tower_detail(tower)
	_update_hover()


func _deselect_tower() -> void:
	if _selected_tower == null:
		return
	_selected_tower = null
	hud.hide_tower_detail()
	_update_hover()


func _on_tower_sell_requested(tower: Node2D) -> void:
	if GameManager.is_over:
		return
	GameManager.add_gold(tower.sell_value())
	GridManager.set_occupied(tower.cell, false)
	_towers_by_cell.erase(tower.cell)
	if _selected_tower == tower:
		_selected_tower = null
	hud.hide_tower_detail()
	tower.queue_free()
	_update_hover()


func _try_place_tower(cell: Vector2i) -> void:
	if GameManager.is_over:
		return
	if not GameManager.is_element_unlocked(selected_element):
		hud.flash_message("Pick an element first")
		return
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
	# Placed low by the raised-geometry sort bias; Tower draws itself back up.
	tower.global_position = GridManager.cell_to_world(cell) \
		+ Vector2(0.0, GridManager.RAISED_SORT_BIAS)
	GridManager.set_occupied(cell, true)
	_towers_by_cell[cell] = tower
	_update_hover()


func _on_element_selected(element: int) -> void:
	selected_element = element
	_update_hover()


func _on_game_over() -> void:
	_deselect_tower()
	get_tree().paused = true
	var waves := GameManager.wave_number
	hud.show_result("Game Over", "You survived %d wave%s." % [waves, "" if waves == 1 else "s"])


func _on_victory() -> void:
	_deselect_tower()
	get_tree().paused = true
	hud.show_result("Victory!", "You cleared all %d waves." % GameManager.MAX_WAVES)


func _restart() -> void:
	get_tree().paused = false
	GridManager.occupied_cells.clear()
	get_tree().reload_current_scene()
