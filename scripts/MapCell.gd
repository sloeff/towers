extends Node2D
## One map tile, drawn in local space around its own origin.
##
## Each cell is its own node so it takes part in the y-sorted layer along with
## towers, units and projectiles. That is what sells the ravine: a unit down
## in the trench gets painted over by the grass block standing in front of it,
## instead of floating on top of the whole map.
##
## The map is one slab of GridManager.RAVINE_DEPTH thickness. Buildable cells
## are blocks - a top face plus the two camera-facing side faces (south-west
## and south-east). Route cells sit flush with the slab's underside. The
## ravine's far walls need no special handling: they are the side faces of the
## grass blocks behind the trench, which get drawn anyway.

const GROUND_COLOR := Color(0.27, 0.42, 0.24)
const GROUND_EDGE := Color(0.21, 0.34, 0.19)
const CLIFF_SW := Color(0.35, 0.28, 0.19)
const CLIFF_SE := Color(0.26, 0.2, 0.13)
const FLOOR_COLOR := Color(0.5, 0.44, 0.3)
const FLOOR_EDGE := Color(0.42, 0.37, 0.25)
const SPAWN_COLOR := Color(0.8, 0.35, 0.35)
const GOAL_COLOR := Color(0.35, 0.65, 0.85)

var cell: Vector2i

var _highlight := Color(0.0, 0.0, 0.0, 0.0)
## Cancels the sort bias baked into this cell's position, so the tile draws
## where it belongs while sorting from somewhere else. See
## GridManager.RAISED_SORT_BIAS and FLOOR_SORT_BIAS.
var _draw_origin := Vector2.ZERO


func setup(target_cell: Vector2i) -> void:
	cell = target_cell
	var bias: float = GridManager.FLOOR_SORT_BIAS if GridManager.path_cells.has(target_cell) \
		else GridManager.RAISED_SORT_BIAS
	position = GridManager.cell_to_world(target_cell) + Vector2(0.0, bias)
	_draw_origin = Vector2(0.0, -bias)


## Transparent clears the highlight.
func set_highlight(color: Color) -> void:
	if color == _highlight:
		return
	_highlight = color
	queue_redraw()


func _draw() -> void:
	var is_route: bool = GridManager.path_cells.has(cell)
	if is_route:
		_draw_ravine_floor()
	else:
		_draw_ground_block()

	if cell == GridManager.spawn_cell():
		_draw_overlay(SPAWN_COLOR, 0.55)
	elif cell == GridManager.goal_cell():
		_draw_overlay(GOAL_COLOR, 0.55)

	if _highlight.a > 0.0:
		_draw_overlay(_highlight, 0.3)


## Corners of this cell's walkable surface, in local space: the ravine floor
## for route cells, the plateau for buildable ones.
func _top_corners() -> PackedVector2Array:
	var corners := GridManager.cell_corners(Vector2i.ZERO)
	var offset := _draw_origin
	if GridManager.path_cells.has(cell):
		offset += Vector2(0.0, GridManager.RAVINE_DEPTH)
	for i in corners.size():
		corners[i] += offset
	return corners


func _closed(corners: PackedVector2Array) -> PackedVector2Array:
	return corners + PackedVector2Array([corners[0]])


## True where the neighbouring cell sits lower than the plateau - either the
## ravine floor, or off the edge of the map.
func _is_lower(neighbour: Vector2i) -> bool:
	return not GridManager.in_bounds(neighbour) or GridManager.path_cells.has(neighbour)


func _draw_ground_block() -> void:
	var corners := _top_corners()
	var drop := Vector2(0.0, GridManager.RAVINE_DEPTH)

	# Only the two camera-facing faces can ever be seen; the others are always
	# hidden behind the neighbouring block's top surface.
	if _is_lower(cell + Vector2i(0, 1)):
		draw_colored_polygon(PackedVector2Array([
			corners[3], corners[2], corners[2] + drop, corners[3] + drop,
		]), CLIFF_SW)
	if _is_lower(cell + Vector2i(1, 0)):
		draw_colored_polygon(PackedVector2Array([
			corners[2], corners[1], corners[1] + drop, corners[2] + drop,
		]), CLIFF_SE)

	draw_colored_polygon(corners, GROUND_COLOR)
	draw_polyline(_closed(corners), GROUND_EDGE, 1.0)


func _draw_ravine_floor() -> void:
	var corners := _top_corners()
	draw_colored_polygon(corners, FLOOR_COLOR)
	draw_polyline(_closed(corners), FLOOR_EDGE, 1.0)


func _draw_overlay(color: Color, alpha: float) -> void:
	var corners := _top_corners()
	draw_colored_polygon(corners, Color(color, alpha))
	draw_polyline(_closed(corners), color, 2.0)
