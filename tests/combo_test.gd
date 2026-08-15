extends Node
## Headless checks for the combination-tower first slice (Fire Breath).
## Run as a SCENE: Godot --headless --path . res://tests/combo_test.tscn
## Exits 0 on success, 1 on any failed assertion.

const ProjectileScript := preload("res://scripts/Projectile.gd")
const _FAKE_ENEMY_SCRIPT := preload("res://tests/fake_enemy.gd")

var _failures := 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok: ", label)
	else:
		_failures += 1
		print("  FAIL: ", label)


func _about(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func _ready() -> void:
	_test_registry()
	_test_transform()
	_test_aura_scaling()
	_test_splash_targets()
	_test_status_effects()
	_test_available_queries()
	await _test_transform_flow()

	print("combo_test: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## --- Combos registry: order-independent pair lookup --------------------------
func _test_registry() -> void:
	var fb := Combos.Combo.FIRE_BREATH
	_check("combo_for(FIRE, AIR) is Fire Breath",
		Combos.combo_for(ElementTypes.Element.FIRE, ElementTypes.Element.AIR) == fb)
	_check("combo_for is order-independent",
		Combos.combo_for(ElementTypes.Element.AIR, ElementTypes.Element.FIRE) == fb)
	_check("combo_for(FIRE, FIRE) is undefined (-1)",
		Combos.combo_for(ElementTypes.Element.FIRE, ElementTypes.Element.FIRE) == -1)
	_check("Fire + Water now forms Steam",
		Combos.combo_for(ElementTypes.Element.FIRE, ElementTypes.Element.WATER) == Combos.Combo.STEAM)
	_check("Fire Breath's parents are Fire and Air",
		Combos.DATA[fb]["parents"].has(ElementTypes.Element.FIRE)
		and Combos.DATA[fb]["parents"].has(ElementTypes.Element.AIR))
	_check("Fire Breath deals Fire-typed damage",
		Combos.DATA[fb]["damage_element"] == ElementTypes.Element.FIRE)
	_check("combos_including(FIRE) contains Fire Breath",
		Combos.combos_including(ElementTypes.Element.FIRE).has(fb))
	_check("combos_including(WATER) now has Steam, Quicksand and Hail",
		Combos.combos_including(ElementTypes.Element.WATER).has(Combos.Combo.STEAM)
		and Combos.combos_including(ElementTypes.Element.WATER).has(Combos.Combo.QUICKSAND)
		and Combos.combos_including(ElementTypes.Element.WATER).has(Combos.Combo.HAIL))


## --- Tower.transform_into: stats, identity, carry-level, reset-tier ----------
func _test_transform() -> void:
	var tower = load("res://scenes/Tower.tscn").instantiate()
	add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)  # base: 8 dmg, 1.2/s, cost 50
	tower.gain_experience(100000)               # push to max level 5
	var carried_level: int = tower.level
	_check("precondition: leveled basic tower", carried_level > 1)

	tower.transform_into(Combos.Combo.FIRE_BREATH)

	_check("transform sets is_combo", tower.is_combo)
	_check("transform records the combo id", tower.combo_id == Combos.Combo.FIRE_BREATH)
	_check("transform sets parent elements", tower.parent_elements.has(ElementTypes.Element.FIRE)
		and tower.parent_elements.has(ElementTypes.Element.AIR))
	_check("combo damage identity is Fire", tower.element == ElementTypes.Element.FIRE)
	_check("combo gains an AoE radius", tower.aoe_radius == 85.0)
	_check("transform carries the XP level over", tower.level == carried_level)
	_check("transform resets tier to 1", tower.tier == 1)
	_check("combo base damage scaled by carried level",
		_about(tower.damage, 18.0 * (1.0 + 0.18 * (carried_level - 1))))
	_check("display_name is the combo name", tower.display_name() == "Fire Breath")
	_check("display_color is the combo colour", tower.display_color() == Color(0.98, 0.55, 0.15))
	_check("source_elements are the two parents",
		tower.source_elements().size() == 2
		and tower.source_elements().has(ElementTypes.Element.AIR))
	_check("upgrade cost is 3x the combo cost", tower.upgrade_cost() == 390)

	tower.queue_free()


## --- Aura combo (Quicksand): damage is aura_dps and rides the tier ladder ----
func _test_aura_scaling() -> void:
	var tower = load("res://scenes/Tower.tscn").instantiate()
	add_child(tower)
	tower.configure(ElementTypes.Element.EARTH)
	tower.transform_into(Combos.Combo.QUICKSAND)

	var aura_dps: float = Combos.DATA[Combos.Combo.QUICKSAND]["aura_dps"]
	_check("aura combo's base damage is its aura_dps", _about(tower.damage, aura_dps))

	# Upgrading a tier must actually strengthen the aura (the old bug: it didn't).
	tower.upgrade_tier()  # Tier 2 -> +50% base damage
	_check("aura damage scales with tier (upgrade isn't a dead gold sink)",
		_about(tower.damage, aura_dps * 1.5))

	tower.queue_free()


## --- Projectile.splash_targets: circle on the un-squashed ground plane -------
func _test_splash_targets() -> void:
	# The 2:1 unsquash DOUBLES the y offset (undoing the iso squash), so a vertical
	# screen offset maps to a larger ground distance: 30px below -> 60px on the
	# ground (inside a 70px radius); 200px right -> 200px (outside).
	var center := Vector2(500.0, 300.0)
	var near_x = _fake_enemy(center + Vector2(60.0, 0.0))    # 60px      -> in
	var near_y = _fake_enemy(center + Vector2(0.0, 30.0))    # 60px (x2) -> in
	var far = _fake_enemy(center + Vector2(200.0, 0.0))      # 200px     -> out
	add_child(near_x)
	add_child(near_y)
	add_child(far)

	var hit := ProjectileScript.splash_targets(center, 70.0, [near_x, near_y, far])
	_check("splash includes an enemy inside the radius (x)", hit.has(near_x))
	_check("splash includes an enemy inside after unsquash (y)", hit.has(near_y))
	_check("splash excludes an enemy outside the radius", not hit.has(far))

	near_x.queue_free()
	near_y.queue_free()
	far.queue_free()


func _fake_enemy(ground_pos: Vector2) -> Node2D:
	var e := Node2D.new()
	e.set_script(_FAKE_ENEMY_SCRIPT)
	e.global_position = ground_pos
	return e


## --- Enemy status effects: slow (min factor), stun (factor 0), burn, refresh --
func _test_status_effects() -> void:
	var enemy = load("res://scenes/Enemy.tscn").instantiate()
	add_child(enemy)
	enemy.configure({
		"element": ElementTypes.Element.EARTH,
		"health": 1000.0, "speed": 60.0, "gold": 0, "xp": 0,
		"lives": 1, "rank": Enemy.Rank.BASIC,
	})
	enemy.health = enemy.max_health

	# Slow: the strongest (lowest) factor wins; two slows don't multiply.
	enemy.apply_slow(0.5, 1.0)
	_check("one slow sets the speed factor", _about(enemy.current_slow_factor(), 0.5))
	enemy.apply_slow(0.7, 1.0)
	_check("a weaker slow doesn't override the stronger", _about(enemy.current_slow_factor(), 0.5))

	# A stun is just a factor-0 slow.
	enemy.apply_slow(0.0, 1.0)
	_check("a stun stops the enemy (factor 0)", _about(enemy.current_slow_factor(), 0.0))

	# Slows expire after their duration, speed returns to full.
	enemy._tick_effects(2.0)
	_check("slows expire and speed returns to full", _about(enemy.current_slow_factor(), 1.0))

	# Burn ticks damage through take_damage; Earth-on-Earth = 0.75 multiplier,
	# so 10 dps for 1s = 7.5 applied.
	var before: float = enemy.health
	enemy.apply_dot(10.0, 3.0, ElementTypes.Element.EARTH)
	enemy._tick_effects(1.0)
	_check("a burn tick damages the enemy", _about(enemy.health, before - 7.5))

	# Re-applying a same-source burn refreshes the one entry instead of stacking.
	enemy._dots.clear()
	enemy.apply_dot(10.0, 3.0, ElementTypes.Element.EARTH, enemy)
	enemy.apply_dot(10.0, 3.0, ElementTypes.Element.EARTH, enemy)
	_check("same-source burn refreshes, not stacks", enemy._dots.size() == 1)

	# A projectile carrying a slow applies it on hit.
	enemy._slows.clear()
	var proj = load("res://scenes/Projectile.tscn").instantiate()
	add_child(proj)
	proj._element = ElementTypes.Element.WATER
	proj._effects = {"slow_factor": 0.5, "slow_duration": 2.0}
	proj._apply_effects(enemy, null, true)
	_check("a projectile applies its carried slow on hit", _about(enemy.current_slow_factor(), 0.5))

	proj.queue_free()
	enemy.queue_free()


## --- GameManager.available_tier / available_combos_for -----------------------
func _test_available_queries() -> void:
	GameManager.new_game()

	var fire_tower = load("res://scenes/Tower.tscn").instantiate()
	add_child(fire_tower)
	fire_tower.configure(ElementTypes.Element.FIRE)

	# Basic tower: available_tier tracks its own element's tier.
	GameManager.choose_element(ElementTypes.Element.FIRE)  # Fire -> tier 1
	_check("basic tower available_tier equals its element tier",
		GameManager.available_tier(fire_tower) == 1)

	# available_combos_for: no partner owned yet.
	_check("no combo offered before the partner is owned",
		GameManager.available_combos_for(fire_tower).is_empty())

	GameManager.choose_element(ElementTypes.Element.AIR)  # Air -> tier 1
	_check("Fire tower offers only Fire Breath with just Air owned",
		GameManager.available_combos_for(fire_tower) == [Combos.Combo.FIRE_BREATH])

	# A second owned partner adds a second transform option.
	GameManager.choose_element(ElementTypes.Element.WATER)  # Water -> tier 1
	var options: Array = GameManager.available_combos_for(fire_tower)
	_check("Fire tower now offers Fire Breath and Steam",
		options.has(Combos.Combo.FIRE_BREATH) and options.has(Combos.Combo.STEAM)
		and options.size() == 2)

	# Combo tier cap is the LOWER of the two parents.
	fire_tower.transform_into(Combos.Combo.FIRE_BREATH)
	_check("combo available_tier is min(parent tiers): 1",
		GameManager.available_tier(fire_tower) == 1)
	GameManager.choose_element(ElementTypes.Element.FIRE)  # Fire -> tier 2, Air still 1
	_check("advancing one parent does not raise the combo cap",
		GameManager.available_tier(fire_tower) == 1)
	GameManager.choose_element(ElementTypes.Element.AIR)   # Air -> tier 2
	_check("advancing both parents raises the combo cap to 2",
		GameManager.available_tier(fire_tower) == 2)

	# A combo never offers a further transform.
	_check("a combo tower is not offered a transform",
		GameManager.available_combos_for(fire_tower).is_empty())

	fire_tower.queue_free()


## --- Main: the transform action (spend gold, transform, carry level) ---------
func _test_transform_flow() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main._on_starting_element_chosen(ElementTypes.Element.FIRE)  # unpause + own Fire
	await get_tree().process_frame
	GameManager.choose_element(ElementTypes.Element.AIR)         # own Air (tier 1)

	var tower = load("res://scenes/Tower.tscn").instantiate()
	main.entities.add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)
	tower.gain_experience(100000)
	var carried_level: int = tower.level

	# Too poor: transform costs 100, player has 50 -> nothing happens.
	GameManager.gold = 50
	main._on_tower_transform_requested(tower, Combos.Combo.FIRE_BREATH)
	_check("a broke player can't transform", not tower.is_combo and GameManager.gold == 50)

	# Affordable: spends the transform cost and becomes the combo, level carried.
	GameManager.gold = 100
	main._on_tower_transform_requested(tower, Combos.Combo.FIRE_BREATH)
	_check("transform spends the transform cost", GameManager.gold == 0)
	_check("the tower is now a combo", tower.is_combo)
	_check("the combo carried its XP level", tower.level == carried_level)

	main.queue_free()
