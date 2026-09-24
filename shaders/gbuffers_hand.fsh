#version 120

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
    vec3 color = shadeLitCustom(albedo.rgb, N, viewPos, lmcoord, 1.0);
    color = applyFog(color, viewPos);

    gl_FragColor = vec4(color, albedo.a);
}
