// ===========================================================================
// Aurora Nights - the full sky: gradient, sun, moon, stars, aurora, clouds
// (Overworld) or the violet starry void (The End).
//
// Shared by composite.fsh (paints the sky behind everything),
// gbuffers_water.fsh and the rain puddles in gbuffers_terrain.fsh (both
// reflect it), so a reflection always matches the real sky. Include AFTER common.glsl. Every option of the sky is declared
// here and only here (except the cloud options, which live in common.glsl
// because the lighting there casts the clouds' shadows): Iris/OptiFine merge
// equally named options pack-wide, so a second copy with a different value
// list would clash.
// ===========================================================================

#ifndef AURORA_SKY_GLSL
#define AURORA_SKY_GLSL 1 // include guard (valued, so Iris/OptiFine never list it as an on/off option)

#define STAR_DENSITY 0.02    // [0.005 0.01 0.02 0.03 0.05]
#define STAR_SHARPNESS 0.35  // [0.2 0.25 0.3 0.35 0.4 0.5]
#define STAR_BRIGHTNESS 1.0  // [0.5 0.75 1.0 1.5 2.0]

#define ENABLE_AURORA // Northern lights in the night sky (and in water reflections). Off in the Potato and Low profiles.
#define AURORA_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.5 2.0]

#define RAINBOWS // A rainbow opposite the sun once the rain stops, fading as the ground dries.

#define WATER_SKY_REFLECTION // Water and rain puddles mirror the real sky (gradient, sun, clouds, stars, aurora) instead of a plain sky gradient. Off in the Potato profile.

#define VOLUMETRIC_CLOUDS // Thick, three-dimensional clouds lit by the sun (bright tops, darker undersides, golden at sunset) instead of a flat layer. Needs the clouds. Off in the Low and Potato profiles.

uniform vec3 moonPosition;

#ifdef ENABLE_CLOUDS
// A single flat, animated noise plane at a fixed world height - not
// volumetric, but very cheap and looks reasonable from below, which is
// where the player is the vast majority of the time. worldDir must be the
// WORLD-space (not view-space) ray direction, same as starField() needs.
vec3 renderClouds(vec3 worldDir, vec3 skyCol, float h) {
    float denom = worldDir.y;
    if (abs(denom) < 0.001) return skyCol; // ray parallel to the cloud plane

    float t = (CLOUD_HEIGHT - cameraPosition.y) / denom;
    if (t <= 0.0) return skyCol; // plane is behind the camera

    // Same coverage function the cloud shadows on the ground use
    // (common.glsl), so shadows and clouds always match.
    float cloud = cloudCoverage(cameraPosition.xz + worldDir.xz * t);

    // Fade out near the horizon (grazing angle) instead of ending in a hard
    // edge, and keep this simple, cheap effect looking sensible whether the
    // camera is below the cloud layer (the common case) or above it.
    float horizonFade = smoothstep(0.02, 0.12, abs(denom));
    cloud *= horizonFade;

    vec3 cloudColor = mix(vec3(0.05, 0.06, 0.09), vec3(1.0, 0.98, 0.95), dayFactor(h));
    cloudColor = mix(cloudColor, vec3(1.0, 0.62, 0.42), twilightFactor(h) * 0.6); // sunset-lit undersides
    cloudColor = mix(cloudColor, vec3(luma(cloudColor) * 0.55), rainStrength * 0.7); // grey rain clouds
    return mix(skyCol, cloudColor, cloud * 0.85);
}

#if CLOUD_STYLE == 0
// Blocky clouds like Minecraft's: the 4-block-thick layer of 12x12 cells
// from blockCloudCellCover() (common.glsl). The view ray is walked cell by
// cell through the layer - a 2D grid walk, only a handful of cells unless the
// ray is nearly flat - and the first cloud cell it reaches decides which face
// is seen: the underside, the top or one of the four sides. Each face gets
// Minecraft's flat shading, tops brightest, undersides darkest.
vec3 renderBlockClouds(vec3 worldDir, vec3 skyCol, float h) {
    float dirY = abs(worldDir.y) < 0.0001 ? 0.0001 : worldDir.y;
    // Move the camera against the drift instead of moving every cell.
    vec3 origin = cameraPosition - vec3(blockCloudDrift(), 0.0, 0.0);

    float t0 = (CLOUD_HEIGHT - origin.y) / dirY;
    float t1 = (CLOUD_HEIGHT + blockCloudThickness - origin.y) / dirY;
    float tEnter = max(min(t0, t1), 0.0);
    float tExit = min(max(t0, t1), tEnter + 420.0); // flat rays: only the near part of the layer
    if (tExit <= tEnter || tEnter > 3000.0) return skyCol;

    vec3 p = origin + worldDir * tEnter;
    vec2 cell = floor(p.xz / blockCloudCell);
    // If the first cell is cloud, the ray came in through its underside or top.
    vec3 normal = vec3(0.0, worldDir.y > 0.0 ? -1.0 : 1.0, 0.0);
    float tHit = -1.0;

    if (blockCloudCellCover(cell) > 0.5) {
        tHit = tEnter;
    } else {
        vec2 stepSign = vec2(worldDir.x >= 0.0 ? 1.0 : -1.0, worldDir.z >= 0.0 ? 1.0 : -1.0);
        vec2 invDir = 1.0 / max(abs(worldDir.xz), vec2(0.00001));
        vec2 tDelta = blockCloudCell * invDir;               // ray length per cell, per axis
        vec2 border = (cell + max(stepSign, 0.0)) * blockCloudCell;
        vec2 tNext = tEnter + abs(border - p.xz) * invDir;   // ray length to the next border, per axis
        for (int i = 0; i < 40; i++) {
            float t;
            if (tNext.x < tNext.y) {
                t = tNext.x;
                cell.x += stepSign.x;
                tNext.x += tDelta.x;
                normal = vec3(-stepSign.x, 0.0, 0.0);
            } else {
                t = tNext.y;
                cell.y += stepSign.y;
                tNext.y += tDelta.y;
                normal = vec3(0.0, 0.0, -stepSign.y);
            }
            if (t > tExit) break;
            if (blockCloudCellCover(cell) > 0.5) {
                tHit = t;
                break;
            }
        }
    }
    if (tHit < 0.0) return skyCol;

    // Minecraft's per-face cloud shading.
    float shade = normal.y > 0.5 ? 1.0 : (normal.y < -0.5 ? 0.7 : (abs(normal.x) > 0.5 ? 0.9 : 0.8));
    // White by day, warm at sunrise/sunset, dark at night, grey in rain -
    // in on-screen terms (see fromDisplay()), like the sky around them.
    vec3 display = mix(vec3(0.10, 0.11, 0.16), vec3(1.0), dayFactor(h));
    display = mix(display, vec3(1.0, 0.78, 0.62), twilightFactor(h) * 0.7);
    display *= 1.0 - rainStrength * 0.45;
    vec3 cloudCol = fromDisplay(display * 0.82) * shade;

    // Far clouds melt into the sky; nearly flat rays (the far edge of the
    // layer) fade out instead of ending in a hard line.
    float fade = exp(-tHit * 0.0005) * smoothstep(0.0, 0.04, abs(worldDir.y));
    return mix(skyCol, cloudCol, 0.88 * fade);
}
#endif

#ifdef VOLUMETRIC_CLOUDS
// Volumetric clouds: a slab of air between CLOUD_HEIGHT and CLOUD_HEIGHT +
// cloudDepth, marched in a fixed number of steps. Their footprint is the same
// cloudFbm() shape the flat clouds and the cloud shadows use; how far up a
// cloud reaches grows with how far that shape is over the coverage
// threshold, which gives every cloud a domed top over a flatter base. A
// second, finer noise frays the edges.
const float cloudDepth = 56.0;

float cloudDensity(vec3 p, float threshold) {
    float height = (p.y - CLOUD_HEIGHT) / cloudDepth; // 0 = base, 1 = top of the slab
    vec2 uv = p.xz * 0.0016 + frameTimeCounter * CLOUD_SPEED * vec2(0.006, 0.0035);
    float top = clamp((cloudFbm(uv) - threshold) * 3.5, 0.0, 1.0);
    float fray = valueNoise(p.xz * 0.04 + vec2(p.y * 0.07, -p.y * 0.05) + frameTimeCounter * 0.02);
    return clamp((top - height) * 5.0 - fray * 0.6, 0.0, 1.0) * smoothstep(0.0, 0.08, height);
}

vec3 renderCloudVolume(vec3 worldDir, vec3 skyCol, float h) {
    if (abs(worldDir.y) < 0.001) return skyCol;

    // Where the view ray enters and leaves the slab (camera below, inside
    // or above it). Grazing rays would cross kilometres of slab: cap the
    // marched length, and give up on very distant entries altogether.
    float t0 = (CLOUD_HEIGHT - cameraPosition.y) / worldDir.y;
    float t1 = (CLOUD_HEIGHT + cloudDepth - cameraPosition.y) / worldDir.y;
    float tEnter = max(min(t0, t1), 0.0);
    float tExit = max(t0, t1);
    if (tExit <= 0.0 || tEnter > 4000.0) return skyCol;
    tExit = min(tExit, tEnter + 420.0);

    const int steps = 14;
    float stepLength = (tExit - tEnter) / float(steps);
    float dither = effectDither(gl_FragCoord.xy);
    float threshold = 1.0 - min(CLOUD_COVERAGE + rainStrength * 0.25, 0.95);

    vec3 lightDir = normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));
    vec3 sunLight = getDayNightSunColor(h) * moonDimming(h) * mix(0.25, 1.6, dayFactor(h));
    vec3 ambient = getSkyAmbient(h);
    // A little brighter when looking toward the light: thin cloud edges glow.
    float towardLight = max(dot(worldDir, lightDir), 0.0);
    float forward = 1.0 + 1.5 * towardLight * towardLight * towardLight * towardLight;

    float transmittance = 1.0;
    vec3 scattered = vec3(0.0);
    for (int i = 0; i < steps; i++) {
        vec3 p = cameraPosition + worldDir * (tEnter + stepLength * (float(i) + dither));
        float density = cloudDensity(p, threshold);
        if (density > 0.001) {
            // One look toward the light: how much cloud sits between this
            // point and the sun shades it (bright tops, dark undersides).
            float shade = cloudDensity(p + lightDir * 14.0, threshold);
            float height = (p.y - CLOUD_HEIGHT) / cloudDepth;
            vec3 lit = sunLight * exp(-shade * 2.5) * forward + ambient * (0.45 + 0.55 * height);

            float stepTransmittance = exp(-density * stepLength * 0.06);
            scattered += lit * (transmittance * (1.0 - stepTransmittance));
            transmittance *= stepTransmittance;
            if (transmittance < 0.03) break;
        }
    }

    scattered *= mix(1.0, 0.45, rainStrength); // grey rain clouds
    // Far-away clouds melt into the sky instead of ending at a hard line.
    float fade = exp(-tEnter * 0.0007) * smoothstep(0.0, 0.06, abs(worldDir.y));
    return mix(skyCol, skyCol * transmittance + scattered, fade);
}
#endif
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

// The moon disc in its current phase (moonPhase, see common.glsl). The disc
// is treated as a little sphere lit from the side: at full moon the light
// comes from straight behind the viewer, at new moon from straight behind the
// moon, in between from the left or right. The unlit part keeps a faint
// glow (earthshine), and some soft noise hints at the darker "seas".
float moonSurface(vec3 dir, vec3 moonDir) {
    const float radius = 0.034; // angular radius in radians, about vanilla's moon size
    float align = dot(dir, moonDir);
    if (align < 0.999) return 0.0;

    // 2D coordinates on the disc: one axis parallel to the horizon, the
    // other perpendicular to it. The fallback only matters when the moon
    // is exactly overhead, where "parallel to the horizon" is undefined.
    vec3 side = cross(normalize(upPosition), moonDir);
    side = dot(side, side) > 1e-6 ? normalize(side) : vec3(1.0, 0.0, 0.0);
    vec3 vertical = cross(moonDir, side);
    vec3 offset = dir - moonDir * align;
    vec2 p = vec2(dot(offset, side), dot(offset, vertical)) / radius;

    float r2 = dot(p, p);
    float disc = 1.0 - smoothstep(0.82, 1.0, r2);
    if (disc <= 0.0) return 0.0;

    vec3 sphereNormal = vec3(p, sqrt(max(1.0 - r2, 0.0)));
    float phaseAngle = float(moonPhase) * (PI / 4.0);
    vec3 towardSun = vec3(sin(phaseAngle), 0.0, cos(phaseAngle));
    float lit = smoothstep(-0.06, 0.06, dot(sphereNormal, towardSun));

    float seas = 0.8 + 0.2 * valueNoise(p * 2.2 + 3.1);
    return disc * mix(0.035, 1.0, lit) * seas;
}

#if SKY_STYLE == 0
// Square, pixelated sun and moon in Minecraft's style.

const float sunHalfSize = 0.085;  // radians: a big, chunky Minecraft sun
const float moonHalfSize = 0.06;

// Angular size of one screen pixel (radians), so hard edges can be exactly
// one pixel soft - enough to stop them stair-stepping and shimmering.
float pixelAngle() {
    return 2.0 / (gbufferProjection[1][1] * viewHeight);
}

// Face coordinates around a sun/moon direction (both WORLD space), on the
// sky in radians: x along its daily path, y across it. The path always runs
// through east and west, also when sunPathRotation tilts it, so the axis it
// turns around is cross(east, body) - except right at the horizon, where
// that vanishes and world north-south, flattened onto the sky, stands in.
// Divided by the distance along the body's direction (a flat projection
// like a camera's), so the square stays square.
vec2 celestialCoords(vec3 worldDir, vec3 body) {
    vec3 axis = vec3(0.0, -body.z, body.y); // cross(east, body)
    if (axis.z < 0.0) axis = -axis;         // always the same side
    vec3 northSouth = normalize(vec3(0.0, 0.0, 1.0) - body * body.z);
    float exact = smoothstep(0.0, 0.15, length(axis));
    axis = normalize(mix(northSouth, axis / max(length(axis), 0.0001), exact));
    vec3 along = cross(body, axis);
    float d = max(dot(worldDir, body), 0.0001);
    return vec2(dot(worldDir, along), dot(worldDir, axis)) / d;
}

// The sun: a bright 8x8-texel face whose outer ring of texels is a little
// warmer and dimmer, inside a faint square glow.
vec3 squareSun(vec3 worldDir, vec3 sunWorld) {
    if (dot(worldDir, sunWorld) < 0.95) return vec3(0.0);
    vec2 uv = celestialCoords(worldDir, sunWorld) / sunHalfSize; // -1..1 across the face
    float edge = max(abs(uv.x), abs(uv.y));
    float aa = pixelAngle() / sunHalfSize;
    float face = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, edge);

    vec2 texel = clamp(floor((uv * 0.5 + 0.5) * 8.0), 0.0, 7.0);
    bool rim = texel.x < 0.5 || texel.y < 0.5 || texel.x > 6.5 || texel.y > 6.5;
    vec3 faceColor = rim ? vec3(1.0, 0.82, 0.45) * 2.2 : vec3(1.0, 0.96, 0.78) * 3.0;

    float glow = 1.0 - smoothstep(1.0, 1.9, edge);
    return faceColor * face + vec3(1.0, 0.85, 0.55) * (glow * glow * 0.25 * (1.0 - face));
}

// The moon: 8x8 texels with a few darker "crater" texels, and the phase cut
// along texel columns, so the lit part grows and shrinks one column at a
// time like Minecraft's moon. Each column counts as part of a cylinder lit
// from the side: at full moon from the front, at new moon from behind.
vec3 squareMoon(vec3 worldDir, vec3 moonWorld) {
    if (dot(worldDir, moonWorld) < 0.97) return vec3(0.0);
    vec2 uv = celestialCoords(worldDir, moonWorld) / moonHalfSize;
    float edge = max(abs(uv.x), abs(uv.y));
    float aa = pixelAngle() / moonHalfSize;
    float face = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, edge);
    if (face <= 0.0) return vec3(0.0);

    vec2 texel = clamp(floor((uv * 0.5 + 0.5) * 8.0), 0.0, 7.0);
    float x = (texel.x + 0.5) / 4.0 - 1.0; // this texel column's center, -1..1
    float phaseAngle = float(moonPhase) * (PI / 4.0);
    float lit = step(0.0, x * sin(phaseAngle) + sqrt(max(1.0 - x * x, 0.0)) * cos(phaseAngle));
    float crater = hash12(texel + 17.0) > 0.78 ? 0.72 : 1.0;
    return vec3(0.85, 0.88, 1.0) * (face * crater * mix(0.035, 1.0, lit));
}
#endif

#ifdef RAINBOWS
// A rainbow after the rain: shows up while the ground is still wetter than
// the current rain explains (wetness lags behind rainStrength, see
// common.glsl), by day, in biomes where it actually rained. The bow is a ring
// about 42 degrees out from the point exactly opposite the sun, red on the
// outside and violet on the inside, and only its part above the horizon is
// drawn - so it stands high when the sun is low and sinks away at noon, just
// like a real one.
vec3 renderRainbow(vec3 dir, vec3 sunDir, float h) {
    float amount = clamp(wetness - rainStrength, 0.0, 1.0) * rainBiome * dayFactor(h);
    if (amount < 0.001) return vec3(0.0);

    float angle = acos(clamp(dot(dir, -sunDir), -1.0, 1.0));
    float x = (angle - 0.733) / 0.03; // 0.733 rad = 42 deg; x = -1 inner edge, +1 outer edge
    float band = max(1.0 - x * x, 0.0);
    if (band <= 0.0) return vec3(0.0);

    // Hue from violet (0.75) on the inside to red (0.0) on the outside.
    float hue = 0.375 - 0.375 * x;
    vec3 col = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);

    float aboveHorizon = smoothstep(0.0, 0.08, dot(dir, normalize(upPosition)));
    return col * (band * amount * aboveHorizon * 0.35);
}
#endif

// Full sky color for a VIEW-SPACE unit direction (the space sunPosition,
// moonPosition and upPosition are in). volumetricClouds: the expensive 3D
// clouds (only the sky itself, painted once per pixel in deferred1.fsh);
// reflections pass false and get the cheap flat cloud layer.
vec3 renderSky(vec3 dir, bool volumetricClouds) {
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

    // Sun and moon stay above the horizon line: looking down past the
    // horizon (from a mountain, say) must not show the sun below it.
    float aboveHorizon = smoothstep(-0.03, 0.0, dot(dir, normalize(upPosition)));
    float sunAlign = dot(dir, sunDir);
    // A wide, soft glare around the sun, so the sky brightens toward it.
    float sunHaze = pow(max(sunAlign, 0.0), 10.0) * 0.22;
    float moonAlign = dot(dir, moonDir);
    // The halo shrinks with the lit part of the moon.
    float moonHalo = pow(max(moonAlign, 0.0), 220.0) * 0.12 * moonIllumination();

#if SKY_STYLE == 0
    vec3 sunWorld = normalize(mat3(gbufferModelViewInverse) * sunDir);
    vec3 moonWorld = normalize(mat3(gbufferModelViewInverse) * moonDir);
    sky += (squareSun(worldDir, sunWorld) * aboveHorizon + sunHaze) * clearSky * getDayNightSunColor(h);
    sky += (squareMoon(worldDir, moonWorld) * (0.8 * aboveHorizon) + vec3(0.85, 0.88, 1.0) * (moonHalo * 0.5 * nightFactor(h))) * clearSky;
#else
    float sunDisc = smoothstep(0.9994, 0.9998, sunAlign);
    float sunGlow = pow(max(sunAlign, 0.0), 340.0) * 0.6;
    sky += ((sunDisc * 3.0 + sunGlow) * aboveHorizon + sunHaze) * clearSky * getDayNightSunColor(h);
    sky += (moonSurface(dir, moonDir) * (0.8 * aboveHorizon) + moonHalo * nightFactor(h)) * clearSky * vec3(0.85, 0.88, 1.0);
#endif

#ifdef RAINBOWS
    sky += renderRainbow(dir, sunDir, h);
#endif

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
    // they are mixed in last rather than added. The blocky ones are cheap
    // enough for reflections too.
    #if CLOUD_STYLE == 0
    sky = renderBlockClouds(worldDir, sky, h);
    #elif defined VOLUMETRIC_CLOUDS
    if (volumetricClouds) sky = renderCloudVolume(worldDir, sky, h);
    else sky = renderClouds(worldDir, sky, h);
    #else
    sky = renderClouds(worldDir, sky, h);
    #endif
#endif

    return sky;
#endif
}

// The sky as seen in a reflection (water, rain puddles), for a VIEW-SPACE
// direction: the full sky with WATER_SKY_REFLECTION, otherwise only its
// cheap gradient.
vec3 reflectedSky(vec3 dir) {
#ifdef WATER_SKY_REFLECTION
    return renderSky(dir, false);
#else
    return skyGradient(dir);
#endif
}

#endif // AURORA_SKY_GLSL
