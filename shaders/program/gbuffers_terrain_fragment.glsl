// gbuffers_terrain.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_terrain.fsh, shaders/world-1/gbuffers_terrain.fsh
// and shaders/world1/gbuffers_terrain.fsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"
#include "/lib/sky.glsl"

uniform sampler2D tex;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;
varying float vFoliage;
varying float vEmissive;
varying float vShine;
varying vec3 worldPos;
varying float vUpFace;

void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;
    if (albedo.a < 0.1) discard;

    // From the dry texture: lava or a glowing ore doesn't dim in the rain.
    vec3 emission = blockEmission(albedo.rgb, vEmissive);

    // Rain: everything under the open sky gets darker; flat, upward-facing
    // ground (not plants, leaves or glowing blocks) also collects puddles,
    // which are darker still.
    float wet = surfaceWetness(lmcoord);
    float puddle = 0.0;
    if (wet > 0.0) {
        if (vUpFace > 0.5 && vFoliage < 0.5 && vEmissive < 0.5) puddle = puddleAmount(worldPos, wet);
        albedo.rgb = wetAlbedo(albedo.rgb, wet + puddle);
    }

    vec3 N = normalize(viewNormal);
    vec3 color = shadeLit(albedo.rgb, N, viewPos, lmcoord, vFoliage);
    color += emission;

#ifndef AURORA_SHINY_BLOCKS
    if (puddle > 0.0) {
        // A thin sheet of still water: a flat mirror for the sky, the same
        // sky the real water reflects. Mostly visible at a low angle, with a
        // little reflection kept even straight down so a puddle still reads
        // as water from above. (With REFLECTIVE_BLOCKS, composite.fsh
        // reflects puddles instead, landscape included.)
        vec3 upN = normalize(upPosition);
        vec3 viewDir = normalize(-viewPos);
        float fresnel = 0.15 + 0.85 * pow(1.0 - clamp(dot(upN, viewDir), 0.0, 1.0), 5.0);
        vec3 reflection = reflectedSky(reflect(-viewDir, upN));
        color = mix(color, reflection, puddle * fresnel);
    }
#endif

    color = applyFog(color, viewPos);

    vec4 surface = surfaceData(N, lmcoord.y, vFoliage > 0.5 ? MAT_FOLIAGE : MAT_SOLID);
#ifdef AURORA_SHINY_BLOCKS
    // Shiny blocks and puddles are reflected later, in composite.fsh. A
    // puddle is a film of still water: as shiny as it is deep, never metal.
    float shine = abs(vShine);
    bool metal = vShine < 0.0;
    if (puddle > shine) {
        shine = puddle;
        metal = false;
    }
    if (shine > 0.0) surface = shinySurfaceData(N, lmcoord.y, shine, metal);
#endif

    /* DRAWBUFFERS:02 */
    gl_FragData[0] = vec4(color, albedo.a);
    gl_FragData[1] = surface;
}
