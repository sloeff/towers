# Towers

Isometric elemental tower defense, built in Godot 4.7. This is a
deliberately scoped-down MVP of the full design doc: single player, one
map, 4 basic elemental towers, no upgrades/combos/potions/items/
multiplayer yet.

The core loop is playable end to end:

  waves spawn -> towers detect + shoot -> elemental damage applies ->
  gold/lives update -> game over on 0 lives (or victory after wave 20)

Everything else in the design doc (combination towers, leveling, potions,
items, trading, multiplayer, difficulty-specific map changes) layers on
top of this - none of it requires reworking what's here.

## Running it

Open the folder as a project in Godot 4.7+ and press F5. `scenes/Main.tscn`
is set as the main scene.

## Controls

| Input | Action |
|---|---|
| Click an element button (or the build bar) | Select which tower to build |
| Left click a green tile | Build the selected tower there |
| Hover a placed tower | Show its range |
| Right click + drag, or arrow keys | Pan the camera |
| Mouse wheel | Zoom |
| "Start next wave" | Skip the countdown |

Towers can only go on the grass beside the route, never on it. The tile
under the cursor highlights green when you can build there and red when
you can't (on the route, occupied, or not enough gold).

## Structure

```
autoload/
  GameManager.gd    - gold, lives, wave number, win/lose (global singleton)
  ElementTypes.gd   - fire/water/earth/air effectiveness table, colors,
                      and the basic-tower stats from BALANCE.md
  GridManager.gd    - the map: route layout, AStarGrid2D pathfinding,
                      isometric cell<->world conversion, build validity
scenes/
  Main.tscn         - the level (camera, map, entities, spawner, HUD)
  HUD.tscn          - gold/lives/wave readout, build bar, result panel
  Enemy.tscn / Tower.tscn / Projectile.tscn
scripts/
  Main.gd           - camera control, tower placement, HUD wiring
  Map.gd            - draws the isometric grid + hover highlight
  Enemy.gd          - health, dynamic pathing (re-routes on grid changes),
                      elemental damage
  Tower.gd          - range detection + firing (targets furthest-along enemy)
  Projectile.gd     - homing shot, applies damage on hit
  WaveSpawner.gd    - wave composition and timing
  HUD.gd            - readout, element buttons, end-of-run panel
```

## Art

All visuals are placeholder shapes drawn in code (`_draw()`), so the game
runs with no assets. `assets/sprites` and `assets/tiles` are where real
art goes; `Map.gd` is the piece to replace with a `TileMapLayer` once
tiles exist.

## Design doc gaps to resolve before/while building

These aren't blockers for the MVP above, but you'll need answers before
expanding past it:

- **Potions & Items** - deferred until after MVP playtesting; specific
  list not decided yet (Gold Find is the only one designed so far -
  see BALANCE.md). Architecturally, build the system to support a wide,
  open-ended variety of potions/items applied to towers, rather than
  hardcoding just Gold Find - e.g. a generic "modifier" resource/data
  structure a tower can hold a list of, instead of one-off flags per
  effect.
- **Numbers** - the values in BALANCE.md are now live in the code
  (`ElementTypes.DATA` for towers, `WaveSpawner._wave_composition()` for
  enemies), but they're first-draft and untuned.
- **Combination tower open questions** - the interaction and cost model
  are now designed (token-based, gold cost on top - see
  COMBO_TOWERS.md), but the gold amounts are still unresolved. Nothing
  from this system is implemented yet.
- **Experience / tower leveling** - designed in DESIGN_DOC.md, not
  implemented yet.
- **Multiplayer** - "players see each other in realtime" is a networking
  feature, not a small add-on. Worth deciding whether this is in scope
  for a first release or a post-launch goal, since it affects the
  architecture of GameManager quite a bit if done early.
- **Map** - the MVP route is a fixed S-shape in `GridManager.ROUTE`. The
  destructible-rock shortcut is supported by the pathfinding
  (`GridManager.set_cell_blocked()`) but nothing triggers it yet, and
  per-difficulty map variants aren't designed - see MAP_LAYOUT.md.
- **HTML5 export** - not tested yet. The design targets browser; export
  early per QUICKSTART.md.

## Requirements

Godot 4.7+ (GL Compatibility renderer, for the eventual web export).
