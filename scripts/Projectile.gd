extends Node2D
## Simple homing projectile. Instantiated and configured by Tower.gd.

@export var travel_speed: float = 320.0

var _target: Node2D = null
var _damage: float = 0.0
var _element: int = 0
## The firing tower, credited with XP if this shot lands the killing blow. May
## be freed before impact (tower sold mid-flight), so consumers must guard it.
var _source: Node2D = null
var _aoe_radius: float = 0.0
## On-hit status effects carried from a combination tower (DESIGN_DOC section 8).
## Any subset of: slow_factor, slow_duration, dot_dps, dot_duration,
## stun_duration, stun_primary_only. Empty for basic towers.
var _effects: Dictionary = {}


func setup(target: Node2D, damage: float, element: int, source: Node2D, aoe_radius := 0.0, effects := {}) -> void:
	_target = target
	_damage = damage
	_element = element
	_source = source
	_aoe_radius = aoe_radius
	_effects = effects
	queue_redraw()


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return

	var aim: Vector2 = _target.aim_position()
	var to_target: Vector2 = aim - global_position
	if to_target.length() < 10.0:
		# The firing tower may have been sold (freed) while this shot was in
		# flight; never hand a dangling reference across take_damage()'s typed
		# parameter - pass null so the killing blow simply grants no XP.
		var source: Node2D = _source if is_instance_valid(_source) else null
		var primary := _target
		if _aoe_radius > 0.0:
			# Same-script static call, unqualified (Projectile.gd has no class_name).
			for e in splash_targets(_target.ground_position(), _aoe_radius, get_tree().get_nodes_in_group("enemies")):
				e.take_damage(_damage, _element, source)
				_apply_effects(e, source, e == primary)
		else:
			_target.take_damage(_damage, _element, source)
			_apply_effects(_target, source, true)
		queue_free()
		return

	global_position += to_target.normalized() * travel_speed * delta


## Apply this projectile's carried status effects to one hit enemy. `source` is
## the (guarded) firing tower, used both to credit a burn's killing blow and to
## key the slow so repeat hits refresh rather than stack. `is_primary` gates
## stuns flagged primary-only (Meteor stuns just its main target, not the
## splash). The enemy may have died to the impact damage, so it is guarded.
func _apply_effects(enemy: Node2D, source: Node2D, is_primary: bool) -> void:
	if _effects.is_empty() or not is_instance_valid(enemy):
		return
	if _effects.has("slow_factor"):
		enemy.apply_slow(_effects["slow_factor"], _effects.get("slow_duration", 1.0), source)
	if _effects.has("dot_dps"):
		enemy.apply_dot(_effects["dot_dps"], _effects.get("dot_duration", 3.0), _element, source)
	if _effects.has("stun_duration"):
		if is_primary or not _effects.get("stun_primary_only", false):
			enemy.apply_slow(0.0, _effects["stun_duration"], source)


func _draw() -> void:
	var color: Color = ElementTypes.color_of(_element)
	draw_circle(Vector2.ZERO, 4.0, color)
	draw_arc(Vector2.ZERO, 4.0, 0.0, TAU, 12, color.lightened(0.5), 1.5)


## Enemies whose ground position is within `radius` of `center`, measured on the
## un-squashed ground plane (same convention as Tower._find_target's range test).
static func splash_targets(center: Vector2, radius: float, enemies: Array) -> Array:
	var hit: Array = []
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var offset: Vector2 = e.ground_position() - center
		if Vector2(offset.x, offset.y * 2.0).length() <= radius:
			hit.append(e)
	return hit
