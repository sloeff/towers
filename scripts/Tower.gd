extends Node2D
## Base tower. Targets the enemy furthest along its path within range and
## fires a homing projectile at it. Range is measured in un-squashed space so
## the circle matches the isometric ground plane.

const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")
const FLOATING_TEXT_SCENE := preload("res://scenes/FloatingText.tscn")

@export var element: int = ElementTypes.Element.FIRE
@export var damage: float = 8.0
@export var fire_rate: float = 1.2  # shots per second
@export var range_radius: float = 170.0
@export var cost: int = 50

## Selling refunds this fraction of the build cost, floored (DESIGN_DOC,
## "Economy"). Enough to undo a misplacement without making sell-and-rebuild
## free.
const SELL_REFUND_RATE := 0.75

## Tower leveling (DESIGN_DOC, "Experience"). A tower gains XP whenever it lands
## a killing blow and levels up automatically - there is no button. Each level
## multiplies the BASE damage and fire rate linearly (range and cost are
## unaffected), capped at MAX_LEVEL. Not to be confused with the token-gated
## "level 2" of combination towers - a separate axis (DESIGN_DOC section 8).
const MAX_LEVEL := 5
## XP to climb from level 1->2, 2->3, ... (index = current level - 1).
const XP_TO_LEVEL := [100, 160, 260, 410]
## Per-level stat gains, as a fraction of the base stat, added linearly.
const DAMAGE_GAIN_PER_LEVEL := 0.18
const FIRE_RATE_GAIN_PER_LEVEL := 0.12

var level: int = 1
var experience: int = 0
## Level-1 stats from ElementTypes.DATA; effective damage/fire_rate are these
## scaled by the current level in _recompute_stats().
var base_damage: float = 8.0
var base_fire_rate: float = 1.2

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


## Gold returned to the player when this tower is sold.
func sell_value() -> int:
	return int(floor(cost * SELL_REFUND_RATE))


func is_at_max_level() -> bool:
	return level >= MAX_LEVEL


## XP needed to reach the next level from the current one, or 0 at the cap.
func experience_to_next_level() -> int:
	if is_at_max_level():
		return 0
	return XP_TO_LEVEL[level - 1]


## Award XP for a killing blow, rolling any overflow into further levels. Fully
## automatic - the tower gets stronger with no player action.
func gain_experience(amount: int) -> void:
	if is_at_max_level():
		return
	experience += amount
	var leveled := false
	while not is_at_max_level() and experience >= XP_TO_LEVEL[level - 1]:
		experience -= XP_TO_LEVEL[level - 1]
		level += 1
		leveled = true
	if is_at_max_level():
		experience = 0
	if leveled:
		_recompute_stats()
		_show_level_up()
		queue_redraw()  # the tower grows taller per level - see _draw()


## Effective damage and fire rate for the current level, off the base stats.
func _recompute_stats() -> void:
	damage = base_damage * (1.0 + DAMAGE_GAIN_PER_LEVEL * (level - 1))
	fire_rate = base_fire_rate * (1.0 + FIRE_RATE_GAIN_PER_LEVEL * (level - 1))


func _show_level_up() -> void:
	var popup := FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = ground_position() + Vector2(0.0, -48.0)
	popup.setup("Level up!", Color(0.5, 0.9, 1.0), 1.5)


func configure(tower_element: int) -> void:
	element = tower_element
	var data: Dictionary = ElementTypes.DATA[tower_element]
	base_damage = data["damage"]
	base_fire_rate = data["fire_rate"]
	range_radius = data["range"]
	cost = data["cost"]
	_recompute_stats()


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
	projectile.setup(target, damage, element, self)


func _draw() -> void:
	# Brighten with each level so a leveled tower reads as stronger at a glance,
	# on top of the extra height below. Level 1 is unchanged.
	var color: Color = ElementTypes.color_of(element).lightened((level - 1) * 0.08)
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

	# The turret grows taller with each level so a leveled-up tower stands out at
	# a glance; the base stays planted on the tile and it extends upward.
	var turret_height := 34.0 + (level - 1) * 4.0
	var turret_top := origin.y - turret_height
	draw_rect(Rect2(origin.x - 11.0, turret_top, 22.0, turret_height), color.darkened(0.25))
	draw_rect(Rect2(origin.x - 11.0, turret_top, 22.0, turret_height), color.darkened(0.7), false, 1.5)
	draw_circle(Vector2(origin.x, turret_top - 6.0), 8.0, color)
