# Towers

Isometric elemental tower defense, built in Godot 4.7, targeting the
browser. Waves of elemental enemies walk a ravine route; you build
elemental towers on the plateau beside it and stop them before they reach
the exit.

At the start of a run you pick **one element** and can only build that
element's towers — the token economy that unlocks the rest isn't built
yet, so for now one run means one element.

**[DESIGN_DOC.md](DESIGN_DOC.md) is the single source of truth** for
design, balance numbers, map layout and implementation notes.

## Dev journal

- 2026-08-12 — Added touch controls (one-finger pan, two-finger pinch-zoom, tap-to-build) and a two-step build confirm with a ghost preview and a "Build" button, shared by desktop and touch.
- 2026-08-12 — Made the game fill any screen edge-to-edge (stretch aspect "expand") so it fits laptops, phones and tablets without letterboxing; full phone/tablet playability still needs touch controls.
- 2026-08-12 — Added automatic tower experience: towers gain XP on killing blows and level up to 5, boosting damage and fire rate, with a live XP bar, a "Level up!" pop-up, and towers growing taller and brighter each level.
- 2026-08-10 — Added tower detail pop-up that displays the active potion effects, experience bar, item slots, tower stats, and a sell button.

## Running it

Open this folder as a project in Godot 4.7+ and press F5.
`scenes/Main.tscn` is the main scene.

## Controls

Desktop and touch share one set of actions:

| Desktop | Touch | Action |
|---|---|---|
| Pick an element | Pick an element | Choose your element at the start of a run |
| Click a green tile | Tap a green tile | Preview a tower there, then press **Build** to confirm |
| Click a placed tower | Tap a placed tower | Open its detail panel (stats, sell) |
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
