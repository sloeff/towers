extends Node2D
## Simple homing projectile. Instantiated and configured by Tower.gd.

@export var travel_speed: float = 320.0

var _target: Node2D = null
var _damage: float = 0.0
var _element: int = 0


func setup(target: Node2D, damage: float, element: int) -> void:
	_target = target
	_damage = damage
	_element = element
	queue_redraw()


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return

	var aim: Vector2 = _target.aim_position()
	var to_target: Vector2 = aim - global_position
	if to_target.length() < 10.0:
		_target.take_damage(_damage, _element)
		queue_free()
		return

	global_position += to_target.normalized() * travel_speed * delta


func _draw() -> void:
	var color: Color = ElementTypes.color_of(_element)
	draw_circle(Vector2.ZERO, 4.0, color)
	draw_arc(Vector2.ZERO, 4.0, 0.0, TAU, 12, color.lightened(0.5), 1.5)
