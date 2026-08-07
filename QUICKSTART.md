# Towers — Quick Start

## Decisions so far
- **Engine**: Godot 4.7 (chose full engine over a JS library like Phaser)
- **Scope**: MVP first — single player, one map, 4 basic elemental towers,
  no upgrades/combos/potions/items/multiplayer yet. Everything else in the
  design doc layers on top later without needing a rewrite.
- **Platform**: Browser (HTML5 export) — test the web export early and
  often as you build, not just at the end. Web export is heavier than a
  native web game (bigger download, slower cold-start via WASM), so
  catching browser-specific issues early matters.

## Run it
Open this folder as a project in Godot 4.7+ and press F5.
`scenes/Main.tscn` is the main scene. See README.md for controls and the
file-by-file structure.

## Where the MVP stands
Working: the isometric map and route, dynamic A* pathing, wave spawning
with scaling composition, click-to-place towers with build validation,
elemental damage multipliers, gold/lives economy, and game over / victory
with restart.

Not built yet: tower selling, tower experience/leveling, elemental tokens
and combination towers, potions and items, the destructible-rock shortcut
trigger, per-difficulty map variants, sound, and real art.

## Next steps, in order
1. **HTML5 export** — do it now, while the project is small, and confirm
   it runs in a real browser. Everything else is easier to debug before
   this than after.
2. **Playtest and tune** — the numbers in BALANCE.md are a first draft.
   Wave 1-20 pacing, tower costs, and enemy HP scaling all need real play.
3. **Tower selling / refunds** — currently a misplaced tower is a
   permanent loss of gold, which makes playtesting frustrating.
4. **Tower experience and leveling** (DESIGN_DOC.md, Experience section).
5. **Elemental tokens + combination towers** (COMBO_TOWERS.md) — needs the
   gold cost amounts decided first.
6. **Real art** — replace the `_draw()` placeholder shapes.

## Design doc gaps to resolve as you go
- **Potions & Items** — no effects list yet beyond Gold Find.
- **Combo tower gold costs** — the only unresolved piece of COMBO_TOWERS.md.
- **Multiplayer** — realtime "watch other players" is a networking
  feature, not a small add-on. Decide if it's in scope for v1 or a
  post-launch goal — affects GameManager's architecture if done early.
- **Per-difficulty map variants** — MAP_LAYOUT.md defers these post-MVP.

## Sprites / art
No AI sprite generation used yet. All visuals are placeholder shapes drawn
in code. Leaning toward a free CC0 pack (e.g. Kenney.nl isometric/tower-
defense packs) to get real-looking art in fast, with AI sprite tools
(PixelLab, Leonardo, Scenario) as a later option once the exact asset list
is known. Drop them in `assets/sprites` and `assets/tiles`.
