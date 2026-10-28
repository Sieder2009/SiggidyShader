// gbuffers_water.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_water.fsh, shaders/world-1/gbuffers_water.fsh
// and shaders/world1/gbuffers_water.fsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"
#include "/lib/sky.glsl"

#define WAVE_HEIGHT 0.10   // [0.0 0.05 0.10 0.15 0.20 0.30]
#define WAVE_SPEED 1.0     // [0.5 0.75 1.0 1.25 1.5]
#define WATER_OPACITY 0.75 // [0.5 0.6 0.7 0.75 0.8 0.9 1.0]
// WATER_SKY_REFLECTION is declared in sky.glsl (rain puddles use it too).

uniform sampler2D tex;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;
varying vec3 worldPos;
varying float topFace;
varying float vIsWater;

// Cheap analytic wave normal via finite differences of a sum-of-sines
// height field - no textures needed, animates with frameTimeCounter.
vec2 waveGradient(vec2 p, float t) {
    float e = 0.35;
    float h0 = sin(p.x * 0.9 + t) * cos(p.y * 0.7 - t * 0.8);
    float hx = sin((p.x + e) * 0.9 + t) * cos(p.y * 0.7 - t * 0.8);
    float hy = sin(p.x * 0.9 + t) * cos((p.y + e) * 0.7 - t * 0.8);
    return vec2(hx - h0, hy - h0) / e;
}

void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;
    bool isWater = vIsWater > 0.5;

    vec3 N = normalize(viewNormal);

    if (isWater && topFace > 0.5) {
        float t = frameTimeCounter * WAVE_SPEED;
        vec2 grad = waveGradient(worldPos.xz * 0.25, t) * WAVE_HEIGHT;
        // grad is a WORLD-space tilt (from worldPos.xz); N is a VIEW-space
        // normal. Rotate the tilt into view space before combining, or the
        // wave bump points the wrong way as soon as the camera yaws/pitches.
        vec3 viewTilt = mat3(gbufferModelView) * vec3(grad.x, 0.0, grad.y);
        N = normalize(N + viewTilt);
    }

    float shadowTerm = sampleShadow(viewPos, N);
    vec3 color = shadeLitCustom(albedo.rgb, N, viewPos, lmcoord, shadowTerm, 0.0);

    // How much of the open sky this surface sees: indoors and in caves
    // there is no sun to glint and no sky to mirror.
    float openSky = skyAccess(lmcoord);

    vec3 viewDir = normalize(-viewPos);
    vec3 L = normalize(shadowLightPosition);
    vec3 H = normalize(L + viewDir);
    float spec = pow(max(dot(N, H), 0.0), 90.0) * shadowTerm * openSky;
    // Same light color and cloud shadow as the direct light in shadeLitCustom().
    if (spec > 0.0) spec *= cloudShadow(viewPos);
    float h = sunHeight();
    color += getDayNightSunColor(h) * moonDimming(h) * spec * 1.5;

    float fresnel = pow(1.0 - clamp(dot(N, viewDir), 0.0, 1.0), 5.0);

    vec3 reflection = getSkyAmbient(h);
    float reflectivity = 0.55;
    if (isWater) {
#if defined AURORA_WATER_FOG || defined AURORA_SSR
        // composite.fsh reflects the sky (and the land) into the water
        // later, after its depth color - doing it here as well would double
        // it, and the depth color would paint over this one anyway.
        reflectivity = 0.0;
#else
        // reflect() of the view ray is already a VIEW-space direction,
        // exactly what reflectedSky() expects. Without WATER_SKY_REFLECTION
        // that is just the sky gradient - still cheap, and closer to the
        // real sky than the flat tint glass and ice keep.
        reflection = reflectedSky(reflect(-viewDir, N));
        reflectivity = 0.8;
#endif
    }
    // Fade the sky reflection out where there's no sky to reflect, and skip
    // it when looking up at the surface from underwater.
    reflection = mix(color, reflection, openSky);
    if (isEyeInWater == 1) reflectivity = 0.0;
    color = mix(color, reflection, fresnel * reflectivity);

    // Only water gets the fresnel-boosted, WATER_OPACITY-scaled alpha;
    // glass, ice etc. keep their texture's own transparency.
    float alpha = isWater ? clamp(albedo.a + fresnel * 0.3, 0.0, 1.0) * WATER_OPACITY : albedo.a;
#ifdef AURORA_WATER_FOG
    // composite.fsh darkens deep water by its real depth, so the surface
    // itself can be much clearer: shallow water now shows its bottom.
    if (isWater) alpha *= 0.55;
#endif

    color = applyFog(color, viewPos);

    /* DRAWBUFFERS:02 */
    gl_FragData[0] = vec4(color, alpha);
    gl_FragData[1] = surfaceData(N, lmcoord.y, isWater ? MAT_WATER : MAT_GLASS);
}
