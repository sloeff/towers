# Combination Towers — Fire Breath Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the transform-into-a-combination-tower pipeline end to end, carrying one combo — Fire Breath (Fire + Air) — with area-of-effect damage.

**Architecture:** A new `Combos` autoload holds combo data + lookups. A placed basic `Tower` is transformed in place into a combo (same node, combo stats + AoE param + presentation accessors). `Projectile` gains an optional AoE-on-impact path. `GameManager` gains two run-state queries (`available_tier`, `available_combo_for`). The tower detail panel gains a Transform button wired through HUD → Main.

**Tech Stack:** Godot 4.7.1, GDScript, GL Compatibility renderer. Standalone headless scene tests (`extends Node` + `.tscn`, run via `Godot --headless --path . res://tests/X.tscn`, self-quitting `0`/`1`).

**Spec:** `docs/superpowers/specs/2026-08-14-combination-towers-fire-breath-design.md`

## Global Constraints

- Godot binary is not on PATH: `~/Downloads/Godot.app/Contents/MacOS/Godot`.
- Run a test scene: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/<name>.tscn` (exit 0 = pass, 1 = fail).
- **Never run `git commit`/`git push`** — the user commits. "Commit" steps below mean **stage with `git add` and stop**; report the suggested commit message to the user, do not execute the commit.
- Never run `git checkout`/`git restore` on files with uncommitted work (this repo has bitten us: it silently reverted an in-progress fix).
- Follow existing patterns: data authorities are autoloads mirroring `ElementTypes`; UI is built in code; static helpers are reached via `preload(...)` + call (see `ElementSelect` calling `Tower`'s `damage_at_tier`).
- Balance numbers live only in `Combos.DATA` — never hardcode them elsewhere.
- All existing test scenes must stay green: `tests/tier_test.tscn`, plus any `fit`/`touch`/`xp` suites present.

---

### Task 1: `Combos` autoload — data + lookups

**Files:**
- Create: `autoload/Combos.gd`
- Modify: `project.godot` (register autoload immediately after `ElementTypes`)
- Create: `tests/combo_test.gd`
- Create: `tests/combo_test.tscn`

**Interfaces:**
- Consumes: `ElementTypes.Element` (FIRE, AIR, WATER).
- Produces:
  - autoload `Combos` with `enum Combo { FIRE_BREATH }` and `const DATA`.
  - `Combos.combo_for(a: int, b: int) -> int` (order-independent; −1 if none).
  - `Combos.combos_including(element: int) -> Array[int]`.
  - `Combos.name_of(combo_id: int) -> String`, `Combos.color_of(combo_id: int) -> Color`.
  - `DATA[id]` keys: `name`, `parents: Array`, `damage_element: int`, `color: Color`, `damage: float`, `fire_rate: float`, `range: float`, `aoe_radius: float`, `cost: int`, `transform_cost: int`.

- [ ] **Step 1: Write the failing test**

Create `tests/combo_test.gd`:

```gdscript
extends Node
## Headless checks for the combination-tower first slice (Fire Breath).
## Run as a SCENE: Godot --headless --path . res://tests/combo_test.tscn
## Exits 0 on success, 1 on any failed assertion.

const ProjectileScript := preload("res://scripts/Projectile.gd")

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
	_check("an undefined pair is -1",
		Combos.combo_for(ElementTypes.Element.FIRE, ElementTypes.Element.WATER) == -1)
	_check("Fire Breath's parents are Fire and Air",
		Combos.DATA[fb]["parents"].has(ElementTypes.Element.FIRE)
		and Combos.DATA[fb]["parents"].has(ElementTypes.Element.AIR))
	_check("Fire Breath deals Fire-typed damage",
		Combos.DATA[fb]["damage_element"] == ElementTypes.Element.FIRE)
	_check("combos_including(FIRE) contains Fire Breath",
		Combos.combos_including(ElementTypes.Element.FIRE).has(fb))
	_check("combos_including(WATER) is empty in this slice",
		Combos.combos_including(ElementTypes.Element.WATER).is_empty())
```

Create `tests/combo_test.tscn` (a scene whose root runs the script — mirror `tests/tier_test.tscn`):

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/combo_test.gd" id="1"]

[node name="ComboTest" type="Node"]
script = ExtResource("1")
```

> If `tests/tier_test.tscn` differs (e.g. different `format`/`uid`), copy its exact structure and only swap the script path and node name.

- [ ] **Step 2: Run test to verify it fails**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Expected: FAIL — `Combos` autoload does not exist yet (parser/identifier error or failed asserts). Exit code 1.

- [ ] **Step 3: Create the `Combos` autoload**

Create `autoload/Combos.gd`:

```gdscript
extends Node
## Data authority for combination towers (DESIGN_DOC section 8). Pure data plus
## lookups, mirroring ElementTypes; no GameManager dependency. Adding a combo is
## a DATA entry, never a logic change. Registered in project.godot [autoload]
## after ElementTypes (DATA references ElementTypes.Element at load time).

enum Combo { FIRE_BREATH }

const DATA := {
	Combo.FIRE_BREATH: {
		"name": "Fire Breath",
		"parents": [ElementTypes.Element.FIRE, ElementTypes.Element.AIR],
		# Element used for the damage multiplier AND the projectile colour.
		"damage_element": ElementTypes.Element.FIRE,
		"color": Color(0.98, 0.55, 0.15),  # distinct orange-gold
		"damage": 18.0,
		"fire_rate": 1.3,
		"range": 200.0,
		"aoe_radius": 85.0,
		"cost": 130,            # feeds upgrade_cost (x3) and sell_value (75%)
		"transform_cost": 100,  # gold to transform, on top of the basic build
	},
}


## The combo formed by an unordered pair of distinct elements, or -1 if none.
func combo_for(a: int, b: int) -> int:
	for id in DATA:
		var parents: Array = DATA[id]["parents"]
		if a != b and a in parents and b in parents:
			return id
	return -1


## Every combo whose parents include `element` (for partner-ownership checks).
func combos_including(element: int) -> Array[int]:
	var out: Array[int] = []
	for id in DATA:
		if element in DATA[id]["parents"]:
			out.append(id)
	return out


func name_of(combo_id: int) -> String:
	return DATA[combo_id]["name"]


func color_of(combo_id: int) -> Color:
	return DATA[combo_id]["color"]
```

- [ ] **Step 4: Register the autoload**

Modify `project.godot` `[autoload]` block so `Combos` loads right after `ElementTypes`:

```ini
[autoload]

GameManager="*res://autoload/GameManager.gd"
ElementTypes="*res://autoload/ElementTypes.gd"
Combos="*res://autoload/Combos.gd"
GridManager="*res://autoload/GridManager.gd"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Expected: PASS — `combo_test: 0 failure(s)`, exit code 0.

- [ ] **Step 6: Stage (do not commit)**

```bash
git add autoload/Combos.gd project.godot tests/combo_test.gd tests/combo_test.tscn
```
Suggested message for the user: `feat: add Combos autoload (Fire Breath data + lookups)`

---

### Task 2: `Tower` combo identity + `transform_into` + accessors

**Files:**
- Modify: `scripts/Tower.gd`
- Test: `tests/combo_test.gd`

**Interfaces:**
- Consumes: `Combos.DATA`, `Combos.name_of`, `Combos.color_of`.
- Produces (on `Tower`):
  - fields `is_combo: bool`, `combo_id: int`, `parent_elements: Array[int]`, `aoe_radius: float`.
  - `transform_into(new_combo_id: int) -> void` — sets combo stats, keeps `level`/`experience`, resets `tier` to 1, recomputes stats.
  - `display_name() -> String`, `display_color() -> Color`, `source_elements() -> Array[int]`.

- [ ] **Step 1: Write the failing test**

Add to `tests/combo_test.gd` — a new test function and call it from `_ready()` before the print:

In `_ready()`, add after `_test_registry()`:
```gdscript
	_test_transform()
```

Add the function:
```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Expected: FAIL — `transform_into`/`is_combo`/`display_name` do not exist. Exit 1.

- [ ] **Step 3: Add combo state to `Tower`**

In `scripts/Tower.gd`, add fields next to the existing `var tier: int = 1` block:

```gdscript
## Combination-tower identity (DESIGN_DOC section 8). A basic tower is
## transformed in place into a combo via transform_into(); these stay at their
## defaults for a basic tower. `element` continues to mean the damage element
## for the multiplier and projectile, so a combo sets it to its damage_element.
var is_combo: bool = false
var combo_id: int = -1
var parent_elements: Array[int] = []
## Splash radius on the un-squashed ground plane; 0 = single-target (all basics).
var aoe_radius: float = 0.0
```

- [ ] **Step 4: Add `transform_into` and the accessors**

In `scripts/Tower.gd`, add (near `upgrade_tier`):

```gdscript
## Turn this placed basic tower into a combination tower: swap in the combo's
## base stats and AoE, keep the earned XP level, and reset the tier to 1 (a combo
## has its own ladder). The caller checks ownership and charges gold.
func transform_into(new_combo_id: int) -> void:
	var data: Dictionary = Combos.DATA[new_combo_id]
	is_combo = true
	combo_id = new_combo_id
	parent_elements = data["parents"]
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Expected: PASS — `combo_test: 0 failure(s)`, exit 0.

- [ ] **Step 6: Verify no regression**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/tier_test.tscn`
Expected: PASS — `tier_test: 0 failure(s)`, exit 0.

- [ ] **Step 7: Stage (do not commit)**

```bash
git add scripts/Tower.gd tests/combo_test.gd
```
Suggested message: `feat: add combo identity and transform_into to Tower`

---

### Task 3: `Tower` uses `display_color()` in `_draw()` and passes AoE to the projectile

**Files:**
- Modify: `scripts/Tower.gd:210` (the `_draw()` colour line) and `scripts/Tower.gd:200-204` (`_fire_at`)

**Interfaces:**
- Consumes: `display_color()` (Task 2); `Projectile.setup(target, damage, element, source, aoe_radius)` (Task 4 extends the signature — see note).
- Produces: no new API. Combo towers draw in their combo colour; `_fire_at` forwards `aoe_radius`.

> **Ordering note:** `_fire_at` passing a 5th argument requires `Projectile.setup` to accept it. Do Task 4 (which adds the defaulted `aoe_radius` param) in the same working session; the 5th argument is harmless once the default exists. If executing strictly one task at a time, apply the `_fire_at` edit as part of Task 4 instead. The `_draw()` colour change below is independent and safe on its own.

- [ ] **Step 1: Change `_draw()` to use the combo-aware colour**

In `scripts/Tower.gd`, in `_draw()` replace:
```gdscript
	var color: Color = ElementTypes.color_of(element).lightened((level - 1) * 0.08)
```
with:
```gdscript
	# display_color() returns the element colour for a basic tower (unchanged) and
	# the combo's distinct colour for a combination tower.
	var color: Color = display_color().lightened((level - 1) * 0.08)
```

- [ ] **Step 2: Forward the AoE radius when firing**

In `scripts/Tower.gd`, in `_fire_at()` replace:
```gdscript
	projectile.setup(target, damage, element, self)
```
with:
```gdscript
	projectile.setup(target, damage, element, self, aoe_radius)
```

- [ ] **Step 3: Sanity check (compiles, basics unaffected)**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/tier_test.tscn`
Expected: PASS. (This depends on Task 4's defaulted param being present — see the ordering note. If Task 4 isn't done yet, apply Step 2 together with Task 4.)

- [ ] **Step 4: Stage (do not commit)**

```bash
git add scripts/Tower.gd
```
Suggested message: `feat: draw combos in their own colour and fire AoE shots`

---

### Task 4: `Projectile` AoE on impact + `splash_targets` helper

**Files:**
- Modify: `scripts/Projectile.gd`
- Test: `tests/combo_test.gd`

**Interfaces:**
- Consumes: `Enemy.ground_position()`, `Enemy.take_damage(amount, element, source)`, the `"enemies"` group.
- Produces:
  - `Projectile.setup(target, damage, element, source, aoe_radius := 0.0)` — 5th param, defaulted so all existing callers are unchanged.
  - `static func splash_targets(center: Vector2, radius: float, enemies: Array) -> Array` — enemies within `radius` of `center` on the un-squashed ground plane; skips invalid nodes.

- [ ] **Step 1: Write the failing test**

Add to `tests/combo_test.gd`. In `_ready()` add after `_test_transform()`:
```gdscript
	_test_splash_targets()
```

Add the function (uses a tiny fake enemy so it doesn't depend on Enemy pathing):
```gdscript
## --- Projectile.splash_targets: circle on the un-squashed ground plane -------
func _test_splash_targets() -> void:
	# Fake enemies exposing just ground_position(), placed relative to a centre.
	# offset.y is halved by the 2:1 unsquash, so a point 120px below is treated
	# as 60px away — inside a 70px radius; a point 200px right is outside.
	var center := Vector2(500.0, 300.0)
	var near_x = _fake_enemy(center + Vector2(60.0, 0.0))    # 60px  -> in
	var near_y = _fake_enemy(center + Vector2(0.0, 120.0))   # 60px* -> in
	var far = _fake_enemy(center + Vector2(200.0, 0.0))      # 200px -> out
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


const _FAKE_ENEMY_SCRIPT := preload("res://tests/fake_enemy.gd")
```

Create `tests/fake_enemy.gd`:
```gdscript
extends Node2D
## Minimal stand-in for splash_targets tests: only ground_position() is needed.
func ground_position() -> Vector2:
	return global_position
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Expected: FAIL — `splash_targets` does not exist. Exit 1.

- [ ] **Step 3: Add the static helper and AoE impact to `Projectile`**

In `scripts/Projectile.gd`, add the AoE field near the other vars:
```gdscript
var _aoe_radius: float = 0.0
```

Change `setup()` to accept and store it:
```gdscript
func setup(target: Node2D, damage: float, element: int, source: Node2D, aoe_radius := 0.0) -> void:
	_target = target
	_damage = damage
	_element = element
	_source = source
	_aoe_radius = aoe_radius
	queue_redraw()
```

In `_process()`, at impact, replace the single `take_damage` call:
```gdscript
		var source: Node2D = _source if is_instance_valid(_source) else null
		_target.take_damage(_damage, _element, source)
		queue_free()
		return
```
with:
```gdscript
		var source: Node2D = _source if is_instance_valid(_source) else null
		if _aoe_radius > 0.0:
			# Same-script static call, unqualified (Projectile.gd has no class_name).
			for e in splash_targets(_target.ground_position(), _aoe_radius, get_tree().get_nodes_in_group("enemies")):
				e.take_damage(_damage, _element, source)
		else:
			_target.take_damage(_damage, _element, source)
		queue_free()
		return
```

Add the static helper at the end of `scripts/Projectile.gd`:
```gdscript
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Expected: PASS — `combo_test: 0 failure(s)`, exit 0.

- [ ] **Step 5: Stage (do not commit)**

```bash
git add scripts/Projectile.gd tests/combo_test.gd tests/fake_enemy.gd
```
Suggested message: `feat: add AoE-on-impact to Projectile with splash_targets`

---

### Task 5: `GameManager.available_tier` + `available_combo_for` (and swap call sites)

**Files:**
- Modify: `autoload/GameManager.gd`
- Modify: `scripts/Main.gd:137-138` (`_can_upgrade_tower`)
- Modify: `scripts/TowerDetailPanel.gd:263-274` (`_refresh_upgrade_button`)
- Test: `tests/combo_test.gd`

**Interfaces:**
- Consumes: `tower.source_elements()`, `tower.is_combo`, `tower.element` (Task 2); `Combos.combos_including`, `Combos.DATA` (Task 1); `element_tier`, `is_element_unlocked` (existing).
- Produces:
  - `GameManager.available_tier(tower) -> int` — min of `element_tier(e)` over `tower.source_elements()`.
  - `GameManager.available_combo_for(tower) -> int` — a combo the basic tower can make now (partner owned), else −1.

- [ ] **Step 1: Write the failing test**

Add to `tests/combo_test.gd`. In `_ready()` add after `_test_splash_targets()`:
```gdscript
	_test_available_queries()
```

Add the function:
```gdscript
## --- GameManager.available_tier / available_combo_for ------------------------
func _test_available_queries() -> void:
	GameManager.new_game()

	var fire_tower = load("res://scenes/Tower.tscn").instantiate()
	add_child(fire_tower)
	fire_tower.configure(ElementTypes.Element.FIRE)

	# Basic tower: available_tier tracks its own element's tier.
	GameManager.choose_element(ElementTypes.Element.FIRE)  # Fire -> tier 1
	_check("basic tower available_tier equals its element tier",
		GameManager.available_tier(fire_tower) == 1)

	# available_combo_for: no partner owned yet.
	_check("no combo offered before the partner is owned",
		GameManager.available_combo_for(fire_tower) == -1)

	GameManager.choose_element(ElementTypes.Element.AIR)  # Air -> tier 1
	_check("Fire tower can combo once Air is owned",
		GameManager.available_combo_for(fire_tower) == Combos.Combo.FIRE_BREATH)

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
		GameManager.available_combo_for(fire_tower) == -1)

	fire_tower.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Expected: FAIL — `available_tier`/`available_combo_for` do not exist. Exit 1.

- [ ] **Step 3: Add the two queries to `GameManager`**

In `autoload/GameManager.gd`, add (after `is_element_unlocked`):
```gdscript
## The highest tier this tower could be upgraded to right now: a basic tower is
## capped by its element's tier; a combo by the LOWER of its two parents' tiers.
func available_tier(tower) -> int:
	var cap: int = 0x7FFFFFFF
	for e in tower.source_elements():
		cap = mini(cap, element_tier(e))
	return cap


## A combo this basic tower can transform into right now (its partner element is
## owned), or -1. Combos themselves never re-transform in this slice.
func available_combo_for(tower) -> int:
	if tower.is_combo:
		return -1
	for combo_id in Combos.combos_including(tower.element):
		for parent in Combos.DATA[combo_id]["parents"]:
			if parent != tower.element and is_element_unlocked(parent):
				return combo_id
	return -1
```

- [ ] **Step 4: Swap the two upgrade-gating call sites to `available_tier`**

In `scripts/Main.gd`, `_can_upgrade_tower`:
```gdscript
func _can_upgrade_tower(tower: Node2D) -> bool:
	return GameManager.available_tier(tower) > tower.tier
```

In `scripts/TowerDetailPanel.gd`, `_refresh_upgrade_button`, change the first line from:
```gdscript
	var element_tier: int = GameManager.element_tier(_tower.element)
```
to:
```gdscript
	var element_tier: int = GameManager.available_tier(_tower)
```
(Leave the rest of the function as-is; the local stays named `element_tier` for the minimal diff — it now holds the combo-aware cap.)

- [ ] **Step 5: Run test to verify it passes**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Expected: PASS — `combo_test: 0 failure(s)`, exit 0.

- [ ] **Step 6: Verify no regression (basic upgrade gating unchanged)**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/tier_test.tscn`
Expected: PASS — `tier_test: 0 failure(s)`, exit 0.

- [ ] **Step 7: Stage (do not commit)**

```bash
git add autoload/GameManager.gd scripts/Main.gd scripts/TowerDetailPanel.gd tests/combo_test.gd
```
Suggested message: `feat: add available_tier/available_combo_for and use combo-aware tier cap`

---

### Task 6: Transform action in `Main` (+ HUD signal relay)

**Files:**
- Modify: `scripts/Main.gd` (new `_on_tower_transform_requested`, connect in `_ready`)
- Modify: `scripts/HUD.gd` (new `tower_transform_requested` signal + relay)
- Modify: `scripts/TowerDetailPanel.gd` (new `transform_pressed` signal + emitter method)
- Test: `tests/combo_test.gd`

**Interfaces:**
- Consumes: `GameManager.available_combo_for`, `GameManager.spend_gold`, `Combos.DATA[id]["transform_cost"]`, `tower.transform_into`, `hud.show_tower_detail`, `hud.flash_message`.
- Produces:
  - `Main._on_tower_transform_requested(tower: Node2D) -> void`.
  - `HUD.tower_transform_requested(tower: Node2D)` signal.
  - `TowerDetailPanel.transform_pressed(tower: Node2D)` signal (button wiring lands in Task 7; the signal + emitter are defined here so Main can be tested now).

> The detail panel's Transform **button** (visibility, label, affordability) is Task 7. This task delivers the headless-testable action + signal plumbing.

- [ ] **Step 1: Write the failing test**

Add to `tests/combo_test.gd`. In `_ready()` add after `_test_available_queries()`:
```gdscript
	await _test_transform_flow()
```
Change the `_ready()` signature to allow `await` (mirror `tier_test`'s `_ready`, which already awaits):
```gdscript
func _ready() -> void:
	_test_registry()
	_test_transform()
	_test_splash_targets()
	_test_available_queries()
	await _test_transform_flow()

	print("combo_test: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
```

Add the function:
```gdscript
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
	main._on_tower_transform_requested(tower)
	_check("a broke player can't transform", not tower.is_combo and GameManager.gold == 50)

	# Affordable: spends the transform cost and becomes the combo, level carried.
	GameManager.gold = 100
	main._on_tower_transform_requested(tower)
	_check("transform spends the transform cost", GameManager.gold == 0)
	_check("the tower is now a combo", tower.is_combo)
	_check("the combo carried its XP level", tower.level == carried_level)

	main.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Expected: FAIL — `_on_tower_transform_requested` does not exist. Exit 1.

- [ ] **Step 3: Add the detail-panel signal + emitter**

In `scripts/TowerDetailPanel.gd`, add to the signals block:
```gdscript
signal transform_pressed(tower: Node2D)
```
Add the emitter method (near `_on_upgrade_pressed`):
```gdscript
func _on_transform_pressed() -> void:
	if is_instance_valid(_tower):
		transform_pressed.emit(_tower)
```

- [ ] **Step 4: Relay it through HUD**

In `scripts/HUD.gd`, add the signal:
```gdscript
signal tower_transform_requested(tower: Node2D)
```
In `_ready()`, next to the existing `tower_detail.upgrade_pressed.connect(...)`:
```gdscript
	tower_detail.transform_pressed.connect(func(tower: Node2D) -> void: tower_transform_requested.emit(tower))
```

- [ ] **Step 5: Add the action + connection in Main**

In `scripts/Main.gd` `_ready()`, next to the `hud.tower_upgrade_requested.connect(...)` line:
```gdscript
	hud.tower_transform_requested.connect(_on_tower_transform_requested)
```
Add the handler (near `_on_tower_upgrade_requested`):
```gdscript
## Transform a placed basic tower into the combo its owned elements allow, for
## gold. The tower keeps its XP level (transform_into) and drops to combo Tier 1.
func _on_tower_transform_requested(tower: Node2D) -> void:
	if GameManager.is_over:
		return
	var combo_id: int = GameManager.available_combo_for(tower)
	if combo_id == -1:
		return
	var transform_cost: int = Combos.DATA[combo_id]["transform_cost"]
	if not GameManager.spend_gold(transform_cost):
		hud.flash_message("Not enough gold")
		return
	tower.transform_into(combo_id)
	hud.show_tower_detail(tower)  # repopulate the panel title/stats for the combo
```

- [ ] **Step 6: Run test to verify it passes**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Expected: PASS — `combo_test: 0 failure(s)`, exit 0.

- [ ] **Step 7: Stage (do not commit)**

```bash
git add scripts/Main.gd scripts/HUD.gd scripts/TowerDetailPanel.gd tests/combo_test.gd
```
Suggested message: `feat: wire the transform action from tower detail panel to Main`

---

### Task 7: Transform button in the tower detail panel

**Files:**
- Modify: `scripts/TowerDetailPanel.gd` (build the button; show/hide + label in refresh; combo-aware title)

**Interfaces:**
- Consumes: `GameManager.available_combo_for`, `Combos.DATA[id]["transform_cost"]`, `Combos.name_of`, `_tower.display_name()`, `_tower.display_color()`, `_on_transform_pressed` (Task 6).
- Produces: no new API; visual/interaction only.

> This task is UI wiring with no headless-testable seam beyond Task 6's signal (already covered). Verify by the smoke run in Step 4 plus a manual check.

- [ ] **Step 1: Build the Transform button**

In `scripts/TowerDetailPanel.gd`, add the field near `_upgrade_button`:
```gdscript
var _transform_button: Button
```
In `_build_ui()`, add a Transform row **above** the existing `buttons` HBox (so it reads as a distinct, promoted action):
```gdscript
	_transform_button = Button.new()
	_transform_button.focus_mode = Control.FOCUS_NONE
	_transform_button.pressed.connect(_on_transform_pressed)
	box.add_child(_transform_button)
```
(Place these lines just before the `var buttons := HBoxContainer.new()` block.)

- [ ] **Step 2: Make the title/colour combo-aware**

In `show_for()`, replace:
```gdscript
	_title.text = "%s Tower" % ElementTypes.element_name(tower.element)
	_title.add_theme_color_override("font_color", ElementTypes.text_color_of(tower.element))
```
with:
```gdscript
	_title.text = tower.display_name() if tower.is_combo else "%s Tower" % ElementTypes.element_name(tower.element)
	_title.add_theme_color_override("font_color",
		tower.display_color() if tower.is_combo else ElementTypes.text_color_of(tower.element))
```

- [ ] **Step 3: Show/hide + label the button in the refresh**

In `_refresh_dynamic()`, add a call at the end:
```gdscript
	_refresh_transform_button()
```
Add the method (near `_refresh_upgrade_button`):
```gdscript
## Offer "Transform → [Combo]" only for a basic tower whose partner element is
## owned; priced-but-disabled when the player can't afford it; hidden otherwise
## (including for combos, which don't re-transform in this slice).
func _refresh_transform_button() -> void:
	var combo_id: int = GameManager.available_combo_for(_tower)
	if combo_id == -1:
		_transform_button.visible = false
		return
	_transform_button.visible = true
	var transform_cost: int = Combos.DATA[combo_id]["transform_cost"]
	var affordable: bool = GameManager.gold >= transform_cost
	_transform_button.text = "Transform → %s  −%dg" % [Combos.name_of(combo_id), transform_cost]
	_transform_button.disabled = not affordable
	_transform_button.tooltip_text = "" if affordable else "Not enough gold"
```

- [ ] **Step 4: Smoke test (loads, runs, no errors)**

Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://scenes/Main.tscn --quit-after 30`
Expected: clean startup, no script errors in output.

Then re-run both suites:
Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/combo_test.tscn`
Run: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/tier_test.tscn`
Expected: both `0 failure(s)`.

- [ ] **Step 5: Manual check (windowed)** — optional but recommended

Launch the game, pick Fire, build a Fire tower, survive to wave 5, choose Air, click the Fire tower → the panel shows **Transform → Fire Breath −100g**. Transform → the tower turns orange-gold, the title reads "Fire Breath", damage jumps to ~18, and shots damage clustered enemies together.

- [ ] **Step 6: Stage (do not commit)**

```bash
git add scripts/TowerDetailPanel.gd
```
Suggested message: `feat: add Transform button to the tower detail panel`

---

### Task 8: Documentation

**Files:**
- Modify: `DESIGN_DOC.md` (section 8)
- Modify: `README.md` (dev journal + controls)
- Modify: `FEATURES_TODO.md` (combination-towers section)

**Interfaces:** none (docs only).

- [ ] **Step 1: Update `DESIGN_DOC.md` section 8**

Mark Fire Breath / the transform pipeline as built. Reconcile the old rules with the shipped model, adding a note like:

> **Shipped model (first combo, Fire Breath).** A placed **basic** tower whose
> partner element is owned can **Transform** (detail panel, gold cost) into the
> pair's combo. This supersedes the old "only level-1 towers transform" rule:
> any basic tower can transform, it **carries its XP level** and drops to combo
> **Tier 1**. A combo has its **own tier ladder**, capped by the **lower of its
> two parents' tiers** — replacing the old "both parents at Level 2" rule.
> Fire Breath (Fire + Air) deals Fire-typed AoE damage; stats live in
> `Combos.DATA`. The other pairs and abilities, and the multi-variant picker,
> are not built yet.

Also update the "Transforming"/"Cost"/"Interaction design" bullets that said the transform is deferred, and record the Fire Breath numbers (18 dmg, 1.3/s, range 200, AoE 85, transform 100g, cost 130 → tier upgrade 390) in the Balance section.

- [ ] **Step 2: Update `README.md`**

Intro: change "Combining elements into hybrid towers is still to come." to note the first combo shipped. Add a dev-journal entry dated 2026-08-14:

> - 2026-08-14 — Added the first **combination tower**: once you own two
>   elements, a placed basic tower can **Transform** (from its detail panel, for
>   gold) into their combo. Shipped Fire + Air → **Fire Breath**, which deals
>   Fire-typed **area-of-effect** damage and hits over 2× as hard as either
>   parent. The combo carries its XP level through the transform and gets its own
>   tier ladder, capped by the lower of its two parents' tiers.

Controls table: note "Transform" alongside "upgrade tier" on the tower detail row.

- [ ] **Step 3: Update `FEATURES_TODO.md`**

Mark the combination-tower framework + first combo (Fire Breath) done; list the remaining combos/abilities, the status-effect system, pull-flying, and the multi-variant picker as still outstanding.

- [ ] **Step 4: Stage (do not commit)**

```bash
git add DESIGN_DOC.md README.md FEATURES_TODO.md
```
Suggested message: `docs: record the Fire Breath combination tower`

---

## Self-Review

**Spec coverage:**
- Combos registry (spec §1) → Task 1. ✓
- Tower combo identity / `transform_into` / accessors (spec §2) → Task 2; `_draw()` colour + `_fire_at` AoE forward → Task 3. ✓
- Projectile AoE + `splash_targets` (spec §3) → Task 4. ✓
- `available_tier` / `available_combo_for` + call-site swaps (spec §4) → Task 5. ✓
- Transform UI + action (spec §5) → Task 6 (action + signal relay) and Task 7 (button). ✓
- Balance numbers (spec §6) → live in `Combos.DATA`, set in Task 1. ✓
- Testing (spec §7) → tests grow across Tasks 1–6; regression against `tier_test` in Tasks 2/5/7. ✓
- Docs (spec "Docs to update") → Task 8. ✓
- Out-of-scope items (multi-variant picker, status effects, other pairs) → not implemented; noted in Task 8 docs and left out by design. ✓
- Minimal impact visual (spec §3, "not a blocker if it slips to polish") → intentionally deferred; the AoE damage itself ships in Task 4. Flagged here so it isn't mistaken for a gap.

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to Task N" — every code step carries literal code. ✓

**Type consistency:** `transform_into(new_combo_id)`, `available_tier(tower)`, `available_combo_for(tower)`, `splash_targets(center, radius, enemies)`, `setup(..., aoe_radius := 0.0)`, `display_name()`, `display_color()`, `source_elements()`, signals `transform_pressed`/`tower_transform_requested`, handler `_on_tower_transform_requested`, `_on_transform_pressed`, `_refresh_transform_button` — names used consistently across Tasks 1–7. ✓

**Cross-task ordering:** Task 3's `_fire_at` 5th arg depends on Task 4's defaulted `setup` param — flagged with an ordering note in Task 3 and an alternative (fold that edit into Task 4) if executing strictly sequentially.
