# Towers

Isometric elemental tower defense, built in Godot 4.7, targeting the
browser. Waves of elemental enemies walk a ravine route; you build
elemental towers on the plateau beside it and stop them before they reach
the exit.

At the start of a run you pick **one element** and can only build that
element's towers. Every 5 rounds you get a choice: advance an element you
own to its next **tier** (then upgrade its towers for gold) or unlock a
new element. Once you own two elements you can **transform** a placed tower
into their **combination tower** — the first, Fire + Air → Fire Breath, is in;
more combos are still to come.

**[DESIGN_DOC.md](DESIGN_DOC.md) is the single source of truth** for
design, balance numbers, map layout and implementation notes.

## Dev journal

- 2026-08-17 - Added items and potions that be equiped on towers.
- 2026-08-15 - Added the **remaining five combination towers**, one per elemental
  pair, each with a distinct mechanic: **Lava** (Fire+Earth, burn/damage-over-time),
  **Steam** (Fire+Water, wide pure AoE), **Meteor** (Earth+Air, heavy hit + 1 s stun),
  **Quicksand** (Earth+Water, projectile-less slow aura), and **Hail** (Air+Water,
  small splash + light slow). Behind them: three reusable enemy status primitives
  (slow — a stun is a factor-0 slow, damage-over-time, and an aura firing mode) and a
  transform panel that now offers **one button per available combo** when a tower has
  several owned partners.
- 2026-08-14 — Added the first **combination tower**: once you own two elements, a
  placed basic tower can **Transform** (from its detail panel, for gold) into their
  combo. Shipped Fire + Air → **Fire Breath**, which deals Fire-typed
  **area-of-effect** damage and hits over 2× as hard as either parent. The combo
  carries its XP level through the transform and gets its own tier ladder, capped
  by the lower of its two parents' tiers.
- 2026-08-14 — Added the elemental **tier** economy: every 5 rounds the game pauses and offers a choice — advance an element you already own to its next tier, or unlock a new one. Placed towers can then be upgraded a tier at a time for gold (3× the purchase price), boosting damage and fire rate and raising their XP cap, all shown and driven from the tower detail panel. (Combination towers, which build on this, are still to come.)
- 2026-08-13 — Made the game landscape-first on phones: the camera fits the board to the screen and re-frames on rotation, and a touch device held in portrait shows a "rotate to landscape" prompt (the board is landscape-shaped) with the run paused until it's rotated.
- 2026-08-12 — Added touch controls (one-finger pan, two-finger pinch-zoom, tap-to-build) and a two-step build confirm with a ghost preview and a "Build" button, shared by desktop and touch.
- 2026-08-12 — Made the game fill any screen edge-to-edge (stretch aspect "expand") so it fits laptops, phones and tablets without letterboxing; full phone/tablet playability still needs touch controls.
- 2026-08-12 — Added automatic tower experience: towers gain XP on killing blows and level up to 5, boosting damage and fire rate, with a live XP bar, a "Level up!" pop-up, and towers growing taller and brighter each level.
- 2026-08-10 — Added tower detail pop-up that displays the active potion effects, experience bar, item slots, tower stats, and a sell button.

## Running it

Open this folder as a project in Godot 4.7+ and press F5.
`scenes/Main.tscn` is the main scene.

### Testing on a phone (or a phone-sized browser)

`./dev-web.sh` builds the HTML5 export to `builds/web/` and serves it locally. 
Open the printed `localhost` URL in Chrome and toggle the device toolbar (Cmd+Shift+M)
to emulate a phone with touch, or open the LAN URL on a real phone on the same
Wi-Fi. Ctrl+C stops it. Needs the web export templates installed once via
Godot → Editor → Manage Export Templates. Override the binary or port with
`GODOT=... PORT=... ./dev-web.sh`.

## Controls

Desktop and touch share one set of actions:

| Desktop | Touch | Action |
|---|---|---|
| Pick an element | Pick an element | Choose your element at the start of a run |
| Click a green tile | Tap a green tile | Preview a tower there, then press **Build** to confirm |
| Click a placed tower | Tap a placed tower | Open its detail panel (stats, sell, upgrade tier, transform to a combo) |
| Right-drag, or arrow keys | One-finger drag | Pan the camera |
| Mouse wheel | Two-finger pinch | Zoom |
| Escape | Tap empty ground / ✕ | Cancel a pending build or close a panel |
| "Start next wave" | "Start next wave" | Skip the countdown |

Building is a two-step confirm: pick a spot to see a ghost tower and its
range, then press **Build** (or tap the same tile again). Towers can only
go on the grass beside the route, never on it — a spot highlights green
when you can build there and red when you can't (on the route, occupied,
or not enough gold).

## Requirements

Godot 4.7+ (GL Compatibility renderer, for the web export).
