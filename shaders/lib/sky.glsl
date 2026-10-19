// ===========================================================================
// Aurora Nights - the full sky: gradient, sun, moon, stars, aurora, clouds
// (Overworld) or the violet starry void (The End).
//
// Shared by composite.fsh (paints the sky behind everything) and
// gbuffers_water.fsh (reflects it), so the reflection always matches the
// real sky. Include AFTER common.glsl. Every option of the sky is declared
// here and only here: Iris/OptiFine merge equally named options pack-wide,
// so a second copy with a different value list would clash.
// ===========================================================================

#ifndef AURORA_SKY_GLSL
#define AURORA_SKY_GLSL 1 // include guard (valued, so Iris/OptiFine never list it as an on/off option)

#define STAR_DENSITY 0.02    // [0.005 0.01 0.02 0.03 0.05]
#define STAR_SHARPNESS 0.35  // [0.2 0.25 0.3 0.35 0.4 0.5]
#define STAR_BRIGHTNESS 1.0  // [0.5 0.75 1.0 1.5 2.0]

#define ENABLE_CLOUDS // A single, cheap procedural cloud layer. Off in the Potato profile.
#define CLOUD_HEIGHT 180.0    // [120.0 150.0 180.0 220.0 260.0]  world Y of the cloud plane
#define CLOUD_COVERAGE 0.55   // [0.3 0.4 0.45 0.5 0.55 0.6 0.7]  higher = more sky covered
#define CLOUD_SPEED 1.0       // [0.0 0.5 1.0 1.5 2.0]

#define ENABLE_AURORA // Northern lights in the night sky (and in water reflections). Off in the Potato and Low profiles.
#define AURORA_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.5 2.0]

uniform vec3 moonPosition;

#ifdef ENABLE_CLOUDS
// A single flat, animated noise plane at a fixed world height - not
// volumetric, but very cheap and looks reasonable from below, which is
// where the player is the vast majority of the time. worldDir must be the
// WORLD-space (not view-space) ray direction, same as starField() needs.
vec3 renderClouds(vec3 worldDir, vec3 skyColor, float h) {
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

    // Rain closes the cloud cover.
    float threshold = 1.0 - min(CLOUD_COVERAGE + rainStrength * 0.25, 0.95);
    float cloud = smoothstep(threshold, threshold + 0.25, density);

    // Fade out near the horizon (grazing angle) instead of ending in a hard
    // edge, and keep this simple, cheap effect looking sensible whether the
    // camera is below the cloud layer (the common case) or above it.
    float horizonFade = smoothstep(0.02, 0.12, abs(denom));
    cloud *= horizonFade;

    vec3 cloudColor = mix(vec3(0.05, 0.06, 0.09), vec3(1.0, 0.98, 0.95), dayFactor(h));
    cloudColor = mix(cloudColor, vec3(1.0, 0.62, 0.42), twilightFactor(h) * 0.6); // sunset-lit undersides
    cloudColor = mix(cloudColor, vec3(luma(cloudColor) * 0.55), rainStrength * 0.7); // grey rain clouds
    return mix(skyColor, cloudColor, cloud * 0.85);
}
#endif

#ifdef ENABLE_AURORA
// Self-written northern lights. The view ray is intersected with a stack of
// horizontal layers; on each one a "ridge" of smooth value noise (bright
// only where the noise crosses 0.5) draws thin, wavy bands, stretched
// east-west. Because every layer sits a little higher, the same band shows
// up a little higher on screen per layer, which smears it upward into a
// curtain - green at its foot, fading to violet at the top.
// worldDir must be the WORLD-space ray direction (fixed to the sky, not
// the screen).
vec3 renderAurora(vec3 worldDir) {
    if (worldDir.y < 0.03) return vec3(0.0);

    float time = frameTimeCounter;
    vec2 flatDir = worldDir.xz / worldDir.y; // at most ~33 at the 0.03 cutoff - no precision issue
    vec3 sum = vec3(0.0);

    for (int i = 0; i < 8; i++) {
        float layer = (float(i) + 0.5) / 8.0; // 0 = curtain foot, 1 = top
        vec2 p = flatDir * (1.0 + layer * 0.35);
        vec2 q = vec2(p.x * 0.22, p.y * 0.85) + vec2(time * 0.010, time * 0.004);

        float n = valueNoise(q) * 0.7 + valueNoise(q * 2.7 + vec2(0.0, time * 0.02)) * 0.3;
        float ridge = 1.0 - abs(n * 2.0 - 1.0);
        ridge *= ridge;
        ridge *= ridge;
        ridge *= ridge; // ^8: thin, sharp bands

        float shimmer = 0.6 + 0.4 * sin(p.x * 2.3 + p.y * 1.7 + time * 0.8);
        vec3 col = mix(vec3(0.15, 1.00, 0.45), vec3(0.55, 0.20, 0.95), layer * layer);
        sum += col * (ridge * shimmer * (1.0 - layer * 0.5));
    }

    // Keep it off the horizon haze, strongest toward the north (-Z in
    // Minecraft), and let the whole display slowly brighten and fade.
    float elevationFade = smoothstep(0.03, 0.25, worldDir.y);
    float northBias = 0.35 + 0.65 * smoothstep(-0.3, 0.6, -worldDir.z);
    float pulse = 0.7 + 0.3 * sin(time * 0.05);

    return sum * (0.45 / 8.0 * AURORA_BRIGHTNESS * elevationFade * northBias * pulse);
}
#endif

// Full sky color for a VIEW-SPACE unit direction (the space sunPosition,
// moonPosition and upPosition are in).
vec3 renderSky(vec3 dir) {
    // Stars, aurora and clouds hash an absolute coordinate (unlike the
    // dot-product-based gradient/sun/moon), so they need a direction that
    // stays fixed to the WORLD as the camera turns - otherwise they would be
    // glued to the screen instead of the sky.
    vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * dir);

#if AURORA_WORLD == -1
    // The Nether has no sky; only reached if something in the Nether ever
    // asks for a reflection. Match vanilla's fog there.
    return fogColor;
#elif AURORA_WORLD == 1
    vec3 sky = skyGradient(dir);
    sky += starField(worldDir, STAR_DENSITY * 1.5, STAR_SHARPNESS) * STAR_BRIGHTNESS * vec3(0.85, 0.75, 1.0) * 0.8;

    // A faint, slowly drifting violet haze over the void.
    float haze = cloudFbm(worldDir.xz / (abs(worldDir.y) + 0.35) * 1.2 + frameTimeCounter * 0.005);
    sky += vec3(0.20, 0.08, 0.30) * (haze * haze * 0.6);
    return sky;
#else
    float h = sunHeight();
    vec3 sky = skyGradient(dir);

    vec3 sunDir = normalize(sunPosition);
    vec3 moonDir = normalize(moonPosition);
    float clearSky = 1.0 - rainStrength * 0.85; // rain hides sun, moon, stars and aurora

    float sunAlign = dot(dir, sunDir);
    float sunDisc = smoothstep(0.9994, 0.9998, sunAlign);
    float sunGlow = pow(max(sunAlign, 0.0), 340.0) * 0.6;
    sky += (sunDisc * 3.0 + sunGlow) * clearSky * getDayNightSunColor(h);

    float moonAlign = dot(dir, moonDir);
    float moonDisc = smoothstep(0.9992, 0.9997, moonAlign);
    float moonHalo = pow(max(moonAlign, 0.0), 220.0) * 0.12;
    sky += (moonDisc * 0.8 + moonHalo * nightFactor(h)) * clearSky * vec3(0.85, 0.88, 1.0);

    float night = nightFactor(h) * clearSky;
    if (night > 0.001) {
        float stars = starField(worldDir, STAR_DENSITY, STAR_SHARPNESS) * STAR_BRIGHTNESS;
        sky += stars * night * vec3(0.9, 0.95, 1.0);
    #ifdef ENABLE_AURORA
        sky += renderAurora(worldDir) * night;
    #endif
    }

#ifdef ENABLE_CLOUDS
    // Clouds occlude whatever is behind them (stars and aurora included), so
    // they are mixed in last rather than added.
    sky = renderClouds(worldDir, sky, h);
#endif

    return sky;
#endif
}

#endif // AURORA_SKY_GLSL
