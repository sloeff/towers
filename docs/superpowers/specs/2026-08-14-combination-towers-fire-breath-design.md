# Combination Towers — First Slice: Fire Breath (Fire + Air, AoE)

Status: approved design, ready for implementation plan
Branch: `combination-towers`
Date: 2026-08-14

## Goal

Deliver the **transform-into-a-combination-tower** pipeline end to end,
carrying exactly one combo — **Fire Breath** (Fire + Air) — with one genuinely
new combat mechanic (area-of-effect damage). Once this slice is real and
tested, every additional combo/ability is a small follow-up on the proven
pipeline.

This is the first slice of DESIGN_DOC section 8's combination towers. It
deliberately excludes: the other five pairs and their ten abilities, status
effects (slow/freeze/DoT/stun), pulling flying units to the ground, and the
multi-variant "pick which combo" picker (Fire+Earth etc.). Those are named as
out of scope below.

## Decisions locked (from brainstorming)

- **First combo:** Fire + Air → Fire Breath. Single-result pair (no variant
  picker). Ability: full damage to every enemy within a small radius of impact.
- **Trigger:** transform a *placed basic tower* via its detail panel (not a new
  build-bar button).
- **Progression:** the combo has its **own tier ladder**, capped by the
  **minimum of its two parent element tiers**.
- **Cost & XP:** transforming costs gold and **carries the tower's XP level
  over**; it **resets tier to 1** (fresh combo ladder — consistent with "each
  placed tower starts at Tier 1").
- **Damage identity:** Fire Breath deals **Fire-typed** damage for the
  elemental multiplier (not "best of both parents").
- **Balance:** Fire Breath is decisively stronger than either parent (see
  Balance), because a transform spends a scarce every-5-rounds element unlock
  plus gold.

## Architecture

Five units, each with one job:

1. **`Combos` (new autoload, `autoload/Combos.gd`)** — pure data authority for
   combo definitions and lookups. Mirrors `ElementTypes`. No `GameManager`
   dependency.
2. **`Tower` (extended)** — the same node represents a combo after
   `transform_into(combo_id)`; combo identity + AoE param live here, plus
   presentation accessors so consumers stop branching on element-vs-combo.
3. **`Projectile` (extended)** — optional AoE on impact; single-target path
   unchanged.
4. **`GameManager` (extended)** — two run-state queries: `available_tier(tower)`
   and `available_combo_for(tower)`.
5. **`TowerDetailPanel` / `HUD` / `Main` (extended)** — the Transform button and
   its signal chain and action.

### 1. `Combos` autoload

New file `autoload/Combos.gd`, registered in `project.godot` `[autoload]`
**immediately after `ElementTypes`** (its `DATA` table references
`ElementTypes.Element` at load time, so `ElementTypes` must load first).

```gdscript
extends Node
## Data authority for combination towers (DESIGN_DOC section 8). Pure data +
## lookups, mirroring ElementTypes; no GameManager dependency. Adding a combo is
## a DATA entry, never a logic change.

enum Combo { FIRE_BREATH }

const DATA := {
    Combo.FIRE_BREATH: {
        "name": "Fire Breath",
        "parents": [ElementTypes.Element.FIRE, ElementTypes.Element.AIR],
        # Element used for the damage multiplier AND the projectile colour.
        "damage_element": ElementTypes.Element.FIRE,
        "color": Color(0.98, 0.55, 0.15),   # distinct orange-gold
        "damage": 18.0,
        "fire_rate": 1.3,
        "range": 200.0,
        "aoe_radius": 85.0,
        "cost": 130,            # feeds upgrade_cost (x3) and sell_value (75%)
        "transform_cost": 100,  # gold to transform, on top of the basic build
    },
}

## The combo formed by an unordered pair of elements, or -1 if none is defined.
func combo_for(a: int, b: int) -> int:
    for id in DATA:
        var parents: Array = DATA[id]["parents"]
        if a in parents and b in parents and a != b:
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

### 2. `Tower` extensions

Represent a combo as the *same* `Tower` node rather than a parallel class —
targeting, XP, the tier ladder, range and most of `_draw()` are identical, so a
subclass would duplicate them. Combos differ only in stats (from the registry),
an AoE param, and presentation.

New state:
```gdscript
var is_combo: bool = false
var combo_id: int = -1
var parent_elements: Array[int] = []
var aoe_radius: float = 0.0   # 0 = single-target (every basic tower)
```

`element` keeps its meaning: **the damage element for the multiplier and the
projectile** (= Fire for Fire Breath). This is why `Enemy.take_damage` and the
multiplier need no change.

New method:
```gdscript
## Turn this placed basic tower into a combination tower: swap in the combo's
## base stats and AoE, keep the earned XP level, and reset the tier to 1 (a
## combo has its own ladder). The caller checks ownership and charges gold.
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
    tier = 1                 # fresh combo ladder; level/experience carried
    _recompute_stats()
    queue_redraw()
```

Presentation accessors (so the detail panel and `_draw()` never branch on
element-vs-combo):
```gdscript
func display_name() -> String:
    return Combos.name_of(combo_id) if is_combo else ElementTypes.element_name(element)

func display_color() -> Color:
    return Combos.color_of(combo_id) if is_combo else ElementTypes.color_of(element)

## The elements this tower's tier cap is drawn from: its own for a basic tower,
## both parents for a combo. Used by GameManager.available_tier.
func source_elements() -> Array[int]:
    return parent_elements if is_combo else [element]
```

`_draw()` change: replace `ElementTypes.color_of(element)` with
`display_color()` so a combo shows its distinct colour. (For a basic tower
`display_color()` returns exactly today's colour — no visual change.) Everything
else in `_draw()` (turret height per level, tier pips) is reused unchanged.

`_fire_at()` change: pass the AoE radius through:
```gdscript
projectile.setup(target, damage, element, self, aoe_radius)
```

`upgrade_cost()`, `upgrade_tier()`, `max_level()`, `sell_value()` are already
generic (they read `cost`/`tier`) and are reused unchanged for combos.

### 3. `Projectile` extensions — AoE on impact

`setup()` gains a trailing `aoe_radius := 0.0` parameter (default preserves
every existing caller's single-target behaviour). On impact:

```gdscript
if _aoe_radius > 0.0:
    var enemies := get_tree().get_nodes_in_group("enemies")
    # Same-script static call, unqualified (Projectile.gd has no class_name).
    for e in splash_targets(_target.ground_position(), _aoe_radius, enemies):
        e.take_damage(_damage, _element, source)
else:
    _target.take_damage(_damage, _element, source)
```

The test reaches the static helper via a preloaded script reference —
`const ProjectileScript := preload("res://scripts/Projectile.gd")` then
`ProjectileScript.splash_targets(...)` — matching how `ElementSelect` already
calls `Tower`'s static `damage_at_tier`. No `class_name` is added.

The radius test reuses Tower's 2:1 iso-unsquash so the splash is a circle on the
ground plane. Extracted as a pure, testable static function:

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

Each hit enemy takes its **own** elemental multiplier (Fire vs its element),
because damage still flows through `Enemy.take_damage`. The primary target is
included (it is within radius 0 of the centre). Source credit: whichever
enemies die in the splash each credit the firing tower a kill + XP, same as a
single kill today.

Impact visual (minimal): a brief fading ring at the impact point sized to
`aoe_radius`, so the area reads. Implemented with a short-lived draw (reuse the
`FloatingText`-style throwaway-node pattern, or a small self-freeing node). Kept
deliberately cheap; not a blocker if it slips to polish.

### 4. `GameManager` extensions — two run-state queries

```gdscript
## The highest tier this tower could be upgraded to right now: a basic tower is
## capped by its element's tier; a combo by the LOWER of its two parents' tiers.
func available_tier(tower) -> int:
    var cap: int = 2147483647
    for e in tower.source_elements():
        cap = mini(cap, element_tier(e))
    return cap

## A combo this basic tower can transform into right now (partner element owned),
## or -1. Combos themselves never re-transform in this slice.
func available_combo_for(tower) -> int:
    if tower.is_combo:
        return -1
    for combo_id in Combos.combos_including(tower.element):
        for parent in Combos.DATA[combo_id]["parents"]:
            if parent != tower.element and is_element_unlocked(parent):
                return combo_id
    return -1
```

`available_tier` **replaces** the two existing `element_tier(tower.element)`
call sites (`Main._can_upgrade_tower`, `TowerDetailPanel._refresh_upgrade_button`)
with **identical behaviour for basic towers** (min over a single element ==
that element's tier), and correct capping for combos.

### 5. Transform UI + action

**`TowerDetailPanel`** gains a Transform button in its own row above the
Upgrade/Sell row, and a signal `transform_pressed(tower)`.
- Visible only when `GameManager.available_combo_for(_tower) != -1` (basic
  tower, partner owned). Hidden for combos and when no combo is available.
- Label: `"Transform → Fire Breath  −%dg"` with `Combos.DATA[id]["transform_cost"]`;
  disabled-but-priced when `GameManager.gold < transform_cost`
  (tooltip "Not enough gold"), matching the Upgrade button's affordability idiom.
- Title/colour use `_tower.display_name()` / `_tower.display_color()` (so after a
  transform the panel reads "Fire Breath" in the combo colour). `show_for` also
  switches from `ElementTypes.element_name(...)` to `display_name()`.

**`HUD`** re-emits: new signal `tower_transform_requested(tower)`; connect
`tower_detail.transform_pressed` to it (mirrors the existing `upgrade_pressed`
wiring).

**`Main`** connects `hud.tower_transform_requested` and handles it:
```gdscript
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
    hud.show_tower_detail(tower)   # repopulate the panel's title/stats
```

No change to `_towers_by_cell`, grid occupancy, or selection: the node is the
same, still on the same cell, still selected.

## Balance

| Stat | Fire (basic) | Air (basic) | **Fire Breath** |
|---|---|---|---|
| Damage | 8 | 7 | **18** |
| Fire rate | 1.2/s | 1.5/s | **1.3/s** |
| Single-target DPS | 9.6 | 10.5 | **23.4** (~2.3×) |
| Range | 170 | 200 | **200** |
| AoE radius | — | — | **85** (full damage to each enemy inside) |
| Element identity | Fire | Air | Fire (125% vs Water) |
| Build/transform gold | 50 | 55 | **+100 transform** (~150 total) |
| Tier upgrade cost | 150 | 165 | **390** (cost 130 × 3) |
| Sell value | 37 | 41 | **97** (75% of 130) |

Fire Breath out-damages either parent by >2× before the splash is even
considered; against groups the AoE stacks on top. Its own tier ladder adds the
standard +50% damage / +20% fire-rate per step on that high base, capped by the
lower of the Fire/Air tiers, so a tiered combo pulls further ahead. All numbers
live in `Combos.DATA` and are tunable in one place.

## Testing (TDD)

New `tests/combo_test.gd` + `tests/combo_test.tscn`, run headless as a scene
(same harness as `tier_test`), self-quitting `0`/`1`.

1. **Registry lookups** — `combo_for(FIRE, AIR)` and `combo_for(AIR, FIRE)` both
   return `FIRE_BREATH`; `combo_for(FIRE, FIRE)` and an undefined pair
   (`FIRE, WATER`) return −1; `parents`/`damage_element` correct.
2. **`available_combo_for`** — basic Fire tower with Air not owned → −1; with Air
   owned → `FIRE_BREATH`; a combo tower → −1.
3. **`available_tier`** — basic tower returns its element's tier; a combo returns
   `min(parent tiers)` (advance one parent only → cap unchanged; advance both →
   cap rises).
4. **`transform_into`** — sets `is_combo`/`combo_id`/`parent_elements`/
   `aoe_radius`; base stats from the registry; `element == FIRE`; **carries
   `level`**; **resets `tier` to 1**; `display_name`/`display_color`/
   `source_elements` correct; recomputed `damage == 18 × level scaling`.
5. **Combo upgrade** — after transform, `upgrade_cost() == 390`; can upgrade only
   while `available_tier > tier` (needs both parents advanced); a tier step
   applies +50% damage on the combo base.
6. **`splash_targets`** — two enemies within the radius are both returned, one
   outside is not; freed/invalid enemies are skipped.
7. **Main transform flow** — place a basic Fire tower, own Fire+Air, enough gold
   → `_on_tower_transform_requested` spends `transform_cost`, tower becomes the
   combo, level carried; too poor → tower unchanged, gold unchanged.
8. **Regression** — the existing `tier_test` basic-tower suite stays green
   (`available_tier` refactor must not change basic behaviour).

## Out of scope (next slices)

- The other five pairs and their abilities; status effects (slow/freeze/DoT/
  stun); pulling flying units to the ground.
- The multi-variant picker for pairs with two results (Fire+Earth, Earth+Air,
  Earth+Water, Air+Water) — the Transform action currently resolves a single
  available combo; a pair offering two will need a choice UI.
- Combo-vs-combo or 3+ element interactions (none planned per the design doc).

## Docs to update on completion

- `DESIGN_DOC.md` section 8: mark Fire Breath / the transform pipeline built;
  reconcile the old "level-1-only transform" and "both parents at Level 2" rules
  with the shipped model (own tier ladder capped by min parent tier; transform
  carries XP level, resets tier).
- `README.md`: dev-journal entry; controls table ("transform" on the tower
  detail panel).
- `FEATURES_TODO.md`: mark the combination-tower framework + first combo done,
  remaining combos/abilities outstanding.
