class_name LevelManager
extends Node

signal level_started(level_number: int, total_waves: int)
signal wave_started(wave_number: int, total_waves: int)
signal wave_completed(wave_number: int)
signal level_completed(level_number: int)
signal all_levels_completed()

# Ship type enum - replaces magic strings
enum ShipType { FRIGATE, BOMBER }

# Timing constants
const DEFAULT_COMPLETION_DELAY := 60.0
const LEVEL1_WAVE2_DELAY := 30.0
const LEVEL2_WAVE2_DELAY := 20.0
const LEVEL2_WAVE3_DELAY := 25.0

# Ship spawn data within a wave
class ShipSpawn:
	var ship_type: int  # ShipType enum value
	var count: int

	func _init(type: int, amount: int) -> void:
		ship_type = type
		count = amount

# Wave data - contains ships and delay before spawning
class WaveData:
	var ships: Array = []  # Array of ShipSpawn
	var delay: float  # Seconds to wait before this wave starts

	func _init(delay_seconds: float = 0.0) -> void:
		delay = delay_seconds

	func add_ships(type: int, amount: int) -> WaveData:
		var spawn = ShipSpawn.new(type, amount)
		ships.append(spawn)
		return self  # Allow chaining

# Level data - contains waves and completion delay
class LevelData:
	var waves: Array = []  # Array of WaveData
	var completion_delay: float = 60.0  # Wait after last wave to complete level

	func add_wave(wave: WaveData) -> LevelData:
		waves.append(wave)
		return self  # Allow chaining

# Level definitions
var levels: Array = []  # Array of LevelData
var current_level: int = 0
var current_wave: int = 0
var wave_timer: float = 0.0
var completion_timer: float = 0.0
var is_spawning_waves: bool = false
var waiting_for_completion: bool = false
var level_active: bool = false

# Reference to game manager for spawning
var game_manager: Node = null


func _ready() -> void:
	_define_levels()


func _define_levels() -> void:
	# Level 1: 2 waves
	var level1 = LevelData.new()
	level1.completion_delay = DEFAULT_COMPLETION_DELAY

	# Wave 1: 5 frigates, starts immediately
	var wave1_1 = WaveData.new(0.0)
	wave1_1.add_ships(ShipType.FRIGATE, 5)
	level1.add_wave(wave1_1)

	# Wave 2: 2 bombers, starts 30s after wave 1
	var wave1_2 = WaveData.new(LEVEL1_WAVE2_DELAY)
	wave1_2.add_ships(ShipType.BOMBER, 2)
	level1.add_wave(wave1_2)

	levels.append(level1)

	# Level 2: More challenging
	var level2 = LevelData.new()
	level2.completion_delay = DEFAULT_COMPLETION_DELAY

	# Wave 1: 3 frigates
	var wave2_1 = WaveData.new(0.0)
	wave2_1.add_ships(ShipType.FRIGATE, 3)
	level2.add_wave(wave2_1)

	# Wave 2: 3 bombers after 20s
	var wave2_2 = WaveData.new(LEVEL2_WAVE2_DELAY)
	wave2_2.add_ships(ShipType.BOMBER, 3)
	level2.add_wave(wave2_2)

	# Wave 3: Mixed wave - 4 frigates + 2 bombers after 25s
	var wave2_3 = WaveData.new(LEVEL2_WAVE3_DELAY)
	wave2_3.add_ships(ShipType.FRIGATE, 4)
	wave2_3.add_ships(ShipType.BOMBER, 2)
	level2.add_wave(wave2_3)

	levels.append(level2)


func start_level(level_index: int) -> void:
	if level_index < 0 or level_index >= levels.size():
		push_error("Invalid level index: %d" % level_index)
		return

	current_level = level_index
	current_wave = 0
	wave_timer = 0.0
	completion_timer = 0.0
	is_spawning_waves = true
	waiting_for_completion = false
	level_active = true

	var total_waves = levels[current_level].waves.size()
	print("Starting Level %d" % (current_level + 1))
	level_started.emit(current_level + 1, total_waves)


func _process(delta: float) -> void:
	if not level_active:
		return

	if is_spawning_waves:
		_process_wave_spawning(delta)
	elif waiting_for_completion:
		_process_completion(delta)


func _process_wave_spawning(delta: float) -> void:
	var level_data = levels[current_level]

	if current_wave >= level_data.waves.size():
		# All waves spawned, wait for completion
		is_spawning_waves = false
		waiting_for_completion = true
		completion_timer = 0.0
		print("All waves spawned. Waiting %.0fs for level completion..." % level_data.completion_delay)
		return

	var wave_data = level_data.waves[current_wave]
	wave_timer += delta

	# Check if it's time to spawn this wave
	if wave_timer >= wave_data.delay:
		_spawn_wave(wave_data)
		current_wave += 1
		wave_timer = 0.0

		wave_started.emit(current_wave, level_data.waves.size())


func _spawn_wave(wave_data: WaveData) -> void:
	print("  Spawning Wave %d" % (current_wave + 1))

	for ship_spawn in wave_data.ships:
		match ship_spawn.ship_type:
			ShipType.FRIGATE:
				_spawn_frigates(ship_spawn.count)
			ShipType.BOMBER:
				_spawn_bombers(ship_spawn.count)
			_:
				push_warning("Unknown ship type: %d" % ship_spawn.ship_type)


func _spawn_frigates(count: int) -> void:
	if not game_manager:
		return

	print("    Spawning %d frigates" % count)
	for i in count:
		game_manager.spawn_frigate()


func _spawn_bombers(count: int) -> void:
	if not game_manager:
		return

	print("    Spawning %d bombers (squadron)" % count)
	game_manager.spawn_bomber_squadron(count)


func _process_completion(delta: float) -> void:
	var level_data = levels[current_level]
	completion_timer += delta

	if completion_timer >= level_data.completion_delay:
		_complete_level()


func _complete_level() -> void:
	print("Level %d Complete!" % (current_level + 1))
	level_completed.emit(current_level)

	waiting_for_completion = false
	level_active = false

	# Check if there are more levels
	if current_level + 1 < levels.size():
		# Could auto-start next level or wait for player input
		pass
	else:
		print("All Levels Completed!")
		all_levels_completed.emit()


func start_next_level() -> void:
	if current_level + 1 < levels.size():
		start_level(current_level + 1)
	else:
		all_levels_completed.emit()


func get_current_level() -> int:
	return current_level + 1  # 1-indexed for display


func get_current_wave() -> int:
	return current_wave  # Already 1-indexed after spawn


func get_total_waves() -> int:
	if current_level < levels.size():
		return levels[current_level].waves.size()
	return 0
