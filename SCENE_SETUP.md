# Scene structure

All scenes now exist and the game runs — this is a map of what's in them
and where to hook real art in.

## Main.tscn (the level, and the main scene)

```
Main            Node2D          scripts/Main.gd - camera, placement, HUD wiring
  Camera2D                      zoom 1.25, centered on the grid in _ready()
  Map           Node2D          scripts/Map.gd  - draws the isometric grid
  Entities      Node2D          y_sort_enabled; holds enemies, towers, projectiles
  WaveSpawner   Node2D          scripts/WaveSpawner.gd; entities_path -> ../Entities
  HUD                           instance of scenes/HUD.tscn
```

`Entities` is y-sorted so towers and enemies overlap correctly in the
isometric view. Everything spawned at runtime goes in there.

## HUD.tscn

```
HUD             CanvasLayer     scripts/HUD.gd
  TopBar/Row                    GoldLabel, LivesLabel, WaveLabel, TimerLabel
  MessageLabel                  transient "Can't build there" / "Not enough gold"
  BuildBar
    ElementButtons              filled in code from ElementTypes.DATA
    NextWaveButton
  ResultPanel                   hidden until game over / victory
    Center/Box                  TitleLabel, DetailLabel, RestartButton
```

`ResultPanel` has `process_mode = Always` so its Restart button still
works while the tree is paused.

## Enemy.tscn / Tower.tscn / Projectile.tscn

Each is a bare `Node2D` with its script attached. Their visuals are drawn
in code via `_draw()` so the project runs with no art assets. To use real
sprites, add a `Sprite2D` child to each scene and delete the matching
`_draw()` body.

Note there are no Area2D/CollisionShape2D nodes anywhere: towers find
targets by distance against the `enemies` group, and projectiles home in
on a target reference. That avoids collision-layer setup entirely and is
plenty fast at this scale.

## Adding element/rank variants

There are no inherited scenes per element. A single `Enemy.tscn` is
configured at spawn time by `Enemy.configure()` from the spec dictionaries
in `WaveSpawner._wave_composition()`, and a single `Tower.tscn` is
configured by `Tower.configure()` from `ElementTypes.DATA`. Adding a new
element means adding one entry to `ElementTypes.DATA` — the build bar
button and tower stats follow automatically.

## Map

`Map.gd` draws the grid from `GridManager` with `_draw()`. Replacing it
with a real `TileMapLayer` is the intended next step once tiles exist in
`assets/tiles` — `GridManager` already owns the cell<->world conversion,
so nothing else needs to change.
