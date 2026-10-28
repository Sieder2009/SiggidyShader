// gbuffers_textured.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_textured.fsh, shaders/world-1/gbuffers_textured.fsh
// and shaders/world1/gbuffers_textured.fsh, which only set AURORA_WORLD (see lib/common.glsl).

// Unlit fallback for what has no program of its own: the vanilla sky/sun/moon
// quads (which composite.fsh fully repaints anyway wherever nothing solid was
// drawn), beacon beams, spider/enderman eyes and enchantment glint - all of
// which vanilla draws at full brightness. Particles and rain/snow are lit
// instead, in gbuffers_textured_lit.

#include "/lib/common.glsl"

uniform sampler2D tex;

varying vec2 texcoord;
varying vec4 vColor;
varying vec3 viewPos;

void main() {
    vec4 color = texture2D(tex, texcoord) * vColor;
    if (color.a < 0.01) discard;
    color.rgb = applyFog(color.rgb, viewPos);
    /* DRAWBUFFERS:0 */
    gl_FragColor = color;
}
