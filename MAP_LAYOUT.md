# Map / route layout — v2 (dynamic grid pathing)

*(Replaces the earlier fixed-waypoint-list design — see below for why.)*

## Why this changed
The original plan was a fixed list of waypoints per enemy. That breaks
the moment a special unit can destroy a rock and open a shortcut mid-
level, since a fixed list can't represent "the route just changed."
Enemies now path live via `GridManager` (Godot's `AStarGrid2D`) across a
grid of solid/open cells, and re-request their path whenever the grid
changes.

**Bonus:** this also gives us "units already past the shortcut keep
their current route" for free — an enemy re-paths from wherever it
*currently* is, so if the shortcut is behind it, A* simply won't route
it backward through it. No special-case logic needed.

## Layout (still an S-shape, same idea as before)
Square grid, isometric-projected. A blocked/rock cell is just a solid
cell in the grid - opening a shortcut is `GridManager.set_cell_blocked(cell, false)`.

14 x 13 grid, `#` = route, `.` = buildable ground:

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

The middle band (y3-y5, y7-y9) is flanked by route on both sides, so a
tower placed there covers two lanes — the "crosses multiple times" spot
the design doc asks for.

## Setup (as implemented)
- The route lives in `GridManager.ROUTE` as a list of corners on a
  14x13 grid: `(0,2) -> (10,2) -> (10,6) -> (2,6) -> (2,10) -> (13,10)`.
  Straight segments between corners are filled in at startup, so every
  turn is a 90-degree corner.
- Spawn is the first corner, the exit is the last. Every cell *not* on
  the route is solid for pathfinding and buildable for towers — so a
  tower can never block the route.
- `GridManager` also owns the isometric cell<->world conversion
  (64x32 tiles), so there's no TileMap dependency yet. `Map.gd` draws
  the grid with `_draw()`; swap it for a `TileMapLayer` once real tiles
  exist and nothing else has to change.
- Opening a shortcut is `GridManager.set_cell_blocked(cell, false)`,
  which emits `grid_changed` and makes every ground enemy re-path. The
  pathfinding supports it; no unit triggers it yet.

## Difficulty variants (from the doc)
Deferred post-MVP. Doc says the map changes per difficulty (shortcuts
appear, good tower spots disappear) - ship easy difficulty with this
single route first, design medium/hard variants once the core loop is
playable and proven fun. With the grid-based system this is now cheaper
than before: a difficulty variant is just a different solid/open cell
layout, not a different waypoint array.
