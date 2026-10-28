// gbuffers_hand.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_hand.fsh, shaders/world-1/gbuffers_hand.fsh
// and shaders/world1/gbuffers_hand.fsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"

uniform sampler2D tex;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;

void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;
    if (albedo.a < 0.1) discard;

    // The hand pass uses a special depth-squashed projection, so the
    // shadow-map matrices don't line up reliably here - skip the shadow
    // lookup (shadowTerm = 1.0) and just use direct + sky + torch light.
    vec3 N = normalize(viewNormal);
    vec3 color = shadeLitCustom(albedo.rgb, N, viewPos, lmcoord, 1.0, 0.0);
    color = applyFog(color, viewPos);

    /* DRAWBUFFERS:02 */
    gl_FragData[0] = vec4(color, albedo.a);
    gl_FragData[1] = surfaceData(N, lmcoord.y, MAT_HAND);
}
