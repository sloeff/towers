class_name Enemy
extends Node2D
## Base enemy. Paths dynamically via GridManager (AStarGrid2D) instead of a
## fixed waypoint list, so a shortcut opening mid-level is picked up live:
## each enemy re-requests its shortest path from wherever it currently is, so
## units already past a newly-opened shortcut simply won't route backward
## through it - no special-casing needed.

signal died(enemy: Node)
signal reached_goal(enemy: Node)

const FLOATING_TEXT_SCENE := preload("res://scenes/FloatingText.tscn")

enum Rank { BASIC, CAPTAIN, BOSS }

const RADIUS := {
	Rank.BASIC: 9.0,
	Rank.CAPTAIN: 12.0,
	Rank.BOSS: 16.0,
}

var element: int = ElementTypes.Element.FIRE
var max_health: float = 30.0
var speed: float = 60.0
var gold_reward: int = 5
var lives_cost: int = 1
var is_flying: bool = false  # flying units ignore ground obstacles/shortcuts
var all_resist: bool = false  # "All resist" enemy: 75% from every element
var rank: int = Rank.BASIC

var health: float
## How far along its path this enemy is; towers target the highest value so
## they shoot whatever is closest to leaking.
var path_progress: float = 0.0

var _goal_cell: Vector2i
var _path: Array[Vector2i] = []
var _index: int = 0


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	GridManager.grid_changed.connect(_on_grid_changed)


func configure(spec: Dictionary) -> void:
	element = spec["element"]
	max_health = spec["health"]
	speed = spec["speed"]
	gold_reward = spec["gold"]
	lives_cost = spec["lives"]
	rank = spec["rank"]
	is_flying = spec.get("flying", false)
	all_resist = spec.get("all_resist", false)


## Called by WaveSpawner to place this enemy and give it a destination.
func start_at(spawn_cell: Vector2i, goal: Vector2i) -> void:
	_goal_cell = goal
	global_position = GridManager.cell_to_surface(spawn_cell)
	_request_path(spawn_cell)


## The enemy's position on the flat grid plane, with the ravine drop taken
## back out. Use this for anything spatial - pathing, tower range - because
## global_position is where the unit is *drawn*, down on the ravine floor.
func ground_position() -> Vector2:
	return global_position - Vector2(0.0, GridManager.RAVINE_DEPTH)


func _request_path(from_cell: Vector2i) -> void:
	_path = GridManager.find_path(from_cell, _goal_cell)
	_index = 0
	# get_id_path() includes the cell we're standing on; skip it.
	if not _path.is_empty() and _path[0] == from_cell:
		_index = 1


func _on_grid_changed() -> void:
	if is_flying:
		return  # flying units aren't affected by ground shortcuts/obstacles
	_request_path(GridManager.world_to_cell(ground_position()))


func _process(delta: float) -> void:
	if _index >= _path.size():
		return
	var target := GridManager.cell_to_surface(_path[_index])
	var to_target := target - global_position
	var step := speed * delta
	if to_target.length() <= step:
		global_position = target
		_index += 1
		path_progress = float(_index)
		if _index >= _path.size():
			_on_reached_goal()
	else:
		global_position += to_target.normalized() * step


func take_damage(amount: float, attacker_element: int) -> void:
	var multiplier: float = 0.75 if all_resist else ElementTypes.get_multiplier(attacker_element, element)
	health -= amount * multiplier
	queue_redraw()
	if health <= 0.0:
		GameManager.add_gold(gold_reward)
		_show_gold_reward()
		died.emit(self)
		queue_free()


## The popup has to outlive this node, so it goes to the parent (Entities) -
## the same reason Tower parents its projectiles there rather than to itself.
func _show_gold_reward() -> void:
	var popup := FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = aim_position()
	popup.setup("+%d" % gold_reward)


func _on_reached_goal() -> void:
	reached_goal.emit(self)
	GameManager.lose_life(lives_cost)
	queue_free()


## Where projectiles should aim: the centre of the body, which sits a radius
## above the unit's feet.
func aim_position() -> Vector2:
	return global_position + Vector2(0.0, -RADIUS[rank])


func _draw() -> void:
	var radius: float = RADIUS[rank]
	var color: Color = Color(0.75, 0.75, 0.75) if all_resist else ElementTypes.color_of(element)
	draw_circle(Vector2(0.0, radius * 0.35), radius * 0.9, Color(0.0, 0.0, 0.0, 0.3))
	draw_circle(Vector2(0.0, -radius), radius, color)
	draw_arc(Vector2(0.0, -radius), radius, 0.0, TAU, 20, color.darkened(0.5), 2.0)

	var bar_width := radius * 2.2
	var bar_top := -radius * 2.0 - 8.0
	var fraction := clampf(health / max_health, 0.0, 1.0)
	draw_rect(Rect2(-bar_width * 0.5, bar_top, bar_width, 4.0), Color(0.1, 0.1, 0.1, 0.8))
	draw_rect(Rect2(-bar_width * 0.5, bar_top, bar_width * fraction, 4.0), Color(0.3, 0.85, 0.35))
