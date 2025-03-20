#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D output_texture;

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
    float roughness;
    float metallic_specular;
};

layout(set = 0, binding = 1, std430) restrict buffer Uniforms {
    Camera camera;
    uint frameNumber;
    uint SphereCount;
    Sphere spheres[];
};

layout(set = 0, binding = 2, std430) restrict buffer Params {
    uint num_bounces;
    uint rays_per_pixel;
}
;
struct Hit
{
    bool didHit;
    float t;
    vec3 hitPoint;
    vec3 normal;
    vec3 color;
    vec3 emission_color;
    float emission_strength;
    float roughness;
    float metallic_specular;
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

    // Vector from ray origin to sphere center
    vec3 oc = ray.origin - sphere.center;

    // Coefficients for the quadratic equation: t^2 + 2bt + c = 0
    // Since ray.dir is normalized, a = dot(ray.dir, ray.dir) = 1
    float b = dot(oc, ray.dir);
    float c = dot(oc, oc) - sphere.radius * sphere.radius;

    // Compute the discriminant
    float discriminant = b * b - c;

    // If discriminant is negative, no real intersection occurs
    if (discriminant < 0.0)
    {
        hit.didHit = false;
        return hit;
    }

    // Compute the two possible intersection distances
    float sqrtDisc = sqrt(discriminant);
    float t1 = -b - sqrtDisc;  // Closer intersection
    float t2 = -b + sqrtDisc;  // Farther intersection

    // Select the smallest positive t
    float t;
    if (t1 > 0.0)
    {
        t = t1;  // t1 is positive, use it as it's the closest
    }
    else if (t2 > 0.0)
    {
        t = t2;  // t1 is negative, but t2 is positive
    }
    else
    {
        // Both t1 and t2 are negative, no intersection in ray's direction
        hit.didHit = false;
        return hit;
    }

    // Intersection occurred, fill in the hit details
    hit.didHit = true;
    hit.t = t;
    hit.hitPoint = ray.origin + t * ray.dir;
    hit.normal = normalize(hit.hitPoint - sphere.center);
    hit.color = sphere.color.xyz;  // Assuming sphere.color is vec4, take RGB
    hit.emission_color = sphere.emission_color;
    hit.emission_strength = sphere.emission_strength;
    hit.roughness = sphere.roughness;
    hit.metallic_specular = sphere.metallic_specular;

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

vec3 GetEnvironmentLight(Ray ray)
{
    vec3 SkyColorHorizon = vec3(0.7, 0.7, 0.8);
    vec3 SkyColorZenith = vec3(0.4, 0.7, 0.8);
    vec3 GroundColor = vec3(0.7, 0.6, 0.4);

    float skyGradientT = pow(smoothstep(0, 0.4, ray.dir.y), 0.35);
    vec3 skyGradient = (1 - skyGradientT) * SkyColorHorizon + skyGradientT * SkyColorZenith;
    
    float groundToSkyT = smoothstep(-0.01, 0, ray.dir.y);
    return (1 - groundToSkyT) * GroundColor + groundToSkyT * skyGradient;
}

vec3 Trace(Ray ray, inout uint seed)
{
    vec3 incomingLight = vec3(0.0, 0.0, 0.0);
    vec3 rayColor = vec3(1.0, 1.0, 1.0);

    for(int i = 0; i < num_bounces; i++)
    {
        Hit hit = GetRayCollision(ray);
        if (hit.didHit)
        {
            ray.origin = hit.hitPoint + 0.001 * hit.normal;
            //ray.dir = HemisphereSampling(hit.normal, seed);
            // cosine weighted sampling
            vec3 diffuseDir = normalize(hit.normal + RandomDirection(seed));
            vec3 specularDir = reflect(ray.dir, hit.normal);
            bool isSpecularBounce = hit.metallic_specular >= UniformRandom(seed);
            float roughness = isSpecularBounce? hit.roughness : 1.0;
            //float roughness = hit.roughness;
            ray.dir = (1 - roughness) * specularDir + roughness * diffuseDir;

            vec3 emittedLight = hit.emission_color * hit.emission_strength;
            incomingLight += emittedLight * rayColor;
            rayColor *= isSpecularBounce ? vec3(1.0, 1.0, 1.0) : hit.color;
        }
        else
        {
            incomingLight += GetEnvironmentLight(ray) * rayColor;
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

    uint seed = (coords.y * imageSize.x + coords.x) + frameNumber * 7791234;

    vec3 color = vec3(0.0, 0.0, 0.0);

    for (int i = 0; i < rays_per_pixel; i++)
        color += Trace(ray, seed);

    color /= rays_per_pixel;

    vec4 prevColor = imageLoad(output_texture, coords);
    color = (prevColor.xyz * (frameNumber - 1) + color) / float(frameNumber);
    imageStore(output_texture, coords, vec4(color.xyz, 1));
}