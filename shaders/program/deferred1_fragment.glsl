// deferred1.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/deferred1.fsh, shaders/world-1/deferred1.fsh
// and shaders/world1/deferred1.fsh, which only set AURORA_WORLD (see lib/common.glsl).

// Runs after all opaque geometry and before water/glass:
// - paints the sky wherever nothing solid was drawn. Doing it here rather
//   than after the translucent pass means water and stained glass in front
//   of the sky now blend over the real sky instead of over a flat fill color.
// - smooths the raw ambient occlusion from deferred.fsh with a small
//   depth-aware blur and darkens the image with it.

#include "/lib/common.glsl"
#include "/lib/sky.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;

varying vec2 texcoord;

vec3 getViewPos(vec2 uv, float depth) {
    vec4 view = gbufferProjectionInverse * vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
    return view.xyz / view.w;
}

float linearZ(float depth) {
    vec4 view = gbufferProjectionInverse * vec4(0.0, 0.0, depth * 2.0 - 1.0, 1.0);
    return -view.z / view.w;
}

#ifdef AURORA_SSAO
// 3x3 taps two pixels apart; taps on a different surface (clearly nearer or
// farther) are left out so the darkening doesn't bleed across edges.
float smoothedAO(float centerZ) {
    vec2 texel = 2.0 / vec2(viewWidth, viewHeight);
    float tolerance = 0.1 + centerZ * 0.03;
    float sum = 0.0;
    float weight = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 uv = texcoord + vec2(float(x), float(y)) * texel;
            float w = abs(linearZ(texture2D(depthtex0, uv).r) - centerZ) < tolerance ? 1.0 : 0.0;
            sum += texture2D(colortex3, uv).r * w;
            weight += w;
        }
    }
    return weight > 0.0 ? sum / weight : 1.0;
}
#endif

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).r;

    if (depth >= 1.0) {
#if AURORA_WORLD == -1
        // The Nether has no sky: the void past the render distance shows
        // vanilla's fog color, so it blends into the fogged terrain.
        color = fogColor;
#else
        // Shifted by this frame's TAA offset, exactly like the geometry
        // (taaJitter() moves everything by that many pixels), so TAA smooths
        // the hard edges of the square sun, moon and blocky clouds too, and
        // the horizon stays lined up with the land.
        vec2 skyUV = texcoord - taaPixelOffset() / vec2(viewWidth, viewHeight);
        color = renderSky(normalize(getViewPos(skyUV, depth)), true);
        // Blindness / Darkness black out the sky, like in vanilla.
        color *= 1.0 - clamp(max(blindness, darknessFactor), 0.0, 1.0);
#endif
    }
#ifdef AURORA_SSAO
    else {
        float ao = smoothedAO(linearZ(depth));
        color *= mix(1.0, ao, SSAO_STRENGTH);
    }
#endif

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(color, 1.0);
}
