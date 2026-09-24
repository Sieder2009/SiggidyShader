#version 120

#include "/lib/common.glsl"

#define EXPOSURE 1.05           // [0.7 0.8 0.9 1.0 1.05 1.1 1.2 1.3 1.5]
#define SATURATION 1.12         // [0.8 0.9 1.0 1.1 1.12 1.2 1.3]
#define VIGNETTE_STRENGTH 0.25  // [0.0 0.1 0.15 0.2 0.25 0.35 0.5]

uniform sampler2D colortex0;

varying vec2 texcoord;

vec3 adjustSaturation(vec3 color, float amount) {
    float l = luma(color);
    return mix(vec3(l), color, amount);
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;

    color *= EXPOSURE;
    color = tonemapACES(color);
    color = adjustSaturation(color, SATURATION);

    float dist = distance(texcoord, vec2(0.5));
    float vignette = smoothstep(0.3, 0.6, dist) * VIGNETTE_STRENGTH;
    color *= (1.0 - vignette);

    gl_FragColor = vec4(color, 1.0);
}
