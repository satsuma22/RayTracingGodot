extends Node3D

var image: Image
var texture: ImageTexture
var rd: RenderingDevice
var texture_rid: RID
var shader: RID
var pipeline: RID
var uniform_set: RID

@onready var texture_rect = $CanvasLayer/TextureRect

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	rd = RenderingServer.create_local_rendering_device()
	
	image = Image.create_empty(512,512, false,Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,1))
	
	texture_rid = create_compute_texture()
	
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
	
	var img_data = image.get_data()
	var tex_view = RDTextureView.new()
	
	return rd.texture_create(tex_format, tex_view)
	
func setup_compute_shader():
	var shader_file = load("res://compute_shader.glsl")
	var shader_spirv = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rid)
	uniform_set = rd.uniform_set_create([uniform], shader, 0)

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
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
