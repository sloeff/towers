extends Node2D
## Base tower. Targets the enemy furthest along its path within range and
## fires a homing projectile at it. Range is measured in un-squashed space so
## the circle matches the isometric ground plane.

const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")

@export var element: int = ElementTypes.Element.FIRE
@export var damage: float = 8.0
@export var fire_rate: float = 1.2  # shots per second
@export var range_radius: float = 170.0
@export var cost: int = 50

var cell: Vector2i
var show_range: bool = false:
	set(value):
		show_range = value
		queue_redraw()

var _fire_cooldown: float = 0.0


## A tower stands on the plateau, so it carries the same sort bias as the
## block under it - otherwise its own tile would sort nearer the camera and
## paint over its base. Everything spatial and every draw call works from
## here rather than from global_position.
func ground_position() -> Vector2:
	return global_position - Vector2(0.0, GridManager.RAISED_SORT_BIAS)


func configure(tower_element: int) -> void:
	element = tower_element
	var data: Dictionary = ElementTypes.DATA[tower_element]
	damage = data["damage"]
	fire_rate = data["fire_rate"]
	range_radius = data["range"]
	cost = data["cost"]


func _process(delta: float) -> void:
	_fire_cooldown -= delta
	if _fire_cooldown > 0.0:
		return
	var target := _find_target()
	if target == null:
		return
	_fire_at(target)
	_fire_cooldown = 1.0 / fire_rate


func _find_target() -> Node2D:
	var best: Node2D = null
	var best_progress := -1.0
	var origin := ground_position()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		# ground_position() on both sides: range is measured on the flat grid
		# plane, so neither the ravine drop nor the sort bias skews it.
		var offset: Vector2 = enemy.ground_position() - origin
		# Undo the 2:1 isometric squash so range is a circle on the ground.
		if Vector2(offset.x, offset.y * 2.0).length() > range_radius:
			continue
		if enemy.path_progress > best_progress:
			best = enemy
			best_progress = enemy.path_progress
	return best


func _fire_at(target: Node2D) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	get_parent().add_child(projectile)
	projectile.global_position = ground_position() + Vector2(0.0, -26.0)
	projectile.setup(target, damage, element)


func _draw() -> void:
	var color: Color = ElementTypes.color_of(element)
	# Draw back up by the sort bias baked into this node's position.
	var origin := Vector2(0.0, -GridManager.RAISED_SORT_BIAS)

	if show_range:
		draw_set_transform(origin, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, range_radius, Color(color, 0.12))
		draw_arc(Vector2.ZERO, range_radius, 0.0, TAU, 48, Color(color, 0.5), 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var base := GridManager.cell_corners(Vector2i.ZERO)
	for i in base.size():
		base[i] += origin
	draw_colored_polygon(base, color.darkened(0.55))
	draw_polyline(base + PackedVector2Array([base[0]]), color.darkened(0.7), 1.5)

	draw_rect(Rect2(origin.x - 11.0, origin.y - 34.0, 22.0, 34.0), color.darkened(0.25))
	draw_rect(Rect2(origin.x - 11.0, origin.y - 34.0, 22.0, 34.0), color.darkened(0.7), false, 1.5)
	draw_circle(origin + Vector2(0.0, -40.0), 8.0, color)
