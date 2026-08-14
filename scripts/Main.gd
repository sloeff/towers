extends Node2D
## Level root: owns camera control and tower placement, and wires the HUD to
## GameManager / WaveSpawner.

const TOWER_SCENE := preload("res://scenes/Tower.tscn")

const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const KEYBOARD_PAN_SPEED := 600.0
## On startup the camera zooms so the board spans this fraction of the screen
## width, leaving a little breathing room at the left and right edges.
const FIT_MARGIN := 0.06
## A one-finger touch that travels less than this (screen px) counts as a tap;
## more than this and it's a pan, so no build is triggered on release.
const TAP_MAX_TRAVEL := 16.0

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

## True once the last pointer input was touch, so we suppress the mouse-driven
## hover highlight (there's no cursor to hover on a touchscreen).
var _touch_mode := false
## Active touch points, index -> latest screen position. Size drives whether a
## gesture is a one-finger pan/tap or a two-finger pinch.
var _touch_points := {}
var _touch_start := Vector2.ZERO
var _single_moved := false
var _pinch_active := false
var _pinch_last_distance := 0.0

## Placement is a two-step confirm (click/tap a tile, then Build): while a build
## is pending, a translucent ghost tower marks the target cell.
var _has_pending := false
var _pending_cell: Vector2i = Vector2i(-1, -1)
var _pending_ghost: Node2D = null

## Pause has several independent reasons that can overlap (picking the starting
## element, the run ending, a phone held in portrait). Each is a flag and
## `_update_pause` ORs them, so clearing one never wrongly resumes another.
var _awaiting_element := true
var _awaiting_choice := false
var _run_ended := false
var _rotate_blocked := false
## Orientation the camera was last framed for, so a minor resize (e.g. a mobile
## browser's address bar) doesn't re-fit and stomp a manual pinch - only an
## actual portrait/landscape flip does.
var _has_fit := false
var _fit_portrait := false


func _ready() -> void:
	GameManager.new_game()
	GameManager.game_over.connect(_on_game_over)
	GameManager.victory.connect(_on_victory)
	hud.element_selected.connect(_on_element_selected)
	hud.starting_element_chosen.connect(_on_starting_element_chosen)
	hud.next_wave_requested.connect(spawner.start_next_wave_early)
	hud.restart_requested.connect(_restart)
	hud.tower_sell_requested.connect(_on_tower_sell_requested)
	hud.tower_upgrade_requested.connect(_on_tower_upgrade_requested)
	hud.tower_transform_requested.connect(_on_tower_transform_requested)
	hud.element_choice_made.connect(_on_element_choice_made)
	hud.tower_detail_closed.connect(_deselect_tower)
	hud.build_confirmed.connect(_confirm_pending_build)
	hud.build_cancelled.connect(_clear_pending_build)
	spawner.wave_cleared.connect(_on_wave_cleared)
	hud.set_spawner(spawner)
	# Re-frame the board and re-check orientation whenever the viewport changes
	# (rotating a phone, resizing a window). The web canvas often reports its
	# real size a frame late, so also run it deferred once at startup.
	get_viewport().size_changed.connect(_apply_display_layout)
	_apply_display_layout.call_deferred()
	_begin_element_select()


## The run doesn't start until the player commits to an element. Pausing holds
## the wave timer and everything else behind the panel, which has
## process_mode = Always so its buttons still respond - same trick as the
## end-of-run ResultPanel.
func _begin_element_select() -> void:
	_awaiting_element = true
	_update_pause()
	hud.show_element_select()


func _on_starting_element_chosen(element: int) -> void:
	GameManager.unlock_element(element)
	hud.select_element(element)
	_awaiting_element = false
	_update_pause()


## The tree is paused while any reason to hold the run is active.
func _update_pause() -> void:
	get_tree().paused = _awaiting_element or _awaiting_choice or _run_ended or _rotate_blocked


## A tier choice is offered after every 5th wave the player survives, but never
## after the final wave - clearing that is the victory, not a choice.
func _should_offer_choice(wave: int) -> bool:
	return wave > 0 and wave % 5 == 0 and wave < GameManager.MAX_WAVES


func _on_wave_cleared(wave: int) -> void:
	if _should_offer_choice(wave):
		_begin_element_choice()


## Pause and show the element panel as a tier choice. Like the start-of-run
## pick, pausing gives the player unlimited time to decide; only a pick resumes.
func _begin_element_choice() -> void:
	_awaiting_choice = true
	_update_pause()
	hud.show_element_choice()


func _on_element_choice_made(element: int) -> void:
	GameManager.choose_element(element)
	_awaiting_choice = false
	_update_pause()


## True when the tower's element has been advanced past the tower's own tier, so
## paying to upgrade it would actually do something.
func _can_upgrade_tower(tower: Node2D) -> bool:
	return GameManager.available_tier(tower) > tower.tier


func _on_tower_upgrade_requested(tower: Node2D) -> void:
	if GameManager.is_over or not _can_upgrade_tower(tower):
		return
	if not GameManager.spend_gold(tower.upgrade_cost()):
		hud.flash_message("Not enough gold")
		return
	tower.upgrade_tier()


## Transform a placed basic tower into the combo its owned elements allow, for
## gold. The tower keeps its XP level (transform_into) and drops to combo Tier 1.
func _on_tower_transform_requested(tower: Node2D) -> void:
	if GameManager.is_over:
		return
	var combo_id: int = GameManager.available_combo_for(tower)
	if combo_id == -1:
		return
	var transform_cost: int = Combos.DATA[combo_id]["transform_cost"]
	if not GameManager.spend_gold(transform_cost):
		hud.flash_message("Not enough gold")
		return
	tower.transform_into(combo_id)
	hud.show_tower_detail(tower)  # repopulate the panel title/stats for the combo


## A touch device held in portrait can't show the landscape-shaped board, so we
## ask the player to rotate rather than render a tiny, half-empty board.
func _should_prompt_rotate(viewport_size: Vector2, touch_available: bool) -> bool:
	return touch_available and viewport_size.y > viewport_size.x


## Frame the board, size the HUD, and toggle the portrait rotate hint. Runs at
## startup and on every viewport change; the camera only re-fits when the
## orientation actually flips (see `_fit_portrait`).
func _apply_display_layout() -> void:
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		_apply_display_layout.call_deferred()
		return
	var portrait := size.y > size.x
	if not _has_fit or portrait != _fit_portrait:
		_fit_camera_to(size)
		_has_fit = true
		_fit_portrait = portrait
	hud.apply_ui_scale(size)
	_rotate_blocked = _should_prompt_rotate(size, DisplayServer.is_touchscreen_available())
	hud.show_rotate_hint(_rotate_blocked)
	_update_pause()


## The board is an isometric diamond, so its world-space extent is not a simple
## corner-to-corner span - take the min/max of all four grid corners, padded by
## a tile so the outermost tiles aren't clipped at the screen edge.
func _board_bounds() -> Rect2:
	var corners := [
		Vector2i.ZERO,
		Vector2i(GridManager.GRID_SIZE.x - 1, 0),
		Vector2i(0, GridManager.GRID_SIZE.y - 1),
		GridManager.GRID_SIZE - Vector2i.ONE,
	]
	var min_p := Vector2.INF
	var max_p := -Vector2.INF
	for cell in corners:
		var world: Vector2 = GridManager.cell_to_world(cell)
		min_p = min_p.min(world)
		max_p = max_p.max(world)
	var pad := Vector2(GridManager.TILE_WIDTH, GridManager.TILE_HEIGHT) * 0.5
	return Rect2(min_p - pad, (max_p - min_p) + pad * 2.0)


## Zoom so the board spans the screen width (minus FIT_MARGIN) and center on it.
## Visible world width = viewport_width / zoom, so zoom = width / board_width.
func _fit_camera_to(viewport_size: Vector2) -> void:
	var bounds := _board_bounds()
	var target := viewport_size.x * (1.0 - FIT_MARGIN) / bounds.size.x
	camera.zoom = Vector2.ONE * clampf(target, MIN_ZOOM, MAX_ZOOM)
	camera.position = bounds.get_center()


func _process(delta: float) -> void:
	var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if pan != Vector2.ZERO:
		camera.position += pan * KEYBOARD_PAN_SPEED * delta / camera.zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		return
	if event is InputEventScreenTouch:
		_touch_mode = true
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_touch_mode = true
		_handle_screen_drag(event)
	elif event is InputEventMouseMotion:
		_touch_mode = false
		if _panning:
			camera.position -= event.relative / camera.zoom.x
		_update_hover()
	elif event is InputEventMouseButton:
		_touch_mode = false
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at(1.1, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at(1.0 / 1.1, event.position)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_on_tap(get_global_mouse_position())


## One finger pans and taps; two fingers pinch-zoom. A tap only fires on release
## if that finger barely moved (see TAP_MAX_TRAVEL) and wasn't part of a pinch.
func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position
		if _touch_points.size() == 1:
			_touch_start = event.position
			_single_moved = false
		elif _touch_points.size() == 2:
			_pinch_active = true
			_pinch_last_distance = _touch_distance()
	else:
		var was_single := _touch_points.size() == 1
		_touch_points.erase(event.index)
		if was_single and not _pinch_active and not _single_moved:
			_on_tap(_screen_to_world(event.position))
		if _touch_points.size() < 2:
			_pinch_active = false
		_update_hover()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_touch_points[event.index] = event.position
	if _pinch_active and _touch_points.size() >= 2:
		var distance := _touch_distance()
		if _pinch_last_distance > 0.0:
			_zoom_at(distance / _pinch_last_distance, _touch_midpoint())
		_pinch_last_distance = distance
	elif _touch_points.size() == 1:
		camera.position -= event.relative / camera.zoom.x
		if _touch_start.distance_to(event.position) > TAP_MAX_TRAVEL:
			_single_moved = true


func _touch_distance() -> float:
	var pts: Array = _touch_points.values()
	return pts[0].distance_to(pts[1]) if pts.size() >= 2 else 0.0


func _touch_midpoint() -> Vector2:
	var pts: Array = _touch_points.values()
	return (pts[0] + pts[1]) * 0.5 if pts.size() >= 2 else Vector2.ZERO


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


## Zoom while keeping the world point under `screen_point` fixed, so pinch and
## wheel zoom toward the fingers / cursor rather than the screen centre.
func _zoom_at(factor: float, screen_point: Vector2) -> void:
	var before := _screen_to_world(screen_point)
	_zoom_by(factor)
	var after := _screen_to_world(screen_point)
	camera.position += before - after


func _zoom_by(factor: float) -> void:
	var level := clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(level, level)


func _update_hover() -> void:
	if _touch_mode:
		# No cursor on a touchscreen, so no tile highlight (-1,-1 = none).
		map.hover_cell = Vector2i(-1, -1)
	else:
		var cell := GridManager.world_to_cell(get_global_mouse_position())
		map.hover_cell = cell
		map.hover_valid = selected_element != -1 and GridManager.can_build(cell) \
			and GameManager.gold >= _selected_cost()
	_update_range_rings()


## A tower shows its range ring while hovered (mouse only) or selected.
func _update_range_rings() -> void:
	var hovered: Node2D = null
	if not _touch_mode:
		hovered = _towers_by_cell.get(GridManager.world_to_cell(get_global_mouse_position()))
	for placed in _towers_by_cell.values():
		placed.show_range = placed == hovered or placed == _selected_tower


func _selected_cost() -> int:
	return ElementTypes.DATA[selected_element]["cost"]


## A click or tap at a world point. Tapping a tower selects it; tapping the tile
## that's already pending confirms the build; otherwise it starts (or moves) a
## pending build. HUD controls consume their own taps before this runs.
func _on_tap(world_pos: Vector2) -> void:
	if GameManager.is_over:
		return
	var cell := GridManager.world_to_cell(world_pos)
	var tower: Node2D = _towers_by_cell.get(cell)
	if tower != null:
		_clear_pending_build()
		_select_tower(tower)
		return
	if _has_pending and cell == _pending_cell:
		_confirm_pending_build()
		return
	_deselect_tower()
	_begin_pending_build(cell)


func _on_cancel() -> void:
	_clear_pending_build()
	_deselect_tower()


## Validate the tile, then show a translucent ghost + range and the Build prompt.
## Placement isn't committed until the player confirms.
func _begin_pending_build(cell: Vector2i) -> void:
	if not GameManager.is_element_unlocked(selected_element):
		_clear_pending_build()
		hud.flash_message("Pick an element first")
		return
	if not GridManager.can_build(cell):
		_clear_pending_build()
		hud.flash_message("Can't build there")
		return
	if GameManager.gold < _selected_cost():
		_clear_pending_build()
		hud.flash_message("Not enough gold")
		return

	_clear_pending_build()
	_has_pending = true
	_pending_cell = cell
	var ghost := TOWER_SCENE.instantiate()
	ghost.configure(selected_element)
	ghost.cell = cell
	ghost.set_process(false)  # a preview only: it must not target or fire
	ghost.modulate = Color(1.0, 1.0, 1.0, 0.45)
	entities.add_child(ghost)
	ghost.global_position = GridManager.cell_to_world(cell) \
		+ Vector2(0.0, GridManager.RAISED_SORT_BIAS)
	ghost.show_range = true
	_pending_ghost = ghost
	hud.show_build_prompt(GridManager.cell_to_world(cell), _selected_cost())


func _confirm_pending_build() -> void:
	if not _has_pending:
		return
	var cell := _pending_cell
	_clear_pending_build()
	_try_place_tower(cell)


func _clear_pending_build() -> void:
	if not _has_pending:
		return
	_has_pending = false
	_pending_cell = Vector2i(-1, -1)
	if is_instance_valid(_pending_ghost):
		_pending_ghost.queue_free()
	_pending_ghost = null
	hud.hide_build_prompt()


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
	_clear_pending_build()  # a pending ghost would be the old element
	_update_hover()


func _on_game_over() -> void:
	_clear_pending_build()
	_deselect_tower()
	_run_ended = true
	_update_pause()
	var waves := GameManager.wave_number
	hud.show_result("Game Over", "You survived %d wave%s." % [waves, "" if waves == 1 else "s"])


func _on_victory() -> void:
	_clear_pending_build()
	_deselect_tower()
	_run_ended = true
	_update_pause()
	hud.show_result("Victory!", "You cleared all %d waves." % GameManager.MAX_WAVES)


func _restart() -> void:
	_run_ended = false
	_update_pause()
	GridManager.occupied_cells.clear()
	get_tree().reload_current_scene()
