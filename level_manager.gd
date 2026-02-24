class_name LevelManager
extends Node

signal level_started(level_number: int, total_waves: int)
signal wave_started(wave_number: int, total_waves: int)
signal level_completed(level_number: int)
signal all_levels_completed()

enum State { IDLE, SPAWNING, WAITING, COMPLETE }

# Wave data - delay before spawning and enemy definitions added later
class WaveData:
	var delay: float

	func _init(delay_seconds: float = 0.0) -> void:
		delay = delay_seconds

# Level data - contains waves and a completion wait after the last wave
class LevelData:
	var waves: Array = []  # Array of WaveData
	var completion_delay: float = 30.0

	func add_wave(wave: WaveData) -> LevelData:
		waves.append(wave)
		return self

var levels: Array = []  # Array of LevelData
var current_level: int = 0
var current_wave: int = 0
var wave_timer: float = 0.0
var completion_timer: float = 0.0
var _state: State = State.IDLE


func _ready() -> void:
	_define_levels()


func _define_levels() -> void:
	# Placeholder level definitions — enemy spawning to be added
	var level1 := LevelData.new()
	level1.add_wave(WaveData.new(0.0))
	level1.add_wave(WaveData.new(10.0))
	levels.append(level1)

	var level2 := LevelData.new()
	level2.add_wave(WaveData.new(0.0))
	level2.add_wave(WaveData.new(10.0))
	level2.add_wave(WaveData.new(10.0))
	levels.append(level2)


func start_level(level_index: int) -> void:
	if level_index < 0 or level_index >= levels.size():
		push_error("Invalid level index: %d" % level_index)
		return

	current_level = level_index
	current_wave = 0
	wave_timer = 0.0
	completion_timer = 0.0
	_state = State.SPAWNING

	var total_waves: int = levels[current_level].waves.size()
	level_started.emit(current_level + 1, total_waves)


func _process(delta: float) -> void:
	match _state:
		State.SPAWNING:
			_process_wave_spawning(delta)
		State.WAITING:
			_process_completion(delta)


func _process_wave_spawning(delta: float) -> void:
	var level_data: LevelData = levels[current_level]

	if current_wave >= level_data.waves.size():
		_state = State.WAITING
		completion_timer = 0.0
		return

	var wave_data: WaveData = level_data.waves[current_wave]
	wave_timer += delta

	if wave_timer >= wave_data.delay:
		wave_timer = 0.0
		current_wave += 1
		wave_started.emit(current_wave, level_data.waves.size())


func _process_completion(delta: float) -> void:
	var level_data: LevelData = levels[current_level]
	completion_timer += delta

	if completion_timer >= level_data.completion_delay:
		_complete_level()


func _complete_level() -> void:
	_state = State.COMPLETE
	level_completed.emit(current_level)

	if current_level + 1 >= levels.size():
		all_levels_completed.emit()


func start_next_level() -> void:
	if current_level + 1 < levels.size():
		start_level(current_level + 1)
	else:
		all_levels_completed.emit()


func get_current_level() -> int:
	return current_level + 1


func get_current_wave() -> int:
	return current_wave


func get_total_waves() -> int:
	if current_level < levels.size():
		return levels[current_level].waves.size()
	return 0
