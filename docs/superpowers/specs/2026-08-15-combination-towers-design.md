# Combination Towers — Remaining Five Pairs

*Design spec. Extends DESIGN_DOC.md section 8. Adds the five combination
towers still unbuilt, one tower per pair, each with a genuinely distinct
ability. Fire + Air → Fire Breath already ships and is unchanged.*

## 1. Goal

Ship the remaining five combination towers, one per elemental pair. Each is a
deliberate power spike over either parent (like Fire Breath) but earns its
distinctness through a **unique mechanic**, not just bigger numbers or a
recoloured AoE.

This requires three new reusable primitives on the enemy (slow, stun, damage
over time), one new tower firing mode (aura, no projectile), and a fix to the
transform flow so a tower with several owned partners can be transformed into
any of its available combos.

## 2. The five towers

| Pair | Tower | Damage element | Unique ability |
|---|---|---|---|
| Fire + Earth | **Lava** | Fire | Burn — direct hit plus a damage-over-time that ticks for 3 s; re-hitting refreshes it |
| Fire + Water | **Steam** | Water | AoE slow — projectile splashes; every enemy in the radius is slowed 50 % for 3 s |
| Earth + Air | **Meteor** | Earth | Stun — very slow fire rate, one heavy hit with a small splash, stuns the primary target 1 s |
| Earth + Water | **Quicksand** | Earth | Slow aura — no projectile; every enemy in range is continuously slowed 40 % and takes a small damage tick |
| Air + Water | **Hail** | Water | Small AoE + light slow — small splash damage, hits slow 25 % for 1.5 s |

Fire Breath (Fire + Air, Fire-typed AoE) is already built; the table above is
what's being added.

## 3. Balance (first-draft numbers)

Parent single-target DPS for reference (Tier 1, Lv 1): Fire 9.6, Water 6.0,
Earth 8.4, Air 10.5. Combos ride the same tier and XP-level ladders as basics;
tier cap is the lower of the two parents' tiers. All stats live in
`autoload/Combos.gd` (`Combos.DATA`).

| Combo | Damage | Fire rate | Range | AoE | Cost / Transform | Ability params |
|---|---|---|---|---|---|---|
| Lava | 14 | 1.0/s | 160 | 0 | 140 / 110g | burn 8 dmg/s for 3 s (Fire-typed) |
| Steam | 12 | 1.1/s | 190 | 90 | 140 / 110g | slow ×0.5 for 3 s |
| Meteor | 55 | 0.35/s | 220 | 60 | 160 / 120g | stun 1 s on primary target |
| Quicksand | — | aura | 150 | (= range) | 150 / 110g | aura 6 dmg/s + slow ×0.6, all in range |
| Hail | 10 | 1.4/s | 200 | 55 | 135 / 100g | slow ×0.75 for 1.5 s |

- **Cost** feeds the combo-tier upgrade (×3) and sell value (75 %), same as
  Fire Breath.
- **Transform** is the gold to convert a placed basic tower; it carries its XP
  level and resets to combo Tier 1.
- Effective DPS lands around 2–2.3× a parent once the ability is counted
  (Lava 14 direct + 8 burn ≈ 22; Meteor 55 × 0.35 ≈ 19 plus stun uptime;
  Quicksand trades direct damage for area control). Tune from playtesting.
- Each combo needs a distinct `color` in `Combos.DATA` so it reads apart from
  Fire Breath's orange-gold and from its parents.

## 4. New mechanics

### 4.1 Enemy status effects (`Enemy.gd`)

Three effects, all timed, ticked in `Enemy._process` alongside existing
movement. A killing blow from any of them credits the firing tower for gold and
XP through the existing `take_damage(amount, element, source)` path, so the XP
and gold routing needs no new code — only a guarded `source` (it may have been
sold mid-effect, same guard as projectiles already use).

- **Slow** — `apply_slow(factor, duration)`. Stores an entry `(factor,
  time_left)` in a small list. The enemy's effective speed each frame is
  `base_speed × (min factor among active slows, or 1.0 if none)`. Min, not
  product, so two 50 % slows don't stack to 25 %. Entries tick down and expire.
- **Stun** — reuses the slow system with `factor = 0` (a full stop is just the
  strongest possible slow). No separate code path. Meteor calls
  `apply_slow(0.0, 1.0)`.
- **Damage over time / burn** — `apply_dot(dps, duration, element, source)`.
  Stores `(dps, time_left, element, source)` in a list; `_process` applies
  `dps × delta` through the normal damage path each frame (so the elemental
  multiplier and the killing-blow credit both apply). Re-hitting refreshes
  `time_left` rather than stacking a second instance (keeps Lava from
  runaway-stacking).

`configure()` and `_removed` handling are unchanged; effect lists clear
naturally when the node frees.

### 4.2 Effect delivery via projectiles (`Projectile.gd`, `Tower.gd`)

Projectiles carry an optional **effects payload** — a small dictionary of
`{slow_factor, slow_duration, dot_dps, dot_duration, stun_duration}`, any subset
present. On impact, after `take_damage`, the projectile applies whatever effects
it carries to each enemy it hit (the single target, or every splash target for
an AoE shot). Meteor's stun applies only to its **primary** target, not the
splash — the payload distinguishes "primary-only" from "all-hit" effects (a
`stun_primary_only` flag, or by applying stun before the splash loop).

`Tower._fire_at` builds this payload from the combo's `Combos.DATA` entry.
Basic towers pass an empty payload, so their behaviour is unchanged.

### 4.3 Aura firing mode (`Tower.gd`) — Quicksand only

Quicksand has no projectile. `Combos.DATA` marks it with `firing_mode: "aura"`
(default `"projectile"` for everything else). In `Tower._process`, an aura
tower skips the target-and-fire path and instead, each frame, scans enemies in
range (same un-squashed distance test as `_find_target`) and to each applies a
short refreshed slow (`apply_slow(0.6, ~0.25)`, re-applied every frame while in
range so it lingers ~0.25 s after an enemy leaves) plus `aura_dps × delta`
direct damage through `take_damage`. No fire-rate cooldown; the effect is
continuous.

Optional polish: an aura tower draws its range ring faintly at all times (not
only when selected) so the slow field reads visually.

## 5. Transform flow — multiple available combos

**Problem.** `GameManager.available_combo_for(tower)` returns the *first*
matching combo. With six combos, a Fire tower whose owner also has Air, Earth
and Water can form Fire Breath, Lava *or* Steam — but the single Transform
button can only surface one.

**Fix.** Replace the single-result lookup with a list:

- `GameManager.available_combos_for(tower) -> Array[int]` — every combo whose
  partner element is owned (excluding combos, which never re-transform).
- `TowerDetailPanel` renders **one Transform button per available combo**,
  each labelled `Transform → <Name>  −<cost>g`, disabled-but-priced when
  unaffordable, in the existing full-width button row above Upgrade/Sell.
- `Main._on_tower_transform_requested` already takes the chosen `combo_id`
  intent from the panel; it keeps charging that combo's `transform_cost` and
  calling `tower.transform_into(combo_id)`.

`available_combo_for` (singular) is removed or kept as a thin
`available_combos_for(tower).front()` shim only if something else needs it;
prefer removing it to avoid two sources of truth.

This also subsumes the old DESIGN_DOC note about "two-result pairs need a
picker UI" for this slice: we ship one tower per pair, so multiplicity comes
only from multiple owned partners, and a button-per-combo covers it. True
two-result-same-pair choices remain out of scope.

## 6. Data shape (`Combos.gd`)

Adding a combo stays a pure `DATA` entry. New optional keys, all defaulted so
Fire Breath's entry needs no change:

```
firing_mode: "projectile" | "aura"   # default "projectile"
slow_factor, slow_duration            # on-hit slow (Steam, Hail)
stun_duration, stun_primary_only      # on-hit stun (Meteor)
dot_dps, dot_duration                 # burn (Lava)
aura_dps                              # aura tick damage (Quicksand)
```

The `Combo` enum gains `LAVA, STEAM, METEOR, QUICKSAND, HAIL`. `combo_for`,
`combos_including`, `name_of`, `color_of` are unchanged — they already iterate
`DATA` generically.

## 7. Out of scope

- Two distinct towers from one pair (the design doc's Lava/Fire Rocks,
  Meteor/Pull Tower etc. two-result pairs) — one tower per pair here.
- Pull Tower's air-to-ground conversion.
- Real art for the new towers/effects (placeholder `_draw` shapes + distinct
  colours only).
- Tuning — every number in section 3 is a first draft.

## 8. Files touched

- `autoload/Combos.gd` — five new `DATA` entries + enum values, new optional keys.
- `autoload/GameManager.gd` — `available_combos_for` (plural) replaces singular.
- `scripts/Enemy.gd` — slow/stun/dot state + `apply_slow` / `apply_dot`, speed
  and tick handling in `_process`.
- `scripts/Projectile.gd` — carry and apply an effects payload on impact.
- `scripts/Tower.gd` — build the payload in `_fire_at`; aura firing mode in
  `_process`; optional always-on aura ring in `_draw`.
- `scripts/TowerDetailPanel.gd` — one Transform button per available combo.
- `scripts/Main.gd` — adjust to the plural lookup (chosen combo already flows
  through).
- `DESIGN_DOC.md` — reconcile section 8's combo table and Balance once built.
