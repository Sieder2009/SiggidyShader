#version 120

#include "/lib/common.glsl"

#define STAR_DENSITY 0.02    // [0.005 0.01 0.02 0.03 0.05]
#define STAR_SHARPNESS 0.35  // [0.2 0.25 0.3 0.35 0.4 0.5]
#define STAR_BRIGHTNESS 1.0  // [0.5 0.75 1.0 1.5 2.0]
#define BLOOM_STRENGTH 0.35  // [0.0 0.15 0.25 0.35 0.5 0.75]

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;
uniform vec3 moonPosition;

uniform float viewWidth;
uniform float viewHeight;

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

    float night = nightFactor(h);
    if (night > 0.001) {
        // starField() hashes its input as an absolute coordinate (not a dot
        // product like the sun/moon/gradient above), so it needs a direction
        // that stays fixed to the WORLD as the camera turns - rotate the
        // view-space ray back into scene space first, otherwise the stars
        // are glued to the screen instead of the sky.
        vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * dir);
        float stars = starField(worldDir, STAR_DENSITY, STAR_SHARPNESS) * STAR_BRIGHTNESS;
        sky += stars * night * vec3(0.9, 0.95, 1.0);
    }

    return sky;
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).r;

    if (depth >= 1.0) {
        color = renderSky(getViewRay());
    }

    if (BLOOM_STRENGTH > 0.0) {
        vec3 glow = vec3(0.0);
        float total = 0.0;
        vec2 px = vec2(1.0 / viewWidth, 1.0 / viewHeight) * 2.0;
        for (int x = -2; x <= 2; x++) {
            for (int y = -2; y <= 2; y++) {
                vec2 offset = vec2(float(x), float(y)) * px;
                vec3 s = texture2D(colortex0, texcoord + offset).rgb;
                float w = max(luma(s) - 0.7, 0.0);
                glow += s * w;
                total += w;
            }
        }
        if (total > 0.0) {
            color += (glow / total) * BLOOM_STRENGTH * 0.4;
        }
    }

    gl_FragColor = vec4(color, 1.0);
}
