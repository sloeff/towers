extends Node
## Headless check for the elemental tier economy (DESIGN_DOC section 8): the
## per-element tier map in GameManager, tower tier stats/upgrade, and Main's
## upgrade gating and every-5-rounds choice trigger. Run as a SCENE:
##   Godot --headless --path . res://tests/tier_test.tscn
## Exits 0 on success, 1 on any failed assertion.

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
	_test_game_manager_tiers()
	_test_tower_tiers()
	await _test_main_choice_and_upgrade()
	await _test_choice_previews_resulting_tier()
	_test_enemy_removed_once()
	_test_wave_cleared_fires_once()

	print("tier_test: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## --- GameManager: the per-element tier map -------------------------------
func _test_game_manager_tiers() -> void:
	GameManager.new_game()
	_check("new_game leaves every element un-owned (tier 0)",
		GameManager.element_tier(ElementTypes.Element.FIRE) == 0
		and not GameManager.is_element_unlocked(ElementTypes.Element.FIRE))

	# Choosing a new element unlocks it at tier 1.
	GameManager.choose_element(ElementTypes.Element.FIRE)
	_check("choosing a new element unlocks it at tier 1",
		GameManager.is_element_unlocked(ElementTypes.Element.FIRE)
		and GameManager.element_tier(ElementTypes.Element.FIRE) == 1)

	# Choosing an element you already own advances its tier.
	GameManager.choose_element(ElementTypes.Element.FIRE)
	_check("choosing an owned element advances it to the next tier",
		GameManager.element_tier(ElementTypes.Element.FIRE) == 2)

	# A second, different element starts fresh at tier 1 without touching the first.
	GameManager.choose_element(ElementTypes.Element.WATER)
	_check("a different element starts at tier 1",
		GameManager.element_tier(ElementTypes.Element.WATER) == 1)
	_check("unlocking a new element leaves the first element's tier alone",
		GameManager.element_tier(ElementTypes.Element.FIRE) == 2)

	# Tiers keep climbing - there is no tier-2 cap.
	GameManager.choose_element(ElementTypes.Element.FIRE)
	_check("tiers keep climbing past 2",
		GameManager.element_tier(ElementTypes.Element.FIRE) == 3)

	# new_game wipes tiers.
	GameManager.new_game()
	_check("new_game resets tiers to 0",
		GameManager.element_tier(ElementTypes.Element.FIRE) == 0)


## --- Tower: per-tower tier, stat boost, raised XP cap, upgrade cost --------
func _test_tower_tiers() -> void:
	var tower = load("res://scenes/Tower.tscn").instantiate()
	add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)  # base: 8 dmg, 1.2/s, cost 50

	_check("a fresh tower starts at tier 1", tower.tier == 1)
	_check("tier-1 damage is the base damage", _about(tower.damage, 8.0))
	_check("upgrade cost is 3x the purchase price", tower.upgrade_cost() == 150)
	_check("tier-1 tower caps at XP level 5", tower.max_level() == 5)

	tower.upgrade_tier()
	_check("upgrade_tier advances the tower to tier 2", tower.tier == 2)
	_check("tier 2 boosts base damage +50%", _about(tower.damage, 8.0 * 1.50))
	_check("tier 2 boosts base fire rate +20%", _about(tower.fire_rate, 1.2 * 1.20))
	_check("tier 2 raises the XP level cap to 7", tower.max_level() == 7)

	# The raised cap actually lets a tier-2 tower level past 5 on kills.
	tower.gain_experience(100000)
	_check("a tier-2 tower can climb past XP level 5", tower.level == 7)
	_check("a maxed tier-2 tower reports max level", tower.is_at_max_level())

	tower.queue_free()


## --- Main: the every-5-rounds choice trigger and the upgrade action --------
func _test_main_choice_and_upgrade() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main._on_starting_element_chosen(ElementTypes.Element.FIRE)  # unpauses the run
	await get_tree().process_frame

	# A choice is offered after every 5th wave survived, but never after the
	# final wave (that's the victory, not a choice).
	_check("wave 5 offers a choice", main._should_offer_choice(5))
	_check("wave 15 offers a choice", main._should_offer_choice(15))
	_check("wave 20 (the last) offers no choice", not main._should_offer_choice(20))
	_check("a non-multiple wave offers no choice", not main._should_offer_choice(7))

	# The choice screen pauses the run and only a pick resumes it.
	main._begin_element_choice()
	_check("the choice screen pauses the run", get_tree().paused)
	main._on_element_choice_made(ElementTypes.Element.WATER)
	_check("making a choice unlocks the element", GameManager.is_element_unlocked(ElementTypes.Element.WATER))
	_check("making a choice resumes the run", not get_tree().paused)

	# Upgrade gating: a tower can only be upgraded while its element out-tiers it.
	var tower = load("res://scenes/Tower.tscn").instantiate()
	main.entities.add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)  # element is tier 1, tower is tier 1
	_check("a tower level with its element can't be upgraded", not main._can_upgrade_tower(tower))

	GameManager.choose_element(ElementTypes.Element.FIRE)  # element -> tier 2
	_check("a tower below its element's tier can be upgraded", main._can_upgrade_tower(tower))

	# Performing the upgrade spends gold and steps the tower up one tier.
	GameManager.gold = 200
	main._on_tower_upgrade_requested(tower)
	_check("upgrading charges the upgrade cost", GameManager.gold == 50)
	_check("upgrading steps the tower to tier 2", tower.tier == 2)
	_check("a tower back at its element's tier can't be upgraded again", not main._can_upgrade_tower(tower))

	# Too poor to upgrade: element is tier 3 but the player can't pay.
	GameManager.choose_element(ElementTypes.Element.FIRE)  # element -> tier 3
	GameManager.gold = 50  # upgrade costs 150
	main._on_tower_upgrade_requested(tower)
	_check("upgrading with too little gold does nothing", tower.tier == 2 and GameManager.gold == 50)

	# The detail panel mirrors that state: element tier 3 > tower tier 2, broke.
	var panel = main.hud.tower_detail
	main.hud.show_tower_detail(tower)
	_check("upgrade button offers the next tier with its price",
		panel._upgrade_button.text.contains("Upgrade") and panel._upgrade_button.text.contains("150"))
	_check("upgrade button is disabled when the player can't afford it",
		panel._upgrade_button.disabled)

	GameManager.gold = 200
	main.hud.show_tower_detail(tower)  # re-populates, re-evaluating affordability
	_check("upgrade button enables once affordable", not panel._upgrade_button.disabled)

	# Step the tower up to its element's tier - the button should read maxed.
	main._on_tower_upgrade_requested(tower)  # tier 2 -> 3 == element tier
	main.hud.show_tower_detail(tower)
	_check("upgrade button reads max at the element's tier",
		panel._upgrade_button.text.contains("max") and panel._upgrade_button.disabled)

	main.queue_free()


## The choice card should preview the stats of the tier the button advances TO,
## not the tier the element is at now, so the payoff of advancing is visible.
func _test_choice_previews_resulting_tier() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main._on_starting_element_chosen(ElementTypes.Element.FIRE)  # Fire owned at tier 1
	await get_tree().process_frame

	main.hud.show_element_choice()
	var es = main.hud.element_select

	# Fire is owned at tier 1; the button advances it to tier 2, so preview tier 2.
	_check("owned element's card previews the next tier's damage",
		es._stat_values[ElementTypes.Element.FIRE]["damage"].text == "%.0f" % (8.0 * 1.50))
	_check("owned element's card previews the next tier's fire rate",
		es._stat_values[ElementTypes.Element.FIRE]["fire_rate"].text == "%.1f/s" % (1.2 * 1.20))

	# Water is unowned; unlocking gives tier 1, so its card shows the base stats.
	_check("unowned element's card shows its tier-1 stats",
		es._stat_values[ElementTypes.Element.WATER]["damage"].text == "%.0f" % 6.0)

	main.queue_free()


## An enemy removed once must not fire its removal signal twice. Two lethal hits
## in the same frame (two projectiles) previously each emitted `died`, which
## over-decremented WaveSpawner's live count and re-fired wave_cleared per kill.
func _test_enemy_removed_once() -> void:
	GameManager.new_game()
	var enemy = load("res://scenes/Enemy.tscn").instantiate()
	add_child(enemy)
	enemy.configure({
		"element": ElementTypes.Element.FIRE,
		"health": 10.0, "speed": 60.0, "gold": 5, "xp": 10,
		"lives": 1, "rank": Enemy.Rank.BASIC,
	})

	# Count via an Array - a lambda captures primitive locals by value, so an
	# int counter would never see the mutation; an Array is captured by reference.
	var deaths := [0]
	enemy.died.connect(func(_e: Node) -> void: deaths[0] += 1)
	enemy.take_damage(1000.0, ElementTypes.Element.EARTH)  # lethal
	enemy.take_damage(1000.0, ElementTypes.Element.EARTH)  # same frame, already dying
	_check("a lethal hit emits died exactly once", deaths[0] == 1)
	enemy.queue_free()


## Defense in depth: even if a stray removal slipped through, the spawner must
## announce a wave cleared (and, on the last wave, win) only once - so the tier
## choice / victory screen can't reopen. Drives _on_enemy_removed past zero.
func _test_wave_cleared_fires_once() -> void:
	GameManager.new_game()
	for _i in GameManager.MAX_WAVES:
		GameManager.advance_wave()  # sit on the final wave

	var root := Node2D.new()
	add_child(root)
	var entities := Node2D.new()
	entities.name = "Entities"
	root.add_child(entities)
	var spawner := Node2D.new()
	spawner.set_script(load("res://scripts/WaveSpawner.gd"))
	spawner.entities_path = ^"../Entities"
	root.add_child(spawner)

	var cleared := [0]
	var won := [0]
	spawner.wave_cleared.connect(func(_w: int) -> void: cleared[0] += 1)
	GameManager.victory.connect(func() -> void: won[0] += 1)

	spawner._alive_enemies = 1
	spawner._spawning = false
	spawner._on_enemy_removed(null)  # the real last kill: clears + wins
	spawner._on_enemy_removed(null)  # a stray extra removal must be ignored

	_check("wave_cleared fires once per wave", cleared[0] == 1)
	_check("victory fires once", won[0] == 1)

	root.queue_free()
