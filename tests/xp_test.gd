extends Node
## Headless check for tower experience. Run as a SCENE (not -s) so the autoloads
## register first:
##   Godot --headless --path . res://tests/xp_test.tscn
## Exits 0 on success, 1 on any failed assertion.

var _failures := 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok: ", label)
	else:
		_failures += 1
		print("  FAIL: ", label)


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


## Latest child FloatingText whose text matches, or null.
func _find_floating_text(want: String) -> Node:
	var found: Node = null
	for c in get_children():
		if c.get("text") == want:
			found = c
	return found


## Fire one lethal projectile from `shooter` at a fresh enemy and let it land.
func _kill_one(shooter: Node2D) -> void:
	var e = load("res://scenes/Enemy.tscn").instantiate()
	add_child(e)
	e.configure({
		"element": ElementTypes.Element.WATER,
		"health": 5.0, "speed": 60.0, "gold": 5, "xp": 10, "lives": 1,
		"rank": Enemy.Rank.BASIC,
	})
	var p = load("res://scenes/Projectile.tscn").instantiate()
	add_child(p)
	p.global_position = e.aim_position()
	p.setup(e, 9999.0, ElementTypes.Element.FIRE, shooter)
	await get_tree().process_frame
	await get_tree().process_frame


func _new_tower() -> Node2D:
	var tower: Node2D = load("res://scenes/Tower.tscn").instantiate()
	add_child(tower)
	tower.configure(ElementTypes.Element.FIRE)
	return tower


func _ready() -> void:
	# Base stats at level 1.
	var t := _new_tower()
	_check("starts level 1", t.level == 1)
	_check("base damage 8", _approx(t.damage, 8.0))
	_check("base fire rate 1.2", _approx(t.fire_rate, 1.2))
	_check("xp to next is 100", t.experience_to_next_level() == 100)

	# One level: +18% dmg, +12% rate off base, xp rolled over to 0.
	t.gain_experience(100)
	_check("level 2 after 100 xp", t.level == 2)
	_check("xp reset to 0", t.experience == 0)
	_check("dmg 9.44 at L2", _approx(t.damage, 9.44))
	_check("rate 1.344 at L2", _approx(t.fire_rate, 1.344))

	# Level-up spawns a visible "Level up!" popup (rides above the map on z=100).
	var popup := _find_floating_text("Level up!")
	_check("level-up spawns a popup", popup != null)
	if popup != null:
		_check("popup rides above map (z=100)", popup.z_index == 100)
		_check("popup has a visible lifetime", popup.lifetime >= 0.5)

	# Overflow rolls through multiple levels (100 -> L2, 160 -> L3).
	var t2 := _new_tower()
	t2.gain_experience(260)
	_check("260 xp reaches level 3", t2.level == 3)
	_check("no leftover xp", t2.experience == 0)

	# Partial progress below a threshold.
	var t3 := _new_tower()
	t3.gain_experience(50)
	_check("stays level 1 at 50 xp", t3.level == 1)
	_check("holds 50 xp", t3.experience == 50)

	# Cap at level 5, stats maxed, no more xp taken.
	var t4 := _new_tower()
	t4.gain_experience(100000)
	_check("caps at level 5", t4.level == 5)
	_check("at max level", t4.is_at_max_level())
	_check("xp to next is 0 at cap", t4.experience_to_next_level() == 0)
	_check("dmg 13.76 at L5", _approx(t4.damage, 13.76))
	_check("rate 1.776 at L5", _approx(t4.fire_rate, 1.776))
	t4.gain_experience(500)
	_check("no xp gained past cap", t4.experience == 0 and t4.level == 5)
	t4.register_kill(10)
	_check("kills still count past the level cap", t4.kills == 1 and t4.level == 5)

	# Kill-path attribution: the killing blow credits the source tower.
	var killer := _new_tower()
	var enemy = load("res://scenes/Enemy.tscn").instantiate()
	add_child(enemy)
	enemy.configure({
		"element": ElementTypes.Element.WATER,  # opposite of fire -> 125%
		"health": 5.0,
		"speed": 60.0,
		"gold": 5,
		"xp": 10,
		"lives": 1,
		"rank": Enemy.Rank.BASIC,
	})
	enemy.take_damage(9999.0, ElementTypes.Element.FIRE, killer)
	_check("killer gained enemy xp", killer.experience == 10)
	_check("killer kill counted", killer.kills == 1)

	# Full in-game path: a LIVE tower's projectiles kill enemies until it levels,
	# proving XP flows tower -> projectile -> enemy death -> level-up popup.
	var shooter := _new_tower()
	for i in 10:  # 10 basic kills x 10 xp = 100 = level 2
		await _kill_one(shooter)
	_check("live tower reached level 2 via projectile kills", shooter.level == 2)
	_check("kills tracked through the projectile path", shooter.kills == 10)
	_check("projectile-driven level-up spawned a popup", _find_floating_text("Level up!") != null)

	# A killing blow from a sold (freed) tower must not error: drive it through a
	# real projectile whose source is freed mid-flight, exactly as a sell does.
	var enemy2 = load("res://scenes/Enemy.tscn").instantiate()
	add_child(enemy2)
	enemy2.configure({
		"element": ElementTypes.Element.WATER,
		"health": 5.0, "speed": 60.0, "gold": 5, "xp": 10, "lives": 1,
		"rank": Enemy.Rank.BASIC,
	})
	var doomed := _new_tower()
	var proj = load("res://scenes/Projectile.tscn").instantiate()
	add_child(proj)
	proj.global_position = enemy2.aim_position()  # right on top -> hits next frame
	proj.setup(enemy2, 9999.0, ElementTypes.Element.FIRE, doomed)
	doomed.free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("freed-tower killing blow didn't crash the enemy", not is_instance_valid(enemy2))

	print("xp_test: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
