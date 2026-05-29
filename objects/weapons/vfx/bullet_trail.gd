extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var _lifetime: float = 0.06
var _elapsed: float = 0.0
var _material: StandardMaterial3D = null


func configure(start: Vector3, hit_point: Vector3, lifetime: float, width: float) -> void:
	var segment: Vector3 = hit_point - start
	var length: float = segment.length()
	if length <= 0.001:
		queue_free()
		return

	_lifetime = maxf(lifetime, 0.01)

	var mesh := CylinderMesh.new()
	mesh.top_radius = width
	mesh.bottom_radius = width
	mesh.height = length
	mesh.radial_segments = 6
	mesh.rings = 1

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(1.0, 0.9, 0.5, 0.9)
	_material.emission_enabled = true
	_material.emission = Color(1.0, 0.8, 0.3)
	mesh.material = _material
	mesh_instance.mesh = mesh

	var midpoint: Vector3 = start + segment * 0.5
	var trail_basis := Basis.looking_at(segment.normalized(), Vector3.UP)
	global_transform = Transform3D(trail_basis.rotated(trail_basis.x, deg_to_rad(90.0)), midpoint)


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / _lifetime, 0.0, 1.0)
	if _material:
		var color: Color = _material.albedo_color
		color.a = lerpf(0.9, 0.0, t)
		_material.albedo_color = color

	if _elapsed >= _lifetime:
		queue_free()
