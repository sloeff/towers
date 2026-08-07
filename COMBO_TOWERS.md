# Combination towers — v2 (token-based)

*(Replaces the earlier adjacency-merge design.)*

## Core loop
- Player picks **one element** at game start — can only build that
  element's towers initially.
- Every 5 rounds (waves) survived → 1 elemental token to spend.
  Separate from the per-tower experience/leveling system in the main
  design doc.
- Spend a token on:
  - **An element you already have** → counts toward upgrading it.
    2 tokens on one element unlocks that element's level 2 upgrade.
  - **A new element** → unlocks that element's basic towers, *and*
    unlocks combining it with element(s) you already have.

## Transforming into a combo tower
- Only **level 1** towers can be transformed (not level 2).
- Requires the second element to be unlocked (at least 1 token spent
  on it).
- Example: Fire Tower (lvl 1) → Hot Water Tower (lvl 1) once Water is
  unlocked.

## Valid pairs
| Pair | Result(s) | Player choice? |
|---|---|---|
| Fire + Earth | Lava, Fire Rocks | Yes - two distinct towers, unique abilities each |
| Fire + Air | Fire Breath | No - single result |
| Fire + Water | Hot Water / Steam | No - single result |
| Earth + Air | Meteor, Pull Tower | Yes - two distinct towers, unique abilities each |
| Earth + Water | Mud Flow, Quick Sand | Yes - two distinct towers, unique abilities each |
| Air + Water | Water Tornado, Hail | Yes - two distinct towers, unique abilities each |

Where a pair has two results, both exist as separate combo towers with
their own unique ability - the player picks which one to build when
transforming a level-1 tower.

No 3- or 4-element combinations planned. No limit on how many combo
*pairs* can be active at once — if a player unlocks 3+ elements over a
run, every valid pair among them is available. The level-1-only
transform restriction still applies per tower.

## Upgrading a combo tower
Requires **both** parent elements at level 2 (2 tokens each, 4 total).
Big investment — combo tower's special ability should be noticeably
stronger to justify it.

## Cost
Tokens make an upgrade/transform *available* to perform - they don't do
it for free. Actually transforming or upgrading a tower still costs
gold, on top of the token investment.

## Interaction design
- Element-select screen at game start.
- Token-earned menu: choose which element to invest the token in.
- Click a placed level-1 tower -> show "Transform into [X]" if a valid
  second element is unlocked, and/or "Upgrade to Level 2" if enough
  tokens are invested in that element already. Both actions also cost
  gold (amount TBD - see BALANCE.md once decided).

## Open questions (unresolved, need answers before implementing)
- **Gold cost amounts** for transforms/upgrades - not yet decided.
