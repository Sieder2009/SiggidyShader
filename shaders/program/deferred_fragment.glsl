// deferred.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/deferred.fsh, shaders/world-1/deferred.fsh
// and shaders/world1/deferred.fsh, which only set AURORA_WORLD (see lib/common.glsl).

// Screen-space ambient occlusion, raw. Runs after all opaque geometry and
// before water/glass, so only solid surfaces are in the depth buffer. The
// result is noisy on purpose (few samples, rotated per pixel) and gets
// smoothed and applied in deferred1.fsh. The whole pass is switched off with
// the SSAO option (program.deferred.enabled in shaders.properties).

#include "/lib/common.glsl"

uniform sampler2D colortex2;
uniform sampler2D depthtex0;

varying vec2 texcoord;

vec3 getViewPos(vec2 uv, float depth) {
    vec4 view = gbufferProjectionInverse * vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
    return view.xyz / view.w;
}

// View-space z of the visible surface at uv (negative = in front of the camera).
float sceneZ(vec2 uv) {
    vec4 view = gbufferProjectionInverse * vec4(0.0, 0.0, texture2D(depthtex0, uv).r * 2.0 - 1.0, 1.0);
    return view.z / view.w;
}

#ifdef AURORA_SSAO
// Points spread over the half-sphere above the surface (about one block
// across), each checked against the depth buffer: if the visible surface at
// that point's screen position is in front of it, something blocks the sky
// from that direction. Close blockers count fully; ones much further away
// in depth (a wall far behind an edge) are faded out.
float ambientOcclusion(vec3 viewPos, vec3 N) {
    const int samples = 8;
    const float radius = 0.7;

    vec3 helper = abs(N.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 T = normalize(cross(helper, N));
    vec3 B = cross(N, T);

    float dither = effectDither(gl_FragCoord.xy);
    float occlusion = 0.0;
    for (int i = 0; i < samples; i++) {
        float x = (float(i) + dither) / float(samples);
        float angle = (float(i) + dither) * 2.39996; // golden angle: evenly spread directions
        float r = sqrt(x);
        vec3 dir = T * (cos(angle) * r) + B * (sin(angle) * r) + N * sqrt(max(1.0 - x, 0.0));
        vec3 samplePos = viewPos + dir * (radius * mix(0.15, 1.0, x * x));

        vec4 clip = gbufferProjection * vec4(samplePos, 1.0);
        vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) continue;

        float z = sceneZ(uv);
        float inFront = z - samplePos.z;
        if (inFront > 0.03) occlusion += 1.0 - smoothstep(radius, radius * 3.0, inFront);
    }
    return 1.0 - occlusion / float(samples);
}
#endif

void main() {
    float ao = 1.0;
#ifdef AURORA_SSAO
    float depth = texture2D(depthtex0, texcoord).r;
    vec4 data = texture2D(colortex2, texcoord);
    int material = materialOf(data);
    if (depth < 1.0 && (material == MAT_SOLID || material == MAT_FOLIAGE || material >= MAT_SHINY)) {
        ao = ambientOcclusion(getViewPos(texcoord, depth), decodeNormal(data.rg));
    }
#endif

    /* DRAWBUFFERS:3 */
    gl_FragData[0] = vec4(ao, 0.0, 0.0, 1.0);
}
