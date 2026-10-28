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
const int colortex2Format = RGBA16;
const int colortex3Format = R8;
const int colortex4Format = RGBA16F;
*/

// colortex2: what the post passes need to know about each opaque/water pixel
// (written by terrain, entities, hand and water - see writeSurface() below):
// rg = view-space normal (octahedral), b = vanilla skylight, a = material.
// Cleared to 0 every frame, which reads back as "nothing here" (sky).
// colortex1 is avoided on purpose: it carries legacy "gdepth" defaults.
// colortex3: raw ambient occlusion from deferred.fsh, blurred in deferred1.fsh.
// colortex4: the TAA history (last frame's anti-aliased picture, written by
// composite2.fsh). Never cleared - it has to survive into the next frame.
const bool colortex2Clear = true;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex4Clear = false;

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

// Tilts the path of the sun and moon away from straight overhead (degrees).
// With 0 the sun crosses exactly east-west through the zenith, so at noon
// every shadow falls straight down and block edges line up with the shadow
// map's texels; a tilt gives shadows a direction all day long. Read by the
// pack loader like shadowMapResolution, and everything here works from
// sunPosition/shadowLightPosition, so sky, light and shadows all follow it.
const float sunPathRotation = -30.0; // [-50.0 -40.0 -30.0 -20.0 -10.0 0.0 10.0 20.0 30.0 40.0 50.0]

// How fast `wetness` (below) follows the rain, in ticks: soaked within about
// half a minute of rain, dry again a few minutes after it stops, so puddles
// and the rainbow outlast the rain itself. Pack-loader constants as well.
const float wetnessHalflife = 300.0;
const float drynessHalflife = 1000.0;

#define SUN_INTENSITY 1.0    // [0.6 0.8 1.0 1.2 1.4 1.6] Strength of direct sunlight against the shadows.
#define AMBIENT_STRENGTH 1.0 // [0.6 0.8 1.0 1.2 1.4]
#define TORCH_INTENSITY 1.0  // [0.6 0.8 1.0 1.2 1.5]
#define ATMOSPHERIC_FOG 1.0  // [0.0 0.5 1.0 1.5 2.0] Light haze over distant land (thicker at sunrise/sunset and in rain). 0 = off.

#define SSAO // Ambient occlusion: corners, gaps and the ground under things get softly darker. Off in the Low and Potato profiles.
#define SSAO_STRENGTH 0.6 // [0.3 0.45 0.6 0.75 0.9 1.0] On top of vanilla's own smooth-lighting shadows in corners, so keep it moderate.

#define WATER_FOG // Water gets clearer in the shallows and darker blue-green the deeper you look into it. Off in the Potato profile.
#define WATER_FOG_DENSITY 0.12 // [0.05 0.08 0.12 0.18 0.25]
#define SCREEN_SPACE_REFLECTIONS // Water, shiny blocks and puddles mirror the land around them (trees, hills, buildings), not only the sky. Off in the Low and Potato profiles.
#define REFLECTIVE_BLOCKS // Polished stone, quartz, ice, obsidian, glazed terracotta, gem and metal blocks shine and reflect; puddles too. Off in the Potato profile.

#define TEMPORAL_AA // Temporal anti-aliasing: blends every frame with the previous ones for smooth edges, calm leaves and noise-free shadows, clouds and reflections. Off in the Low and Potato profiles.
#define TAA_BLEND 0.9      // [0.8 0.85 0.9 0.94] How much of the previous frames is kept: higher = smoother, but more smearing on fast movement.
#define TAA_SHARPNESS 0.3  // [0.0 0.15 0.3 0.45 0.6] Sharpens the picture again after TAA's slight softening.

// Program-side switches derived from the options above. Valued, so they
// never show up as options themselves; each option is still asked for with
// a plain #ifdef right here, which is how Iris/OptiFine find on/off options.
#ifdef SSAO
    #define AURORA_SSAO 1
#endif
#ifdef WATER_FOG
    #define AURORA_WATER_FOG 1
#endif
#ifdef SCREEN_SPACE_REFLECTIONS
    #define AURORA_SSR 1
#endif
#ifdef REFLECTIVE_BLOCKS
    #define AURORA_SHINY_BLOCKS 1
#endif
#ifdef TEMPORAL_AA
    #define AURORA_TAA 1
#endif

#define HELD_LIGHT // Holding a torch, lantern, glowstone, ... in either hand lights up the area around you.
#define EMISSION_STRENGTH 1.5 // [0.0 0.5 1.0 1.5 2.0 3.0] How strongly light-emitting blocks (lava, glowstone, torch flames, ...) glow. 0 = vanilla look.
//#define GLOWING_ORES // The colored crystals in Overworld ores (iron, copper, gold, redstone, lapis, emerald, diamond) glow faintly. Off by default.

#define WAVING_PLANTS // Grass, flowers, crops and leaves sway in the wind (their shadows too). Off in the Potato profile.
#define WAVING_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define WAVING_SPEED 1.0    // [0.5 0.75 1.0 1.5 2.0]

// The cloud layer's options live here rather than in sky.glsl because the
// lighting below needs the exact same clouds for their shadows.
#define ENABLE_CLOUDS // A single, cheap procedural cloud layer. Off in the Potato profile.
#define CLOUD_HEIGHT 180.0    // [120.0 150.0 180.0 220.0 260.0]  world Y of the cloud plane
#define CLOUD_COVERAGE 0.55   // [0.3 0.4 0.45 0.5 0.55 0.6 0.7]  higher = more sky covered
#define CLOUD_SPEED 1.0       // [0.0 0.5 1.0 1.5 2.0]
#define CLOUD_SHADOWS // Clouds cast big, slowly drifting shadows on the land. Needs the clouds. Off in the Low and Potato profiles.
#define CLOUD_STYLE 0 // [0 1] 0 = blocky clouds like Minecraft's (12x12 cells, 4 blocks thick), 1 = soft clouds (a flat layer, or 3D with VOLUMETRIC_CLOUDS)

// The look of the sky. Iris/OptiFine merge equally named options pack-wide,
// so these live here once; sky.glsl uses them too.
#define SKY_STYLE 0 // [0 1] 0 = Minecraft: square, pixelated sun and moon and square stars; 1 = realistic: round sun and moon, twinkling stars
#define VANILLA_SKY_COLORS // The sky and fog take Minecraft's own colors, biome by biome (off = Aurora Nights' own sky gradient).
#ifdef VANILLA_SKY_COLORS
    #define AURORA_VANILLA_SKY 1
#endif

#define RAIN_PUDDLES // Rain darkens the ground under the open sky and leaves puddles that mirror the sky, drying up slowly afterwards. Off in the Potato profile.
#define MOON_PHASE_INFLUENCE 0.5 // [0.0 0.25 0.5 0.75 1.0] How much darker moonlight gets toward new moon. 0 = every night is as bright as full moon.
#define UNDERWATER_CAUSTICS // While you're under water, sunlight on everything around you ripples like light through waves.

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
const int ID_ORE            = 202; // ores: only the colored crystals glow, and only with GLOWING_ORES
const int ID_WATER          = 300;
const int ID_POLISHED       = 400; // polished stone, quartz, prismarine bricks: a faint, blurry sheen
const int ID_GLOSSY         = 401; // ice, obsidian, glazed terracotta: clearly glossy
const int ID_GEM            = 402; // diamond, emerald, amethyst blocks: very shiny
const int ID_METAL          = 403; // iron, gold, copper, netherite, ...: metal, tints its reflection

// Material codes in colortex2.a (stored as code / 10).
const int MAT_NONE    = 0; // nothing drawn here: sky
const int MAT_SOLID   = 2; // blocks and entities
const int MAT_FOLIAGE = 3; // plants and leaves
const int MAT_HAND    = 4; // first-person hand/item: special projection, skipped by SSAO/reflections/TAA
const int MAT_GLASS   = 5; // stained glass, ice, slime, ... (translucent, nothing special)
const int MAT_WATER   = 6;
// Shiny surfaces carry their shininess in the same channel:
// 0.70..0.84 = shiny non-metal (codes 7-8), 0.86..1.00 = metal (codes 9-10).
// See shinySurfaceData() / shineOf() further down.
const int MAT_SHINY   = 7;
const int MAT_METAL   = 9;

// ---------------------------------------------------------------------------
// Uniforms shared by (almost) every stage
// ---------------------------------------------------------------------------

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

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
uniform vec3 skyColor; // vanilla's sky color right now (biome, time of day and weather included)

uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;

uniform float rainStrength;
uniform float wetness;   // rainStrength smoothed by wetnessHalflife/drynessHalflife above
uniform float rainBiome; // custom uniform from shaders.properties: 1 where it really rains
uniform float frameTimeCounter;
uniform float blindness;
uniform float darknessFactor;
uniform ivec2 eyeBrightnessSmooth; // smoothed light level at the camera, 0..240 (x = block, y = sky)
uniform int isEyeInWater;
uniform int moonPhase;   // 0 = full moon, 1-3 waning, 4 = new moon, 5-7 waxing
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
    vec3 dayColor    = vec3(1.00, 0.93, 0.82); // warm sunlight against the cool sky light below
    vec3 sunsetColor = vec3(1.00, 0.52, 0.20);
    vec3 nightColor  = vec3(0.42, 0.52, 0.88);
    return dayColor * dayFactor(h) + sunsetColor * twilightFactor(h) + nightColor * nightFactor(h);
}

vec3 getSkyAmbient(float h) {
    vec3 day    = vec3(0.48, 0.64, 0.98);
    vec3 sunset = vec3(0.52, 0.38, 0.50);
    vec3 night  = vec3(0.05, 0.07, 0.14);
    return day * dayFactor(h) + sunset * twilightFactor(h) + night * nightFactor(h);
}

// Lit fraction of the moon's face: 1 at full moon, 0 at new moon.
float moonIllumination() {
    return 0.5 + 0.5 * cos(float(moonPhase) * (PI / 4.0));
}

// Scales direct light by the moon phase at night (1.0 by day, so it can
// simply multiply getDayNightSunColor() wherever that is the light color).
float moonDimming(float h) {
    float moon = 1.0 - MOON_PHASE_INFLUENCE * (1.0 - moonIllumination());
    return mix(1.0, moon, nightFactor(h));
}

// The plain sky gradient for a VIEW-SPACE direction: no sun disc, stars,
// aurora or clouds (those are added on top by renderSky() in sky.glsl).
// Lives here rather than in sky.glsl because applyFog() below also uses it
// as the distance-fog color, so far terrain fades into exactly the sky that
// composite.fsh paints behind it instead of into vanilla's flat fog color.
// The HDR scene color that ends up on screen as `display` after
// composite1's exposure (1.05), ACES tonemap and saturation (1.12) at their
// default values: those three are undone here, in reverse order (the ACES
// curve's inverse is the positive root of a quadratic). Used to put
// Minecraft's own sky colors on screen as Minecraft shows them - fed in
// directly, the tonemap would wash its blue out to a pale grey-blue.
// Capped at 0.8 on screen (scaled down evenly to keep the hue, half of it
// clipped to keep the brightness), which keeps the scene value under 1.0:
// a brighter sky would make the whole picture bloom.
vec3 fromDisplay(vec3 display) {
    float brightest = max(display.r, max(display.g, display.b));
    vec3 c = mix(display * min(1.0, 0.8 / max(brightest, 0.0001)), min(display, vec3(0.8)), 0.5);
    float l = luma(c);
    c = max(vec3(l) + (c - l) / 1.12, 0.0);
    vec3 a = c * 2.43 - 2.51;
    vec3 b = c * 0.59 - 0.03;
    vec3 e = c * 0.14;
    vec3 x = (-b - sqrt(max(b * b - 4.0 * a * e, 0.0))) / (2.0 * a);
    return x / 1.05;
}

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

#ifdef AURORA_VANILLA_SKY
    // Minecraft's own colors: its sky color overhead, its fog color at the
    // horizon - so every biome keeps its own sky (and rain darkens it the
    // way vanilla does, already included in both). Not under water, in lava
    // or in powder snow, where vanilla's fog color turns into that
    // material's color: there the gradient below takes over.
    if (isEyeInWater == 0) {
        float overhead = smoothstep(-0.05, 0.35, upness);
        vec3 vanillaSky = mix(fromDisplay(fogColor), fromDisplay(skyColor), overhead);

        // Minecraft's sunrise/sunset glow: warm, on the side of the sun,
        // fading upward.
        float towardSunV = max(dot(dir, normalize(sunPosition)), 0.0);
        float lowSky = 1.0 - smoothstep(0.0, 0.45, abs(upness));
        return vanillaSky + vec3(0.85, 0.32, 0.08) * (twilight * towardSunV * towardSunV * lowSky * 0.6);
    }
#endif

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

    #if AURORA_WORLD == 0
        // Aerial perspective: on top of vanilla's fog at the edge of the
        // render distance, a thin haze already starts close by, so hills
        // further away look further away. Thicker around sunrise/sunset and
        // in rain. Not while the camera is in a cave (judged by how much sky
        // it has seen lately) - the haze has the sky's color.
        float h = sunHeight();
        float density = 0.0012 * ATMOSPHERIC_FOG * (1.0 + 1.5 * twilightFactor(h) + 2.0 * rainStrength);
        float haze = (1.0 - exp(-dist * density)) * 0.85;
        haze *= smoothstep(0.2, 0.7, float(eyeBrightnessSmooth.y) / 240.0);
        fogFactor = 1.0 - (1.0 - fogFactor) * (1.0 - haze);
    #endif
    }
#endif
    return mix(color, fogCol, fogFactor);
}

// ---------------------------------------------------------------------------
// Cheap 2D value noise (clouds and their shadows, aurora, End sky, puddles,
// caustics). Self-contained - no noise texture asset needed.
// hash12: Dave Hoskins, "Hash without Sine" (credited at hash13 below).
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

// Blocky clouds (CLOUD_STYLE 0): like Minecraft's, the cloud layer is a
// grid of 12x12-block cells, each either cloud or clear, drifting slowly
// along +X. A coarse noise field groups the cells into irregular clouds of a
// few cells across, a per-cell hash frays their outlines. Rain fills the sky.
const float blockCloudCell = 12.0;
const float blockCloudThickness = 4.0;

// How far the cloud grid has drifted (blocks, X only).
float blockCloudDrift() {
    return frameTimeCounter * CLOUD_SPEED * 0.6;
}

// 1.0 if the cell with this integer index is cloud.
float blockCloudCellCover(vec2 cell) {
    float n = valueNoise(cell * 0.18) * 0.75 + hash12(cell) * 0.25;
    float threshold = 1.0 - min(CLOUD_COVERAGE * 0.75 + rainStrength * 0.3, 0.9);
    return step(threshold, n);
}

// How much cloud covers the cloud plane at this world XZ position (0 = clear
// sky, 1 = solid cloud). The one definition of the clouds' shape: sky.glsl
// draws exactly this, and cloudShadow() below darkens the ground under it.
float cloudCoverage(vec2 worldXZ) {
#if CLOUD_STYLE == 0
    return blockCloudCellCover(floor((worldXZ - vec2(blockCloudDrift(), 0.0)) / blockCloudCell));
#else
    // NOT wrapped/mod()'d: a hard mod() would leave a visible seam wherever
    // it wraps, since the noise isn't periodic there. The 0.0016 scale keeps
    // the argument well under 1000 even at the ~30,000,000-block world
    // border, so float precision is no problem at this scale.
    vec2 uv = worldXZ * 0.0016 + frameTimeCounter * CLOUD_SPEED * vec2(0.006, 0.0035);
    float density = cloudFbm(uv);

    // Rain closes the cloud cover.
    float threshold = 1.0 - min(CLOUD_COVERAGE + rainStrength * 0.25, 0.95);
    return smoothstep(threshold, threshold + 0.25, density);
#endif
}

// How much direct sun/moon light gets past the cloud layer to this point
// (1 = all of it). Follows the light ray from the surface up to the cloud
// plane and looks at the cloud cover there, so the shadows line up with the
// clouds in the sky and drift with them.
float cloudShadow(vec3 viewPos) {
#ifdef ENABLE_CLOUDS
#ifdef CLOUD_SHADOWS
#if AURORA_WORLD == 0
    vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
    vec3 lightDir = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
    // A low sun would reach the cloud plane far, far away - limit how flat
    // the ray can get so the lookup stays near the player.
    float t = (CLOUD_HEIGHT - worldPos.y) / max(lightDir.y, 0.15);
    if (t > 0.0) {
        float cover = cloudCoverage(worldPos.xz + lightDir.xz * t);
        return 1.0 - cover * 0.7;
    }
#endif
#endif
#endif
    return 1.0;
}

// Underwater caustics: two drifting noise fields; wherever they are nearly
// equal a thin bright line appears, which together forms the familiar
// moving net of light that waves focus onto everything under water.
float waterCaustics(vec3 viewPos) {
#ifdef UNDERWATER_CAUSTICS
    if (isEyeInWater == 1) {
        vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
        vec2 p = worldPos.xz * 0.9 + worldPos.y * 0.3;
        float t = frameTimeCounter * 0.8;
        float a = valueNoise(p + vec2(t * 0.6, t * 0.35));
        float b = valueNoise(p * 1.4 + vec2(5.3 - t * 0.45, 1.7 + t * 0.5));
        float lines = clamp(1.0 - abs(a - b) * 3.0, 0.0, 1.0);
        lines *= lines;
        lines *= lines;
        return 0.6 + lines * 1.6;
    }
#endif
    return 1.0;
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

// 0 = not emissive, 1 = the whole block glows, 2 = only its bright pixels
// glow, 3 = only its colorful pixels glow (ores).
float emissiveKindOf(int blockId) {
    if (blockId == ID_EMISSIVE)       return 1.0;
    if (blockId == ID_EMISSIVE_LIGHT) return 2.0;
#ifdef GLOWING_ORES
    if (blockId == ID_ORE)            return 3.0;
#endif
    return 0.0;
}

// How shiny a block is (block.properties IDs 400-403): 0 = matte, up to 1 =
// mirror. NEGATIVE means metal (its reflection takes on the block's color).
float shineOfBlock(int blockId) {
#ifdef AURORA_SHINY_BLOCKS
    if (blockId == ID_POLISHED) return 0.25;
    if (blockId == ID_GLOSSY)   return 0.55;
    if (blockId == ID_GEM)      return 0.7;
    if (blockId == ID_METAL)    return -0.6;
#endif
    return 0.0;
}

// Extra HDR light a glowing block gives off on its own, ON TOP of the
// regular lighting. Pushing these pixels above 1.0 is also what makes
// composite1.fsh's bloom pick them up.
vec3 blockEmission(vec3 albedo, float emissiveKind) {
    if (emissiveKind < 0.5) return vec3(0.0);
    float brightest = max(albedo.r, max(albedo.g, albedo.b));
    float mask = 1.0;
    if (emissiveKind > 2.5) {
        // Stone and deepslate are grey; the ore crystals are the only
        // colorful pixels, so glow by saturation, a little weaker than a
        // real light source.
        float darkest = min(albedo.r, min(albedo.g, albedo.b));
        mask = smoothstep(0.12, 0.30, brightest - darkest) * 0.6;
    } else if (emissiveKind > 1.5) {
        // Torch sticks, lantern frames, ... stay dark; only the bright
        // flame/light pixels of the texture glow.
        mask = smoothstep(0.55, 0.85, brightest);
    }
    return albedo * (mask * EMISSION_STRENGTH);
}

// ---------------------------------------------------------------------------
// Rain-wet ground and puddles (Overworld only - it never rains elsewhere).
// ---------------------------------------------------------------------------

// 0 = dry, 1 = soaked. Only where rain actually lands: under the open sky
// (vanilla skylight 15; under leaves it drops to 14 and below), and only in
// biomes where it rains (see rainBiome in shaders.properties).
float surfaceWetness(vec2 lmcoord) {
#if AURORA_WORLD == 0
#ifdef RAIN_PUDDLES
    return clamp(wetness * rainBiome, 0.0, 1.0) * smoothstep(0.88, 0.95, lmcoord.y);
#endif
#endif
    return 0.0;
}

// Wet materials look darker and a little more saturated; raising the color
// to a power above 1 does both at once.
vec3 wetAlbedo(vec3 albedo, float wet) {
    return pow(albedo, vec3(1.0 + 0.7 * wet));
}

// Where on an upward-facing surface the water collects (0..1). Two octaves
// of world-space noise, so the puddles stay put; the wetter it is, the more
// of the ground they cover - up to roughly a third of it.
float puddleAmount(vec3 worldPos, float wet) {
    float n = valueNoise(worldPos.xz * 0.22) * 0.65 + valueNoise(worldPos.xz * 0.85 + 3.7) * 0.35;
    float threshold = 1.0 - 0.42 * wet;
    return smoothstep(threshold, threshold + 0.06, n) * wet;
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

// Our own, softer take on vanilla's per-face shading, for the light that
// comes from all around (sky, torches, the Nether/End glow): tops get all of
// it, walls less, undersides least, east/west walls a little less than
// north/south ones like in vanilla. Vanilla's own baked version is switched
// off (oldLighting=false in shaders.properties) so it can't stack on top of
// the sun's N.L; plants keep an even, slightly dimmed value since their
// crossed quads have no meaningful facing.
float faceShade(vec3 N, float foliage) {
    vec3 w = mat3(gbufferModelViewInverse) * N;
    float side = mix(0.72, 0.85, w.z * w.z);
    float shade = w.y >= 0.0 ? mix(side, 1.0, w.y) : mix(side, 0.55, -w.y);
    return mix(shade, 0.9, foliage);
}

// shadowTerm is passed in explicitly (rather than always sampled here) so
// gbuffers_hand can skip the shadow-map lookup, whose matrices are not
// reliable for the hand's special projection, and so gbuffers_water can
// reuse it for its sun highlight.
vec3 shadeLitCustom(vec3 albedo, vec3 N, vec3 viewPos, vec2 lmcoord, float shadowTerm, float foliage) {
    vec3 L = normalize(shadowLightPosition);
    float diffuse = diffuseTerm(N, L, foliage);
    float shade = faceShade(N, foliage);

    float blockLight = max(lmcoord.x, heldLightLevel(viewPos));
    vec3 torchLight = vec3(1.0, 0.58, 0.28) * pow(max(blockLight, 0.0), 2.6) * 3.0 * TORCH_INTENSITY * shade;

#if AURORA_WORLD == -1
    // Nether: no sun, no sky - a warm, dim ambient so the dimension isn't
    // pitch black away from lava and glowstone.
    vec3 light = vec3(0.32, 0.22, 0.18) * AMBIENT_STRENGTH * shade + torchLight;
#elif AURORA_WORLD == 1
    // The End: a pale violet light from above (the End has no skylight, so
    // no skyAccess gate here) over a cool violet ambient.
    vec3 directLight = vec3(0.62, 0.52, 0.85) * (0.75 * SUN_INTENSITY * diffuse * shadowTerm * waterCaustics(viewPos));
    vec3 light = directLight + vec3(0.20, 0.16, 0.28) * AMBIENT_STRENGTH * shade + torchLight;
#else
    float h = sunHeight();
    vec3 sunColor = getDayNightSunColor(h) * moonDimming(h);
    float dirStrength = mix(0.22, 1.55, dayFactor(h)) * SUN_INTENSITY;
    float direct = diffuse * shadowTerm * dirStrength * skyAccess(lmcoord);
    // Cloud shadows and caustics only matter where direct light lands at
    // all - skip their noise lookups everywhere else.
    if (direct > 0.0) direct *= cloudShadow(viewPos) * waterCaustics(viewPos);
    vec3 directLight = sunColor * direct;

    vec3 skyLight = getSkyAmbient(h) * AMBIENT_STRENGTH * (lmcoord.y * lmcoord.y) * shade;
    vec3 wetTint = mix(vec3(1.0), vec3(0.78, 0.82, 0.92), rainStrength * 0.6);

    vec3 light = (directLight + skyLight + torchLight + vec3(0.02) * shade) * wetTint;
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

// The color deep water fades to (WATER_FOG, composite.fsh): a dark
// blue-green, lit by whatever light reaches into the water there.
vec3 waterFogColor(float skylight) {
#if AURORA_WORLD == -1
    vec3 light = vec3(0.32, 0.22, 0.18);
#elif AURORA_WORLD == 1
    vec3 light = vec3(0.30, 0.25, 0.42);
#else
    float h = sunHeight();
    vec3 light = getSkyAmbient(h) * (skylight * skylight)
               + getDayNightSunColor(h) * (moonDimming(h) * mix(0.05, 0.35, dayFactor(h)) * skylight);
#endif
    return vec3(0.05, 0.24, 0.30) * (light * AMBIENT_STRENGTH + 0.01);
}

// ---------------------------------------------------------------------------
// Surface data for the post passes (colortex2, see the top of this file).
// Normals are stored octahedrally: the unit sphere folded onto a square,
// which keeps their precision even across all directions in two channels.
// ---------------------------------------------------------------------------

vec2 encodeNormal(vec3 n) {
    n /= abs(n.x) + abs(n.y) + abs(n.z);
    if (n.z < 0.0) {
        vec2 flipSign = vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
        n.xy = (1.0 - abs(n.yx)) * flipSign;
    }
    return n.xy * 0.5 + 0.5;
}

vec3 decodeNormal(vec2 e) {
    e = e * 2.0 - 1.0;
    vec3 n = vec3(e, 1.0 - abs(e.x) - abs(e.y));
    if (n.z < 0.0) {
        vec2 flipSign = vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
        n.xy = (1.0 - abs(n.yx)) * flipSign;
    }
    return normalize(n);
}

vec4 surfaceData(vec3 N, float skylight, int material) {
    return vec4(encodeNormal(N), skylight, float(material) / 10.0);
}

int materialOf(vec4 data) {
    return int(data.a * 10.0 + 0.5);
}

// A shiny surface (block or puddle): shine 0..1, metal or not, packed into
// the material channel (see MAT_SHINY/MAT_METAL at the top). The two ranges
// keep a gap at 0.85, so 16-bit rounding can never move a value from one
// into the other.
vec4 shinySurfaceData(vec3 N, float skylight, float shine, bool metal) {
    float a = (metal ? 0.86 : 0.70) + 0.14 * clamp(shine, 0.0, 1.0);
    return vec4(encodeNormal(N), skylight, a);
}

float shineOf(vec4 data) {
    int material = materialOf(data);
    if (material < MAT_SHINY) return 0.0;
    return clamp((data.a - (material >= MAT_METAL ? 0.86 : 0.70)) / 0.14, 0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Procedural, twinkling star field (used by sky.glsl).
// hash13 below (and hash12 further up): Dave Hoskins, "Hash without Sine",
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
#if SKY_STYLE == 0
    // Minecraft: small, steady squares of slightly different brightness.
    // (The chebyshev "radius" makes each star a little cube in its cell,
    // which the sky sphere cuts as a square.)
    float d = max(abs(f.x), max(abs(f.y), abs(f.z)));
    return mask * (1.0 - smoothstep(sharpness * 0.85, sharpness, d)) * (0.55 + 0.45 * fract(star * 73.0));
#else
    float d = length(f);
    float twinkle = 0.6 + 0.4 * sin(frameTimeCounter * (1.5 + star * 3.0) + star * 30.0);

    return mask * (1.0 - smoothstep(0.0, sharpness, d)) * twinkle;
#endif
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

// Per-pixel noise for the sampled effects (SSAO, clouds, light shafts,
// reflections). With TAA it shifts every frame (the same paper's trick:
// offset the pattern by 5.588238 pixels per frame), so TAA averages the
// noise away; without TAA it stays put, since moving noise would only
// flicker. Takes gl_FragCoord.xy as a parameter because this file is also
// included by vertex shaders, where gl_FragCoord doesn't exist.
float effectDither(vec2 fragCoord) {
#ifdef AURORA_TAA
    return ditherPattern(fragCoord + 5.588238 * mod(float(frameCounter), 64.0));
#else
    return ditherPattern(fragCoord);
#endif
}

// ---------------------------------------------------------------------------
// TAA jitter: every frame the whole picture is shifted by a different
// fraction of a pixel (Halton 2/3 sequence, 8 positions), so the history
// composite2.fsh accumulates ends up with several samples per pixel - that
// is what smooths the edges. Called at the end of every gbuffers vertex
// shader; does nothing without TAA.
// ---------------------------------------------------------------------------

float halton(float index, float base) {
    float f = 1.0;
    float r = 0.0;
    for (int i = 0; i < 4; i++) {
        if (index <= 0.0) break;
        f /= base;
        r += f * mod(index, base);
        index = floor(index / base);
    }
    return r;
}

// This frame's shift, in pixels (-0.5..0.5); zero without TAA.
vec2 taaPixelOffset() {
#ifdef AURORA_TAA
    float index = mod(float(frameCounter), 8.0) + 1.0;
    return vec2(halton(index, 2.0), halton(index, 3.0)) - 0.5;
#else
    return vec2(0.0);
#endif
}

vec4 taaJitter(vec4 clipPos) {
#ifdef AURORA_TAA
    clipPos.xy += taaPixelOffset() * (2.0 / vec2(viewWidth, viewHeight)) * clipPos.w;
#endif
    return clipPos;
}

#endif // AURORA_COMMON_GLSL
