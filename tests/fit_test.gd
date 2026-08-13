extends Node
## Headless check for fit-to-screen (camera fit + HUD scaling). Run as a SCENE:
##   Godot --headless --path . res://tests/fit_test.tscn
## Exits 0 on success, 1 on any failed assertion.

var _failures := 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok: ", label)
	else:
		_failures += 1
		print("  FAIL: ", label)


func _about(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)  # Main._ready pauses the tree for the element pick
	main._on_starting_element_chosen(ElementTypes.Element.FIRE)
	await get_tree().process_frame

	var bounds: Rect2 = main._board_bounds()
	_check("board bounds have positive size", bounds.size.x > 0.0 and bounds.size.y > 0.0)

	# --- Fit to a tall portrait phone: board should span the width ---
	main._fit_camera_to(Vector2(1280, 2770))
	var visible_w: float = 1280.0 / main.camera.zoom.x
	var fill: float = bounds.size.x / visible_w
	_check("board fills the screen width on a phone", fill >= 0.90 and fill <= 0.99)
	_check("camera centers on the board (x)", _about(main.camera.position.x, bounds.get_center().x, 0.5))
	_check("camera centers on the board (y)", _about(main.camera.position.y, bounds.get_center().y, 0.5))

	# --- Clamp: a tiny viewport can't zoom out past MIN_ZOOM ---
	main._fit_camera_to(Vector2(200, 400))
	_check("fit clamps to MIN_ZOOM on a tiny viewport", main.camera.zoom.x == main.MIN_ZOOM)

	# --- Clamp: a huge viewport can't zoom in past MAX_ZOOM ---
	main._fit_camera_to(Vector2(5000, 5000))
	_check("fit clamps to MAX_ZOOM on a huge viewport", main.camera.zoom.x == main.MAX_ZOOM)

	# --- HUD scale is pure and clamped ---
	var hud = main.hud
	_check("ui scale is 1.0 at the reference desktop size", _about(hud.compute_ui_scale(Vector2(1280, 720)), 1.0))
	_check("ui scale grows on a phone (larger logical short side)", hud.compute_ui_scale(Vector2(1280, 2770)) > 1.0)
	_check("ui scale clamps at the top end", _about(hud.compute_ui_scale(Vector2(4000, 4000)), 2.5))
	_check("ui scale never shrinks below 1.0", _about(hud.compute_ui_scale(Vector2(400, 500)), 1.0))

	# --- Applying the scale enlarges the HUD font (real propagation) ---
	hud.apply_ui_scale(Vector2(1280, 720))
	var base_size: int = main.hud.gold_label.get_theme_default_font_size()
	hud.apply_ui_scale(Vector2(1280, 2770))
	var phone_size: int = main.hud.gold_label.get_theme_default_font_size()
	_check("HUD font grows when the UI is scaled up", phone_size > base_size)

	# --- Rotate hint fires only for a touch device held in portrait ---
	_check("portrait + touch prompts a rotate", main._should_prompt_rotate(Vector2(1280, 2770), true))
	_check("landscape + touch does not prompt", not main._should_prompt_rotate(Vector2(1563, 720), true))
	_check("portrait on desktop (no touch) does not prompt", not main._should_prompt_rotate(Vector2(1280, 2770), false))

	# --- HUD rotate overlay toggles visibility ---
	hud.show_rotate_hint(true)
	_check("rotate overlay shows", hud.rotate_hint.visible)
	hud.show_rotate_hint(false)
	_check("rotate overlay hides", not hud.rotate_hint.visible)

	# --- Pause is reason-based, so rotate-block can't fight the other pauses ---
	main._rotate_blocked = true
	main._update_pause()
	_check("a rotate block pauses the tree", get_tree().paused)
	main._rotate_blocked = false
	main._update_pause()
	_check("clearing the rotate block resumes (element already chosen)", not get_tree().paused)

	print("fit_test: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
