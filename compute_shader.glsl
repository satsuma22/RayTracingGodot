#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, binding = 0) uniform image2D output_texture;

struct Camera {
    vec3 position;
    mat3 basis;
    float fov;
    float aspect;
};

struct Sphere {
    vec3 center;
    float radius;
};

layout(set = 0, binding = 1, std430) restrict buffer Uniforms {
    Camera camera;
    Sphere sphere;
};

bool raySphereIntersect(vec3 origin, vec3 dir, vec3 center, float radius)
{
    vec3 oc = origin - center;
    float a = dot(dir, dir);
    float b = 2.0 * dot(oc, dir);
    float c = dot(oc, oc) - radius * radius;
    float discriminant = b * b - 4 * a * c;

    if (discriminant <= 0.0)
    {
        return false;
    }

    return true;
}

void main() {
    ivec2 coords = ivec2(gl_GlobalInvocationID.xy);
    ivec2 imageSize = imageSize(output_texture);

    if (coords.x >= imageSize.x || coords.y >= imageSize.y)
    {
        return;
    }

    float u = (float(coords.x) + 0.5) / float(imageSize.x);
    float v = (float(coords.y) + 0.5) / float(imageSize.y);

    float tanFov = tan(radians(camera.fov) / 2.0);
    float x = (-camera.aspect * tanFov) + (2.0 * camera.aspect * tanFov * u);
    float y = tanFov - (2.0 * tanFov * v);
    vec3 dirCamera = vec3(x, y, -1.0);

    vec3 dirWorld = camera.basis * dirCamera;
    vec3 origin = camera.position;

    vec4 color = vec4(0.0, 0.0, 0.0, 1.0);

    if( raySphereIntersect(origin, dirWorld, sphere.center, sphere.radius) )
    {
        color = vec4(1.0, 0.0, 0.0, 1.0);
    }
    
    imageStore(output_texture, coords, color);
}