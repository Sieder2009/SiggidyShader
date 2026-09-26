#version 120

#include "/lib/common.glsl"

#define STAR_DENSITY 0.02    // [0.005 0.01 0.02 0.03 0.05]
#define STAR_SHARPNESS 0.35  // [0.2 0.25 0.3 0.35 0.4 0.5]
#define STAR_BRIGHTNESS 1.0  // [0.5 0.75 1.0 1.5 2.0]

#define ENABLE_CLOUDS // A single, cheap procedural cloud layer. Off in the Potato profile.
#define CLOUD_HEIGHT 180.0    // [120.0 150.0 180.0 220.0 260.0]  world Y of the cloud plane
#define CLOUD_COVERAGE 0.55   // [0.3 0.4 0.45 0.5 0.55 0.6 0.7]  higher = more sky covered
#define CLOUD_SPEED 1.0       // [0.0 0.5 1.0 1.5 2.0]

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;
uniform vec3 moonPosition;

varying vec2 texcoord;

// Reconstructs the VIEW-SPACE ray direction for this screen pixel at the
// far plane. Deliberately left in view space (not transformed to
// world/scene space) so it can be dotted directly against sunPosition /
// moonPosition / upPosition, which Iris/OptiFine also provide in view space.
vec3 getViewRay() {
    vec4 clip = vec4(texcoord * 2.0 - 1.0, 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    view /= view.w;
    return normalize(view.xyz);
}

#ifdef ENABLE_CLOUDS
// A single flat, animated noise plane at a fixed world height - not
// volumetric, but very cheap and looks reasonable from below, which is
// where the player is the vast majority of the time. worldDir must be the
// WORLD-space (not view-space) ray direction, same as starField() needs.
vec3 renderClouds(vec3 worldDir, vec3 skyColor, float dayNightMix) {
    float denom = worldDir.y;
    if (abs(denom) < 0.001) return skyColor; // ray parallel to the cloud plane

    float t = (CLOUD_HEIGHT - cameraPosition.y) / denom;
    if (t <= 0.0) return skyColor; // plane is behind the camera

    vec2 samplePos = cameraPosition.xz + worldDir.xz * t;
    // NOT wrapped/mod()'d: an earlier version of this function wrapped
    // samplePos to guard against float precision loss far from world
    // origin (the lesson this project's earlier highperf-shader draft
    // learned for its rain ripples) - but a hard mod() here just trades that
    // problem for a worse one, a visible seam at every wrap boundary, since
    // the noise field isn't actually periodic at that boundary. The 0.0016
    // scale below keeps the noise argument small enough (well under 1000
    // even at the edge of Minecraft's ~30,000,000-block world border) that
    // the original precision concern doesn't actually apply at this scale.
    vec2 uv = samplePos * 0.0016 + frameTimeCounter * CLOUD_SPEED * vec2(0.006, 0.0035);
    float density = cloudFbm(uv);

    float threshold = 1.0 - CLOUD_COVERAGE;
    float cloud = smoothstep(threshold, threshold + 0.25, density);

    // Fade out near the horizon (grazing angle) instead of ending in a hard
    // edge, and keep this simple, cheap effect looking sensible whether the
    // camera is below the cloud layer (the common case) or above it.
    float horizonFade = smoothstep(0.02, 0.12, abs(denom));
    cloud *= horizonFade;

    vec3 cloudColor = mix(vec3(0.05, 0.06, 0.09), vec3(1.0, 0.98, 0.95), dayNightMix);
    return mix(skyColor, cloudColor, cloud * 0.85);
}
#endif

vec3 renderSky(vec3 dir) {
    vec3 up = normalize(upPosition);
    float h = sunHeight();

    vec3 zenithDay   = vec3(0.30, 0.50, 0.85);
    vec3 zenithNight = vec3(0.02, 0.03, 0.08);
    vec3 horizonDay  = vec3(0.75, 0.85, 1.00);
    vec3 horizonNight= vec3(0.10, 0.11, 0.18);
    vec3 horizonSunset = vec3(1.00, 0.55, 0.25);

    vec3 zenith  = mix(zenithNight, zenithDay, dayFactor(h));
    vec3 horizon = mix(horizonNight, horizonDay, dayFactor(h));
    horizon = mix(horizon, horizonSunset, twilightFactor(h) * 0.85);

    // How close this ray is to the true horizon (dot(dir, up) == 0), biased
    // toward the zenith with a gentle power curve for a nicer gradient.
    float t = clamp(dot(dir, up) * 0.5 + 0.5, 0.0, 1.0);
    vec3 sky = mix(horizon, zenith, pow(t, 0.45));

    vec3 sunDir = normalize(sunPosition);
    vec3 moonDir = normalize(moonPosition);

    float sunAlign = dot(dir, sunDir);
    float sunDisc = smoothstep(0.9994, 0.9998, sunAlign);
    float sunGlow = pow(max(sunAlign, 0.0), 340.0) * 0.6;
    sky += (sunDisc * 3.0 + sunGlow) * getDayNightSunColor(h);

    float moonAlign = dot(dir, moonDir);
    float moonDisc = smoothstep(0.9992, 0.9997, moonAlign);
    sky += moonDisc * vec3(0.85, 0.88, 1.0) * 0.8;

    // starField() and renderClouds() both hash an absolute coordinate
    // (unlike the dot-product-based gradient/sun/moon above), so they need
    // a direction that stays fixed to the WORLD as the camera turns -
    // rotate the view-space ray back into scene space once, up front,
    // otherwise stars/clouds would be glued to the screen instead of the sky.
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * dir);

    float night = nightFactor(h);
    if (night > 0.001) {
        float stars = starField(worldDir, STAR_DENSITY, STAR_SHARPNESS) * STAR_BRIGHTNESS;
        sky += stars * night * vec3(0.9, 0.95, 1.0);
    }

#ifdef ENABLE_CLOUDS
    // Clouds occlude whatever is behind them (stars included), so they are
    // mixed in last rather than added.
    sky = renderClouds(worldDir, sky, dayFactor(h));
#endif

    return sky;
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).r;

    if (depth >= 1.0) {
        color = renderSky(getViewRay());
    }

    gl_FragColor = vec4(color, 1.0);
}
