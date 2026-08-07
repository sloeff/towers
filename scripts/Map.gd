extends Node2D
## Builds the map as one MapCell node per grid cell.
##
## This node is y-sorted, and so is its parent, so Godot merges these tiles
## into the same sort as Entities' towers and units - terrain in front of a
## unit is drawn after it and occludes it. See MapCell.gd for the tile
## geometry itself.
##
## Placeholder art - swap for a TileMapLayer once real tiles exist.

const CELL_SCRIPT := preload("res://scripts/MapCell.gd")

const VALID_COLOR := Color(0.4, 0.95, 0.5)
const INVALID_COLOR := Color(0.95, 0.35, 0.35)
const NO_HIGHLIGHT := Color(0.0, 0.0, 0.0, 0.0)

var hover_cell: Vector2i = Vector2i(-1, -1):
	set(value):
		if value == hover_cell:
			return
		hover_cell = value
		_refresh_hover()

var hover_valid: bool = false:
	set(value):
		if value == hover_valid:
			return
		hover_valid = value
		_refresh_hover()

var _cells := {}
var _highlighted := Vector2i(-1, -1)


func _ready() -> void:
	for y in GridManager.GRID_SIZE.y:
		for x in GridManager.GRID_SIZE.x:
			var cell := Vector2i(x, y)
			var tile: Node2D = CELL_SCRIPT.new()
			tile.setup(cell)
			add_child(tile)
			_cells[cell] = tile


func _refresh_hover() -> void:
	if _cells.has(_highlighted):
		_cells[_highlighted].set_highlight(NO_HIGHLIGHT)
	_highlighted = hover_cell
	if _cells.has(hover_cell):
		_cells[hover_cell].set_highlight(VALID_COLOR if hover_valid else INVALID_COLOR)
