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

## Body radius per rank. A captain or boss has to be obvious at a glance, so
## the radius roughly tracks the square root of the rank's HP multiplier (3x
## and 7x - see DESIGN_DOC's Balance section): the drawn *area* then scales
## with how much punishment the unit absorbs. A boss ends up 44 px across on a
## 64 px tile, which is as big as it can get without covering its neighbours.
## Everything else in _draw() - shadow, health bar - is derived from this, and
## so is aim_position(), so these are the only numbers to change.
const RADIUS := {
	Rank.BASIC: 9.0,
	Rank.CAPTAIN: 15.0,
	Rank.BOSS: 22.0,
}

var element: int = ElementTypes.Element.FIRE
var max_health: float = 30.0
var speed: float = 60.0
var gold_reward: int = 5
var xp_reward: int = 10  # XP granted to the tower that lands the killing blow
var lives_cost: int = 1
var is_flying: bool = false  # flying units ignore ground obstacles/shortcuts
var all_resist: bool = false  # "All resist" enemy: 75% from every element
var rank: int = Rank.BASIC

var health: float
## How far along its path this enemy is; towers target the highest value so
## they shoot whatever is closest to leaking.
var path_progress: float = 0.0

## Status effects applied by combination towers (DESIGN_DOC section 8).
## Slows (a stun is a slow with factor 0) and damage-over-time both live in
## small lists ticked in _process. Each entry is keyed by its `source` tower so
## a repeated application (an aura re-applying every frame, or a re-hit)
## refreshes the existing entry instead of piling up duplicates.
##   _slows: { factor: float, time_left: float, source }
##   _dots:  { dps: float, time_left: float, element: int, source }
var _slows: Array[Dictionary] = []
var _dots: Array[Dictionary] = []

## Set the instant this enemy is killed or leaks, so it can be removed only
## once. `queue_free` is deferred, so without this a second hit or a goal-reach
## in the same frame would fire `died`/`reached_goal` again and double-count.
var _removed: bool = false

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
	xp_reward = spec["xp"]
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
	_tick_effects(delta)
	if _removed:
		return  # a burn tick may have killed this enemy
	if _index >= _path.size():
		return
	var target := GridManager.cell_to_surface(_path[_index])
	var to_target := target - global_position
	# Slows (and stuns, which are factor-0 slows) scale movement; at factor 0 the
	# step is 0 and the unit is frozen in place.
	var step := speed * current_slow_factor() * delta
	if to_target.length() <= step:
		global_position = target
		_index += 1
		path_progress = float(_index)
		if _index >= _path.size():
			_on_reached_goal()
	else:
		global_position += to_target.normalized() * step


## Apply (or refresh) a slow. `factor` multiplies speed (0 = a full stun); the
## effective speed uses the strongest active slow, so slows don't multiply
## together. Keyed by `source` so an aura re-applying every frame or a repeat
## hit refreshes one entry instead of stacking many.
func apply_slow(factor: float, duration: float, source: Node2D = null) -> void:
	for s in _slows:
		if source != null and s["source"] == source:
			s["factor"] = factor
			s["time_left"] = duration
			return
	_slows.append({"factor": factor, "time_left": duration, "source": source})


## Apply (or refresh) a damage-over-time. Ticks through take_damage each frame,
## so the elemental multiplier and the killing-blow credit both apply. Keyed by
## `source` so a re-hit refreshes rather than stacking a second burn.
func apply_dot(dps: float, duration: float, dot_element: int, source: Node2D = null) -> void:
	for d in _dots:
		if source != null and d["source"] == source:
			d["dps"] = dps
			d["time_left"] = duration
			d["element"] = dot_element
			return
	_dots.append({"dps": dps, "time_left": duration, "element": dot_element, "source": source})


## Strongest (lowest) factor among active slows, or 1.0 when unslowed.
func current_slow_factor() -> float:
	var factor := 1.0
	for s in _slows:
		factor = minf(factor, s["factor"])
	return factor


## Tick slows and burns each frame: expire finished slows, and apply each burn's
## damage for this frame. A burn tick can land the killing blow (crediting its
## source tower), so this bails the moment the enemy is removed.
func _tick_effects(delta: float) -> void:
	for i in range(_slows.size() - 1, -1, -1):
		_slows[i]["time_left"] -= delta
		if _slows[i]["time_left"] <= 0.0:
			_slows.remove_at(i)
	for i in range(_dots.size() - 1, -1, -1):
		var d := _dots[i]
		var source: Node2D = d["source"] if is_instance_valid(d["source"]) else null
		take_damage(d["dps"] * delta, d["element"], source)
		if _removed:
			return
		d["time_left"] -= delta
		if d["time_left"] <= 0.0:
			_dots.remove_at(i)


## `source` is the tower that fired the shot, credited with XP if this is the
## killing blow (per DESIGN_DOC: only the killing blow earns XP). It may have
## been sold since firing, so it is guarded before use.
func take_damage(amount: float, attacker_element: int, source: Node2D = null) -> void:
	if _removed:
		return
	var multiplier: float = 0.75 if all_resist else ElementTypes.get_multiplier(attacker_element, element)
	health -= amount * multiplier
	queue_redraw()
	if health <= 0.0:
		_removed = true
		GameManager.add_gold(gold_reward)
		if is_instance_valid(source):
			source.register_kill(xp_reward)
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
	if _removed:
		return
	_removed = true
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
