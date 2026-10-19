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
#define AURORA_COMMON_GLSL 1 // include guard (valued, so Iris/OptiFine never list it as an on/off option)

// Which dimension this program was compiled for. Set by the thin wrapper
// files: shaders/ (Overworld, and any modded dimension) = 0,
// shaders/world-1/ (Nether) = -1, shaders/world1/ (The End) = 1.
// Iris/OptiFine load a dimension folder as its own, complete program set -
// they do NOT fall back to shaders/ for files missing from it - which is why
// every stage has a wrapper in each folder and its real code in program/.
#ifndef AURORA_WORLD
    #define AURORA_WORLD 0
#endif

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

// Whether THIS program actually uses a shadow map: the option above, except
// in the Nether, which has no sun. Tested with a plain #ifdef on purpose -
// Iris/OptiFine only list an on/off option in the menu if some #ifdef/#ifndef
// asks for it - and given a value, so it never shows up as an option itself.
#ifdef SHADOW_ENABLED
    #if AURORA_WORLD != -1
        #define AURORA_SHADOWS 1
    #endif
#endif

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

#define HELD_LIGHT // Holding a torch, lantern, glowstone, ... in either hand lights up the area around you.
#define EMISSION_STRENGTH 1.5 // [0.0 0.5 1.0 1.5 2.0 3.0] How strongly light-emitting blocks (lava, glowstone, torch flames, ...) glow. 0 = vanilla look.

#define WAVING_PLANTS // Grass, flowers, crops and leaves sway in the wind (their shadows too). Off in the Potato profile.
#define WAVING_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define WAVING_SPEED 1.0    // [0.5 0.75 1.0 1.5 2.0]

const float PI = 3.14159265359;

// ---------------------------------------------------------------------------
// Block IDs, assigned in shaders/block.properties - keep both in sync.
// Read in vertex shaders as int(mc_Entity.x + 0.5). Only these exact,
// positive IDs mean anything: blocks not listed there, block entities
// (chests, signs, ...) and the breaking-block overlay all arrive as 0 or -1.
// ---------------------------------------------------------------------------

const int ID_PLANT          = 100; // rooted ground plants: only the top edge sways
const int ID_PLANT_UPPER    = 101; // upper half of 2-block plants: both edges sway, the top one more
const int ID_LEAVES         = 102; // leaf blocks: the whole block sways gently
const int ID_FOLIAGE_STATIC = 103; // thin plants that should be lit like foliage but must not move (vines, ...)
const int ID_EMISSIVE       = 200; // the whole block glows (glowstone, lava, sea lantern, ...)
const int ID_EMISSIVE_LIGHT = 201; // only the bright pixels glow (torch flames, lantern glass, fire, ...)
const int ID_WATER          = 300;

// ---------------------------------------------------------------------------
// Uniforms shared by (almost) every stage
// ---------------------------------------------------------------------------

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

// The matrices are declared unconditionally (an unused uniform costs
// nothing) because shadow.vsh needs them for waving plants in every
// profile; only the shadow map sampler itself is tied to shadows being on.
// The Nether has no sun, so it neither renders (no shadow program in
// world-1/) nor samples a shadow map.
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
#ifdef AURORA_SHADOWS
    uniform sampler2DShadow shadowtex0;
#endif

uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform vec3 cameraPosition;
uniform vec3 fogColor;

uniform float rainStrength;
uniform float frameTimeCounter;
uniform float blindness;
uniform float darknessFactor;
uniform int isEyeInWater;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

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

// The plain sky gradient for a VIEW-SPACE direction: no sun disc, stars,
// aurora or clouds (those are added on top by renderSky() in sky.glsl).
// Lives here rather than in sky.glsl because applyFog() below also uses it
// as the distance-fog color, so far terrain fades into exactly the sky that
// composite.fsh paints behind it instead of into vanilla's flat fog color.
vec3 skyGradient(vec3 dir) {
    vec3 up = normalize(upPosition);
    float upness = dot(dir, up);

#if AURORA_WORLD == 1
    // The End: a deep violet void, a little lighter toward the horizon.
    float tEnd = clamp(upness * 0.5 + 0.5, 0.0, 1.0);
    return mix(vec3(0.10, 0.06, 0.14), vec3(0.025, 0.015, 0.05), tEnd);
#else
    float h = sunHeight();
    float day = dayFactor(h);
    float twilight = twilightFactor(h);

    vec3 zenith  = mix(vec3(0.02, 0.03, 0.08), vec3(0.30, 0.50, 0.85), day);
    vec3 horizon = mix(vec3(0.10, 0.11, 0.18), vec3(0.75, 0.85, 1.00), day);
    horizon = mix(horizon, vec3(1.00, 0.55, 0.25), twilight * 0.85);

    // How close this ray is to the true horizon (dot(dir, up) == 0), biased
    // toward the zenith with a gentle power curve for a nicer gradient.
    float t = clamp(upness * 0.5 + 0.5, 0.0, 1.0);
    vec3 sky = mix(horizon, zenith, pow(t, 0.45));

    // Sunrise/sunset: a warm glow low on the horizon, strongest on the side
    // of the sky the sun is actually on instead of all the way around.
    float towardSun = max(dot(dir, normalize(sunPosition)), 0.0);
    float nearHorizon = 1.0 - abs(upness);
    sky += vec3(1.00, 0.42, 0.12) * (twilight * towardSun * towardSun * towardSun * nearHorizon * nearHorizon * 0.8);

    // Overcast: rain washes the sky out toward a darker grey.
    sky = mix(sky, vec3(luma(sky) * 0.65), rainStrength * 0.75);
    return sky;
#endif
}

// ---------------------------------------------------------------------------
// Distance fog, using vanilla's own fixed-function fog state (gl_Fog) for
// the fog DISTANCES, which Iris/OptiFine keep populated with the correct
// render-distance / water / lava / blindness values in every #version 120
// stage. In open air (Overworld/End) the fog COLOR is replaced by the custom
// sky's own color for this view direction, so distant terrain melts into
// the sky behind it with no visible seam.
// ---------------------------------------------------------------------------

vec3 applyFog(vec3 color, vec3 viewPos) {
    float dist = length(viewPos);
    float fogFactor = clamp((dist - gl_Fog.start) / max(gl_Fog.end - gl_Fog.start, 1.0), 0.0, 1.0);
    fogFactor *= fogFactor;

    vec3 fogCol = gl_Fog.color.rgb;
#if AURORA_WORLD != -1
    // Underwater / in lava / in powder snow, keep vanilla's own fog color.
    // Blindness and Darkness fade the fog back to vanilla's (black) color.
    if (isEyeInWater == 0) {
        vec3 skyCol = skyGradient(viewPos / max(dist, 0.0001));
        fogCol = mix(skyCol, gl_Fog.color.rgb, clamp(max(blindness, darknessFactor), 0.0, 1.0));
    }
#endif
    return mix(color, fogCol, fogFactor);
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
#ifdef AURORA_SHADOWS
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
// Waving plants. windOffset() depends ONLY on a vertex's absolute world
// position, the time and the block ID, so gbuffers_terrain.vsh and
// shadow.vsh (which must move every vertex by exactly the same amount, or
// shadows would crawl against their casters) agree, and two vertices that
// share a world position - the seam between the two halves of a tall
// flower, the corners of neighbouring leaf blocks - always stay glued.
// ---------------------------------------------------------------------------

// How strongly a vertex sways (0 = it doesn't). topVertex: true for the
// upper edge of the block's texture, i.e.  gl_MultiTexCoord0.t < mc_midTexCoord.t.
float waveAmount(int blockId, bool topVertex) {
#ifdef WAVING_PLANTS
    if (blockId == ID_PLANT)       return topVertex ? 1.0 : 0.0;
    if (blockId == ID_PLANT_UPPER) return topVertex ? 2.0 : 1.0;
    if (blockId == ID_LEAVES)      return 0.55;
#endif
    return 0.0;
}

// A small, self-written sum of sines: two crossing sways plus a slow,
// world-position-dependent "gust" envelope so not every plant moves in sync.
vec3 windOffset(vec3 worldPos, float amount) {
    // Fold the phase input into a moderate range: far from the world origin
    // a raw coordinate times a frequency loses so much float precision that
    // the motion turns into jitter. Unlike the cloud plane's continuous noise
    // a wrap is invisible here - every plant sways on its own, so it only
    // shifts which plant is in which phase, it doesn't tear a surface.
    vec3 p = mod(worldPos, 1024.0);
    float t = frameTimeCounter * WAVING_SPEED;

    float gust  = 0.6 + 0.4 * sin(t * 0.37 + p.x * 0.045 + p.z * 0.060);
    float swayX = sin(t * 1.70 + p.x * 0.63 + p.z * 0.29 + p.y * 0.21) + 0.35 * sin(t * 3.90 + p.z * 1.37);
    float swayZ = sin(t * 1.45 + p.z * 0.71 - p.x * 0.33 + p.y * 0.17) + 0.35 * sin(t * 3.30 + p.x * 1.21);

    float strength = 0.055 * WAVING_STRENGTH * (1.0 + rainStrength * 0.9);
    return vec3(swayX, 0.0, swayZ) * (gust * strength * amount);
}

// ---------------------------------------------------------------------------
// Per-block material flags, computed once per vertex and passed on as
// varyings (every vertex of a block has the same ID, so they interpolate
// to exactly that constant).
// ---------------------------------------------------------------------------

float foliageOf(int blockId) {
    return (blockId >= ID_PLANT && blockId <= ID_FOLIAGE_STATIC) ? 1.0 : 0.0;
}

// 0 = not emissive, 1 = the whole block glows, 2 = only its bright pixels glow.
float emissiveKindOf(int blockId) {
    if (blockId == ID_EMISSIVE)       return 1.0;
    if (blockId == ID_EMISSIVE_LIGHT) return 2.0;
    return 0.0;
}

// Extra HDR light a glowing block gives off on its own, ON TOP of the
// regular lighting. Pushing these pixels above 1.0 is also what makes
// composite1.fsh's bloom pick them up.
vec3 blockEmission(vec3 albedo, float emissiveKind) {
    if (emissiveKind < 0.5) return vec3(0.0);
    float mask = 1.0;
    if (emissiveKind > 1.5) {
        // Torch sticks, lantern frames, ... stay dark; only the bright
        // flame/light pixels of the texture glow.
        mask = smoothstep(0.55, 0.85, max(albedo.r, max(albedo.g, albedo.b)));
    }
    return albedo * (mask * EMISSION_STRENGTH);
}

// ---------------------------------------------------------------------------
// Shared lighting model used by terrain / water / entities / hand.
// ---------------------------------------------------------------------------

// How much open sky a surface sees, from vanilla's skylight level (0 in
// caves, and everywhere in the Nether and the End). Keeps direct sun/moon
// light out of caves: without it any cave wall facing the sun would light
// up whenever the shadow map can't catch the occluder - beyond
// shadowDistance, and always on the Potato profile (no shadow map at all).
float skyAccess(vec2 lmcoord) {
    return smoothstep(0.15, 0.55, lmcoord.y);
}

// foliage = 1: thin, translucent plants and leaves. Crossed plant quads have
// sideways normals, so plain N.L would leave half of every grass tuft black;
// instead they take light from either side, with a floor for the light that
// shines through them.
float diffuseTerm(vec3 N, vec3 L, float foliage) {
    float NdotL = dot(N, L);
    return mix(max(NdotL, 0.0), 0.45 + 0.55 * abs(NdotL), foliage);
}

// Light from a light-emitting item held in either hand, in the same 0..1
// units as lmcoord.x, with vanilla's falloff of one light level per block.
float heldLightLevel(vec3 viewPos) {
#ifdef HELD_LIGHT
    // Some loaders report out-of-range values for non-light items - clamp
    // to vanilla's 0..15 range.
    float level = clamp(max(float(heldBlockLightValue), float(heldBlockLightValue2)), 0.0, 15.0);
    return clamp((level - length(viewPos)) / 15.0, 0.0, 1.0);
#else
    return 0.0;
#endif
}

// shadowTerm is passed in explicitly (rather than always sampled here) so
// gbuffers_hand can skip the shadow-map lookup, whose matrices are not
// reliable for the hand's special projection, and so gbuffers_water can
// reuse it for its sun highlight.
vec3 shadeLitCustom(vec3 albedo, vec3 N, vec3 viewPos, vec2 lmcoord, float shadowTerm, float foliage) {
    vec3 L = normalize(shadowLightPosition);
    float diffuse = diffuseTerm(N, L, foliage);

    float blockLight = max(lmcoord.x, heldLightLevel(viewPos));
    vec3 torchLight = vec3(1.0, 0.58, 0.28) * pow(max(blockLight, 0.0), 2.6) * 3.0 * TORCH_INTENSITY;

#if AURORA_WORLD == -1
    // Nether: no sun, no sky - a warm, dim ambient so the dimension isn't
    // pitch black away from lava and glowstone.
    vec3 light = vec3(0.32, 0.22, 0.18) * AMBIENT_STRENGTH + torchLight;
#elif AURORA_WORLD == 1
    // The End: a pale violet light from above (the End has no skylight, so
    // no skyAccess gate here) over a cool violet ambient.
    vec3 directLight = vec3(0.62, 0.52, 0.85) * (0.75 * diffuse * shadowTerm);
    vec3 light = directLight + vec3(0.20, 0.16, 0.28) * AMBIENT_STRENGTH + torchLight;
#else
    float h = sunHeight();
    vec3 sunColor = getDayNightSunColor(h);
    float dirStrength = mix(0.20, 1.35, dayFactor(h));
    vec3 directLight = sunColor * (diffuse * shadowTerm * dirStrength * skyAccess(lmcoord));

    vec3 skyLight = getSkyAmbient(h) * AMBIENT_STRENGTH * (lmcoord.y * lmcoord.y);
    vec3 wetTint = mix(vec3(1.0), vec3(0.78, 0.82, 0.92), rainStrength * 0.6);

    vec3 light = (directLight + skyLight + torchLight + vec3(0.02)) * wetTint;
#endif

    return albedo * light;
}

vec3 shadeLit(vec3 albedo, vec3 N, vec3 viewPos, vec2 lmcoord, float foliage) {
    float shadowTerm = 1.0;
#ifdef AURORA_SHADOWS
    vec3 L = normalize(shadowLightPosition);
    // Only pay for the shadow-map lookup where it can change anything: not
    // on faces turned away from the light, and (Overworld) not where the
    // skylight gate already removes all direct light anyway.
    bool needShadow = diffuseTerm(N, L, foliage) > 0.0;
    #if AURORA_WORLD == 0
        needShadow = needShadow && skyAccess(lmcoord) > 0.0;
    #endif
    if (needShadow) {
        // Offset foliage toward the light, whichever side is being lit, so a
        // back-lit leaf or grass quad isn't shadowed by itself.
        vec3 shadowN = (foliage > 0.5 && dot(N, L) < 0.0) ? -N : N;
        shadowTerm = sampleShadow(viewPos, shadowN);
    }
#endif
    return shadeLitCustom(albedo, N, viewPos, lmcoord, shadowTerm, foliage);
}

// ---------------------------------------------------------------------------
// Procedural, twinkling star field (used by sky.glsl).
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
// Cheap 2D value noise (used by sky.glsl's cloud plane, aurora and End sky).
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
