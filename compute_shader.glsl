#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

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
    vec4 color;
    vec3 emission_color;
    float emission_strength;
};

layout(set = 0, binding = 1, std430) restrict buffer Uniforms {
    Camera camera;
    uint SphereCount;
    Sphere spheres[];
};

struct Hit
{
    bool didHit;
    float t;
    vec3 hitPoint;
    vec3 normal;
    vec3 color;
    vec3 emission_color;
    float emission_strength;
};

struct Ray
{
    vec3 origin;
    vec3 dir;
};

float UniformRandom(inout uint state)
{
    state = state * 747796405 + 2891336453;
    uint result = ((state >> ((state >> 28) + 4)) ^ state) * 277803737;
    result = (result >> 22) ^ result;
    return result / 4294967295.0;
}

float GaussianRandom(inout uint state)
{
    float theta = 2 * 3.1415926 * UniformRandom(state);
    float rho = sqrt(-2 * log(UniformRandom(state)));
    return rho * cos(theta);
}

vec3 RandomDirection(inout uint state)
{
    float x = GaussianRandom(state);
    float y = GaussianRandom(state);
    float z = GaussianRandom(state);
    return normalize(vec3(x, y, z));
}

vec3 HemisphereSampling(vec3 normal, inout uint seed)
{
    vec3 dir = RandomDirection(seed);
    return dir * sign(dot(normal, dir));
}

Hit raySphereIntersect(Ray ray, Sphere sphere)
{
    Hit hit;
    hit.didHit = false;
    
    vec3 oc = ray.origin - sphere.center;
    float a = dot(ray.dir, ray.dir);
    float b = 2.0 * dot(oc, ray.dir);
    float c = dot(oc, oc) - sphere.radius * sphere.radius;
    float discriminant = b * b - 4 * a * c;

    if (discriminant < 0.0)
    {
        return hit;
    }

    float t1 = (-b - sqrt(discriminant)) / (2 * a);
    float t2 = (-b + sqrt(discriminant)) / (2 * a);

    hit.didHit = true;
    hit.t = t1 >= 0.0 ? t1 : t2;
    hit.hitPoint = ray.origin + ray.dir * hit.t;
    hit.normal = normalize(hit.hitPoint - sphere.center);
    hit.color = vec3(sphere.color.xyz);
    hit.emission_color = sphere.emission_color;
    hit.emission_strength = sphere.emission_strength;

    return hit;
}

Hit GetRayCollision(Ray ray)
{
    Hit closestHit;
    closestHit.t = 1e9;
    closestHit.didHit = false;
    
    for (int i = 0; i < SphereCount; i++)
    {
        Hit hit = raySphereIntersect(ray, spheres[i]);
        if (hit.didHit && hit.t < closestHit.t)
        {
            closestHit = hit;
        }
    }

    return closestHit;
}

vec3 Trace(Ray ray, inout uint seed)
{
    int maxBounces = 2;
    
    vec3 incomingLight = vec3(0.0, 0.0, 0.0);
    vec3 rayColor = vec3(1.0, 1.0, 1.0);

    for(int i = 0; i < maxBounces; i++)
    {
        Hit hit = GetRayCollision(ray);
        if (hit.didHit)
        {
            ray.origin = hit.hitPoint;
            ray.dir = HemisphereSampling(hit.normal, seed);

            vec3 emittedLight = hit.emission_color * hit.emission_strength;
            incomingLight += emittedLight * rayColor;
            rayColor *= hit.color;
        }
        else
        {
            break;
        }
    }

    return incomingLight;
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

    Ray ray;
    ray.origin = camera.position;
    ray.dir = normalize(camera.basis * dirCamera);

    uint seed = coords.y * imageSize.x + coords.x;

    vec3 color = Trace(ray, seed);

    imageStore(output_texture, coords, vec4(color.xyz, 1));
}