extends Node2D
## Spawns waves of enemies at the map's spawn cell, each pathing to the exit
## via GridManager (AStarGrid2D) - not a fixed waypoint list, so routes react
## live to the grid changing (e.g. a shortcut opening).
##
## Wave composition scales through both headcount and enemy strength, per the
## scaling decision in DESIGN_DOC.md's Gold section.

signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)

const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")

## Gold per kill, flat across every wave - the values in DESIGN_DOC.md's Balance
## section, paid literally. This deliberately does NOT scale with the wave
## number, while the design's Gold section still calls for rewards that grow per
## round; the two disagree until that's decided (DESIGN_DOC, open questions).
const GOLD_BASIC := 5
const GOLD_ALL_RESIST := 10
const GOLD_CAPTAIN := 20
const GOLD_BOSS := 50

## XP granted to the tower that lands the killing blow, by rank (DESIGN_DOC,
## "Tower experience"). Independent of the gold values above.
const XP_BASIC := 10
const XP_ALL_RESIST := 15
const XP_CAPTAIN := 30
const XP_BOSS := 75

@export var entities_path: NodePath = ^"../Entities"
@export var wave_interval_seconds: float = 30.0
@export var first_wave_delay: float = 10.0
@export var spawn_gap_seconds: float = 0.6

var time_until_next_wave: float = 0.0

@onready var _entities: Node2D = get_node(entities_path)

var _alive_enemies: int = 0
var _spawning: bool = false
## The last wave we announced as cleared, so wave_cleared (and the victory it
## triggers) fires exactly once per wave even if the live count is ever driven
## past zero - the tier choice and victory screens must not reopen.
var _cleared_wave: int = 0


func _ready() -> void:
	time_until_next_wave = first_wave_delay


func _process(delta: float) -> void:
	if GameManager.is_over or _spawning:
		return
	if GameManager.wave_number >= GameManager.MAX_WAVES:
		return
	time_until_next_wave -= delta
	if time_until_next_wave <= 0.0:
		_start_next_wave()


## Public hook for the "start next wave early" button in the design doc's
## gold bonus section. The bonus itself isn't implemented yet.
func start_next_wave_early() -> void:
	if not _spawning and not GameManager.is_over and GameManager.wave_number < GameManager.MAX_WAVES:
		_start_next_wave()


func _start_next_wave() -> void:
	_spawning = true
	GameManager.advance_wave()
	var wave: int = GameManager.wave_number
	wave_started.emit(wave)

	for spec in _wave_composition(wave):
		_spawn_enemy(spec)
		await get_tree().create_timer(spawn_gap_seconds).timeout
		if not is_inside_tree():
			return

	# The inter-wave countdown starts only now, once the last unit of the round
	# has spawned into the level (DESIGN_DOC, "Interval between groups"). While
	# _spawning is true above, _process freezes the countdown.
	_spawning = false
	time_until_next_wave = wave_interval_seconds


## Spawn order is the order of this array, one every `spawn_gap_seconds`.
## Leaders march at the FRONT of their wave: the boss first, then the captain,
## then the rank and file. The player sees what they're up against as the wave
## arrives rather than after clearing it.
func _wave_composition(wave: int) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var basic_health := 30.0 * pow(1.12, wave - 1)

	if wave % 10 == 0:
		specs.append({
			"element": ElementTypes.ALL[(wave + 1) % ElementTypes.ALL.size()],
			"health": basic_health * 7.0,
			"speed": 45.0,
			"gold": GOLD_BOSS,
			"xp": XP_BOSS,
			"lives": 5,
			"rank": Enemy.Rank.BOSS,
		})

	if wave % 5 == 0:
		specs.append({
			"element": ElementTypes.ALL[wave % ElementTypes.ALL.size()],
			"health": basic_health * 3.0,
			"speed": 60.0,
			"gold": GOLD_CAPTAIN,
			"xp": XP_CAPTAIN,
			"lives": 3,
			"rank": Enemy.Rank.CAPTAIN,
		})

	for i in 6 + wave * 2:
		specs.append({
			"element": ElementTypes.ALL[i % ElementTypes.ALL.size()],
			"health": basic_health,
			"speed": 60.0,
			"gold": GOLD_BASIC,
			"xp": XP_BASIC,
			"lives": 1,
			"rank": Enemy.Rank.BASIC,
			"flying": ElementTypes.ALL[i % ElementTypes.ALL.size()] == ElementTypes.Element.AIR,
		})

	if wave >= 4 and wave % 3 == 0:
		specs.append({
			"element": ElementTypes.Element.EARTH,
			"health": basic_health * 1.7,
			"speed": 60.0,
			"gold": GOLD_ALL_RESIST,
			"xp": XP_ALL_RESIST,
			"lives": 1,
			"rank": Enemy.Rank.BASIC,
			"all_resist": true,
		})

	return specs


func _spawn_enemy(spec: Dictionary) -> void:
	var enemy := ENEMY_SCENE.instantiate()
	enemy.configure(spec)
	_entities.add_child(enemy)
	enemy.start_at(GridManager.spawn_cell(), GridManager.goal_cell())
	_alive_enemies += 1
	enemy.died.connect(_on_enemy_removed)
	enemy.reached_goal.connect(_on_enemy_removed)


func _on_enemy_removed(_enemy: Node) -> void:
	_alive_enemies -= 1
	if _alive_enemies > 0 or _spawning:
		return
	if GameManager.wave_number == _cleared_wave:
		return  # already announced this wave; never fire twice
	_cleared_wave = GameManager.wave_number
	wave_cleared.emit(GameManager.wave_number)
	if GameManager.wave_number >= GameManager.MAX_WAVES:
		GameManager.win()
