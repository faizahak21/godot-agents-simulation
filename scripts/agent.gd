extends RigidBody3D

signal evacuated(exit_side: int)

enum ExitSide { SOUTH, NORTH }

const DOOR_JAMB_CLEARANCE: float = 0.05
const CHARACTER_SCENE_PATH := "res://assets/characters/retro/characterMedium.fbx"
const CHARACTER_ANIMATION_PATHS := {
	"idle": "res://assets/characters/retro/idle.fbx",
	"run": "res://assets/characters/retro/run.fbx",
}
const CHARACTER_SKIN_PATTERN := "res://assets/characters/retro/skins/office_%d.png"
const CHARACTER_HEIGHT: float = 1.7
const BODY_HALF_HEIGHT: float = 0.8
const STAND_UP_DURATION: float = 0.55
# Pose assise construite a la main : le pack ne fournit pas d'animation "assis".
const SIT_DROP: float = 0.42
const SIT_HIP_ANGLE: float = 85.0
const SIT_KNEE_ANGLE: float = -85.0

static var character_scene: PackedScene
static var character_animations: AnimationLibrary
static var character_materials: Dictionary = {}

@export_category("Deplacement")
@export var exit_position: Vector3 = Vector3(0.0, 0.8, 11.0)
@export var exit_side: ExitSide = ExitSide.SOUTH
@export var exit_center_x: float = 0.0
@export var door_plane_z: float = 10.15
@export var door_wall_thickness: float = 0.3
@export var waypoints: PackedVector3Array = PackedVector3Array()
@export var start_seated: bool = true
@export var random_seed: int = 0
@export_range(0.5, 8.0, 0.1) var desired_speed: float = 2.5
@export_range(1.0, 100.0, 1.0) var force_gain: float = 20.0
@export_range(0.8, 3.0, 0.1) var door_width: float = 1.5
@export_range(0.1, 0.4, 0.05) var body_radius: float = 0.25
@export_range(0.5, 2.0, 0.1) var neighbor_radius: float = 1.0
@export_range(0.0, 3.0, 0.1) var neighbor_repulsion: float = 1.2
@export_range(0.0, 3.0, 0.1) var obstacle_avoidance_radius: float = 0.0

var steering_rng := RandomNumberGenerator.new()
var agitation_timer := 0.0
var lateral_agitation := 0.0
var current_waypoint_index := 0
var person_visual: Node3D
var left_arm: MeshInstance3D
var right_arm: MeshInstance3D
var left_leg: MeshInstance3D
var right_leg: MeshInstance3D
var walking_phase := 0.0
var clothing_material: StandardMaterial3D
var base_clothing_color := Color.WHITE
var waiting_for_alarm := true
var reaction_remaining := 0.0
var seated := true
var torso_mesh: MeshInstance3D
var character_model: Node3D
var character_skeleton: Skeleton3D
var sit_amount := 0.0
var animation_player: AnimationPlayer
var speed_ring: MeshInstance3D
var speed_ring_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("agents")
	can_sleep = false
	if random_seed == 0:
		steering_rng.randomize()
	else:
		steering_rng.seed = random_seed
	var contact_material := PhysicsMaterial.new()
	contact_material.friction = 0.05
	contact_material.bounce = 0.0
	physics_material_override = contact_material
	seated = start_seated
	freeze = seated
	if not _create_character_model():
		_create_humanoid_visual()
	_create_speed_ring()




func start_evacuation(reaction_delay: float) -> void:
	if not waiting_for_alarm:
		return
	waiting_for_alarm = false
	reaction_remaining = maxf(reaction_delay, 0.0)


func _process(delta: float) -> void:
	_update_character_animation(delta)
	if waiting_for_alarm:
		return
	if reaction_remaining > 0.0:
		reaction_remaining = maxf(reaction_remaining - delta, 0.0)
		return
	if seated:
		_stand_up()


func _stand_up() -> void:
	seated = false
	speed_ring.visible = true
	if character_model != null:
		var model_tween := create_tween()
		model_tween.tween_property(self, "sit_amount", 0.0, STAND_UP_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		model_tween.tween_callback(_finish_standing)
		return
	var stand_tween := create_tween()
	stand_tween.set_parallel(true)
	stand_tween.tween_property(person_visual, "position:y", 0.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	stand_tween.tween_property(left_leg, "position", Vector3(-0.09, -0.39, 0.0), 0.55)
	stand_tween.tween_property(right_leg, "position", Vector3(0.09, -0.39, 0.0), 0.55)
	stand_tween.tween_property(left_leg, "rotation:x", 0.0, 0.55)
	stand_tween.tween_property(right_leg, "rotation:x", 0.0, 0.55)
	stand_tween.tween_property(left_arm, "position", Vector3(-0.24, 0.10, 0.0), 0.55)
	stand_tween.tween_property(right_arm, "position", Vector3(0.24, 0.10, 0.0), 0.55)
	stand_tween.tween_property(left_arm, "rotation:x", 0.0, 0.55)
	stand_tween.tween_property(right_arm, "rotation:x", 0.0, 0.55)
	stand_tween.set_parallel(false)
	stand_tween.tween_callback(_finish_standing)


func _finish_standing() -> void:
	freeze = false
	if character_model != null:
		_play_animation("idle", 0.2)


func _physics_process(delta: float) -> void:
	if waiting_for_alarm or seated:
		return
	agitation_timer -= delta
	if agitation_timer <= 0.0:
		lateral_agitation = steering_rng.randf_range(-1.0, 1.0)
		agitation_timer = steering_rng.randf_range(0.2, 0.5)

	while current_waypoint_index < waypoints.size():
		var waypoint_offset := waypoints[current_waypoint_index] - global_position
		waypoint_offset.y = 0.0
		if waypoint_offset.length_squared() >= 0.16:
			break
		current_waypoint_index += 1

	var final_leg := current_waypoint_index >= waypoints.size()
	var target_position := exit_position if final_leg else waypoints[current_waypoint_index]
	var desired_direction := target_position - global_position
	desired_direction.y = 0.0
	var clear_half_width := door_width * 0.5 - body_radius - DOOR_JAMB_CLEARANCE
	var alignment_start_z := door_plane_z - door_wall_thickness * 0.5 - body_radius - 0.15 if exit_side == ExitSide.SOUTH else door_plane_z + door_wall_thickness * 0.5 + body_radius + 0.15
	var near_exit_wall := global_position.z >= alignment_start_z if exit_side == ExitSide.SOUTH else global_position.z <= alignment_start_z
	var aligning_with_door := final_leg and near_exit_wall and absf(global_position.x - exit_center_x) > clear_half_width
	if aligning_with_door:
		desired_direction = Vector3(signf(exit_center_x - global_position.x), 0.0, 0.0)
	var planar_velocity := linear_velocity
	planar_velocity.y = 0.0

	if desired_direction.length_squared() > 0.01:
		var movement_direction := desired_direction.normalized()
		if not aligning_with_door:
			for neighbor_node: Node in get_tree().get_nodes_in_group("agents"):
				if neighbor_node == self:
					continue
				var neighbor := neighbor_node as RigidBody3D
				if neighbor == null:
					continue
				var away_from_neighbor: Vector3 = global_position - neighbor.global_position
				away_from_neighbor.y = 0.0
				var distance: float = away_from_neighbor.length()
				if distance > 0.001 and distance < neighbor_radius:
					var strength: float = (neighbor_radius - distance) / neighbor_radius
					movement_direction += away_from_neighbor.normalized() * strength * neighbor_repulsion
			for obstacle: Node3D in get_tree().get_nodes_in_group("obstacles"):
				var away_from_obstacle: Vector3 = global_position - obstacle.global_position
				away_from_obstacle.y = 0.0
				var obstacle_distance: float = away_from_obstacle.length()
				if obstacle_avoidance_radius > 0.0 and obstacle_distance > 0.001 and obstacle_distance < obstacle_avoidance_radius:
					var obstacle_strength: float = (obstacle_avoidance_radius - obstacle_distance) / obstacle_avoidance_radius
					movement_direction += away_from_obstacle.normalized() * obstacle_strength * 2.0
		if movement_direction.length_squared() > 0.001:
			movement_direction = movement_direction.normalized()
		var desired_velocity := movement_direction * desired_speed
		apply_central_force((desired_velocity - planar_velocity) * force_gain)
		if global_position.z < exit_position.z - 3.0:
			apply_central_force(Vector3(lateral_agitation * force_gain * 0.5, 0.0, 0.0))
	_update_humanoid_pose(delta)

	var crossed_exit := global_position.z >= exit_position.z if exit_side == ExitSide.SOUTH else global_position.z <= exit_position.z
	if crossed_exit and absf(global_position.x - exit_center_x) <= door_width * 0.5 - body_radius:
		evacuated.emit(exit_side)
		queue_free()


func _create_humanoid_visual() -> void:
	var old_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if old_mesh != null:
		old_mesh.visible = false

	var person := Node3D.new()
	person.name = "HumanoidVisual"
	add_child(person)
	person_visual = person

	var clothing_colors: Array[Color] = [
		Color("#315f68"), Color("#a94f3d"), Color("#526746"),
		Color("#485987"), Color("#a17632"), Color("#78506a")
	]
	clothing_material = StandardMaterial3D.new()
	base_clothing_color = clothing_colors[steering_rng.randi_range(0, clothing_colors.size() - 1)]
	clothing_material.albedo_color = base_clothing_color
	clothing_material.roughness = 0.9
	var trousers := StandardMaterial3D.new()
	trousers.albedo_color = base_clothing_color.darkened(0.3)
	trousers.roughness = 0.95
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#d7ae88")
	skin.roughness = 0.9
	var hair := StandardMaterial3D.new()
	hair.albedo_color = Color("#40332d")
	hair.roughness = 0.95
	var shoes := StandardMaterial3D.new()
	shoes.albedo_color = Color("#303638")
	shoes.roughness = 0.95

	torso_mesh = _add_person_capsule(person, "Torso", 0.16, 0.58, Vector3(0.0, 0.08, 0.0), clothing_material)
	_add_person_capsule(person, "Shoulders", 0.12, 0.42, Vector3(0.0, 0.28, 0.0), clothing_material, Vector3(0.0, 0.0, PI * 0.5))
	_add_person_capsule(person, "Neck", 0.065, 0.13, Vector3(0.0, 0.43, 0.0), skin)
	left_arm = _add_person_capsule(person, "LeftArm", 0.07, 0.44, Vector3(-0.24, 0.10, 0.0), clothing_material)
	right_arm = _add_person_capsule(person, "RightArm", 0.07, 0.44, Vector3(0.24, 0.10, 0.0), clothing_material)
	left_leg = _add_person_capsule(person, "LeftLeg", 0.075, 0.48, Vector3(-0.09, -0.39, 0.0), trousers)
	right_leg = _add_person_capsule(person, "RightLeg", 0.075, 0.48, Vector3(0.09, -0.39, 0.0), trousers)
	_add_person_sphere(person, "LeftShoe", Vector3(-0.09, -0.70, 0.06), Vector3(0.13, 0.08, 0.24), shoes)
	_add_person_sphere(person, "RightShoe", Vector3(0.09, -0.70, 0.06), Vector3(0.13, 0.08, 0.24), shoes)

	_add_person_sphere(person, "Head", Vector3(0.0, 0.57, 0.0), Vector3(0.24, 0.28, 0.24), skin)
	_add_person_sphere(person, "Hair", Vector3(0.0, 0.68, -0.015), Vector3(0.245, 0.09, 0.25), hair)
	_add_person_sphere(person, "Nose", Vector3(0.0, 0.57, 0.125), Vector3(0.07, 0.06, 0.08), skin)
	if seated:
		person.position.y = -0.16
		left_leg.position = Vector3(-0.09, -0.29, 0.2)
		right_leg.position = Vector3(0.09, -0.29, 0.2)
		left_leg.rotation.x = PI * 0.5
		right_leg.rotation.x = PI * 0.5
		left_arm.position = Vector3(-0.24, -0.02, 0.22)
		right_arm.position = Vector3(0.24, -0.02, 0.22)
		left_arm.rotation.x = PI * 0.5
		right_arm.rotation.x = PI * 0.5
		torso_mesh.rotation.x = -0.12


func _add_person_capsule(parent: Node3D, mesh_name: String, radius: float, height: float, mesh_position: Vector3, material: Material, mesh_rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = height
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.position = mesh_position
	mesh_instance.rotation = mesh_rotation
	mesh_instance.mesh = capsule
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_person_sphere(parent: Node3D, mesh_name: String, mesh_position: Vector3, dimensions: Vector3, material: Material) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.position = mesh_position
	mesh_instance.scale = dimensions
	mesh_instance.mesh = sphere
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _create_character_model() -> bool:
	if character_scene == null:
		if not ResourceLoader.exists(CHARACTER_SCENE_PATH):
			return false
		character_scene = load(CHARACTER_SCENE_PATH) as PackedScene
		if character_scene == null:
			return false
	var old_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if old_mesh != null:
		old_mesh.visible = false
	# Meme tirage que la version capsule pour garder la sequence aleatoire du deplacement identique.
	var variant := steering_rng.randi_range(0, 5)

	person_visual = Node3D.new()
	person_visual.name = "CharacterVisual"
	add_child(person_visual)
	character_model = character_scene.instantiate() as Node3D
	person_visual.add_child(character_model)
	var bounds := _get_model_bounds(character_model)
	if bounds.size.y > 0.01:
		var model_scale := CHARACTER_HEIGHT / bounds.size.y
		character_model.scale = Vector3.ONE * model_scale
		character_model.position.y = -BODY_HALF_HEIGHT - bounds.position.y * model_scale
	var outfit := _get_character_material(variant)
	if outfit != null:
		for node in character_model.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = outfit

	var skeletons := character_model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		character_skeleton = skeletons[0] as Skeleton3D
	if character_animations == null:
		character_animations = _load_character_animations()
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	# Avance manuelle pour pouvoir plier les jambes apres l'animation (pose assise).
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	character_model.add_child(animation_player)
	animation_player.add_animation_library("", character_animations)
	_play_animation("idle", 0.0)
	if animation_player.has_animation("idle"):
		animation_player.seek(variant * 0.17, true)
	sit_amount = 1.0 if seated else 0.0
	_update_character_animation(0.0)
	return true


static func _load_character_animations() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for animation_key: String in CHARACTER_ANIMATION_PATHS:
		var path: String = CHARACTER_ANIMATION_PATHS[animation_key]
		if not ResourceLoader.exists(path):
			continue
		var source := (load(path) as PackedScene).instantiate()
		for player_node in source.find_children("*", "AnimationPlayer", true, false):
			var player := player_node as AnimationPlayer
			for source_name in player.get_animation_list():
				if source_name.contains("Targeting"):
					continue
				var animation := player.get_animation(source_name).duplicate() as Animation
				animation.loop_mode = Animation.LOOP_LINEAR
				library.add_animation(animation_key, animation)
		source.free()
	return library


# sit_amount = 1 : assis, 0 : debout.
func _update_character_animation(delta: float) -> void:
	if character_model == null:
		return
	animation_player.advance(delta)
	person_visual.position.y = -SIT_DROP * sit_amount
	if character_skeleton == null or sit_amount <= 0.0:
		return
	for side in ["Left", "Right"]:
		_bend_bone(side + "UpLeg", SIT_HIP_ANGLE * sit_amount)
		_bend_bone(side + "Leg", SIT_KNEE_ANGLE * sit_amount)


func _bend_bone(bone_name: String, angle_degrees: float) -> void:
	var bone := character_skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var animated := character_skeleton.get_bone_pose_rotation(bone)
	character_skeleton.set_bone_pose_rotation(bone, animated * Quaternion(Vector3.RIGHT, deg_to_rad(angle_degrees)))


func _get_character_material(variant: int) -> StandardMaterial3D:
	if character_materials.has(variant):
		return character_materials[variant]
	var texture_path := CHARACTER_SKIN_PATTERN % variant
	var material: StandardMaterial3D = null
	if ResourceLoader.exists(texture_path):
		material = StandardMaterial3D.new()
		material.albedo_texture = load(texture_path) as Texture2D
		material.roughness = 0.8
	character_materials[variant] = material
	return material


func _get_model_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var model_inverse := model.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var box := model_inverse * mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func _play_animation(animation_name: String, blend: float) -> void:
	if animation_player == null or not animation_player.has_animation(animation_name):
		return
	if animation_player.current_animation != animation_name:
		animation_player.play(animation_name, blend)


func _create_speed_ring() -> void:
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.24
	ring_mesh.outer_radius = 0.32
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 6
	speed_ring_material = StandardMaterial3D.new()
	speed_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	speed_ring_material.albedo_color = Color("#3fd17f")
	speed_ring = MeshInstance3D.new()
	speed_ring.name = "SpeedRing"
	speed_ring.mesh = ring_mesh
	speed_ring.scale = Vector3(1.0, 0.15, 1.0)
	speed_ring.position.y = -BODY_HALF_HEIGHT + 0.03
	speed_ring.material_override = speed_ring_material
	speed_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	speed_ring.visible = not seated
	add_child(speed_ring)


func _update_humanoid_pose(delta: float) -> void:
	if seated:
		return
	var planar_speed := Vector2(linear_velocity.x, linear_velocity.z).length()
	var speed_ratio := clampf(planar_speed / maxf(desired_speed, 0.1), 0.0, 1.0)
	# Anneau au sol : vert = avance librement, rouge = bloque dans la foule.
	speed_ring_material.albedo_color = Color("#e5413a").lerp(Color("#3fd17f"), speed_ratio)
	if planar_speed > 0.08:
		var forward := Vector3(linear_velocity.x, 0.0, linear_velocity.z).normalized()
		person_visual.rotation.y = lerp_angle(person_visual.rotation.y, atan2(forward.x, forward.z), minf(delta * 10.0, 1.0))
	if character_model != null:
		if planar_speed < 0.25:
			_play_animation("idle", 0.25)
			animation_player.speed_scale = 1.0
		else:
			_play_animation("run", 0.2)
			animation_player.speed_scale = clampf(planar_speed / 3.2, 0.35, 1.2)
		return
	var speed_color := Color("#4286b8").lerp(Color("#e35c42"), speed_ratio)
	clothing_material.albedo_color = base_clothing_color.lerp(speed_color, 0.72)
	if planar_speed > 0.08:
		walking_phase += delta * clampf(planar_speed * 5.0, 3.0, 12.0)
	else:
		walking_phase = move_toward(walking_phase, 0.0, delta * 4.0)
	var stride := sin(walking_phase) * minf(planar_speed * 0.12, 0.35)
	left_leg.rotation.x = stride
	right_leg.rotation.x = -stride
	left_arm.rotation.x = -stride * 0.7
	right_arm.rotation.x = stride * 0.7
