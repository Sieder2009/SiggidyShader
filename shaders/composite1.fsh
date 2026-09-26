#version 120

#include "/lib/common.glsl"

// Bloom and tonemap live in their own pass (after composite.fsh, before
// final.fsh) for two reasons: (1) composite.fsh's sky repaint writes into
// colortex0, but a texture sampler bound for READING in that same pass still
// shows the buffer's content from BEFORE this frame's draw call, so bloom
// sampled here - one pass later - is the first point where the sun/sky
// composite.fsh just painted is actually visible to it; (2) tonemapping
// needs to happen once, in linear HDR, before final.fsh's antialiasing runs
// on the resulting (now LDR) image.

#define ENABLE_BLOOM // Soft glow around very bright pixels (sun, lava, glowstone, full daylight sky). Off in Low/Potato profiles.
#define BLOOM_STRENGTH 0.35 // [0.0 0.15 0.25 0.35 0.5 0.75]

#define EXPOSURE 1.05    // [0.7 0.8 0.9 1.0 1.05 1.1 1.2 1.3 1.5]
#define SATURATION 1.12  // [0.8 0.9 1.0 1.1 1.12 1.2 1.3]

#ifdef ENABLE_BLOOM
// Tells Iris/OptiFine to (re)generate colortex0's mip chain from this
// frame's content before this stage runs - getBloom() below is the only
// thing that reads it, so gate the (otherwise wasted, non-trivial) per-frame
// mip regeneration cost behind the same toggle Low/Potato already use to
// turn bloom off.
const bool colortex0MipmapEnabled = true;
#endif

uniform sampler2D colortex0;

varying vec2 texcoord;

vec3 adjustSaturation(vec3 color, float amount) {
    float l = luma(color);
    return mix(vec3(l), color, amount);
}

#ifdef ENABLE_BLOOM
// Cheap bloom via the hardware-built mip chain of colortex0 instead of a
// wide manual box blur. colortex0 is stored as HDR (see common.glsl's
// colortex0Format comment), so anything genuinely brighter than 1.0 survives
// the "- 1.0" below and blooms, with no separate threshold/bright-pass
// buffer needed. Because the threshold is applied AFTER the mip chain's
// averaging (not before), this reliably catches large and/or very bright
// sources - the sun disc, full daylight sky, large lava lakes - but a small,
// isolated overbright source (a single torch/glowstone block seen from far
// away) can get diluted below 1.0 by its darker surroundings during
// averaging and not bloom; that's the known tradeoff for two texture reads
// total instead of a wide, threshold-then-blur pass.
vec3 getBloom(vec2 uv) {
    // texture2D's third argument is an explicit LOD BIAS - core GLSL 1.20,
    // safe in a fragment shader on any driver (unlike texture2DLod/
    // texelFetch, which this pack avoids to stay compatible with older/
    // weaker GPUs). On a 1:1 fullscreen pass the automatically computed LOD
    // is ~0, so this bias is effectively the mip level.
    vec3 tight = max(texture2D(colortex0, uv, 3.0).rgb - 1.0, 0.0);
    vec3 wide  = max(texture2D(colortex0, uv, 6.0).rgb - 1.0, 0.0);
    return tight * 0.6 + wide * 0.4;
}
#endif

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;

#ifdef ENABLE_BLOOM
    color += getBloom(texcoord) * BLOOM_STRENGTH;
#endif

    color *= EXPOSURE;
    color = tonemapACES(color);
    color = adjustSaturation(color, SATURATION);

    gl_FragColor = vec4(color, 1.0);
}
