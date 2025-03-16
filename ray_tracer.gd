extends Node3D

var image: Image
var texture: ImageTexture
var rd: RenderingDevice
var texture_rid: RID
var storage_buffer_rid: RID
var shader: RID
var pipeline: RID
var uniform_set: RID

var width: int = 512
var height: int = 512

@onready var camera = $Camera3D
@onready var sphere = $MeshInstance3D
@onready var texture_rect = $CanvasLayer/TextureRect

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	rd = RenderingServer.create_local_rendering_device()
	
	image = Image.create_empty(512,512, false,Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,1))
	
	texture_rid = create_compute_texture()
	storage_buffer_rid = create_compute_storage()
	
	texture = ImageTexture.create_from_image(image)
	texture_rect.texture = texture
	
	setup_compute_shader()
	run_compute_shader()

func create_compute_texture() -> RID:
	var tex_format = RDTextureFormat.new()
	tex_format.width = 512
	tex_format.height = 512
	tex_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	#var img_data = image.get_data()
	var tex_view = RDTextureView.new()
	
	return rd.texture_create(tex_format, tex_view)
	
func create_compute_storage() -> RID:
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
	
	buffer.append_array(_vector3_to_bytes(sphere.global_transform.origin))
	buffer.append_array(_float_to_bytes(sphere.global_transform.basis.get_scale().length()))
	
	'''
	buffer.append_array(_vector3_to_bytes(Vector3(0.0, 0.0, 0.0)))  # Camera at origin
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_vector3_to_bytes(Vector3(1.0, 0.0, 0.0)))   # Basis X
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_vector3_to_bytes(Vector3(0.0, 1.0, 0.0)))   # Basis Y
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_vector3_to_bytes(Vector3(0.0, 0.0, 1.0)))   # Basis Z
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_float_to_bytes(90.0))                       # FOV
	buffer.append_array(_float_to_bytes(1.0))                        # Aspect
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_float_to_bytes(0.0))
	buffer.append_array(_vector3_to_bytes(Vector3(0.0, 0.0, -3.0)))  # Sphere center
	buffer.append_array(_float_to_bytes(1.0))                        # Sphere radius
	'''
	return rd.storage_buffer_create(buffer.size(), buffer)
	
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
	
	uniform_set = rd.uniform_set_create([texture_uniform, buffer_uniform], shader, 0)

func run_compute_shader():
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 512/8, 512/8, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
	update_texture()
	
func update_texture():
	var tex_data = rd.texture_get_data(texture_rid, 0)
	image = Image.create_from_data(512, 512, false, Image.FORMAT_RGBA8, tex_data)
	texture.update(image)
	
func _vector3_to_bytes(v: Vector3) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.append_array(PackedFloat32Array([v.x]).to_byte_array())
	bytes.append_array(PackedFloat32Array([v.y]).to_byte_array())
	bytes.append_array(PackedFloat32Array([v.z]).to_byte_array())
	return bytes
	
func _float_to_bytes(f: float) -> PackedByteArray:
	return PackedFloat32Array([f]).to_byte_array()
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
