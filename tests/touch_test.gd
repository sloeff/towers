extends Node
## Headless check for touch controls. Run as a SCENE:
##   Godot --headless --path . res://tests/touch_test.tscn
## Exits 0 on success, 1 on any failed assertion.

var _failures := 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok: ", label)
	else:
		_failures += 1
		print("  FAIL: ", label)


func _touch(main: Node, index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	main._unhandled_input(e)


func _drag(main: Node, index: int, pos: Vector2, relative: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = relative
	main._unhandled_input(e)


func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)  # Main._ready pauses the tree for the element pick
	main._on_starting_element_chosen(ElementTypes.Element.FIRE)  # arm Fire, unpause
	await get_tree().process_frame

	# --- One-finger drag pans the camera (and does NOT build) ---
	var cam_before: Vector2 = main.camera.position
	_touch(main, 0, Vector2(400, 300), true)
	_drag(main, 0, Vector2(460, 300), Vector2(60, 0))
	_touch(main, 0, Vector2(460, 300), false)
	_check("one-finger drag pans the camera", main.camera.position != cam_before)
	_check("a drag does not start a build", not main._has_pending)

	# --- Two-finger pinch-out zooms in ---
	var zoom_before: float = main.camera.zoom.x
	_touch(main, 0, Vector2(300, 300), true)
	_touch(main, 1, Vector2(500, 300), true)   # start distance 200
	_drag(main, 0, Vector2(250, 300), Vector2(-50, 0))
	_drag(main, 1, Vector2(550, 300), Vector2(50, 0))  # distance -> 300
	_check("pinch-out zooms in", main.camera.zoom.x > zoom_before)
	_touch(main, 0, Vector2(250, 300), false)
	_touch(main, 1, Vector2(550, 300), false)
	await get_tree().process_frame

	# --- Tap a buildable tile -> pending build (ghost + prompt), not placed yet ---
	var world0: Vector2 = GridManager.cell_to_world(Vector2i(0, 0))
	var screen0: Vector2 = main.get_viewport().get_canvas_transform() * world0
	_touch(main, 0, screen0, true)
	_touch(main, 0, screen0, false)  # no movement -> tap
	_check("tap on buildable tile starts a pending build", main._has_pending)
	_check("pending build shows a ghost", is_instance_valid(main._pending_ghost))
	_check("build prompt is shown", main.hud.build_prompt.visible)
	_check("nothing placed until confirmed", not main._towers_by_cell.has(Vector2i(0, 0)))
	var gold_before: int = GameManager.gold

	# --- Confirm builds it and spends gold ---
	main._confirm_pending_build()
	_check("confirm places the tower", main._towers_by_cell.has(Vector2i(0, 0)))
	_check("confirm clears the pending state", not main._has_pending)
	_check("build prompt hidden after confirm", not main.hud.build_prompt.visible)
	_check("gold spent on confirm", GameManager.gold == gold_before - 50)

	# --- Tapping a placed tower selects it (opens the detail panel) ---
	main._on_tap(world0)
	_check("tapping a tower selects it", main._selected_tower != null)

	# --- Cancel clears a pending build without placing ---
	main._on_tap(GridManager.cell_to_world(Vector2i(1, 0)))
	_check("tapping empty ground starts a new pending build", main._has_pending)
	_check("selecting cleared when a new pending starts", main._selected_tower == null)
	main._clear_pending_build()
	_check("cancel clears the pending build", not main._has_pending)
	_check("cancel removes the ghost", main._pending_ghost == null)
	_check("no tower placed on cancel", not main._towers_by_cell.has(Vector2i(1, 0)))

	# Note: whether HUD Controls respond to touch (with mouse emulation off) can't
	# be exercised reliably headless - GUI touch routing needs a real window. It's
	# a real-device check. Godot's viewport GUI does process InputEventScreenTouch
	# natively, so Controls respond to touch regardless of the emulation setting.

	print("touch_test: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
