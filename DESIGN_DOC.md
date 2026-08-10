# Towers — Game Design Document

*Working title. Isometric elemental tower defense, browser (HTML5), built
in Godot. This is the single source of truth for the project: design
intent, balance numbers, map layout and implementation notes all live
here.

**Contents**

1. [Status and decisions](#1-status-and-decisions)
2. [Introduction](#2-introduction)
3. [Unique selling points](#3-unique-selling-points)
4. [General idea](#4-general-idea)
5. [Target audience](#5-target-audience)
6. [Core systems](#6-core-systems) — gold, lives, wave interval, experience, potions, items
7. [Towers](#7-towers)
8. [Elemental progression and combination towers](#8-elemental-progression-and-combination-towers)
9. [Enemies](#9-enemies)
10. [Level design and map layout](#10-level-design-and-map-layout)
11. [Multiplayer](#11-multiplayer)
12. [Balance](#12-balance) — every number in the game
13. [Implementation](#13-implementation)
14. [Open questions](#14-open-questions)

---

## 1. Status and decisions

- **Engine**: Godot 4.7
- **Platform**: Browser via HTML5 export
- **Scope**: MVP first — single player, one map, 4 basic elemental
  towers, no upgrades/combos/potions/items/multiplayer. Everything else
  layers on top later without a rewrite.

### Where the MVP stands

**Working:** the isometric map and route, the ravine the route runs
through, dynamic A* pathing, wave spawning with scaling composition, the
start-of-run element pick, click-to-place towers with build validation,
click-a-tower detail panel with selling, elemental damage multipliers,
floating gold rewards on a kill, the gold/lives economy, game over /
victory with restart, and the HTML5 export deployed to GitHub Pages.

**Not built yet:** tower experience and leveling,
elemental tokens and combination towers, potions and items, the
destructible-rock shortcut trigger, per-difficulty map variants, sound,
and real art.

### Next steps, in order

1. **Playtest and tune.** Every number in [Balance](#12-balance) is a
   first draft. Wave 1–20 pacing, tower costs and enemy HP scaling all
   need real play.
2. **Tower experience and leveling** — see [Experience](#experience).
   This is also what lights up the detail panel's disabled *Upgrade*
   button.
3. **Elemental tokens and combination towers** — see
   [section 8](#8-elemental-progression-and-combination-towers). Needs the
   gold costs decided first.
4. **Real art** — replace the `_draw()` placeholder shapes.

---

## 2. Introduction

Towers is a tower defense game that revolves around the four basic
elements: fire, water, earth and air. Like every tower defense game, the
goal is to stop hordes of enemy units from reaching a certain area. To
achieve this the player has to build towers to destroy the enemy units
before they reach the area. At the start of every game the player has a
number of lives; if an enemy unit reaches the area, the player loses one
life. After the player has lost all lives, it's game over.

---

## 3. Unique selling points

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
  [Open questions](#14-open-questions).)*
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

---

## 4. General idea

Towers has only 1 level. The idea is that the player starts on easy and
already struggles to finish the game. The player has to search carefully
for working strategies — there isn't one correct way, but many different
ones. The player levels up and gains access to better towers. After
beating easy mode, the player can move on to medium, then hard — the
"Diablo idea," so to speak. Higher difficulty levels don't so much mean
better towers, but better potions and items. Units gain HP faster and the
number of units per wave increases.

---

## 5. Target audience

Towers aims at males between 12 and 40 years old. The game will be
hardcore — a quick tutorial will explain the basics, then the player is
on their own: exploring the game, finding good strategies, and
optimizing.

---

## 6. Core systems

### Gold

The main currency in the game is gold. Players receive gold for every
enemy unit killed. Captains and bosses reward more gold. When the last
enemy unit of a round is killed, the player receives a gold bonus,
calculated from how quickly all units were killed and whether the round
was started early.

**Scaling decision:** difficulty ramps through *both* unit count and unit
strength — not unit count alone. Increasing unit count per round
indefinitely isn't stable: by late game it would spawn such a massive
horde that performance tanks. So later waves both spawn more units *and*
make them stronger.

> **Unresolved — does the kill reward scale per round?** The original
> design said the gold reward per kill increases with every round, so
> value would scale through enemy strength as well as headcount. The
> implementation pays the flat values in [Balance](#12-balance) on every
> wave, so enemy HP is currently the only thing that ramps. That means
> the economy tightens sharply over a run: income per enemy is fixed
> while enemies get roughly 8.6× tankier by wave 20. Decide which
> behaviour wins before tuning the economy.

The round-clear speed bonus and the bonus for starting a round early are
both designed but not implemented.

### Lives

When a unit reaches the exit, the player loses one life. A captain costs
3 lives, a boss costs 5. Starting lives depend on difficulty — see
[Balance](#12-balance).

### Interval between groups

A timer starts when the last unit of the round has spawned into the level, this timer is set to 30 seconds. A player can
choose to start the next group earlier, increasing score and the
end-of-round gold bonus. The early start works
(`WaveSpawner.start_next_wave_early()`); the bonus for it does not exist
yet.

### Experience

Towers gain experience when they land the killing blow. If a tower deals
99% of the damage to a unit but doesn't land the killing blow, it gets
nothing. Every unit grants the same amount of experience, and this
doesn't change over the course of the game. Captains and bosses grant
more experience.

Experience is tied to tower levels — after a certain amount of
experience, the tower levels up. Once a tower levels up, it deals more
damage and gets a higher fire rate. The experience required for a level
increases exponentially. The extra damage and fire rate increase
linearly.

Damage deliberately doesn't scale up exponentially — otherwise towers
would stay exactly as strong as the units. The intent is for players to
make towers stronger through potions or items instead.

### Potions

Small one-time upgrades applied to a tower.

- **Gold Find** — applied to a tower; if that tower lands the killing
  blow, it earns extra gold on top of the normal kill reward. Amount TBD
  after playtesting.

### Items

Bigger upgrades that can be equipped, and traded with other players.
No specific items designed yet.

**Architectural note for both:** the specific list of potions and items
is deferred until after MVP playtesting, but the code should support a
wide, open-ended variety of them applied to towers rather than
hardcoding just Gold Find — e.g. a generic "modifier" resource or data
structure that a tower holds a list of, instead of one-off flags per
effect. Building that shape now costs nothing; retrofitting it later
means touching every stat read.

---

## 7. Towers

Every element has one tower that deals 125% damage to its own element.

**Fire towers** (mainly damage towers)
- Basic tower
- Damage over time
- Inferno — slow attack with AoE damage over time
- Vulcano — very slow but high damage all around the tower

**Earth towers** (splash damage towers with stun ability)
- Basic tower
- Stun ability
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
- Slowing ability
- Water spring (just a name)
- Freeze tower — can freeze a single enemy
- Ice Storm — can freeze multiple enemies
- Blizzard — can freeze even larger groups of enemies

Only the four basic towers exist. Their stats are in
[Balance](#12-balance). Per-tower detail (concept art, description,
technical notes, discussion points) is worth filling in here as each
tower gets designed properly.

---

## 8. Elemental progression and combination towers

At the start of the game the player picks **one element**, and can only
build towers of that element until more are unlocked. *(This part is
implemented; everything below it is not.)*

### Elemental tokens

Every 5 rounds survived, the player receives 1 elemental token to spend.
This is separate from the per-tower experience system in
[Experience](#experience).

A token can go to:

- **An element you already have** → counts toward upgrading that
  element's towers. 2 tokens on one element unlocks its level 2 upgrade.
- **A new element** → unlocks that element's basic towers, *and* unlocks
  combining it with any element you already have.

### Transforming into a combination tower

Once two elements are unlocked, an existing **level 1** tower of either
element can be transformed into their combo tower — e.g. a level 1 Fire
Tower becomes a level 1 Hot Water Tower once the player has spent a token
on Water. Only level 1 towers can transform; a level 2 tower cannot.

| Pair | Result(s) | Player choice? |
|---|---|---|
| Fire + Earth | Lava, Fire Rocks | Yes — two distinct towers, unique ability each |
| Fire + Air | Fire Breath | No — single result |
| Fire + Water | Hot Water / Steam | No — single result |
| Earth + Air | Meteor, Pull Tower | Yes — two distinct towers, unique ability each |
| Earth + Water | Mud Flow, Quick Sand | Yes — two distinct towers, unique ability each |
| Air + Water | Water Tornado, Hail | Yes — two distinct towers, unique ability each |

Pull Tower pulls air units to the ground so they become ground units.

Where a pair lists two towers, both exist as separate combo towers with
their own unique ability — the player picks which one to build when
transforming, rather than it being resolved automatically.

No 3- or 4-element combinations are planned. There's no limit on how many
combo *pairs* can be active at once, though: if a player unlocks 3+
elements over a run, every valid pair among them is available. The
level-1-only restriction still applies per tower.

### Upgrading a combination tower

Requires **both** parent elements at level 2 — 2 tokens each, 4 total. A
big investment, so the resulting combo tower's special ability should be
noticeably stronger to justify it.

### Cost

Tokens make an upgrade or transform *available*; they don't perform it
for free. Actually transforming or upgrading a tower still costs gold on
top of the token investment. **The gold amounts are not decided yet** —
this is the one thing blocking implementation.

### Interaction design

- Element-select screen at game start, choosing 1 of 4. *(Implemented.)*
- When a token is earned, a menu lets the player choose which element to
  spend it on — an element they already have, or a new one.
- Click an already-placed level 1 tower → show *"Transform into [Combo
  Tower]"* if a valid second element is unlocked, and/or *"Upgrade to
  Level 2"* if enough tokens are invested in that element. Both cost gold.

---

## 9. Enemies

Every enemy is made of one of the 4 elements. An enemy attacked by a
tower of the same element takes only 75% damage. Attacked by the opposite
element it takes 125%. The other two elements deal 100%. E.g. a fire
enemy takes 100% from earth and air towers, 75% from fire, 125% from
water.

**Enemy types**
- Fire
- Water
- Air (flying — ignores ground obstacles and shortcuts)
- Earth
- Captains (cost 3 lives)
- Boss / Chief (cost 5 lives)
- All-resist (75% damage from every tower)

Stats are in [Balance](#12-balance).

---

## 10. Level design and map layout

Towers has one map. Enemy units follow a specific route (air units too).
Players can build towers along the edge of the route — never on it. The
map should offer spots where enemy units cross multiple times. The route
is a straight line with 90-degree corners, designed to read as a winding
path. The whole map won't fit on screen at normal zoom, so the player
scrolls to view different sections and can zoom out to see the whole
level.

The route runs along the floor of a ravine, one tile below the buildable
plateau the towers stand on.

### Dynamic pathing, not a waypoint list

Enemies path live across a grid of solid/open cells and re-request
their path whenever the grid changes. **Bonus:** this gives "units
already past the shortcut keep their current route" for free — an enemy
re-paths from wherever it *currently* is, so if the shortcut is behind it,
A* simply won't route it backward through it. No special-case logic.

### The route

14 × 13 grid, `#` = route, `.` = buildable ground, `S` = spawn, `E` = exit:

```
     x0            x13
y0   . . . . . . . . . . . . . .
y1   . . . . . . . . . . . . . .
y2   S # # # # # # # # # # . . .
y3   . . . . . . . . . . # . . .
y4   . . . . . . . . . . # . . .
y5   . . . . . . . . . . # . . .
y6   . . # # # # # # # # # . . .
y7   . . # . . . . . . . . . . .
y8   . . # . . . . . . . . . . .
y9   . . # . . . . . . . . . . .
y10  . . # # # # # # # # # # # E
y11  . . . . . . . . . . . . . .
y12  . . . . . . . . . . . . . .
```

The middle band (y3–y5, y7–y9) is flanked by route on both sides, so a
tower placed there covers two lanes — the "crosses multiple times" spot
the design calls for.

As implemented: the route is a list of corners,
`(0,2) → (10,2) → (10,6) → (2,6) → (2,10) → (13,10)`, with the straight
segments between them filled in at startup so every turn is 90 degrees.
Spawn is the first corner, the exit the last. Every cell *not* on the
route is solid for pathfinding and buildable for towers — which is why a
tower can never block the route, and why no path-blocking validation is
needed anywhere.

### Destructible shortcuts

A blocked rock cell is just a solid cell in the grid; opening a shortcut
flips it open and makes every ground enemy re-path. The pathfinding
supports this fully, but no unit triggers it yet.

### Difficulty variants

Deferred post-MVP. The map should change per difficulty — a shortcut
appears (shorter enemy route), or previously good tower spots become
unavailable. Ship easy with this single route first; design medium and
hard once the core loop is playable and proven fun. With the grid-based
system this is cheap: a difficulty variant is just a different solid/open
cell layout, not a different waypoint array.

---

## 11. Multiplayer

Players can take on the fight together with their friends. Players don't
play together in the same instance, but each separately. They can,
however, see what the other is doing in realtime — so they can learn from
each other.

Not in scope for v1. Realtime sync across players is a networking system,
not a small add-on, and it affects the architecture of the run-state
singleton quite a bit if done early. Decide whether it's a v1 feature or
a post-launch goal before building much more.

---

## 12. Balance

Not final — concrete starting points so the game is playable instead of
relying on placeholders. Tune all of it from playtesting. These numbers
live in code in two places: `ElementTypes.DATA` for towers, and
`WaveSpawner` for enemies and rewards. Keep them in sync with this
section.

### Economy

Kill rewards are paid **flat on every wave** — they do not grow with the
round number. See the unresolved note under [Gold](#gold).

| | Value |
|---|---|
| Starting gold | 150 |
| Basic enemy kill | 5 gold |
| All-resist kill | 10 gold |
| Captain kill | 20 gold |
| Boss kill | 50 gold |
| Tower sell refund | 75% of build cost, floored |
| Wave auto-start interval | 30 s |
| Round-clear speed bonus | not implemented |
| Early-start bonus | not implemented |

### Starting lives, by difficulty

| Easy | Medium | Hard |
|---|---|---|
| 20 | 15 | 10 |

### Basic towers

| Tower | Cost | Damage | Fire rate | Range |
|---|---|---|---|---|
| Fire  | 50 | 8  | 1.2/s | 170 |
| Water | 50 | 6  | 1.0/s | 190 |
| Earth | 60 | 12 | 0.7/s | 150 |
| Air   | 55 | 7  | 1.5/s | 200 |

Range is measured on the flat isometric ground plane, so a range
"circle" is round in world terms and drawn as an ellipse.

### Enemies

Enemy HP is **not** a fixed number per rank. There is one base value that
grows every wave, and each rank is a multiple of it:

```
base HP = 30 × 1.12^(wave − 1)
```

That compounds to roughly 8.6× by wave 20. Every rank rides the same
curve, so the whole roster gets tougher together.

| Type | HP | Speed | Lives cost | Body | Appears on |
|---|---|---|---|---|---|
| Basic (any element) | 1 × base | 60 | 1 | 18 px | every wave |
| All-resist | 1.7 × base | 60 | 1 | 18 px | waves divisible by 3, from wave 4 → 6, 9, 12, 15, 18 |
| Captain | 3 × base | 60 | 3 | 30 px | every 5th wave → 5, 10, 15, 20 |
| Boss | 7 × base | **45** | 5 | 44 px | every 10th wave → **10 and 20 only** |

Body size is how a player tells the ranks apart at a glance, so it tracks
roughly the square root of the HP multiplier — the drawn *area* then
scales with how much punishment the unit absorbs. A boss is 44 px across
on a 64 px tile, about as large as it can get without swallowing its
neighbours. The shadow, health bar and projectile aim point are all
derived from this one number.

Because captains, bosses and all-resists don't spawn in wave 1, their
multiplier applied to the wave-1 base (90 / 210 / 51) is a number that
never actually occurs in play. What you meet is:

| Rank | First appearance | Wave 20 |
|---|---|---|
| Basic | 30 (wave 1) | 258 |
| All-resist | 90 (wave 6) | 350 (wave 18) |
| Captain | 142 (wave 5) | 775 |
| Boss | 582 (wave 10) | 1809 |

All-resist takes 75% damage from every element, ignoring the normal
matchup table. It counts as a basic-rank unit, so it is *not* larger —
it's identified by its grey body instead of an element colour. Bosses are
the only rank slower than 60.

> **Watch in playtesting:** a wave-20 boss has 1809 HP against a fire
> tower's ~9.6 damage per second, and bosses appear only twice in a whole
> run. Whether that reads as a climax or a wall is an open question.

### Wave scaling

- 8 enemies in wave 1 (`6 + 2 × wave`), growing to 48 by wave 20 —
  including the rank spawns above.
- HP per rank as above.
- Kill rewards do **not** scale; see [Economy](#economy).
- 20 waves clears the game.

---

## 13. Implementation

*A map of what exists, and where real art hooks in. Detailed
architectural rules and invariants live in `CLAUDE.md`.*

### Scenes

```
Main.tscn        the level, and the main scene
  Camera2D       zoom 1.25, centred on the grid at startup
  Map            builds one node per grid cell from the route data
  Entities       holds enemies, towers, projectiles, floating text
  WaveSpawner    wave composition and timing
  HUD            instance of HUD.tscn

HUD.tscn
  TopBar/Row              gold, lives, wave and next-wave-timer labels
  MessageLabel            transient "Can't build there" / "Not enough gold"
  BuildBar                element buttons (unlocked only) + next-wave button
  ResultPanel             hidden until game over / victory
  ElementSelectPanel      the start-of-run element pick
  TowerDetailPanel        floating popover for the selected tower

Enemy.tscn / Tower.tscn / Projectile.tscn / FloatingText.tscn
  bare Node2D + script each
```

`Main`, `Map` and `Entities` share one depth sort, so terrain in front of
a unit correctly occludes it — that's what makes the ravine read as a
ravine.

### Tower detail panel

Clicking a placed tower selects it and opens `TowerDetailPanel`, a
floating popover that re-anchors to the tower each frame (screen-space,
via the world canvas transform, so it tracks pan and zoom). It shows the
tower's damage, range and fire rate, a **Sell** button (refunds 75% of
build cost, floored — frees the cell for a rebuild), and a disabled
**Upgrade** button awaiting the leveling / token economy. `Main` owns the
selection state and performs the sell; the panel only reads stats and
emits intent. The vertical layout leaves room for the planned
active-buffs section and item slots (the modifier system under
[Items](#items)) without a rebuild.

### Adding an element

There are no inherited scenes per element or per rank. A single
`Enemy.tscn` is configured at spawn time from the wave composition, and a
single `Tower.tscn` from `ElementTypes.DATA`. Adding an element means
adding one entry to `ElementTypes.DATA` — tower stats, colour, the build
bar button and the element pick card all follow automatically.

### No physics anywhere

There are no `Area2D` or `CollisionShape2D` nodes. Towers find targets by
distance against the `enemies` group; projectiles home in on a direct
target reference. That avoids collision-layer setup entirely and is
plenty fast at this scale. This was a deliberate change away from an
earlier collision-based approach — don't reintroduce it without a reason.

### Art

All visuals are placeholder shapes drawn in code, so the game runs with
no assets. Replacing them means adding a `Sprite2D` child to a scene and
deleting its `_draw()` body; the map cell is the one to swap for real
tiles. Because the cell↔world conversion is owned centrally, moving the
map to a real `TileMapLayer` doesn't touch anything else.

No AI sprite generation used so far. Current leaning is a free CC0 pack
(e.g. the Kenney.nl isometric / tower-defense packs) to get real-looking
art in fast, with AI sprite tools (PixelLab, Leonardo, Scenario) as a
later option once the exact asset list is known. They go in
`assets/sprites` and `assets/tiles`.

---

## 14. Open questions

Check here before inventing a rule.

- **Does the kill reward scale per round?** The design says yes, the
  build pays flat. See the note under [Gold](#gold).
- **Combination tower gold costs.** The interaction and token model are
  designed; the gold amounts for transforms and upgrades are not. This is
  the only thing blocking implementation of
  [section 8](#8-elemental-progression-and-combination-towers).
- **Element pros and cons.** The element-select screen reserves a block
  per card for them (`ElementTypes.DATA[...]["pros"]` / `["cons"]`, one
  bullet per entry). Both are empty because the strengths and weaknesses
  beyond the raw stats aren't designed yet.
- **Potions and items.** No effects list beyond Gold Find. Deferred until
  after MVP playtesting — but build the generic modifier system described
  under [Items](#items) rather than hardcoding.
- **Multiplayer.** How do players communicate — chat, video, voice? And
  is multiplayer in scope for v1 at all?
- **Wave interval.** 25 s is a placeholder; the original doc left it as
  "xx seconds".
- **Per-difficulty map variants.** Deferred post-MVP, not designed.
- **Boss pacing.** Bosses appear only twice in a run (waves 10 and 20),
  and the wave-20 one has 1809 HP against a fire tower's ~9.6 DPS. Climax
  or wall? See the note under [Enemies](#enemies).
- **All the numbers.** Everything in [Balance](#12-balance) is a first
  draft and untuned.
