#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, binding = 0) uniform image2D output_texture;

void main() {
    ivec2 coords = ivec2(gl_GlobalInvocationID.xy);
    vec4 color = vec4(float(coords.x) / 512.0, float(coords.y) / 512.0, 0.5, 1.0);
    imageStore(output_texture, coords, color);
}