extends Node3D

const AGENT_SCENE: PackedScene = preload("res://scenes/agent.tscn")
const CAMERA_RIG_SCRIPT: Script = preload("res://scripts/camera_rig.gd")
const AGENT_RADIUS: float = 0.25
const DOOR_CLEARANCE_MARGIN: float = 0.1
const MEETING_WALL_X: float = 1.8
const MEETING_START_Z: float = -1.0
const MEETING_END_Z: float = 4.5
const MEETING_DOOR_Z: float = 1.5
const MEETING_DOOR_WIDTH: float = 1.4
const NORTH_EXIT_SIDE_MARGIN: float = 1.5

@export_category("Dimensions de la salle")
@export_range(10.0, 50.0, 0.5) var room_width: float = 20.0
@export_range(10.0, 50.0, 0.5) var room_depth: float = 20.0
@export_range(0.8, 3.0, 0.1) var door_width: float = 1.5
@export_range(0.15, 0.5, 0.05) var wall_thickness: float = 0.3
@export_range(2.0, 5.0, 0.25) var wall_height: float = 3.0
@export_category("Sorties")
@export var upper_right_exit_enabled: bool = true

const FLOOR_THICKNESS: float = 0.2

@export_category("Foule")
@export_range(1, 200, 1) var agent_count: int = 60
@export_range(1.0, 100.0, 1.0) var agent_force_gain: float = 10.0
@export var random_seed: int = 0

@export_category("Alerte et reaction")
@export_range(1.0, 30.0, 1.0) var alarm_delay: float = 5.0
@export_range(0.0, 8.0, 0.1) var max_reaction_delay: float = 3.0
@export_range(30.0, 600.0, 10.0) var duree_max: float = 180.0

@export_category("Obstacle experimental")
@export var pillar_enabled: bool = false
@export_range(0.3, 1.5, 0.1) var pillar_diameter: float = 0.8
@export_range(-3.0, 3.0, 0.1) var pillar_offset_x: float = 0.0
@export_range(0.5, 4.0, 0.1) var pillar_distance_from_door: float = 1.8

@export_category("Campagne automatique")
@export var campaign_enabled: bool = false
@export var campaign_forces: PackedFloat32Array = PackedFloat32Array([10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0])
@export_range(1, 20, 1) var campaign_repetitions: int = 5

const TRACKING_DIR := "user://tracking"
const SUMMARY_PATH := "user://evacuation_summary.csv"
const CAMPAIGN_STATE_PATH := "user://evacuation_campaign.json"
const DOOR_ZONE_DEPTH := 3.0
const DOOR_ZONE_EXTRA_WIDTH := 2.0
const CAMPAIGN_RELOAD_DELAY := 2.0

var initial_agent_count := 0
var evacuated_count := 0
var evacuated_south_count := 0
var evacuated_north_count := 0
var simulation_time := 0.0
var sample_time := 0.0
var exits_since_sample := 0
var max_door_density_this_sample := 0.0
var tracking_file: FileAccess
var active_seed := 0
var campaign_force_index := 0
var campaign_repetition_index := 0
var campaign_seed_base := 1
var campaign_running := false
var alarm_countdown := 0.0
var evacuation_started := false
var alarm_label: Label
var alarm_panel: PanelContainer
var alarm_flash_time := 0.0
var run_finished := false
var hud_time_label: Label
var hud_evacuated_label: Label
var hud_exits_label: Label
var hud_flow_label: Label
var hud_density_label: Label
var hud_config_label: Label
var hud_progress: ProgressBar
var pause_label: Label
var displayed_flow := 0.0
var displayed_density := 0.0
var camera_rig: Camera3D
var main_light: DirectionalLight3D
var alarm_lights: Array[OmniLight3D] = []
var alarm_beacon_material: StandardMaterial3D


func _ready() -> void:
	if campaign_enabled:
		_begin_campaign_run()
	_create_environment()
	_create_room()
	if pillar_enabled:
		_create_pillar()
	_create_camera()
	_create_alarm_ui()
	_spawn_agents()
	_start_measurements()
	alarm_countdown = alarm_delay


func _process(delta: float) -> void:
	_update_hud()
	if not evacuation_started:
		alarm_countdown = maxf(alarm_countdown - delta, 0.0)
		alarm_label.text = "ALARME DANS %.1f s" % alarm_countdown
		if alarm_countdown <= 0.0:
			_trigger_alarm()
		return
	if run_finished:
		alarm_panel.modulate.a = 1.0
		return
	alarm_flash_time += delta
	var flash := absf(sin(alarm_flash_time * 5.0))
	alarm_panel.modulate.a = 0.78 + 0.22 * flash
	_set_alarm_lights(flash)
	simulation_time += delta
	sample_time += delta
	displayed_density = _get_door_density()
	max_door_density_this_sample = maxf(max_door_density_this_sample, displayed_density)
	if simulation_time >= duree_max:
		_write_tracking_row(sample_time)
		_finish_measurements("timeout")
		alarm_label.text = "TEMPS LIMITE - %d AGENTS RESTANTS" % (initial_agent_count - evacuated_count)
		return
	if sample_time >= 1.0:
		displayed_flow = float(exits_since_sample) / sample_time
		_write_tracking_row(sample_time)
		sample_time = 0.0
		exits_since_sample = 0
		max_door_density_this_sample = 0.0


func _create_alarm_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "AlarmUI"
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	alarm_panel = PanelContainer.new()
	alarm_panel.name = "AlarmBanner"
	alarm_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#a83025"), Color("#ff8a6e")))
	alarm_panel.anchor_left = 0.5
	alarm_panel.anchor_right = 0.5
	alarm_panel.offset_left = -240.0
	alarm_panel.offset_right = 240.0
	alarm_panel.offset_top = 18.0
	alarm_panel.custom_minimum_size = Vector2(480.0, 52.0)
	canvas.add_child(alarm_panel)
	alarm_label = Label.new()
	alarm_label.name = "AlarmText"
	alarm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alarm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	alarm_label.add_theme_color_override("font_color", Color.WHITE)
	alarm_label.add_theme_font_size_override("font_size", 22)
	alarm_panel.add_child(alarm_label)
	alarm_label.text = "ALARME DANS %.1f s" % alarm_delay

	_create_stats_panel(canvas)
	_create_help_panel(canvas)

	pause_label = Label.new()
	pause_label.text = "PAUSE"
	pause_label.visible = false
	pause_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	pause_label.add_theme_font_size_override("font_size", 56)
	pause_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	pause_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	pause_label.add_theme_constant_override("outline_size", 10)
	canvas.add_child(pause_label)


func _make_panel_style(background: Color, border: Color = Color(1.0, 1.0, 1.0, 0.08)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	return style


func _make_hud_label(parent: Control, font_size: int = 15, color: Color = Color("#dfe7e4")) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _create_stats_panel(canvas: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "StatsPanel"
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.11, 0.12, 0.82)))
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(270.0, 0.0)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	_make_hud_label(column, 18, Color.WHITE).text = "Simulation d'evacuation"
	hud_config_label = _make_hud_label(column, 12, Color("#8fa6a0"))
	hud_config_label.text = "%d agents  |  porte %.1f m  |  force %.0f%s" % [mini(agent_count, _generate_seat_positions().size()), door_width, agent_force_gain, "  |  pilier" if pillar_enabled else ""]
	column.add_child(HSeparator.new())

	hud_time_label = _make_hud_label(column, 26, Color.WHITE)
	hud_progress = ProgressBar.new()
	hud_progress.show_percentage = false
	hud_progress.custom_minimum_size = Vector2(0.0, 10.0)
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color(1.0, 1.0, 1.0, 0.1)
	bar_background.set_corner_radius_all(5)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color("#3fbf7f")
	bar_fill.set_corner_radius_all(5)
	hud_progress.add_theme_stylebox_override("background", bar_background)
	hud_progress.add_theme_stylebox_override("fill", bar_fill)
	column.add_child(hud_progress)
	hud_evacuated_label = _make_hud_label(column)
	hud_exits_label = _make_hud_label(column, 13, Color("#a9bbb6"))
	hud_flow_label = _make_hud_label(column, 13, Color("#a9bbb6"))
	hud_density_label = _make_hud_label(column, 13, Color("#a9bbb6"))


func _create_help_panel(canvas: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "HelpPanel"
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.11, 0.12, 0.7)))
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 18.0
	panel.offset_top = -18.0
	panel.offset_bottom = -18.0
	canvas.add_child(panel)
	var help := _make_hud_label(panel, 12, Color("#a9bbb6"))
	help.text = "C : camera automatique    Clic + glisser : tourner    Molette : zoom    Clic molette : deplacer\nT : vue du dessus    R : reinitialiser    Espace : pause    F : plein ecran"


func _update_hud() -> void:
	var minutes := int(simulation_time) / 60
	hud_time_label.text = "%02d:%05.2f" % [minutes, simulation_time - minutes * 60.0] if evacuation_started else "En attente"
	var total := maxi(initial_agent_count, 1)
	hud_progress.max_value = total
	hud_progress.value = evacuated_count
	hud_evacuated_label.text = "Evacues : %d / %d  (%d%%)" % [evacuated_count, initial_agent_count, roundi(100.0 * evacuated_count / total)]
	if upper_right_exit_enabled:
		hud_exits_label.text = "Sortie sud : %d    Sortie nord : %d" % [evacuated_south_count, evacuated_north_count]
	else:
		hud_exits_label.text = "Sortie sud : %d" % evacuated_south_count
	hud_flow_label.text = "Debit : %.2f agents/s" % displayed_flow
	hud_density_label.text = "Densite porte : %.2f agents/m2" % displayed_density


func _on_pause_toggled(paused: bool) -> void:
	pause_label.visible = paused


func _trigger_alarm() -> void:
	evacuation_started = true
	alarm_label.text = "ALARME INCENDIE  -  EVACUEZ"
	camera_rig.call("set_phase", "alarm")
	create_tween().tween_property(main_light, "light_energy", 0.75, 1.5)
	var reaction_rng := RandomNumberGenerator.new()
	reaction_rng.seed = active_seed + 1729
	var minimum_reaction_delay := minf(0.5, max_reaction_delay)
	for agent_node: Node in get_tree().get_nodes_in_group("agents"):
		var agent := agent_node as RigidBody3D
		if agent != null:
			agent.call("start_evacuation", reaction_rng.randf_range(minimum_reaction_delay, max_reaction_delay))
	simulation_time = 0.0
	sample_time = 0.0
	print("Alarme declenchee : les agents commencent leur reaction.")


func _generate_seat_positions() -> Array[Vector3]:
	var seats: Array[Vector3] = []
	for row in range(6):
		var seat_z := -9.0 + row * 1.15
		for column in range(8):
			var side_column := column if column < 4 else column - 4
			var side := -1.0 if column < 4 else 1.0
			var seat_x := side * (2.7 + side_column * 1.9)
			seats.append(Vector3(seat_x, 0.8, seat_z))
	for row in range(2):
		for side in [-1.0, 1.0]:
			seats.append(Vector3(side * 6.0, 0.8, 0.3 + row * 3.0))
	for desk_z in [5.5, 7.4]:
		for desk_x in [-7.0, -3.0, 3.0, 7.0]:
			seats.append(Vector3(desk_x, 0.8, desk_z))
	return seats


func _create_workstation(position: Vector3, seat_index: int) -> void:
	var desk_material := StandardMaterial3D.new()
	desk_material.albedo_color = Color("#b48b64")
	desk_material.roughness = 0.86
	var equipment_material := StandardMaterial3D.new()
	equipment_material.albedo_color = Color("#35464a")
	var chair_material := StandardMaterial3D.new()
	chair_material.albedo_color = Color("#486a69")
	# Hauteurs mesurees depuis le sol ; l'agent assis regarde vers +Z (vers son ecran).
	var floor_position := Vector3(position.x, 0.0, position.z)
	_create_visual_box("Desk_%02d" % seat_index, floor_position + Vector3(0.0, 0.73, 0.68), Vector3(1.1, 0.04, 0.62), desk_material)
	for leg_x in [-0.5, 0.5]:
		_create_visual_box("DeskLeg_%02d" % seat_index, floor_position + Vector3(leg_x, 0.355, 0.68), Vector3(0.05, 0.71, 0.56), desk_material)
	_create_visual_box("Monitor_%02d" % seat_index, floor_position + Vector3(0.0, 1.0, 0.9), Vector3(0.5, 0.3, 0.04), equipment_material)
	_create_visual_box("MonitorStand_%02d" % seat_index, floor_position + Vector3(0.0, 0.8, 0.92), Vector3(0.06, 0.12, 0.06), equipment_material)
	_create_visual_box("Keyboard_%02d" % seat_index, floor_position + Vector3(0.0, 0.76, 0.52), Vector3(0.38, 0.02, 0.13), equipment_material)
	_create_visual_box("ChairSeat_%02d" % seat_index, floor_position + Vector3(0.0, 0.44, -0.02), Vector3(0.46, 0.06, 0.44), chair_material)
	_create_visual_box("ChairBack_%02d" % seat_index, floor_position + Vector3(0.0, 0.72, -0.24), Vector3(0.44, 0.5, 0.05), chair_material)
	_create_visual_box("ChairBase_%02d" % seat_index, floor_position + Vector3(0.0, 0.21, -0.02), Vector3(0.06, 0.42, 0.06), equipment_material)


func _exit_tree() -> void:
	if tracking_file != null:
		tracking_file.close()
		tracking_file = null


func _spawn_agents() -> void:
	var rng := RandomNumberGenerator.new()
	if random_seed == 0:
		rng.randomize()
	else:
		rng.seed = random_seed
	active_seed = rng.seed

	var seat_positions := _generate_seat_positions()
	for index in range(seat_positions.size()):
		var swap_index := rng.randi_range(index, seat_positions.size() - 1)
		var temporary_seat := seat_positions[index]
		seat_positions[index] = seat_positions[swap_index]
		seat_positions[swap_index] = temporary_seat

	var spawn_positions: Array[Vector3] = []
	for index in range(mini(agent_count, seat_positions.size())):
		var spawn_position := seat_positions[index]
		var seated_in_meeting := spawn_position.z >= MEETING_START_Z and spawn_position.z <= MEETING_END_Z and absf(spawn_position.x) > MEETING_WALL_X + 0.5
		var seated_at_lower_desk := spawn_position.z >= 5.0
		if not seated_in_meeting and not seated_at_lower_desk:
			_create_workstation(spawn_position, index)

		var agent := AGENT_SCENE.instantiate() as RigidBody3D
		agent.position = spawn_position
		var exit_center_x := 0.0
		var exit_side := 0
		if upper_right_exit_enabled:
			var south_approach := Vector3(0.0, 0.8, room_depth * 0.5 - 0.5)
			var north_approach := Vector3(room_width * 0.5 - NORTH_EXIT_SIDE_MARGIN, 0.8, -room_depth * 0.5 + 0.5)
			var access_position := _get_access_position(spawn_position)
			if Vector2(access_position.x - north_approach.x, access_position.z - north_approach.z).length_squared() < Vector2(access_position.x - south_approach.x, access_position.z - south_approach.z).length_squared():
				exit_center_x = north_approach.x
				exit_side = 1
		var clear_half_width := maxf(door_width * 0.5 - AGENT_RADIUS - DOOR_CLEARANCE_MARGIN, 0.0)
		var target_x := exit_center_x + rng.randf_range(-clear_half_width * 0.5, clear_half_width * 0.5)
		var exit_position := Vector3(target_x, 0.8, room_depth * 0.5 + 1.0) if exit_side == 0 else Vector3(target_x, 0.8, -room_depth * 0.5 - 1.0)
		agent.set("exit_position", exit_position)
		agent.set("exit_side", exit_side)
		agent.set("exit_center_x", exit_center_x)
		agent.set("door_plane_z", room_depth * 0.5 + wall_thickness * 0.5 if exit_side == 0 else -room_depth * 0.5 - wall_thickness * 0.5)
		agent.set("door_wall_thickness", wall_thickness)
		agent.set("door_width", door_width)
		agent.set("force_gain", agent_force_gain)
		agent.set("random_seed", active_seed + index + 1)
		agent.set("waypoints", _get_escape_route(spawn_position, exit_side))
		agent.set("obstacle_avoidance_radius", pillar_diameter * 0.5 + 0.75 if pillar_enabled else 0.0)
		agent.set("start_seated", true)
		agent.connect("evacuated", _on_agent_evacuated)
		add_child(agent)
		spawn_positions.append(spawn_position)


func _get_access_position(spawn_position: Vector3) -> Vector3:
	if spawn_position.z >= MEETING_START_Z and spawn_position.z <= MEETING_END_Z and absf(spawn_position.x) > MEETING_WALL_X + 0.5:
		return Vector3(signf(spawn_position.x) * (MEETING_WALL_X - 0.8), 0.8, MEETING_DOOR_Z)
	return spawn_position


func _get_escape_route(spawn_position: Vector3, exit_side: int) -> PackedVector3Array:
	var route := PackedVector3Array()
	var in_meeting_room := spawn_position.z >= MEETING_START_Z and spawn_position.z <= MEETING_END_Z and absf(spawn_position.x) > MEETING_WALL_X + 0.5
	if spawn_position.z < MEETING_START_Z - 0.6 and exit_side == 0:
		route.append(Vector3(0.0, 0.8, MEETING_START_Z - 0.6))
		route.append(Vector3(0.0, 0.8, MEETING_START_Z + 0.7))
	elif in_meeting_room:
		route.append(Vector3(spawn_position.x, 0.8, MEETING_DOOR_Z))
		route.append(Vector3(signf(spawn_position.x) * (MEETING_WALL_X - 0.8), 0.8, MEETING_DOOR_Z))
		if exit_side == 1:
			route.append(Vector3(0.0, 0.8, MEETING_START_Z - 0.7))
	elif spawn_position.z > MEETING_END_Z + 0.6 and exit_side == 1:
		route.append(Vector3(0.0, 0.8, MEETING_END_Z + 0.7))
		route.append(Vector3(0.0, 0.8, MEETING_START_Z - 0.7))
	if exit_side == 1:
		route.append(Vector3(room_width * 0.5 - NORTH_EXIT_SIDE_MARGIN, 0.8, -room_depth * 0.5 + 1.0))
	return route


func _find_spawn_position(rng: RandomNumberGenerator, placed_positions: Array[Vector3]) -> Vector3:
	for _attempt in range(1000):
		var region_roll := rng.randf()
		var candidate: Vector3
		if region_roll < 0.18:
			candidate = Vector3(rng.randf_range(-8.8, -2.5), 0.8, rng.randf_range(-0.4, MEETING_END_Z - 0.5))
		elif region_roll < 0.36:
			candidate = Vector3(rng.randf_range(2.5, 8.8), 0.8, rng.randf_range(-0.4, MEETING_END_Z - 0.5))
		elif region_roll < 0.82:
			candidate = Vector3(rng.randf_range(-8.8, 8.8), 0.8, rng.randf_range(-8.8, MEETING_START_Z - 0.7))
		else:
			candidate = Vector3(rng.randf_range(-8.8, 8.8), 0.8, rng.randf_range(MEETING_END_Z + 0.7, 8.8))

		var in_door_approach := absf(candidate.x) < door_width * 0.5 + 1.0 and candidate.z > room_depth * 0.5 - 3.0
		if in_door_approach:
			continue

		var overlaps_agent := false
		for placed_position in placed_positions:
			if candidate.distance_squared_to(placed_position) < 0.36:
				overlaps_agent = true
				break
		if not overlaps_agent:
			return candidate

	return Vector3(0.0, -1.0, 0.0)


func _start_measurements() -> void:
	initial_agent_count = get_tree().get_nodes_in_group("agents").size()
	var tracking_directory := ProjectSettings.globalize_path(TRACKING_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(tracking_directory)
	if directory_error != OK:
		push_error("Impossible de creer le dossier de suivi.")
		return
	var tracking_path := "%s/run_seed_%d_force_%.1f_door_%.1f_pillar_%s_exits_%d_alarm_%.1f_reaction_%.1f.csv" % [TRACKING_DIR, active_seed, agent_force_gain, door_width, str(pillar_enabled).to_lower(), 2 if upper_right_exit_enabled else 1, alarm_delay, max_reaction_delay]
	tracking_file = FileAccess.open(tracking_path, FileAccess.WRITE)
	if tracking_file == null:
		push_error("Impossible de creer le fichier de suivi CSV.")
		return
	tracking_file.store_line("temps_s,agents_restants,agents_sortis,debit_agents_s,densite_max_agents_m2,sorties_basses,sorties_hautes")
	tracking_file.flush()


func _get_door_density() -> float:
	var south_agents := 0
	var north_agents := 0
	var zone_half_width := door_width * 0.5 + DOOR_ZONE_EXTRA_WIDTH * 0.5
	var south_zone_start_z := room_depth * 0.5 - DOOR_ZONE_DEPTH
	var north_zone_center_x := room_width * 0.5 - NORTH_EXIT_SIDE_MARGIN
	var north_zone_end_z := -room_depth * 0.5 + DOOR_ZONE_DEPTH
	for agent in get_tree().get_nodes_in_group("agents"):
		if absf(agent.global_position.x) <= zone_half_width and agent.global_position.z >= south_zone_start_z:
			south_agents += 1
		if upper_right_exit_enabled and absf(agent.global_position.x - north_zone_center_x) <= zone_half_width and agent.global_position.z <= north_zone_end_z:
			north_agents += 1
	var zone_area := (door_width + DOOR_ZONE_EXTRA_WIDTH) * DOOR_ZONE_DEPTH
	var south_density := float(south_agents) / zone_area
	var north_density := float(north_agents) / zone_area if upper_right_exit_enabled else 0.0
	return maxf(south_density, north_density)


func _write_tracking_row(interval: float) -> void:
	if tracking_file == null:
		return
	var remaining := maxi(initial_agent_count - evacuated_count, 0)
	var flow := float(exits_since_sample) / maxf(interval, 0.001)
	tracking_file.store_line("%.3f,%d,%d,%.3f,%.3f,%d,%d" % [simulation_time, remaining, evacuated_count, flow, max_door_density_this_sample, evacuated_south_count, evacuated_north_count])
	tracking_file.flush()


func _on_agent_evacuated(exit_side: int) -> void:
	evacuated_count += 1
	exits_since_sample += 1
	if exit_side == 0:
		evacuated_south_count += 1
	else:
		evacuated_north_count += 1
	if evacuated_count >= initial_agent_count:
		if sample_time > 0.0:
			_write_tracking_row(sample_time)
		_finish_measurements("complete")


func _finish_measurements(status: String) -> void:
	if run_finished:
		return
	run_finished = true
	if status == "complete":
		alarm_label.text = "EVACUATION TERMINEE EN %.1f s" % simulation_time
		alarm_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("#24734f"), Color("#6fe0a6")))
	camera_rig.call("set_phase", "finished")
	_set_alarm_lights(0.0)
	if tracking_file != null:
		tracking_file.close()
		tracking_file = null

	if not _ensure_summary_schema():
		push_error("Impossible de mettre a jour le schema du fichier recapitulatif.")
		return
	var summary_exists := FileAccess.file_exists(SUMMARY_PATH)
	var summary_file := FileAccess.open(SUMMARY_PATH, FileAccess.READ_WRITE if summary_exists else FileAccess.WRITE)
	if summary_file == null:
		push_error("Impossible d'ecrire le fichier recapitulatif CSV.")
		return
	if summary_exists:
		summary_file.seek_end()
	else:
		summary_file.store_line("agents_initiaux,largeur_porte_m,force,pilier,temps_total_s,seed,sorties_configurees,sorties_basses,sorties_hautes,alarme_delai_s,reaction_max_s,statut,agents_restants_fin")
	summary_file.store_line("%d,%.3f,%.3f,%s,%.3f,%d,%d,%d,%d,%.3f,%.3f,%s,%d" % [initial_agent_count, door_width, agent_force_gain, str(pillar_enabled).to_lower(), simulation_time, active_seed, 2 if upper_right_exit_enabled else 1, evacuated_south_count, evacuated_north_count, alarm_delay, max_reaction_delay, status, initial_agent_count - evacuated_count])
	summary_file.close()
	print("Simulation %s : %d agents restants a %.1f s." % [status, initial_agent_count - evacuated_count, simulation_time])
	if campaign_running and status == "timeout":
		_advance_campaign()
	elif campaign_running:
		_advance_campaign()


func _ensure_summary_schema() -> bool:
	if not FileAccess.file_exists(SUMMARY_PATH):
		return true
	var input_file := FileAccess.open(SUMMARY_PATH, FileAccess.READ)
	if input_file == null:
		return false
	var lines := input_file.get_as_text().split("\n", false)
	input_file.close()
	if lines.is_empty():
		return true
	var header := lines[0].strip_edges().trim_prefix("\uFEFF")
	if header.ends_with(",sorties_configurees,sorties_basses,sorties_hautes,alarme_delai_s,reaction_max_s,statut,agents_restants_fin"):
		return true
	if header.ends_with(",sorties_configurees,sorties_basses,sorties_hautes,alarme_delai_s,reaction_max_s"):
		lines[0] = header + ",statut,agents_restants_fin"
		for line_index in range(1, lines.size()):
			var row := lines[line_index].strip_edges()
			if row.is_empty():
				continue
			var values := row.split(",")
			if values.size() == 11:
				lines[line_index] = row + ",complete,0"
		return _write_summary_lines(lines)
	var has_exit_columns := header.ends_with(",sorties_configurees,sorties_basses,sorties_hautes")
	if not has_exit_columns and header != "agents_initiaux,largeur_porte_m,force,pilier,temps_total_s,seed":
		return false
	if has_exit_columns:
		lines[0] = header + ",alarme_delai_s,reaction_max_s"
	else:
		lines[0] = header + ",sorties_configurees,sorties_basses,sorties_hautes,alarme_delai_s,reaction_max_s"
	for line_index in range(1, lines.size()):
		var row := lines[line_index].strip_edges()
		if row.is_empty():
			continue
		var values := row.split(",")
		if values.size() == 6:
			lines[line_index] = row + ",1," + values[0] + ",0,0,0,complete,0"
		elif values.size() == 9:
			lines[line_index] = row + ",0,0,complete,0"
		elif values.size() == 11:
			lines[line_index] = row + ",complete,0"
	return _write_summary_lines(lines)


func _write_summary_lines(lines: PackedStringArray) -> bool:
	var output_file := FileAccess.open(SUMMARY_PATH, FileAccess.WRITE)
	if output_file == null:
		return false
	output_file.store_string("\n".join(lines) + "\n")
	output_file.close()
	return true


func _begin_campaign_run() -> void:
	if campaign_forces.is_empty():
		push_error("La campagne ne contient aucune force a tester.")
		campaign_enabled = false
		return
	var campaign_data: Dictionary = {}
	if FileAccess.file_exists(CAMPAIGN_STATE_PATH):
		var state_file := FileAccess.open(CAMPAIGN_STATE_PATH, FileAccess.READ)
		if state_file != null:
			var parsed: Variant = JSON.parse_string(state_file.get_as_text())
			state_file.close()
			if parsed is Dictionary:
				campaign_data = parsed
	if campaign_data.is_empty():
		campaign_data = {"force_index": 0, "repetition_index": 0, "seed_base": int(Time.get_unix_time_from_system())}
		_save_campaign_state(campaign_data)
	campaign_force_index = clampi(int(campaign_data.get("force_index", 0)), 0, campaign_forces.size() - 1)
	campaign_repetition_index = clampi(int(campaign_data.get("repetition_index", 0)), 0, campaign_repetitions - 1)
	campaign_seed_base = int(campaign_data.get("seed_base", 1))
	agent_force_gain = campaign_forces[campaign_force_index]
	random_seed = campaign_seed_base + campaign_force_index * campaign_repetitions + campaign_repetition_index
	campaign_running = true
	print("Campagne: force %.1f, repetition %d/%d" % [agent_force_gain, campaign_repetition_index + 1, campaign_repetitions])


func _save_campaign_state(campaign_data: Dictionary) -> void:
	var state_file := FileAccess.open(CAMPAIGN_STATE_PATH, FileAccess.WRITE)
	if state_file == null:
		push_error("Impossible de sauvegarder l'avancement de la campagne.")
		return
	state_file.store_string(JSON.stringify(campaign_data))
	state_file.close()


func _advance_campaign() -> void:
	campaign_repetition_index += 1
	if campaign_repetition_index >= campaign_repetitions:
		campaign_repetition_index = 0
		campaign_force_index += 1
	if campaign_force_index >= campaign_forces.size():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CAMPAIGN_STATE_PATH))
		campaign_running = false
		print("Campagne terminee: toutes les forces et repetitions ont ete executees.")
		return
	var campaign_data := {
		"force_index": campaign_force_index,
		"repetition_index": campaign_repetition_index,
		"seed_base": campaign_seed_base
	}
	_save_campaign_state(campaign_data)
	await get_tree().create_timer(CAMPAIGN_RELOAD_DELAY).timeout
	get_tree().reload_current_scene()


func _create_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#1d3236")
	sky_material.sky_horizon_color = Color("#56706c")
	sky_material.ground_bottom_color = Color("#0f1a1c")
	sky_material.ground_horizon_color = Color("#56706c")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d5dedb")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.ssao_enabled = true
	environment.ssao_radius = 0.8
	environment.ssao_intensity = 1.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.glow_hdr_threshold = 1.2
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	world.environment = environment
	add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_color = Color("#fff4e5")
	light.light_energy = 1.1
	light.shadow_enabled = true
	light.shadow_blur = 1.5
	light.directional_shadow_max_distance = 80.0
	add_child(light)
	main_light = light

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	fill_light.light_color = Color("#bcd6ff")
	fill_light.light_energy = 0.3
	add_child(fill_light)


func _create_room() -> void:
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#7f8d88")
	floor_material.albedo_texture = _make_noise_texture(0.08, 0.82)
	floor_material.uv1_scale = Vector3(room_width / 4.0, room_depth / 4.0, 1.0)
	floor_material.roughness = 0.97
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color("#d9ddd5")
	wall_material.roughness = 0.85
	var glass_material := StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.72, 0.86, 0.9, 0.22)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.roughness = 0.05
	glass_material.metallic = 0.3
	glass_material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX

	_create_box(
		"Floor",
		Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0),
		Vector3(room_width, FLOOR_THICKNESS, room_depth),
		floor_material
	)

	var wall_y := wall_height * 0.5
	var opening_width := minf(door_width, room_width - wall_thickness * 2.0)
	var segment_width := (room_width - opening_width) * 0.5
	var side_length := room_depth + wall_thickness * 2.0

	var north_wall_z := -(room_depth * 0.5 + wall_thickness * 0.5)
	if upper_right_exit_enabled:
		var north_exit_center_x := room_width * 0.5 - NORTH_EXIT_SIDE_MARGIN
		var north_wall_start_x := -room_width * 0.5 - wall_thickness
		var north_wall_end_x := room_width * 0.5 + wall_thickness
		var north_left_width := north_exit_center_x - door_width * 0.5 - north_wall_start_x
		var north_right_width := north_wall_end_x - north_exit_center_x - door_width * 0.5
		_create_box("NorthWallLeft", Vector3(north_wall_start_x + north_left_width * 0.5, wall_y, north_wall_z), Vector3(north_left_width, wall_height, wall_thickness), wall_material, 0.05)
		_create_box("NorthWallRight", Vector3(north_exit_center_x + door_width * 0.5 + north_right_width * 0.5, wall_y, north_wall_z), Vector3(north_right_width, wall_height, wall_thickness), wall_material, 0.05)
		_create_exit_sign("UpperRightExit", Vector3(north_exit_center_x, 0.0, -room_depth * 0.5 + 0.35), "SORTIE NORD")
	else:
		_create_box("NorthWall", Vector3(0.0, wall_y, north_wall_z), Vector3(room_width + wall_thickness * 2.0, wall_height, wall_thickness), wall_material, 0.05)
	_create_box(
		"WestWall",
		Vector3(-(room_width * 0.5 + wall_thickness * 0.5), wall_y, 0.0),
		Vector3(wall_thickness, wall_height, side_length),
		wall_material,
		0.05
	)
	_create_box(
		"EastWall",
		Vector3(room_width * 0.5 + wall_thickness * 0.5, wall_y, 0.0),
		Vector3(wall_thickness, wall_height, side_length),
		wall_material,
		0.05
	)
	_create_box(
		"SouthWallLeft",
		Vector3(-(opening_width * 0.5 + segment_width * 0.5), wall_y, room_depth * 0.5 + wall_thickness * 0.5),
		Vector3(segment_width, wall_height, wall_thickness),
		wall_material,
		0.05
	)
	_create_box(
		"SouthWallRight",
		Vector3(opening_width * 0.5 + segment_width * 0.5, wall_y, room_depth * 0.5 + wall_thickness * 0.5),
		Vector3(segment_width, wall_height, wall_thickness),
		wall_material,
		0.05
	)

	_create_exit_sign("SouthExit", Vector3(0.0, 0.0, room_depth * 0.5 - 0.35), "SORTIE SUD" if upper_right_exit_enabled else "SORTIE")

	var corridor_material := StandardMaterial3D.new()
	corridor_material.albedo_color = Color("#b9b4a8")
	corridor_material.albedo_texture = _make_noise_texture(0.25, 0.9)
	corridor_material.uv1_scale = Vector3(1.0, (room_depth - 2.0) / (MEETING_WALL_X * 2.0), 1.0)
	corridor_material.roughness = 0.45
	_create_visual_box(
		"CentralCorridorFloor",
		Vector3(0.0, 0.012, 1.0),
		Vector3(MEETING_WALL_X * 2.0, 0.025, room_depth - 2.0),
		corridor_material
	)

	var left_room_width := room_width * 0.5 - wall_thickness - MEETING_WALL_X
	var room_segment_center_x := MEETING_WALL_X + left_room_width * 0.5
	_create_box(
		"MeetingNorthWest",
		Vector3(-room_segment_center_x, wall_y, MEETING_START_Z - wall_thickness * 0.5),
		Vector3(left_room_width, wall_height, wall_thickness),
		glass_material,
		0.05
	)
	_create_box(
		"MeetingNorthEast",
		Vector3(room_segment_center_x, wall_y, MEETING_START_Z - wall_thickness * 0.5),
		Vector3(left_room_width, wall_height, wall_thickness),
		glass_material,
		0.05
	)
	_create_box(
		"MeetingSouthWest",
		Vector3(-room_segment_center_x, wall_y, MEETING_END_Z + wall_thickness * 0.5),
		Vector3(left_room_width, wall_height, wall_thickness),
		glass_material,
		0.05
	)
	_create_box(
		"MeetingSouthEast",
		Vector3(room_segment_center_x, wall_y, MEETING_END_Z + wall_thickness * 0.5),
		Vector3(left_room_width, wall_height, wall_thickness),
		glass_material,
		0.05
	)
	_create_meeting_side_walls(-MEETING_WALL_X, wall_y, glass_material)
	_create_meeting_side_walls(MEETING_WALL_X, wall_y, glass_material)
	_create_office_furniture()
	_create_lower_workstations()
	_create_alarm_beacons()
	_create_decorations()


func _create_exit_sign(sign_name: String, floor_position: Vector3, text: String) -> void:
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color("#1f9e5a")
	marker_material.emission_enabled = true
	marker_material.emission = Color("#2fd47c")
	marker_material.emission_energy_multiplier = 1.6
	_create_visual_box(sign_name + "Marker", floor_position + Vector3(0.0, 0.025, 0.0), Vector3(door_width, 0.04, 0.45), marker_material)

	var label := Label3D.new()
	label.name = sign_name + "Label"
	label.text = text
	label.position = floor_position + Vector3(0.0, wall_height + 0.6, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 64
	label.pixel_size = 0.01
	label.outline_size = 14
	label.modulate = Color("#5cf09c")
	label.outline_modulate = Color("#0b2a19")
	add_child(label)

	var exit_light := OmniLight3D.new()
	exit_light.name = sign_name + "Light"
	exit_light.position = floor_position + Vector3(0.0, wall_height - 0.4, 0.0)
	exit_light.light_color = Color("#3cf08a")
	exit_light.light_energy = 1.2
	exit_light.omni_range = 3.5
	add_child(exit_light)


func _create_alarm_beacons() -> void:
	alarm_beacon_material = StandardMaterial3D.new()
	alarm_beacon_material.albedo_color = Color("#5a1410")
	alarm_beacon_material.emission_enabled = true
	alarm_beacon_material.emission = Color("#ff2a1a")
	alarm_beacon_material.emission_energy_multiplier = 0.0
	var half_width := room_width * 0.5 - 0.1
	var half_depth := room_depth * 0.5 - 0.1
	var beacon_y := wall_height - 0.25
	var positions: Array[Vector3] = [
		Vector3(-half_width, beacon_y, -half_depth * 0.5),
		Vector3(half_width, beacon_y, -half_depth * 0.5),
		Vector3(-half_width, beacon_y, half_depth * 0.5),
		Vector3(half_width, beacon_y, half_depth * 0.5),
		Vector3(0.0, beacon_y, MEETING_START_Z - 0.3),
	]
	for index in range(positions.size()):
		_create_visual_box("AlarmBeacon_%d" % index, positions[index], Vector3(0.22, 0.14, 0.22), alarm_beacon_material)
		var beacon_light := OmniLight3D.new()
		beacon_light.name = "AlarmLight_%d" % index
		beacon_light.position = positions[index] + Vector3(0.0, -0.3, 0.0)
		beacon_light.light_color = Color("#ff3b24")
		beacon_light.light_energy = 0.0
		beacon_light.omni_range = 7.0
		add_child(beacon_light)
		alarm_lights.append(beacon_light)


func _set_alarm_lights(intensity: float) -> void:
	for beacon_light in alarm_lights:
		beacon_light.light_energy = 2.2 * intensity
	if alarm_beacon_material != null:
		alarm_beacon_material.emission_energy_multiplier = 4.0 * intensity


func _create_decorations() -> void:
	var pot_material := StandardMaterial3D.new()
	pot_material.albedo_color = Color("#e3ddd0")
	pot_material.roughness = 0.6
	var leaf_material := StandardMaterial3D.new()
	leaf_material.albedo_color = Color("#3f7a44")
	leaf_material.roughness = 0.85
	var half_width := room_width * 0.5 - 0.5
	var half_depth := room_depth * 0.5 - 0.5
	var plant_positions: Array[Vector3] = [
		Vector3(-half_width, 0.0, -half_depth),
		Vector3(-half_width, 0.0, half_depth),
		Vector3(half_width, 0.0, half_depth),
	]
	if not upper_right_exit_enabled:
		plant_positions.append(Vector3(half_width, 0.0, -half_depth))
	for index in range(plant_positions.size()):
		var base := plant_positions[index]
		var pot := CylinderMesh.new()
		pot.top_radius = 0.24
		pot.bottom_radius = 0.18
		pot.height = 0.45
		_add_mesh("PlantPot_%d" % index, pot, base + Vector3(0.0, 0.225, 0.0), pot_material)
		for leaf_index in range(3):
			var leaves := SphereMesh.new()
			leaves.radius = 0.32 - leaf_index * 0.06
			leaves.height = leaves.radius * 2.2
			_add_mesh("PlantLeaves_%d_%d" % [index, leaf_index], leaves, base + Vector3(0.0, 0.75 + leaf_index * 0.32, 0.0), leaf_material)

	var baseboard_material := StandardMaterial3D.new()
	baseboard_material.albedo_color = Color("#4b5552")
	var inner_width := room_width
	var inner_depth := room_depth
	_create_visual_box("BaseboardWest", Vector3(-inner_width * 0.5 + 0.02, 0.06, 0.0), Vector3(0.04, 0.12, inner_depth), baseboard_material)
	_create_visual_box("BaseboardEast", Vector3(inner_width * 0.5 - 0.02, 0.06, 0.0), Vector3(0.04, 0.12, inner_depth), baseboard_material)

	var board_material := StandardMaterial3D.new()
	board_material.albedo_color = Color("#f4f6f4")
	board_material.roughness = 0.25
	for side in [-1.0, 1.0]:
		_create_visual_box("Whiteboard", Vector3(side * (room_width * 0.5 - 0.03), 1.5, 1.7), Vector3(0.04, 1.0, 2.2), board_material)


func _add_mesh(mesh_name: String, mesh: Mesh, position: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	visual.name = mesh_name
	visual.mesh = mesh
	visual.position = position
	visual.material_override = material
	add_child(visual)


func _create_meeting_side_walls(x_position: float, wall_y: float, material: Material) -> void:
	var door_start_z := MEETING_DOOR_Z - MEETING_DOOR_WIDTH * 0.5
	var door_end_z := MEETING_DOOR_Z + MEETING_DOOR_WIDTH * 0.5
	var first_segment_length := door_start_z - MEETING_START_Z
	var second_segment_length := MEETING_END_Z - door_end_z
	_create_box(
		"MeetingSideWall",
		Vector3(x_position, wall_y, MEETING_START_Z + first_segment_length * 0.5),
		Vector3(wall_thickness, wall_height, first_segment_length),
		material,
		0.05
	)
	_create_box(
		"MeetingSideWall",
		Vector3(x_position, wall_y, door_end_z + second_segment_length * 0.5),
		Vector3(wall_thickness, wall_height, second_segment_length),
		material,
		0.05
	)


func _create_pillar() -> void:
	var pillar := StaticBody3D.new()
	pillar.name = "ExperimentalPillar"
	pillar.position = Vector3(pillar_offset_x, wall_height * 0.5, room_depth * 0.5 - pillar_distance_from_door)
	pillar.add_to_group("obstacles")
	var contact_material := PhysicsMaterial.new()
	contact_material.friction = 0.05
	contact_material.bounce = 0.0
	pillar.physics_material_override = contact_material
	add_child(pillar)

	var radius := pillar_diameter * 0.5
	var collision_shape := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = radius
	cylinder_shape.height = wall_height
	collision_shape.shape = cylinder_shape
	pillar.add_child(collision_shape)

	var pillar_material := StandardMaterial3D.new()
	pillar_material.albedo_color = Color("#b65d45")
	pillar_material.roughness = 0.72
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = radius
	cylinder_mesh.bottom_radius = radius
	cylinder_mesh.height = wall_height
	var visual := MeshInstance3D.new()
	visual.mesh = cylinder_mesh
	visual.material_override = pillar_material
	pillar.add_child(visual)


func _create_office_furniture() -> void:
	var table_material := StandardMaterial3D.new()
	table_material.albedo_color = Color("#d1d1c4")
	var chair_material := StandardMaterial3D.new()
	chair_material.albedo_color = Color("#486a69")

	for meeting_x in [-5.8, 5.8]:
		_create_visual_box("MeetingTable", Vector3(meeting_x, 0.72, 1.7), Vector3(2.6, 0.12, 1.2), table_material)
		for chair_z in [0.45, 2.95]:
			for chair_x in [meeting_x - 0.75, meeting_x, meeting_x + 0.75]:
				_create_visual_box("MeetingChair", Vector3(chair_x, 0.28, chair_z), Vector3(0.5, 0.12, 0.5), chair_material)


func _create_lower_workstations() -> void:
	var seat_index := 60
	for desk_z in [5.5, 7.4]:
		for desk_x in [-7.0, -5.0, -3.0, 3.0, 5.0, 7.0]:
			_create_workstation(Vector3(desk_x, 0.8, desk_z), seat_index)
			seat_index += 1


func _create_visual_box(object_name: String, position: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.name = object_name
	visual.position = position
	visual.mesh = mesh
	visual.material_override = material
	add_child(visual)


func _create_box(box_name: String, position: Vector3, size: Vector3, material: Material, friction: float = 0.3) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = position
	var contact_material := PhysicsMaterial.new()
	contact_material.friction = friction
	contact_material.bounce = 0.0
	body.physics_material_override = contact_material
	add_child(body)

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	var base_material := material as BaseMaterial3D
	if base_material != null and base_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)


func _make_noise_texture(frequency: float, darkest: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = frequency
	noise.seed = 7
	var ramp := Gradient.new()
	ramp.set_color(0, Color(darkest, darkest, darkest))
	ramp.set_color(1, Color.WHITE)
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	return texture


func _create_camera() -> void:
	var scene_camera := get_node_or_null("TopDownCamera")
	if scene_camera != null:
		scene_camera.queue_free()
	var camera := Camera3D.new()
	camera.set_script(CAMERA_RIG_SCRIPT)
	camera.name = "OrbitCamera"
	add_child(camera)
	camera.call("setup", room_width, room_depth, upper_right_exit_enabled, room_width * 0.5 - NORTH_EXIT_SIDE_MARGIN)
	camera.connect("pause_toggled", _on_pause_toggled)
	camera.current = true
	camera_rig = camera
