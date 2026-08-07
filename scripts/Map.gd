extends Node2D
## Draws the isometric grid: the enemy route, the buildable ground beside it,
## and the cell the mouse is currently over. Placeholder art - swap for a
## TileMapLayer once real tiles exist (see assets/tiles).

const GROUND_COLOR := Color(0.27, 0.42, 0.24)
const GROUND_EDGE := Color(0.22, 0.35, 0.2)
const ROUTE_COLOR := Color(0.62, 0.55, 0.38)
const ROUTE_EDGE := Color(0.5, 0.44, 0.3)
const SPAWN_COLOR := Color(0.8, 0.35, 0.35)
const GOAL_COLOR := Color(0.35, 0.65, 0.85)

var hover_cell: Vector2i = Vector2i(-1, -1):
	set(value):
		if value == hover_cell:
			return
		hover_cell = value
		queue_redraw()

var hover_valid: bool = false:
	set(value):
		if value == hover_valid:
			return
		hover_valid = value
		queue_redraw()


func _draw() -> void:
	for y in GridManager.GRID_SIZE.y:
		for x in GridManager.GRID_SIZE.x:
			var cell := Vector2i(x, y)
			var is_route: bool = GridManager.path_cells.has(cell)
			var corners := GridManager.cell_corners(cell)
			draw_colored_polygon(corners, ROUTE_COLOR if is_route else GROUND_COLOR)
			draw_polyline(
				corners + PackedVector2Array([corners[0]]),
				ROUTE_EDGE if is_route else GROUND_EDGE,
				1.0
			)

	_draw_marker(GridManager.spawn_cell(), SPAWN_COLOR)
	_draw_marker(GridManager.goal_cell(), GOAL_COLOR)

	if GridManager.in_bounds(hover_cell):
		var color := Color(0.4, 0.95, 0.5) if hover_valid else Color(0.95, 0.35, 0.35)
		var corners := GridManager.cell_corners(hover_cell)
		draw_colored_polygon(corners, Color(color, 0.3))
		draw_polyline(corners + PackedVector2Array([corners[0]]), color, 2.0)


func _draw_marker(cell: Vector2i, color: Color) -> void:
	var corners := GridManager.cell_corners(cell)
	draw_colored_polygon(corners, Color(color, 0.55))
	draw_polyline(corners + PackedVector2Array([corners[0]]), color, 2.0)
