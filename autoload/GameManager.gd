extends Node
## Autoload singleton. Holds run-wide state: gold, lives, wave number.
## Registered in project.godot under [autoload] as "GameManager".

signal gold_changed(new_amount: int)
signal lives_changed(new_amount: int)
signal wave_changed(new_wave: int)
signal elements_changed
signal game_over
signal victory

const STARTING_GOLD := 150
const MAX_WAVES := 20

enum Difficulty { EASY, MEDIUM, HARD }

# Starting lives per design doc: easy 20, medium 15, hard 10.
const STARTING_LIVES := {
	Difficulty.EASY: 20,
	Difficulty.MEDIUM: 15,
	Difficulty.HARD: 10,
}

var gold: int = 0
var lives: int = 20  # overwritten by difficulty on new_game()
var wave_number: int = 0
var is_over: bool = false

## Elements the player is allowed to build, in the order they were unlocked.
## Empty until the start-of-run element pick, which unlocks exactly one. The
## elemental token economy (COMBO_TOWERS.md) will extend this list later; it is
## an array rather than a single value for that reason.
var unlocked_elements: Array[int] = []


func new_game(difficulty: Difficulty = Difficulty.EASY) -> void:
	gold = STARTING_GOLD
	lives = STARTING_LIVES[difficulty]
	wave_number = 0
	is_over = false
	unlocked_elements.clear()
	gold_changed.emit(gold)
	lives_changed.emit(lives)
	wave_changed.emit(wave_number)
	elements_changed.emit()


func unlock_element(element: int) -> void:
	if unlocked_elements.has(element):
		return
	unlocked_elements.append(element)
	elements_changed.emit()


func is_element_unlocked(element: int) -> bool:
	return unlocked_elements.has(element)


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func advance_wave() -> void:
	wave_number += 1
	wave_changed.emit(wave_number)


func lose_life(amount: int = 1) -> void:
	if is_over:
		return
	lives = maxi(lives - amount, 0)
	lives_changed.emit(lives)
	if lives == 0:
		is_over = true
		game_over.emit()


func win() -> void:
	if is_over:
		return
	is_over = true
	victory.emit()
