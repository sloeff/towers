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
## XP to climb from level 1->2, 2->3, ... (index = current level - 1). Past the
## end of the array (a higher-tier tower's raised cap) the last step repeats.
const XP_TO_LEVEL := [100, 160, 260, 410]
## Per-level stat gains, as a fraction of the base stat, added linearly.
const DAMAGE_GAIN_PER_LEVEL := 0.18
const FIRE_RATE_GAIN_PER_LEVEL := 0.12

## Tower tiers (DESIGN_DOC section 8) - the token/choice axis, separate from the
## automatic XP level above. The player advances an element's tier through the
## every-5-rounds choice; each placed tower is then upgraded one tier at a time
## for gold. A tier multiplies the tower's BASE damage and fire rate and raises
## its XP level cap; range and purchase cost are unchanged.
const TIER_DAMAGE_GAIN := 0.50
const TIER_FIRE_RATE_GAIN := 0.20
const XP_LEVELS_PER_TIER := 2
## Upgrading one tier costs this multiple of the tower's purchase price.
const UPGRADE_COST_MULT := 3

var tier: int = 1

## Combination-tower identity (DESIGN_DOC section 8). A basic tower is
## transformed in place into a combo via transform_into(); these stay at their
## defaults for a basic tower. `element` continues to mean the damage element for
## the multiplier and projectile, so a combo sets it to its damage_element.
var is_combo: bool = false
var combo_id: int = -1
var parent_elements: Array[int] = []
## Splash radius on the un-squashed ground plane; 0 = single-target (all basics).
var aoe_radius: float = 0.0

var level: int = 1
var experience: int = 0
## Lifetime killing blows landed by this tower, shown in the detail panel so the
## player can see which tower is pulling its weight. Counts past the level cap.
var kills: int = 0
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


## Highest XP level this tower can reach, raised by its tier.
func max_level() -> int:
	return MAX_LEVEL + XP_LEVELS_PER_TIER * (tier - 1)


func is_at_max_level() -> bool:
	return level >= max_level()


## XP to climb from the given level, clamped to the last defined step so a
## higher-tier tower can keep leveling past the base curve.
func _xp_for_level(current_level: int) -> int:
	return XP_TO_LEVEL[mini(current_level - 1, XP_TO_LEVEL.size() - 1)]


## Cost in gold to upgrade this tower one tier (DESIGN_DOC section 8).
func upgrade_cost() -> int:
	return cost * UPGRADE_COST_MULT


## Advance this tower one tier: bigger base stats and a higher XP cap. The
## caller checks the element's tier and charges gold; this just applies it.
func upgrade_tier() -> void:
	tier += 1
	_recompute_stats()
	queue_redraw()


## Turn this placed basic tower into a combination tower: swap in the combo's
## base stats and AoE, keep the earned XP level, and reset the tier to 1 (a combo
## has its own ladder). The caller checks ownership and charges gold.
func transform_into(new_combo_id: int) -> void:
	var data: Dictionary = Combos.DATA[new_combo_id]
	is_combo = true
	combo_id = new_combo_id
	parent_elements.assign(data["parents"])  # untyped Array -> Array[int]
	element = data["damage_element"]
	aoe_radius = data["aoe_radius"]
	base_damage = data["damage"]
	base_fire_rate = data["fire_rate"]
	range_radius = data["range"]
	cost = data["cost"]
	tier = 1  # fresh combo ladder; level/experience carried
	_recompute_stats()
	queue_redraw()


## Display name/colour that answer for both a basic tower and a combo, so the
## detail panel and _draw() never branch on element-vs-combo.
func display_name() -> String:
	return Combos.name_of(combo_id) if is_combo else ElementTypes.element_name(element)


func display_color() -> Color:
	return Combos.color_of(combo_id) if is_combo else ElementTypes.color_of(element)


## The elements this tower's tier cap is drawn from: its own for a basic tower,
## both parents for a combo. Used by GameManager.available_tier.
func source_elements() -> Array[int]:
	return parent_elements if is_combo else [element]


## XP needed to reach the next level from the current one, or 0 at the cap.
func experience_to_next_level() -> int:
	if is_at_max_level():
		return 0
	return _xp_for_level(level)


## Called by an enemy this tower killed: tally the kill (always) and award XP
## (which the level cap may ignore).
func register_kill(xp: int) -> void:
	kills += 1
	gain_experience(xp)


## Award XP for a killing blow, rolling any overflow into further levels. Fully
## automatic - the tower gets stronger with no player action.
func gain_experience(amount: int) -> void:
	if is_at_max_level():
		return
	experience += amount
	var leveled := false
	while not is_at_max_level() and experience >= _xp_for_level(level):
		experience -= _xp_for_level(level)
		level += 1
		leveled = true
	if is_at_max_level():
		experience = 0
	if leveled:
		_recompute_stats()
		_show_level_up()
		queue_redraw()  # the tower grows taller per level - see _draw()


## Base damage scaled to a tier - the single source for both a live tower's
## stats and the choice screen's tier preview. Range and cost don't scale.
static func damage_at_tier(base: float, at_tier: int) -> float:
	return base * (1.0 + TIER_DAMAGE_GAIN * (at_tier - 1))


static func fire_rate_at_tier(base: float, at_tier: int) -> float:
	return base * (1.0 + TIER_FIRE_RATE_GAIN * (at_tier - 1))


## Effective damage and fire rate off the base stats, scaled by both axes: the
## tier (paid upgrade) and the XP level (automatic). Range is unaffected by both.
func _recompute_stats() -> void:
	damage = damage_at_tier(base_damage, tier) * (1.0 + DAMAGE_GAIN_PER_LEVEL * (level - 1))
	fire_rate = fire_rate_at_tier(base_fire_rate, tier) * (1.0 + FIRE_RATE_GAIN_PER_LEVEL * (level - 1))


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
	if _is_aura():
		_process_aura(delta)
		return
	_fire_cooldown -= delta
	if _fire_cooldown > 0.0:
		return
	var target := _find_target()
	if target == null:
		return
	_fire_at(target)
	_fire_cooldown = 1.0 / fire_rate


## True for a combo whose firing_mode is "aura" (Quicksand): no projectile, it
## applies its effect to every enemy in range each frame instead.
func _is_aura() -> bool:
	return is_combo and Combos.DATA[combo_id].get("firing_mode", "projectile") == "aura"


## How long an aura's slow lingers after an enemy leaves the field: it's
## re-applied (refreshed) every frame while inside, so this is the tail once out.
const AURA_SLOW_LINGER := 0.3


## Aura tick: slow every enemy in range and deal a small slice of damage, each
## frame. Damage rides the normal take_damage path (elemental multiplier and
## killing-blow credit included).
func _process_aura(delta: float) -> void:
	var data: Dictionary = Combos.DATA[combo_id]
	var slow_factor: float = data.get("slow_factor", 1.0)
	var dps: float = data.get("aura_dps", 0.0)
	for enemy in _enemies_in_range():
		enemy.apply_slow(slow_factor, AURA_SLOW_LINGER, self)
		if dps > 0.0:
			enemy.take_damage(dps * delta, element, self)


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


## Every enemy within range on the un-squashed ground plane (aura targeting).
func _enemies_in_range() -> Array:
	var hit: Array = []
	var origin := ground_position()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var offset: Vector2 = enemy.ground_position() - origin
		if Vector2(offset.x, offset.y * 2.0).length() <= range_radius:
			hit.append(enemy)
	return hit


## The on-hit status effects this tower's projectile carries, pulled from the
## combo's data (empty for a basic tower). See Combos.DATA for the keys.
func _combo_effects() -> Dictionary:
	if not is_combo:
		return {}
	var data: Dictionary = Combos.DATA[combo_id]
	var effects: Dictionary = {}
	for key in ["slow_factor", "slow_duration", "dot_dps", "dot_duration",
			"stun_duration", "stun_primary_only"]:
		if data.has(key):
			effects[key] = data[key]
	return effects


func _fire_at(target: Node2D) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	get_parent().add_child(projectile)
	projectile.global_position = ground_position() + Vector2(0.0, -26.0)
	projectile.setup(target, damage, element, self, aoe_radius, _combo_effects())


func _draw() -> void:
	# Brighten with each level so a leveled tower reads as stronger at a glance,
	# on top of the extra height below. Level 1 is unchanged.
	# display_color() returns the element colour for a basic tower (unchanged) and
	# the combo's distinct colour for a combination tower.
	var color: Color = display_color().lightened((level - 1) * 0.08)
	# Draw back up by the sort bias baked into this node's position.
	var origin := Vector2(0.0, -GridManager.RAISED_SORT_BIAS)

	# An aura tower (Quicksand) always shows its field so the slow zone reads even
	# when unselected; other towers show their range only while selected.
	if show_range or _is_aura():
		var fill_alpha := 0.12 if show_range else 0.08
		draw_set_transform(origin, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, range_radius, Color(color, fill_alpha))
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

	# One bright pip per tier above the first, banded up the turret, so a
	# paid-upgrade tower reads as ranked-up independently of its XP height/brightness.
	for i in tier - 1:
		var pip_y := origin.y - 8.0 - i * 7.0
		draw_circle(Vector2(origin.x, pip_y), 2.5, Color(1.0, 0.92, 0.6))
