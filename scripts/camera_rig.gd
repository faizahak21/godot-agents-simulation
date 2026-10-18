extends Camera3D

# Camera de presentation : par defaut elle enchaine seule des plans adaptes a la
# phase de la simulation (attente, alarme, evacuation, fin).
# Toute action souris (ou T/R) passe en mode manuel ; C relance le mode automatique.
# Manuel : clic + glisser = rotation, clic molette = deplacement, molette = zoom,
# T = vue du dessus orthographique, R = reinitialiser. Espace = pause, F = plein ecran.

signal pause_toggled(paused: bool)

const MIN_PITCH: float = 12.0
const MAX_PITCH: float = 89.0
const MANUAL_SMOOTHING: float = 10.0
const AUTO_SMOOTHING: float = 1.3
const DEFAULT_SHOT_DURATION: float = 7.0

var auto_mode := true
var phase := "waiting"
var room_size := Vector2(20.0, 20.0)
var north_exit_enabled := true
var north_exit_x := 8.5

var focus := Vector3.ZERO
var yaw := 0.0
var pitch := 55.0
var distance := 30.0
var top_down := false

var _target_focus := Vector3.ZERO
var _target_yaw := 0.0
var _target_pitch := 55.0
var _target_distance := 30.0
var _rotating := false
var _panning := false
var _shots: Array[Dictionary] = []
var _shot_index := 0
var _shot_time := 0.0


func setup(width: float, depth: float, has_north_exit: bool, north_x: float) -> void:
	room_size = Vector2(width, depth)
	north_exit_enabled = has_north_exit
	north_exit_x = north_x
	set_phase("waiting")
	_snap_to_targets()


func set_phase(new_phase: String) -> void:
	phase = new_phase
	_shots = _build_shots(new_phase)
	_shot_index = 0
	_start_shot()


func reset_view() -> void:
	top_down = false
	_target_focus = Vector3(0.0, 0.0, 1.0)
	_target_yaw = _nearest_yaw(0.0)
	_target_pitch = 58.0
	_target_distance = _overview_distance()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fov = 50.0
	near = 0.1
	far = 300.0


func _overview_distance() -> float:
	return maxf(room_size.x, room_size.y) * 1.3


func _build_shots(for_phase: String) -> Array[Dictionary]:
	var half_depth := room_size.y * 0.5
	var shots: Array[Dictionary] = []
	match for_phase:
		"waiting":
			shots.append({"focus": Vector3(0.0, 0.0, 0.5), "yaw": 25.0, "pitch": 46.0, "distance": _overview_distance(), "drift": -4.0, "duration": 6.0})
			shots.append({"focus": Vector3(-5.5, 0.8, -6.0), "yaw": 15.0, "pitch": 34.0, "distance": 8.0, "drift": 2.5})
			shots.append({"focus": Vector3(5.8, 0.8, 1.7), "yaw": -25.0, "pitch": 48.0, "distance": 8.0, "drift": -2.5})
		"alarm":
			shots.append({"focus": Vector3(0.0, 0.8, -3.0), "yaw": 0.0, "pitch": 44.0, "distance": 14.0, "drift": 3.0, "duration": 6.0, "next": "evacuating"})
		"evacuating":
			shots.append({"focus": "crowd", "yaw": 10.0, "pitch": 50.0, "distance": 15.0, "drift": 3.0})
			shots.append({"focus": Vector3(0.0, 0.5, half_depth - 1.8), "yaw": 165.0, "pitch": 38.0, "distance": 9.0, "drift": 2.0})
			if north_exit_enabled:
				shots.append({"focus": Vector3(north_exit_x, 0.5, -half_depth + 1.8), "yaw": -15.0, "pitch": 40.0, "distance": 9.0, "drift": -2.0})
			shots.append({"focus": Vector3(0.0, 0.0, 0.0), "yaw": 0.0, "pitch": 84.0, "distance": _overview_distance() * 1.05, "drift": 0.0})
		_:
			shots.append({"focus": Vector3(0.0, 0.0, 0.5), "yaw": 0.0, "pitch": 55.0, "distance": _overview_distance(), "drift": 5.0, "duration": 1000.0})
	return shots


func _start_shot() -> void:
	if _shots.is_empty():
		return
	var shot := _shots[_shot_index]
	_shot_time = 0.0
	top_down = false
	_target_focus = _get_shot_focus(shot)
	_target_yaw = _nearest_yaw(shot["yaw"])
	_target_pitch = shot["pitch"]
	_target_distance = shot["distance"]


func _get_shot_focus(shot: Dictionary) -> Vector3:
	if shot["focus"] is Vector3:
		return shot["focus"]
	var agents := get_tree().get_nodes_in_group("agents")
	if agents.is_empty():
		return Vector3.ZERO
	var center := Vector3.ZERO
	for agent: Node3D in agents:
		center += agent.global_position
	center /= agents.size()
	center.y = 0.5
	return center


func _nearest_yaw(target: float) -> float:
	return yaw + wrapf(target - yaw, -180.0, 180.0)


func _update_auto(delta: float) -> void:
	if _shots.is_empty():
		return
	var shot := _shots[_shot_index]
	_shot_time += delta
	_target_yaw += float(shot["drift"]) * delta
	if not (shot["focus"] is Vector3):
		_target_focus = _get_shot_focus(shot)
		# Filmer la foule depuis l'interieur de la piece pour que les murs ne la cachent pas.
		var to_center := Vector2(-_target_focus.x, -_target_focus.z)
		if to_center.length() > 3.0:
			var inward_yaw := rad_to_deg(atan2(to_center.x, to_center.y))
			_target_yaw = lerpf(_target_yaw, _nearest_yaw(inward_yaw), minf(delta * 0.8, 1.0))
	if _shot_time < float(shot.get("duration", DEFAULT_SHOT_DURATION)):
		return
	if shot.has("next"):
		set_phase(shot["next"])
	else:
		_shot_index = (_shot_index + 1) % _shots.size()
		_start_shot()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_rotating = button.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_take_manual_control()
					_target_distance = maxf(_target_distance * 0.9, 4.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_take_manual_control()
					_target_distance = minf(_target_distance * 1.1, 120.0)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _rotating and not top_down:
			_take_manual_control()
			_target_yaw -= motion.relative.x * 0.3
			_target_pitch = clampf(_target_pitch + motion.relative.y * 0.3, MIN_PITCH, MAX_PITCH)
		elif _panning or (_rotating and top_down):
			_take_manual_control()
			var pan_scale := _target_distance * 0.0015
			var right := global_transform.basis.x
			var forward := Vector3(-right.z, 0.0, right.x)
			_target_focus -= right * motion.relative.x * pan_scale
			_target_focus -= forward * motion.relative.y * pan_scale
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_T:
				_take_manual_control()
				top_down = not top_down
			KEY_R:
				_take_manual_control()
				reset_view()
			KEY_C:
				auto_mode = true
				_start_shot()
			KEY_F:
				var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_SPACE:
				get_tree().paused = not get_tree().paused
				pause_toggled.emit(get_tree().paused)


func _take_manual_control() -> void:
	if auto_mode:
		auto_mode = false
		_target_pitch = clampf(_target_pitch, MIN_PITCH, MAX_PITCH)


func _process(delta: float) -> void:
	if auto_mode and not get_tree().paused:
		_update_auto(delta)
	var weight := 1.0 - exp(-(AUTO_SMOOTHING if auto_mode else MANUAL_SMOOTHING) * delta)
	focus = focus.lerp(_target_focus, weight)
	yaw = lerpf(yaw, _target_yaw, weight)
	pitch = lerpf(pitch, MAX_PITCH if top_down else _target_pitch, weight)
	distance = lerpf(distance, _target_distance, weight)
	_apply_transform()


func _snap_to_targets() -> void:
	focus = _target_focus
	yaw = _target_yaw
	pitch = _target_pitch
	distance = _target_distance
	_apply_transform()


func _apply_transform() -> void:
	projection = PROJECTION_ORTHOGONAL if top_down else PROJECTION_PERSPECTIVE
	size = distance * 0.9
	var pitch_rad := deg_to_rad(pitch)
	var yaw_rad := deg_to_rad(yaw)
	var offset := Vector3(sin(yaw_rad) * cos(pitch_rad), sin(pitch_rad), cos(yaw_rad) * cos(pitch_rad)) * distance
	position = focus + offset
	look_at(focus, Vector3.UP if pitch < 89.5 else Vector3.FORWARD)
