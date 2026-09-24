#version 120

// GUI-editable shadow map settings (Iris/OptiFine scan for these two names).
const int shadowMapResolution = 2048; // [1024 2048 4096]
const float shadowDistance = 160.0;   // [64.0 96.0 128.0 160.0 200.0 256.0]

uniform sampler2D tex;

varying vec2 texcoord;

void main() {
    // Alpha-test cutout foliage (leaves, grass, ...) so it casts a
    // correctly shaped shadow instead of a solid quad.
    if (texture2D(tex, texcoord).a < 0.1) discard;
    gl_FragColor = vec4(1.0);
}
