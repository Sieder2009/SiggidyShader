// ===========================================================================
// Aurora Nights - shared uniforms, helpers and lighting model
//
// Included by every stage via:  #include "/lib/common.glsl"
//
// All coordinate-space-sensitive helpers (sunHeight, sky ray/normal checks)
// consistently work in VIEW SPACE, matching the space that sunPosition,
// moonPosition, shadowLightPosition and upPosition are provided in by
// Iris/OptiFine. Never compare a view-space vector's raw .y component
// against "world up" - always dot() it against upPosition instead.
// ===========================================================================

#ifndef AURORA_COMMON_GLSL
#define AURORA_COMMON_GLSL

// Store the main color buffer as HDR (same 32 bits/pixel as the RGBA8
// default, just distributed differently - no extra bandwidth cost) so the
// sun disc / bright sky isn't clipped to 1.0 before composite1.fsh's bloom
// and tonemap ever see it. Must stay inside a real comment: this is Iris/
// OptiFine's own convention for declaring buffer formats, read by the pack
// loader and ignored by the GLSL compiler.
/*
const int colortex0Format = R11F_G11F_B10F;
*/

#define SHADOW_ENABLED // Dynamic sun/moon shadows. Turn off on very weak GPUs for a big performance gain (skips the whole shadow pass).
#define SHADOW_QUALITY 1 // [0 1 2] 0 = 1 tap (cheapest), 1 = 5 taps, 2 = 9 taps (softest, most expensive)

// GUI-editable shadow map resolution/distance. Declared here (not in
// shadow.fsh) so every stage that needs them (PCF texel size, the distance
// fade below) sees the SAME value the shadow map was actually allocated at.
// Both are Iris/OptiFine "const-scanned" pipeline options, NOT real runtime
// uniforms - there is no engine-injected `uniform float shadowDistance`, so
// declaring it as a uniform (as an earlier version of this file did) always
// reads back as 0.0 and silently breaks anything that depends on it.
const int shadowMapResolution = 2048; // [512 1024 1536 2048 3072 4096]
const float shadowDistance = 160.0;   // [64.0 96.0 128.0 160.0 200.0 256.0]
const bool shadowHardwareFiltering = true; // free bilinear PCF per shadow2D() tap

#define AMBIENT_STRENGTH 1.0 // [0.6 0.8 1.0 1.2 1.4]
#define TORCH_INTENSITY 1.0  // [0.6 0.8 1.0 1.2 1.5]

const float PI = 3.14159265359;

// ---------------------------------------------------------------------------
// Uniforms shared by (almost) every stage
// ---------------------------------------------------------------------------

uniform mat4 gbufferModelViewInverse;

#ifdef SHADOW_ENABLED
    uniform mat4 shadowModelView;
    uniform mat4 shadowProjection;
    uniform sampler2DShadow shadowtex0;
#endif

uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform vec3 cameraPosition;

uniform float rainStrength;
uniform float frameTimeCounter;

// ---------------------------------------------------------------------------
// Small math / color helpers
// ---------------------------------------------------------------------------

float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 tonemapACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Day / night / twilight weighting, all built from FORWARD-ordered
// smoothstep() calls (edge0 < edge1) - GLSL only guarantees smoothstep()
// behaviour when edges are ascending, so any "inverted" ramp is built with
// 1.0 - smoothstep(...) instead of swapping the edge arguments.
// ---------------------------------------------------------------------------

// How high the sun currently is above the horizon, in view space: >0 day, <0 night.
float sunHeight() {
    return dot(normalize(upPosition), normalize(sunPosition));
}

// 0 = night, 1 = full day
float dayFactor(float h) {
    return smoothstep(-0.05, 0.30, h);
}

// 0 = no night, 1 = full night
float nightFactor(float h) {
    return 1.0 - smoothstep(-0.30, -0.05, h);
}

// 0..1 bump centered on the sunrise/sunset band
float twilightFactor(float h) {
    return clamp(1.0 - dayFactor(h) - nightFactor(h), 0.0, 1.0);
}

vec3 getDayNightSunColor(float h) {
    vec3 dayColor    = vec3(1.00, 0.97, 0.90);
    vec3 sunsetColor = vec3(1.00, 0.55, 0.22);
    vec3 nightColor  = vec3(0.40, 0.50, 0.85);
    return dayColor * dayFactor(h) + sunsetColor * twilightFactor(h) + nightColor * nightFactor(h);
}

vec3 getSkyAmbient(float h) {
    vec3 day    = vec3(0.55, 0.72, 1.00);
    vec3 sunset = vec3(0.55, 0.40, 0.48);
    vec3 night  = vec3(0.05, 0.07, 0.13);
    return day * dayFactor(h) + sunset * twilightFactor(h) + night * nightFactor(h);
}

// ---------------------------------------------------------------------------
// Distance fog, using vanilla's own fixed-function fog state (gl_Fog),
// which Iris/OptiFine keep populated with the correct render-distance /
// biome / water / lava / blindness fog values in every #version 120 stage.
// ---------------------------------------------------------------------------

vec3 applyFog(vec3 color, vec3 viewPos) {
    float dist = length(viewPos);
    float fogFactor = clamp((dist - gl_Fog.start) / max(gl_Fog.end - gl_Fog.start, 1.0), 0.0, 1.0);
    fogFactor *= fogFactor;
    return mix(color, gl_Fog.color.rgb, fogFactor);
}

// ---------------------------------------------------------------------------
// Shadows
//
// distortShadowClip() warps the shadow-map clip position so that resolution
// is concentrated close to the player. It MUST be applied identically here
// and in shadow.vsh, which is why it lives in this shared file instead of
// being duplicated.
// ---------------------------------------------------------------------------

vec3 distortShadowClip(vec3 pos) {
    float factor = length(pos.xy) + 0.10;
    return vec3(pos.xy / factor, pos.z * 0.5);
}

float sampleShadow(vec3 viewPos, vec3 normal) {
#ifdef SHADOW_ENABLED
    vec3 scenePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    // normal is in VIEW space; rotate it into the same (unrotated) scene
    // space as scenePos before using it as an offset, otherwise the anti-acne
    // bias points the wrong way whenever the camera isn't at the default
    // orientation.
    vec3 sceneNormal = normalize(mat3(gbufferModelViewInverse) * normal);
    scenePos += sceneNormal * 0.06; // normal offset to fight shadow acne

    vec4 shadowClip = shadowProjection * (shadowModelView * vec4(scenePos, 1.0));
    shadowClip.xyz = distortShadowClip(shadowClip.xyz);
    vec3 shadowScreen = shadowClip.xyz * 0.5 + 0.5;

    if (shadowScreen.x < 0.0 || shadowScreen.x > 1.0 ||
        shadowScreen.y < 0.0 || shadowScreen.y > 1.0 ||
        shadowScreen.z < 0.0 || shadowScreen.z > 1.0) {
        return 1.0;
    }

    // shadowtex0 is a shadow sampler (shadowHardwareFiltering = true above),
    // so each shadow2D() tap is already a free hardware-bilinear 2x2 PCF -
    // the loop below only decides how many of those (already soft) taps to
    // blend, which is what actually costs performance.
    float texel = 1.0 / float(shadowMapResolution);
    float refZ = shadowScreen.z - 0.0012;
    float lit;

#if SHADOW_QUALITY <= 0
    lit = shadow2D(shadowtex0, vec3(shadowScreen.xy, refZ)).r;
#elif SHADOW_QUALITY == 1
    lit  = shadow2D(shadowtex0, vec3(shadowScreen.xy, refZ)).r;
    lit += shadow2D(shadowtex0, vec3(shadowScreen.xy + vec2( texel, 0.0), refZ)).r;
    lit += shadow2D(shadowtex0, vec3(shadowScreen.xy + vec2(-texel, 0.0), refZ)).r;
    lit += shadow2D(shadowtex0, vec3(shadowScreen.xy + vec2(0.0,  texel), refZ)).r;
    lit += shadow2D(shadowtex0, vec3(shadowScreen.xy + vec2(0.0, -texel), refZ)).r;
    lit *= 0.2;
#else
    lit = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            lit += shadow2D(shadowtex0, vec3(shadowScreen.xy + vec2(float(x), float(y)) * texel, refZ)).r;
        }
    }
    lit *= (1.0 / 9.0);
#endif

    // Fade to fully lit over the last 20% of shadowDistance instead of
    // hard-cutting to "always lit" right at the boundary, which would
    // otherwise show up as a visible brightness ring at that distance.
    float distFade = smoothstep(shadowDistance * 0.8, shadowDistance, length(viewPos));
    return mix(lit, 1.0, distFade);
#else
    return 1.0;
#endif
}

// ---------------------------------------------------------------------------
// Shared lighting model used by terrain / water / entities / hand.
// shadowTerm is passed in explicitly (rather than always sampled here) so
// gbuffers_hand can skip the shadow-map lookup, whose matrices are not
// reliable for the hand's special projection.
// ---------------------------------------------------------------------------

vec3 shadeLitCustom(vec3 albedo, vec3 N, vec3 viewPos, vec2 lmcoord, float shadowTerm) {
    float h = sunHeight();
    vec3 L = normalize(shadowLightPosition);
    float NdotL = max(dot(N, L), 0.0);

    vec3 sunColor = getDayNightSunColor(h);
    float dirStrength = mix(0.20, 1.35, dayFactor(h));
    vec3 directLight = sunColor * NdotL * shadowTerm * dirStrength;

    vec3 skyLight = getSkyAmbient(h) * AMBIENT_STRENGTH * (lmcoord.y * lmcoord.y);
    vec3 torchLight = vec3(1.0, 0.58, 0.28) * pow(max(lmcoord.x, 0.0), 2.6) * 3.0 * TORCH_INTENSITY;

    vec3 wetTint = mix(vec3(1.0), vec3(0.78, 0.82, 0.92), rainStrength * 0.6);

    return albedo * (directLight + skyLight + torchLight + vec3(0.02)) * wetTint;
}

vec3 shadeLit(vec3 albedo, vec3 N, vec3 viewPos, vec2 lmcoord) {
    return shadeLitCustom(albedo, N, viewPos, lmcoord, sampleShadow(viewPos, N));
}

// ---------------------------------------------------------------------------
// Procedural, twinkling star field (used by composite.fsh's sky pass).
// hash13/hash12 below: Dave Hoskins, "Hash without Sine",
// https://www.shadertoy.com/view/4djSRW - a small, widely reused public hash
// snippet, credited here for consistency with ditherPattern()'s credit below.
// ---------------------------------------------------------------------------

float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

// density is the approximate FRACTION of cells that light up as a star
// (e.g. 0.02 = ~2% of cells) - bigger density value = more stars.
float starField(vec3 dir, float density, float sharpness) {
    vec3 p = dir * 400.0;
    vec3 cell = floor(p);
    float star = hash13(cell);
    float mask = step(1.0 - density, star);

    vec3 f = fract(p) - 0.5;
    float d = length(f);
    float twinkle = 0.6 + 0.4 * sin(frameTimeCounter * (1.5 + star * 3.0) + star * 30.0);

    return mask * (1.0 - smoothstep(0.0, sharpness, d)) * twinkle;
}

// ---------------------------------------------------------------------------
// Cheap 2D value noise (used by composite.fsh's procedural cloud plane).
// Self-contained - no noise texture asset needed.
// ---------------------------------------------------------------------------

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fixed 3-octave fbm - same cost on every pixel/GPU, no dynamic loop count.
float cloudFbm(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 3; i++) {
        sum += valueNoise(p) * amp;
        p = p * 2.03 + 11.0;
        amp *= 0.5;
    }
    return sum;
}

// ---------------------------------------------------------------------------
// Interleaved-gradient-noise dither (Jimenez, "Next Generation Post
// Processing in Call of Duty: Advanced Warfare", 2014) - a small, widely
// published per-pixel noise pattern used to break up banding in gradients
// (sky, fog, bloom) for close to no cost.
// ---------------------------------------------------------------------------

float ditherPattern(vec2 fragCoord) {
    return fract(52.9829189 * fract(dot(fragCoord, vec2(0.06711056, 0.00583715))));
}

#endif // AURORA_COMMON_GLSL
