# Balance — MVP starting values

Not final, just concrete starting points so the game is playable instead
of relying on placeholder numbers. Tune all of this from playtesting.

## Economy
- Starting gold: 150
- Basic enemy kill: 5 gold
- Captain kill: 20 gold (costs 3 lives if it reaches the exit)
- Boss kill: 50 gold (costs 5 lives if it reaches the exit)
- Wave auto-starts every 25s. Starting early should reward bonus gold
  (not implemented yet — see WaveSpawner.start_next_wave_early()).

## Basic towers

| Tower | Cost | Damage | Fire rate |
|---|---|---|---|
| Fire  | 50 | 8  | 1.2/s |
| Water | 50 | 6  | 1.0/s |
| Earth | 60 | 12 | 0.7/s |
| Air   | 55 | 7  | 1.5/s |

Set these as the exported values on each element's inherited Tower scene.

## Enemies

| Type | HP | Speed |
|---|---|---|
| Basic (any element) | 30  | 60 |
| Captain              | 90  | 60 |
| Boss                  | 200 | 45 |
| All-resist            | 50  | 60 |

## Wave scaling
Starts at 6 enemies per wave, +2 per wave number (already the default in
WaveSpawner.gd's placeholder scaling — kept as-is since it lines up).

**Scaling decision:** difficulty ramps through *both* unit count and
unit strength — not unit count alone. Pure headcount scaling isn't
stable long-term (late-game hordes would tank performance), so later
waves should also increase enemy HP/gold-value, not just spawn more of
them. Exact curve TBD after playtesting; Enemy.gd's `max_health` and
`gold_reward` are the exported values to scale per-wave once numbers
are decided.

## Potions
- **Gold Find** — applied to a tower; if that tower lands the killing
  blow, it earns bonus gold on top of the normal kill reward. Amount
  TBD after playtesting.
