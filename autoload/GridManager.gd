extends Node
## Autoload singleton. Owns the pathfinding grid (AStarGrid2D), the isometric
## cell<->world conversion, and the map layout, so every enemy can query the
## shortest path to the exit and re-route live when the grid changes (e.g. a
## shortcut opening when a special unit destroys a blocking rock).
## Registered in project.godot under [autoload] as "GridManager".

signal grid_changed

const TILE_WIDTH := 64.0
const TILE_HEIGHT := 32.0

## How far below the buildable plateau the route sits, in pixels. Grid logic
## (pathing, build validity, mouse picking) stays on the flat plane; only
## surface positions and drawing apply the drop.
##
const RAVINE_DEPTH := 18.0

## Raised geometry - the grass plateau and anything standing on it - is placed
## this far below its cell centre purely so it sorts nearer the camera, and
## draws itself back up by the same amount.
##
## Y-sorting alone can't express elevation. A unit crossing a tile sweeps
## exactly TILE_HEIGHT * 0.5 of sort key, which is also the spacing between
## neighbouring tiles' keys, so without a bias it overtakes the block beside
## it partway across every tile and their draw order flips - a one pixel
## flicker at the lip. Biasing raised geometry past the unit's whole sweep
## makes "in front and raised" win everywhere on the tile.
##
## Must stay inside (RAVINE_DEPTH, RAVINE_DEPTH + TILE_HEIGHT * 0.5): below
## that and front blocks stop occluding units, above it and blocks behind
## start to.
const RAISED_SORT_BIAS := 26.0

## Route floor tiles sort a whole tile further from the camera than their
## centre. The ground never occludes what stands on it, so a floor tile must
## never overtake a unit clipping the corner of a neighbouring cell - which is
## what happened at the route's 90-degree bends before this existed.
const FLOOR_SORT_BIAS := -TILE_HEIGHT

const GRID_SIZE := Vector2i(14, 13)

## Corners of the enemy route (see MAP_LAYOUT.md). Straight segments between
## consecutive entries are filled in to produce the walkable cells, so every
## turn is a 90-degree corner.
const ROUTE := [
	Vector2i(0, 2),
	Vector2i(10, 2),
	Vector2i(10, 6),
	Vector2i(2, 6),
	Vector2i(2, 10),
	Vector2i(13, 10),
]

var astar := AStarGrid2D.new()
var path_cells := {}  # Vector2i -> true; the walkable route
var occupied_cells := {}  # Vector2i -> true; cells with a tower on them


func _ready() -> void:
	_build_route()
	astar.region = Rect2i(Vector2i.ZERO, GRID_SIZE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var cell := Vector2i(x, y)
			astar.set_point_solid(cell, not path_cells.has(cell))


func _build_route() -> void:
	for i in ROUTE.size() - 1:
		var from: Vector2i = ROUTE[i]
		var to: Vector2i = ROUTE[i + 1]
		var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
		var cell := from
		while cell != to:
			path_cells[cell] = true
			cell += step
	path_cells[ROUTE[-1]] = true


func spawn_cell() -> Vector2i:
	return ROUTE[0]


func goal_cell() -> Vector2i:
	return ROUTE[-1]


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_SIZE.x and cell.y < GRID_SIZE.y


func can_build(cell: Vector2i) -> bool:
	return in_bounds(cell) and not path_cells.has(cell) and not occupied_cells.has(cell)


func set_occupied(cell: Vector2i, occupied: bool) -> void:
	if occupied:
		occupied_cells[cell] = true
	else:
		occupied_cells.erase(cell)


## Flip a route cell solid/open - e.g. a rock being destroyed opens a shortcut.
## Emits grid_changed so all active enemies know to re-path.
func set_cell_blocked(cell: Vector2i, blocked: bool) -> void:
	astar.set_point_solid(cell, blocked)
	if blocked:
		path_cells.erase(cell)
	else:
		path_cells[cell] = true
	grid_changed.emit()


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if not in_bounds(from_cell) or not in_bounds(to_cell):
		return []
	return astar.get_id_path(from_cell, to_cell)


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2((cell.x - cell.y) * TILE_WIDTH * 0.5, (cell.x + cell.y) * TILE_HEIGHT * 0.5)


## Where something standing on this cell actually sits on screen: the ravine
## floor for route cells, the plateau for everything else. Anything that gets
## drawn or y-sorted should be placed here rather than at cell_to_world().
func cell_to_surface(cell: Vector2i) -> Vector2:
	var pos := cell_to_world(cell)
	if path_cells.has(cell):
		pos.y += RAVINE_DEPTH
	return pos


func world_to_cell(world_pos: Vector2) -> Vector2i:
	var a := world_pos.x / (TILE_WIDTH * 0.5)
	var b := world_pos.y / (TILE_HEIGHT * 0.5)
	return Vector2i(roundi((a + b) * 0.5), roundi((b - a) * 0.5))


## The four corners of a cell's isometric diamond, in world space.
func cell_corners(cell: Vector2i) -> PackedVector2Array:
	var c := cell_to_world(cell)
	return PackedVector2Array([
		c + Vector2(0.0, -TILE_HEIGHT * 0.5),
		c + Vector2(TILE_WIDTH * 0.5, 0.0),
		c + Vector2(0.0, TILE_HEIGHT * 0.5),
		c + Vector2(-TILE_WIDTH * 0.5, 0.0),
	])
