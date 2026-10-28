// gbuffers_textured_lit.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_textured_lit.fsh, shaders/world-1/gbuffers_textured_lit.fsh
// and shaders/world1/gbuffers_textured_lit.fsh, which only set AURORA_WORLD (see lib/common.glsl).

// Particles (smoke, splashes, block-breaking bits, ...) and rain/snow: with
// no gbuffers_particles/gbuffers_weather in the pack, Iris and OptiFine both
// fall back to this program for them. Before it existed they ended up in the
// unlit gbuffers_textured and kept their full daytime brightness - rain and
// smoke glowed at night and deep in caves. gbuffers_textured stays unlit on
// purpose for what else lands there (sky quads, beacon beams, spider eyes,
// enchantment glint).

#include "/lib/common.glsl"

uniform sampler2D tex;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;

void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;
    if (albedo.a < 0.01) discard;

    // These tiny, camera-facing quads have no meaningful normal: light them
    // as if they faced the sun/moon, with the soft two-sided foliage response,
    // so only shadows, skylight and block light decide how bright they are.
    vec3 N = normalize(shadowLightPosition);
    vec3 color = shadeLit(albedo.rgb, N, viewPos, lmcoord, 1.0);

    // Vanilla hands its glowing particles (flames, lava sparks, end rod and
    // glow particles, ...) the maximum block light (level 15 = 0.97 here,
    // 14 = 0.91); let those glow like emissive blocks rather than only being
    // lit.
    if (lmcoord.x > 0.95) color += albedo.rgb * EMISSION_STRENGTH;

    color = applyFog(color, viewPos);

    /* DRAWBUFFERS:0 */
    gl_FragColor = vec4(color, albedo.a);
}
