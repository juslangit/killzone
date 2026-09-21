extends Node3D

## Everything you see when the rifle goes off: the flash at the barrel, the
## tracer, and the puff where the round lands.
##
## All of it is drawn from pooled nodes rather than spawned and freed, because
## the rifle fires roughly nine times a second and allocating a scene per shot
## is the kind of thing that turns into a stutter later.

const TRACER_COUNT := 24
const TRACER_LIFE := 0.055
const FLASH_LIFE := 0.045
const IMPACT_LIFE := 0.22

@export var player_path: NodePath

var _tracers: Array[MeshInstance3D] = []
var _tracer_timers: Array[float] = []
var _next_tracer := 0

var _flash: OmniLight3D
var _flash_timer := 0.0

var _impacts: Array[MeshInstance3D] = []
var _impact_timers: Array[float] = []
var _next_impact := 0


func _ready() -> void:
	var player := get_node_or_null(player_path) as Player
	if player:
		player.fired.connect(_on_fired)

	var tracer_material := StandardMaterial3D.new()
	tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_material.albedo_color = Color(1.0, 0.86, 0.45)
	tracer_material.emission_enabled = true
	tracer_material.emission = Color(1.0, 0.78, 0.3)
	tracer_material.emission_energy_multiplier = 3.0
	tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED

	for i in TRACER_COUNT:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.035, 0.035, 1.0)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = tracer_material.duplicate()
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_tracers.append(node)
		_tracer_timers.append(0.0)

	var impact_material := StandardMaterial3D.new()
	impact_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	impact_material.albedo_color = Color(0.95, 0.9, 0.75)
	impact_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for i in 12:
		var sphere := SphereMesh.new()
		sphere.radius = 0.11
		sphere.height = 0.22
		sphere.radial_segments = 8
		sphere.rings = 4
		var node := MeshInstance3D.new()
		node.mesh = sphere
		node.material_override = impact_material.duplicate()
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_impacts.append(node)
		_impact_timers.append(0.0)

	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.82, 0.45)
	_flash.light_energy = 0.0
	_flash.omni_range = 5.0
	add_child(_flash)


func _on_fired(from: Vector3, to: Vector3, hit: bool) -> void:
	var tracer := _tracers[_next_tracer]
	var timer_index := _next_tracer
	_next_tracer = (_next_tracer + 1) % TRACER_COUNT

	var length := from.distance_to(to)
	if length < 0.05:
		return
	tracer.mesh.size = Vector3(0.035, 0.035, length)
	tracer.global_position = (from + to) * 0.5
	tracer.look_at(to, Vector3.UP)
	tracer.visible = true
	_tracer_timers[timer_index] = TRACER_LIFE

	_flash.global_position = from
	_flash_timer = FLASH_LIFE

	if hit:
		var impact := _impacts[_next_impact]
		_impact_timers[_next_impact] = IMPACT_LIFE
		_next_impact = (_next_impact + 1) % _impacts.size()
		impact.global_position = to
		impact.visible = true


func _process(delta: float) -> void:
	for i in _tracers.size():
		if _tracer_timers[i] <= 0.0:
			continue
		_tracer_timers[i] -= delta
		var node := _tracers[i]
		var fade: float = clampf(_tracer_timers[i] / TRACER_LIFE, 0.0, 1.0)
		node.material_override.albedo_color.a = fade
		node.visible = _tracer_timers[i] > 0.0

	for i in _impacts.size():
		if _impact_timers[i] <= 0.0:
			continue
		_impact_timers[i] -= delta
		var node := _impacts[i]
		var fade: float = clampf(_impact_timers[i] / IMPACT_LIFE, 0.0, 1.0)
		node.material_override.albedo_color.a = fade
		node.scale = Vector3.ONE * (0.5 + (1.0 - fade) * 1.4)
		node.visible = _impact_timers[i] > 0.0

	if _flash_timer > 0.0:
		_flash_timer -= delta
		_flash.light_energy = clampf(_flash_timer / FLASH_LIFE, 0.0, 1.0) * 7.0
	else:
		_flash.light_energy = 0.0
