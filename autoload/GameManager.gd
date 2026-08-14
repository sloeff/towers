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
## elemental tier economy (DESIGN_DOC.md section 8) extends this list.
var unlocked_elements: Array[int] = []

## Per-element tier, keyed by element. An element is "owned" iff it has an entry
## here (tier >= 1). The start-of-run pick and every-5-rounds choice both flow
## through choose_element: picking a new element adds it at tier 1, picking one
## you already own advances its tier. Tiers keep climbing - there is no cap.
var element_tiers: Dictionary = {}


func new_game(difficulty: Difficulty = Difficulty.EASY) -> void:
	gold = STARTING_GOLD
	lives = STARTING_LIVES[difficulty]
	wave_number = 0
	is_over = false
	unlocked_elements.clear()
	element_tiers.clear()
	gold_changed.emit(gold)
	lives_changed.emit(lives)
	wave_changed.emit(wave_number)
	elements_changed.emit()


## Spend a tier choice on an element: a new element is unlocked at tier 1, an
## element already owned is advanced to the next tier. Used for both the
## start-of-run pick and the mid-run choice.
func choose_element(element: int) -> void:
	if element_tiers.has(element):
		element_tiers[element] += 1
	else:
		element_tiers[element] = 1
		unlocked_elements.append(element)
	elements_changed.emit()


## Kept for the start-of-run pick, which unlocks exactly one element at tier 1.
func unlock_element(element: int) -> void:
	if element_tiers.has(element):
		return
	choose_element(element)


## The element's current tier, or 0 if the player doesn't own it.
func element_tier(element: int) -> int:
	return element_tiers.get(element, 0)


func is_element_unlocked(element: int) -> bool:
	return element_tiers.has(element)


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
