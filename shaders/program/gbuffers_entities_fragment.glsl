// gbuffers_entities.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_entities.fsh, shaders/world-1/gbuffers_entities.fsh
// and shaders/world1/gbuffers_entities.fsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"

uniform sampler2D tex;
uniform vec4 entityColor; // vanilla's red hurt flash / creeper fuse white flash (rgb + strength in a)

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;

void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;
    if (albedo.a < 0.1) discard;
    albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);

    vec3 N = normalize(viewNormal);
    vec3 color = shadeLit(albedo.rgb, N, viewPos, lmcoord, 0.0);
    color = applyFog(color, viewPos);

    /* DRAWBUFFERS:02 */
    gl_FragData[0] = vec4(color, albedo.a);
    gl_FragData[1] = surfaceData(N, lmcoord.y, MAT_SOLID);
}
