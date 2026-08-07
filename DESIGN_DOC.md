# Towers — Game Design Document

*Working title. Isometric elemental tower defense, browser (HTML5),
built in Godot. This doc merges the original design doc with decisions
made since — add your own notes/ideas anywhere, it's yours to edit.*

---

## Status / Decisions

- **Engine**: Godot (full engine, not a JS library)
- **Platform**: Browser via HTML5 export — test exports early and often
- **Scope**: MVP first (single player, one map, 4 basic towers, no
  upgrades/combos/potions/items/multiplayer), expand after
- Starter project + scripts already scaffolded — see `TowersProject.zip`
  and `SCENE_SETUP.md` from earlier
- Balance numbers, combo tower UX, and map layout have a first draft —
  see the matching sections below (also exist as standalone files in the
  project: `BALANCE.md`, `COMBO_TOWERS.md`, `MAP_LAYOUT.md`)

---

## Introduction

Towers (working title) is a tower defense game that revolves around the
four basic elements: fire, water, earth and air. Like every tower
defense game, the goal is to stop hordes of enemy units from reaching a
certain area. To achieve this the player has to build towers to destroy
the enemy units before they reach the area. At the start of every game
the player has a number of lives; if an enemy unit reaches the area, the
player loses one life. After the player has lost all lives, it's game
over.

## Unique selling points

The idea of a tower defense game is not new — there are several games on
the market for Android and iOS. Towers has unique gameplay features that
will make it stand out from the crowd:

- The four basic elements: fire, water, earth and air. Every element has
  a counterpart — fire vs. water, earth vs. air. This counterpart
  relationship is used throughout the entire game.
- Players can combine these elements into new towers! For example, fire
  and earth gives lava, and water and air gives a water tornado.
- Every tower has a unique ability.
- Single player and multiplayer! Play alone or with your friends against
  the evil horde. *(MVP note: multiplayer is out of scope for v1 — see
  Open Questions.)*
- Players can watch other players to see their strategies.
- Enemies also use the elements principle — fire enemies take less
  damage from fire towers but more from water towers.
- Different ranks of enemies. Captains and bosses are stronger, and you
  lose more lives if they make it through your defenses.
- Enemies can drop potions or items. Potions are small one-time upgrades
  for a tower. Items are bigger upgrades and can be equipped. Items are
  also tradable with other players.
- Some towers have improved magic find — killing a unit gives a higher
  chance of finding potions/items, and of better quality.
- A trade system for items between players!
- Different difficulty settings: easy, medium, hard.
- A leveling system — gain experience, and with every level buy upgrades
  for your towers.

## General idea

Towers has only 1 level. The idea is that the player starts on easy and
already struggles to finish the game. The player has to search carefully
for working strategies — there isn't one correct way, but many different
ones. The player levels up and gains access to better towers. After
beating easy mode, the player can move on to medium, then hard — the
"Diablo idea," so to speak. Higher difficulty levels don't so much mean
better towers, but better potions and items. Units gain HP faster and
the number of units per wave increases.

## Multiplayer

Players can take on the fight together with their friends. Players don't
play together in the same instance, but each separately. They can,
however, see what the other is doing in realtime — so they can learn
from each other.

> Discussion: How do we make sure players can communicate while playing?
> Chat? Video? Voice?

*MVP note: not in scope for v1 (see Open Questions below) — realtime
sync across players is a networking system, not a small add-on.*

## Target audience

Towers aims at males between 12 and 40 years old. The game will be
hardcore — a quick tutorial will explain the basics, then the player is
on their own: exploring the game, finding good strategies, and
optimizing.

## Gold

The main currency in the game is gold. Players receive gold for every
enemy unit killed. Captains and bosses reward more gold. The gold reward
per kill increases with every round. When the last enemy unit of a round
is killed, the player receives a gold bonus, calculated from how quickly
all units were killed and whether the round was started early.

**Decision:** both, but not unit-count alone. Increasing unit count per
round indefinitely isn't a stable option — by late-game it would spawn
such a massive horde that performance tanks (turns into a slideshow).
So: increase the number of units per round *and* make later units
stronger, so they're worth more gold per kill — value scales through
enemy strength, not just raw headcount. Exact numbers to be tuned after
playtesting.

**MVP starting values** (draft, tune from playtesting):
- Starting gold: 150
- Basic enemy kill: 5 gold
- Captain kill: 20 gold
- Boss kill: 50 gold
- Round-clear speed bonus: not implemented yet

## Lives

When a unit reaches a certain point, the player loses one life. A
captain costs 3 lives, a boss costs 5 lives. Starting lives depend on
difficulty: **easy 20, medium 15, hard 10.**

## Towers

Every element has one tower that deals 125% damage to its own element.
This tower is very expensive to build.

**Fire towers** (mainly damage towers)
- Basic tower
- Inferno — slow attack with AoE damage over time
- Vulcano — very slow but high damage all around the tower

**Earth towers** (splash damage towers with stun ability)
- Basic tower
- Earthquake — AoE damage and slow
- Rock sling — splash and AoE stun, hurls big rocks at groups of enemies
- Waller — creates walls, does not attack

**Wind towers** (mostly anti-air towers)
- Basic tower
- Tornado — chance to pick up enemies
- Harsh winds — chance to push back an enemy
- Lightning — damages creatures with lightning damage, extra damage if
  creatures are walking in water

**Water towers** (mostly slow towers)
- Basic tower
- Water spring (just a name)
- Freeze tower — can freeze a single enemy
- Ice Storm — can freeze multiple enemies
- Blizzard — can freeze even larger groups of enemies

*(Original doc had an empty table here for per-tower Name / Concept Art /
Description / Technical stuff / Discussion points — worth filling in per
tower as they get designed in detail.)*

**MVP basic tower stats** (draft):

| Tower | Cost | Damage | Fire rate |
|---|---|---|---|
| Fire  | 50 | 8  | 1.2/s |
| Water | 50 | 6  | 1.0/s |
| Earth | 60 | 12 | 0.7/s |
| Air   | 55 | 7  | 1.5/s |

## Elemental progression & combination towers

*(v2 — replaces the earlier adjacency-based combine design)*

At the start of the game, the player picks **one element**. They can
only build towers of that element until they unlock more.

**Elemental tokens**
Every 5 rounds (waves) survived, the player receives 1 elemental token
to spend. This is separate from the per-tower experience/leveling
system described under Experience.

**Spending a token — two options**
- **Invest in an element you already have** → counts toward upgrading
  that element's towers. 2 tokens spent on one element unlocks that
  element's tower upgrade to level 2.
- **Spend on a new element** → unlocks that element's basic towers for
  building, *and* unlocks the ability to combine it with any element(s)
  the player already has.

**Transforming into a combination tower**
Once two elements are unlocked, an existing **level 1** tower of either
element can be transformed into their combo tower — e.g. a Fire Tower
(level 1) transforms into a Hot Water Tower (level 1) once the player
has spent a token on Water. Only level-1 towers can be transformed; a
level-2 tower cannot transform directly.

- Fire + Earth → Lava **or** Fire Rocks (two distinct towers, each with
  its own unique ability — player picks which to build)
- Fire + Air → Fire Breath
- Fire + Water → Hot Water / Steam
- Earth + Air → Meteor **or** Pull Tower (pulls air units to the ground
  so they become ground units)
- Earth + Water → Mud Flow **or** Quick Sand
- Air + Water → Water Tornado **or** Hail

Where a pair lists two towers, both exist as separate combo tower
options with their own unique ability — the player chooses which one
to build when transforming (not one-or-the-other resolved automatically).

No plans to support 3- or 4-element combinations at this time. There's
no limit on how many combo *pairs* can be active at once, though — if a
player unlocks 3+ elements over a run, every valid pair among them is
available. The level-1-only restriction still applies per tower.

Tokens make an upgrade/transform *available* — spending the token
doesn't do it for free. Actually performing the transform or upgrade
still costs gold, on top of the token investment.

**Upgrading a combination tower**
Requires **both** parent elements to be upgraded to level 2 (2 tokens
spent on each — 4 tokens total). A big investment, so the resulting
combo tower's special ability should be noticeably stronger to justify
the cost.

**v2 interaction design (draft)**
- Start of game: element-select screen (choose 1 of 4 starting
  elements).
- When a token is earned: a menu lets the player choose which element
  to spend it on (existing element to invest, or a new element to
  unlock).
- Click an already-placed level-1 tower → if a valid transform is
  unlocked, show a *"Transform into [Combo Tower]"* button. If enough
  tokens are invested for a same-element upgrade, show an *"Upgrade to
  Level 2"* button instead/alongside.

This removes the need for two physically adjacent towers and the merge
interaction from v1 — combining is now driven entirely by the token
economy, which is simpler to build for MVP.

## Enemies

Every enemy is made of one of the 4 elements: fire, water, earth, air.
An enemy attacked by a tower of the same element takes only 75% damage.
Attacked by the opposite element, it takes 125%. The other two elements
deal 100% damage. E.g. a fire enemy takes 100% from earth/air towers,
75% from fire, 125% from water.

**Enemy types**
- Fire
- Water
- Air (flying)
- Earth
- Captains (cost 3 lives)
- Boss/Chief (cost 5 lives)
- All-resist (75% damage from all towers)

**MVP enemy stats** (draft):

| Type | HP | Speed |
|---|---|---|
| Basic (any element) | 30  | 60 |
| Captain              | 90  | 60 |
| Boss                  | 200 | 45 |
| All-resist            | 50  | 60 |

## Interval between groups

A new enemy group starts every xx seconds. A player can choose to start
the next group earlier, increasing score and the end-of-round gold
bonus.

*MVP draft: 25 seconds auto-start interval; early-start bonus not
implemented yet.*

## Level design

Towers will have one map. Enemy units follow a specific route (air units
too). Players can build towers along the edge of the route — not on it.
The map design should offer spots where enemy units cross multiple
times. The route is a straight line with 90-degree corners, designed to
visually read as a winding path. The whole map won't fit on screen at
normal zoom, so the player scrolls to view different sections, and can
zoom out to see the entire level.

The map changes when moving to the next difficulty level — e.g. a
shortcut appears (shorter enemy route), or previously good tower spots
become unavailable.

**Dynamic shortcuts:** special enemy units can destroy blocking rocks
mid-level, permanently opening a shortcut. Units path dynamically (via
a grid-based pathfinder, not a fixed route) and always take the
shortest path to the exit from wherever they currently are — so once a
shortcut opens, units still approaching it reroute to use it, while
units that already passed that point simply continue on naturally
(re-pathing from their current position won't route them backward).

**MVP route draft:** S-shaped path with one 90° bend so the middle
section gets crossed twice — see `MAP_LAYOUT.md` for the actual
waypoint coordinates.

*Deferred post-MVP: per-difficulty map variants (shortcuts, blocked-off
spots) aren't designed yet. Ship the easy difficulty with this single
route first — revisit medium/hard layouts once the core loop is
playable and proven fun.*

## Experience

Towers gain experience when they land the killing blow. If a tower deals
99% of the damage to a unit but doesn't land the killing blow, it gets
nothing. Every unit grants the same amount of experience, and this
doesn't change over the course of the game. Captains and bosses grant
more experience. Experience is tied to tower levels — after a certain
amount of experience, the tower levels up. Once a tower levels up, it
deals more damage and gets a higher fire rate. The experience required
for a level increases exponentially. The extra damage and fire rate
increase linearly.

(Damage doesn't scale up exponentially — otherwise towers would stay
exactly as strong as the units. The intent is for players to make towers
stronger through potions or items instead.)

## Potions

- **Gold Find** — applied to a tower; if that tower gets the killing
  blow, it earns extra gold on top of the normal kill reward. Numbers
  TBD after playtesting.

*Deferred: the specific list of potions and items isn't decided yet —
will be filled in after playtesting the MVP. Architecturally, the code
should support a vast variety of potions/items that can be applied to
towers (not hardcode just Gold Find), so new ones can be added later
without reworking the system.*

## Items

*(empty — same deferred note as Potions above applies)*

---

## Open Questions

- How do players communicate during multiplayer sessions? Chat, video,
  voice? (and is multiplayer even in scope for v1?)
- Exact wave interval ("xx seconds") — currently a placeholder at 25s
