// gbuffers_terrain.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_terrain.fsh, shaders/world-1/gbuffers_terrain.fsh
// and shaders/world1/gbuffers_terrain.fsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"

uniform sampler2D tex;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;
varying float vFoliage;
varying float vEmissive;

void main() {
    vec4 albedo = texture2D(tex, texcoord) * vColor;
    if (albedo.a < 0.1) discard;

    vec3 N = normalize(viewNormal);
    vec3 color = shadeLit(albedo.rgb, N, viewPos, lmcoord, vFoliage);
    color += blockEmission(albedo.rgb, vEmissive);
    color = applyFog(color, viewPos);

    gl_FragColor = vec4(color, albedo.a);
}
