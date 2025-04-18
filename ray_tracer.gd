extends Node3D

var image: Image
var texture: ImageTexture
var rd: RenderingDevice
var texture_rid: RID
var storage_buffer_rid: RID
var param_buffer_rid: RID
var shader: RID
var pipeline: RID
var uniform_set_rid: RID
var buffer_size: int

var width: int = 1920
var height: int = 1080
var sampleCount: int = 1

var num_bounces = 10;
var rays_per_pixel = 1;


@onready var camera = $Camera3D
@onready var texture_rect = $CanvasLayer/TextureRect
@onready var bounces_spin_box = $CanvasLayer/BouncesSpinBox
@onready var rays_spin_box = $CanvasLayer/RaysSpinBox

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	rd = RenderingServer.create_local_rendering_device()
	
	image = Image.create_empty(width, height, false,Image.FORMAT_RGBAF)
	image.fill(Color(0,0,0,1))
	
	texture_rid = create_compute_texture()
	storage_buffer_rid = create_compute_storage()
	param_buffer_rid = create_param_storage()
	
	texture = ImageTexture.create_from_image(image)
	texture_rect.texture = texture
	
	bounces_spin_box.value = num_bounces
	rays_spin_box.value = rays_per_pixel
	
	setup_compute_shader()
	run_compute_shader()

func create_compute_texture() -> RID:
	var tex_format = RDTextureFormat.new()
	tex_format.width = width
	tex_format.height = height
	tex_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	#var img_data = image.get_data()
	var tex_view = RDTextureView.new()
	
	return rd.texture_create(tex_format, tex_view)
	
func get_shader_storage_buffer() -> PackedByteArray:
	var buffer := PackedByteArray()
	
	buffer.append_array(_vector3_to_bytes(camera.global_transform.origin))
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_vector3_to_bytes(camera.basis.x))
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_vector3_to_bytes(camera.basis.y))
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_vector3_to_bytes(camera.basis.z))
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_float_to_bytes(camera.fov))
	buffer.append_array(_float_to_bytes(float(width)/ height))
	
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_float_to_bytes(0.0))
	
	var sphereList := []
	for child in get_children():
		if child is MeshInstance3D and child.mesh is SphereMesh:
			var meshInstance = child as MeshInstance3D
			var sphere = meshInstance.mesh as SphereMesh
			var material = meshInstance.get_surface_override_material(0) as StandardMaterial3D
			var color: Vector4
			var emission_color: Vector3
			var emission_strength: float
			var roughness: float
			var metallic: float
			if material == null:
				color = Vector4(1.0, 1.0, 1.0, 1.0)
				emission_color = Vector3(0.0, 0.0, 0.0)
				emission_strength = 0.0
				roughness = 1.0
				metallic = 0.0
			else:
				color = Vector4(material.albedo_color.r, material.albedo_color.g, material.albedo_color.b, material.albedo_color.a)
				emission_color = Vector3(material.emission.r, material.emission.g, material.emission.b)
				emission_strength = material.emission_energy_multiplier
				roughness = material.roughness
				metallic = material.metallic_specular
				
			sphereList.append({
				"center" : meshInstance.global_transform.origin,
				"radius" : meshInstance.global_transform.basis.get_scale().x * 0.5,
				"color"  : color,
				"emission_color" : emission_color,
				"emission_strength" : emission_strength,
				"roughness" : roughness,
				"metallic" : metallic
			})	
	
	buffer.append_array(PackedInt32Array([sampleCount]).to_byte_array())
	buffer.append_array(PackedInt32Array([sphereList.size()]).to_byte_array())
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_float_to_bytes(0.0))
	
	for sphere in sphereList:
		buffer.append_array(_vector3_to_bytes(sphere.center))
		buffer.append_array(_float_to_bytes(sphere.radius))
		buffer.append_array(_vector4_to_bytes(sphere.color))
		buffer.append_array(_vector3_to_bytes(sphere.emission_color))
		buffer.append_array(_float_to_bytes(sphere.emission_strength))
		buffer.append_array(_float_to_bytes(sphere.roughness))
		buffer.append_array(_float_to_bytes(sphere.metallic))
		buffer.append_array(_float_to_bytes(0))
		buffer.append_array(_float_to_bytes(0))
	
	return buffer
	
func create_compute_storage() -> RID:
	var buffer := get_shader_storage_buffer()
	buffer_size = buffer.size()
	return rd.storage_buffer_create(buffer.size(), buffer)

func update_compute_storage():
	var buffer := get_shader_storage_buffer()
	
	if buffer.size() == buffer_size:
		rd.buffer_update(storage_buffer_rid, 0, buffer.size(), buffer)
	else:
		rd.free_rid(storage_buffer_rid)
		storage_buffer_rid = rd.storage_buffer_create(buffer.size(), buffer)
		buffer_size = buffer.size()
		_update_uniform_set()

func get_shader_param_buffer() -> PackedByteArray:
	var buffer := PackedByteArray()
	buffer.append_array(PackedInt32Array([num_bounces]).to_byte_array())
	buffer.append_array(PackedInt32Array([rays_per_pixel]).to_byte_array())
	
	return buffer

func create_param_storage() -> RID:
	var buffer := get_shader_param_buffer()
	return rd.storage_buffer_create(buffer.size(), buffer)

func update_param_storage():
	var buffer := get_shader_param_buffer()
	rd.buffer_update(param_buffer_rid, 0, buffer.size(), buffer)

func setup_compute_shader():
	var shader_file = load("res://compute_shader.glsl")
	var shader_spirv = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	
	var texture_uniform = RDUniform.new()
	texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform.binding = 0
	texture_uniform.add_id(texture_rid)
	
	var buffer_uniform := RDUniform.new()
	buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	buffer_uniform.binding = 1
	buffer_uniform.add_id(storage_buffer_rid)
	
	var param_uniform := RDUniform.new()
	param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	param_uniform.binding = 2
	param_uniform.add_id(param_buffer_rid)
	
	uniform_set_rid = rd.uniform_set_create([texture_uniform, buffer_uniform, param_uniform], shader, 0)

func _update_uniform_set():
	var texture_uniform = RDUniform.new()
	texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform.binding = 0
	texture_uniform.add_id(texture_rid)
	
	var buffer_uniform := RDUniform.new()
	buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	buffer_uniform.binding = 1
	buffer_uniform.add_id(storage_buffer_rid)
	
	var param_uniform := RDUniform.new()
	param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	param_uniform.binding = 2
	param_uniform.add_id(param_buffer_rid)
	
	rd.free_rid(uniform_set_rid)
	uniform_set_rid = rd.uniform_set_create([texture_uniform, buffer_uniform, param_uniform], shader, 0)
	
func run_compute_shader():
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_rid, 0)
	rd.compute_list_dispatch(compute_list, (width + 15)/16, (height + 15)/16, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
	update_texture()
	
func update_texture():
	var tex_data_new = rd.texture_get_data(texture_rid, 0)
	image = Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, tex_data_new)
	texture.update(image)
	
func _vector3_to_bytes(v: Vector3) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.append_array(PackedFloat32Array([v.x]).to_byte_array())
	bytes.append_array(PackedFloat32Array([v.y]).to_byte_array())
	bytes.append_array(PackedFloat32Array([v.z]).to_byte_array())
	return bytes
	
func _vector4_to_bytes(v: Vector4) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.append_array(PackedFloat32Array([v.x]).to_byte_array())
	bytes.append_array(PackedFloat32Array([v.y]).to_byte_array())
	bytes.append_array(PackedFloat32Array([v.z]).to_byte_array())
	bytes.append_array(PackedFloat32Array([v.w]).to_byte_array())
	return bytes
	
func _float_to_bytes(f: float) -> PackedByteArray:
	return PackedFloat32Array([f]).to_byte_array()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	sampleCount += 1
	update_compute_storage()
	update_param_storage()
	run_compute_shader()


func _on_bounces_spin_box_value_changed(value: float) -> void:
	num_bounces = int(value)


func _on_rays_spin_box_value_changed(value: float) -> void:
	rays_per_pixel = int(value)


func _on_button_pressed() -> void:
	sampleCount = 1 
