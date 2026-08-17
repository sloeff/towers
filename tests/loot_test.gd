extends Node
## Headless check for potions and items (DESIGN_DOC section 6): the Inventory
## bag, the generic modifier stack on Tower, Gold Find on a killing blow, the
## drop roll, and Main's apply/equip/unequip flow. Run as a SCENE:
##   Godot --headless --path . res://tests/loot_test.tscn
## Exits 0 on success, 1 on any failed assertion.

var _failures := 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok: ", label)
	else:
		_failures += 1
		print("  FAIL: ", label)


func _about(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


func _ready() -> void:
	_test_inventory()
	_test_tower_modifiers()
	_test_modifiers_survive_tier_and_transform()
	_test_item_slots()
	_test_gold_find()
	_test_drop_roll()
	await _test_main_loot_flow()
	await _test_panels()

	print("loot_test: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## --- Inventory: the bag ----------------------------------------------------
func _test_inventory() -> void:
	Inventory.reset()
	_check("a fresh bag is empty", Inventory.is_empty() and Inventory.total_held() == 0)

	Inventory.add(Loot.Id.GOLD_FIND)
	Inventory.add(Loot.Id.GOLD_FIND)
	Inventory.add(Loot.Id.RUBY_CORE)
	_check("adding stacks the same loot", Inventory.count(Loot.Id.GOLD_FIND) == 2)
	_check("total_held counts across stacks", Inventory.total_held() == 3)
	_check("total_found tracks everything found this run", Inventory.total_found == 3)

	_check("ids_of_kind filters to potions",
		Inventory.ids_of_kind(Loot.Kind.POTION) == ([Loot.Id.GOLD_FIND] as Array[int]))
	_check("ids_of_kind filters to items",
		Inventory.ids_of_kind(Loot.Kind.ITEM) == ([Loot.Id.RUBY_CORE] as Array[int]))

	_check("removing takes one off the stack",
		Inventory.remove(Loot.Id.GOLD_FIND) and Inventory.count(Loot.Id.GOLD_FIND) == 1)
	_check("removing the last one drops the stack",
		Inventory.remove(Loot.Id.GOLD_FIND) and not Inventory.has(Loot.Id.GOLD_FIND))
	_check("removing what you don't have fails", not Inventory.remove(Loot.Id.GOLD_FIND))

	# A restart must not carry loot over.
	GameManager.new_game()
	_check("new_game empties the bag", Inventory.is_empty() and Inventory.total_found == 0)


## --- Tower: the generic modifier stack -------------------------------------
func _test_tower_modifiers() -> void:
	var tower = load("res://scenes/Tower.tscn").instantiate()
	add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)  # base: 8 dmg, 1.2/s, range 170

	_check("a fresh tower has no loot on it",
		tower.potion_mods.is_empty() and tower.items.is_empty())
	_check("no loot means the base damage", _about(tower.damage, 8.0))

	tower.apply_potion(Loot.Id.SHARPENING_OIL)  # +10% damage
	_check("a potion raises the stat it modifies", _about(tower.damage, 8.0 * 1.10))
	_check("a potion is recorded for the panel badges",
		tower.potions_taken == ([Loot.Id.SHARPENING_OIL] as Array[int]))

	# Two sources of the same key add, they don't multiply: +10% and +20% is +30%.
	tower.equip_item(Loot.Id.RUBY_CORE)  # +20% damage
	_check("potion and item bonuses of the same key add", _about(tower.damage, 8.0 * 1.30))
	_check("mod_total sums across potions and items",
		_about(tower.mod_total(Loot.MOD_DAMAGE), 0.30))

	# Range and AoE are modifiable too - the reason they're derived stats now.
	tower.apply_potion(Loot.Id.FARSIGHT)  # +8% range
	_check("range scales with loot", _about(tower.range_radius, 170.0 * 1.08))
	_check("an unrelated stat is untouched", _about(tower.fire_rate, 1.2))

	tower.queue_free()


## The regression the derived-stat refactor exists for: a tier upgrade or a combo
## transform recomputes every stat, so it must not wipe the loot bonuses.
func _test_modifiers_survive_tier_and_transform() -> void:
	var tower = load("res://scenes/Tower.tscn").instantiate()
	add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)
	tower.apply_potion(Loot.Id.FARSIGHT)         # +8% range
	tower.apply_potion(Loot.Id.SHARPENING_OIL)   # +10% damage

	tower.upgrade_tier()  # tier 2: +50% damage, +20% fire rate, range untouched
	_check("a tier upgrade keeps the range bonus", _about(tower.range_radius, 170.0 * 1.08))
	_check("tier and loot damage bonuses stack",
		_about(tower.damage, 8.0 * 1.50 * 1.10))

	# Transforming swaps in the combo's bases; the loot rides across.
	tower.transform_into(Combos.Combo.FIRE_BREATH)  # 18 dmg, range 200, aoe 85
	_check("a transform keeps the loot bonuses",
		_about(tower.range_radius, 200.0 * 1.08) and _about(tower.damage, 18.0 * 1.10))

	# Splash is a modifiable stat, so Blast Cap has to reach it on a combo.
	tower.equip_item(Loot.Id.BLAST_CAP)  # +25% splash
	_check("splash scales with loot", _about(tower.aoe_radius, 85.0 * 1.25))

	tower.queue_free()


## --- Tower: item slots -----------------------------------------------------
func _test_item_slots() -> void:
	var tower = load("res://scenes/Tower.tscn").instantiate()
	add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)

	for i in tower.MAX_ITEM_SLOTS:
		_check("slot %d accepts an item" % i, tower.equip_item(Loot.Id.RUBY_CORE))
	_check("a full tower reports no free slot", not tower.has_free_item_slot())
	_check("equipping into a full tower fails", not tower.equip_item(Loot.Id.RUBY_CORE))
	_check("three +20% items give +60% damage", _about(tower.damage, 8.0 * 1.60))

	_check("unequipping hands the item back", tower.unequip_item(0) == Loot.Id.RUBY_CORE)
	_check("unequipping removes its bonus", _about(tower.damage, 8.0 * 1.40))
	_check("unequipping an empty slot yields nothing", tower.unequip_item(5) == -1)

	tower.queue_free()


## --- Gold Find: paid to the tower that lands the killing blow ---------------
func _test_gold_find() -> void:
	GameManager.new_game()
	var tower = load("res://scenes/Tower.tscn").instantiate()
	add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)
	tower.apply_potion(Loot.Id.GOLD_FIND)  # +2 gold per kill
	_check("Gold Find reports its bonus", tower.gold_find_bonus() == 2)

	var before: int = GameManager.gold
	_kill_enemy(tower)
	_check("a kill pays the reward plus Gold Find", GameManager.gold == before + 5 + 2)

	# A tower without the potion pays the plain reward, and so does a kill with no
	# surviving killer (the tower was sold between the shot and the hit).
	var plain = load("res://scenes/Tower.tscn").instantiate()
	add_child(plain)
	plain.configure(ElementTypes.Element.FIRE)
	before = GameManager.gold
	_kill_enemy(plain)
	_check("a kill without Gold Find pays the plain reward", GameManager.gold == before + 5)

	before = GameManager.gold
	_kill_enemy(null)
	_check("a kill with no surviving killer still pays the reward",
		GameManager.gold == before + 5)

	tower.queue_free()
	plain.queue_free()


## Spawn a basic enemy worth 5 gold and kill it outright, crediting `killer`.
func _kill_enemy(killer) -> void:
	var enemy = load("res://scenes/Enemy.tscn").instantiate()
	add_child(enemy)
	enemy.configure({
		"element": ElementTypes.Element.FIRE,
		"health": 10.0, "speed": 60.0, "gold": 5, "xp": 10,
		"lives": 1, "rank": Enemy.Rank.BASIC,
	})
	enemy.take_damage(1000.0, ElementTypes.Element.EARTH, killer)


## --- Drops -----------------------------------------------------------------
func _test_drop_roll() -> void:
	_check("a boss always drops", Loot.drop_chance(Enemy.Rank.BOSS) == 1.0)
	_check("a captain drops more often than a basic",
		Loot.drop_chance(Enemy.Rank.CAPTAIN) > Loot.drop_chance(Enemy.Rank.BASIC))
	_check("an all-resist drops more often than a plain basic",
		Loot.drop_chance(Enemy.Rank.BASIC, true) > Loot.drop_chance(Enemy.Rank.BASIC, false))

	seed(1234)
	_check("a boss kill always yields a real loot id",
		Loot.roll_drop(Enemy.Rank.BOSS) in Loot.DATA)

	# Magic find raises the odds. Seeded so the comparison is deterministic; the
	# gap (4% vs 8% over 4000 rolls) is far wider than the sampling noise.
	var rolls := 4000
	seed(99)
	var plain := _count_drops(rolls, 0.0)
	seed(99)
	var lucky := _count_drops(rolls, 1.0)
	_check("magic find produces more drops", lucky > plain)
	_check("basic drops stay rare", plain < rolls / 4)

	# Leaking must never pay loot: the roll lives on the kill path only.
	GameManager.new_game()
	var enemy = load("res://scenes/Enemy.tscn").instantiate()
	add_child(enemy)
	enemy.configure({
		"element": ElementTypes.Element.FIRE,
		"health": 10.0, "speed": 60.0, "gold": 5, "xp": 10,
		"lives": 1, "rank": Enemy.Rank.BOSS,  # would always drop if it were killed
	})
	enemy._on_reached_goal()
	_check("an enemy that reaches the exit drops nothing", Inventory.total_found == 0)


func _count_drops(rolls: int, magic_find: float) -> int:
	var drops := 0
	for _i in rolls:
		if Loot.roll_drop(Enemy.Rank.BASIC, false, magic_find) >= 0:
			drops += 1
	return drops


## --- Main: the apply / equip / unequip flow --------------------------------
func _test_main_loot_flow() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main._on_starting_element_chosen(ElementTypes.Element.FIRE)
	await get_tree().process_frame

	var tower = load("res://scenes/Tower.tscn").instantiate()
	main.entities.add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)
	tower.cell = Vector2i(4, 4)
	main._towers_by_cell[tower.cell] = tower

	Inventory.reset()
	Inventory.add(Loot.Id.SHARPENING_OIL)
	Inventory.add(Loot.Id.RUBY_CORE)

	# Drinking a potion spends it out of the bag for good.
	main._on_tower_use_potion_requested(tower)
	main._on_loot_picked(Loot.Id.SHARPENING_OIL)
	_check("applying a potion takes it out of the bag",
		not Inventory.has(Loot.Id.SHARPENING_OIL))
	_check("applying a potion boosts the tower", _about(tower.damage, 8.0 * 1.10))

	# Equipping moves the item onto the tower; unequipping returns it.
	main._on_tower_equip_requested(tower)
	main._on_loot_picked(Loot.Id.RUBY_CORE)
	_check("equipping takes the item out of the bag", not Inventory.has(Loot.Id.RUBY_CORE))
	_check("equipping fills a slot", tower.items.size() == 1)
	_check("equipping boosts the tower", _about(tower.damage, 8.0 * 1.30))

	main._on_tower_unequip_requested(tower, 0)
	_check("unequipping returns the item to the bag", Inventory.has(Loot.Id.RUBY_CORE))
	_check("unequipping removes its bonus", _about(tower.damage, 8.0 * 1.10))

	# Picking loot the bag no longer holds is a no-op, not a free copy.
	main._on_tower_use_potion_requested(tower)
	main._on_loot_picked(Loot.Id.SHARPENING_OIL)
	_check("picking loot you no longer hold does nothing",
		_about(tower.damage, 8.0 * 1.10) and tower.potions_taken.size() == 1)

	# Selling a tower returns its equipped items to the bag; drunk potions are gone.
	main._on_tower_equip_requested(tower)
	main._on_loot_picked(Loot.Id.RUBY_CORE)
	main._on_tower_sell_requested(tower)
	_check("selling a tower returns its items to the bag",
		Inventory.has(Loot.Id.RUBY_CORE))

	main.queue_free()


## --- The two panels: the bag and the loot half of the tower detail ---------
func _test_panels() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	main._on_starting_element_chosen(ElementTypes.Element.FIRE)
	await get_tree().process_frame

	var tower = load("res://scenes/Tower.tscn").instantiate()
	main.entities.add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)

	var panel = main.hud.tower_detail
	var bag = main.hud.inventory_panel

	# Empty bag: the loot controls are visible but inert, so the player can see
	# the tower has slots without being able to click into an empty list.
	Inventory.reset()
	main.hud.show_tower_detail(tower)
	_check("the potion button is disabled with an empty bag", panel._potion_button.disabled)
	_check("item slots are disabled with an empty bag", panel._item_slots[0].disabled)
	_check("a tower with no potions shows no badges",
		panel._potion_row.get_child_count() == 0)
	_check("the bag button counts nothing", main.hud.bag_button.text == "Bag (0)")

	Inventory.add(Loot.Id.SHARPENING_OIL)
	Inventory.add(Loot.Id.RUBY_CORE)
	main.hud.show_tower_detail(tower)
	_check("the potion button enables once a potion is held",
		not panel._potion_button.disabled)
	_check("the bag button shows the count", main.hud.bag_button.text == "Bag (2)")

	# Drinking and equipping show up on the panel.
	main._on_tower_use_potion_requested(tower)
	main._on_loot_picked(Loot.Id.SHARPENING_OIL)
	main._on_tower_equip_requested(tower)
	main._on_loot_picked(Loot.Id.RUBY_CORE)
	main.hud.show_tower_detail(tower)
	_check("a drunk potion adds a badge", panel._potion_row.get_child_count() == 1)
	_check("an equipped item labels its slot",
		panel._item_slots[0].text == Loot.badge_of(Loot.Id.RUBY_CORE))
	_check("an empty slot stays marked empty", panel._item_slots[1].text == "+")
	_check("Gold Find is hidden without the potion", not panel._gold_find.visible)

	tower.apply_potion(Loot.Id.GOLD_FIND)
	main.hud.show_tower_detail(tower)
	_check("Gold Find shows once the tower has it",
		panel._gold_find.visible and panel._gold_find.text.contains("+2g"))

	# The bag button opens and closes the browse view.
	main.hud._on_bag_pressed()
	_check("the bag button opens the bag", bag.visible)
	_check("an emptied bag shows its empty notice", bag._list.get_child_count() == 1)
	main.hud._on_bag_pressed()
	_check("the bag button closes it again", not bag.visible)

	# A filtered pick lists only that kind, one row per held stack.
	Inventory.add(Loot.Id.RUBY_CORE)
	Inventory.add(Loot.Id.FARSIGHT)
	main.hud.show_loot_pick(Loot.Kind.ITEM)
	_check("a pick view lists only the filtered kind", bag._list.get_child_count() == 1)
	main.hud.show_loot_pick(Loot.Kind.POTION)
	_check("the potion pick lists the held potion", bag._list.get_child_count() == 1)

	# Escape (Main's cancel) abandons a pending pick and closes the bag with it.
	main._loot_target = tower
	main._on_cancel()
	_check("cancelling closes a pending pick", not bag.visible and main._loot_target == null)

	# The bag is a full-screen panel that draws over the element-choice and
	# result screens, and it stops processing when the tree pauses - so leaving it
	# open across a pause would cover those screens with a panel whose own Close
	# button no longer responds. Anything that pauses the run must close it.
	main.hud._on_bag_pressed()
	main._begin_element_choice()
	_check("a pause closes the bag", not bag.visible)
	main._on_element_choice_made(ElementTypes.Element.WATER)

	main.hud._on_bag_pressed()
	main._on_game_over()
	_check("game over closes the bag", not bag.visible)

	main.queue_free()
