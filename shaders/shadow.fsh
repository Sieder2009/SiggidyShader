#version 120

// shadowMapResolution and shadowDistance (the GUI-editable shadow-pass
// constants) both live in common.glsl now, included by shadow.vsh - this
// file doesn't need to declare either itself. It also deliberately does NOT
// include common.glsl: this file renders INTO shadowtex0, and common.glsl
// declares shadowtex0 as a sampler input, which would be a pointless (if
// harmless, since it's unused/dead-code-eliminated) read/write aliasing risk
// to avoid entirely rather than rely on the compiler for.

uniform sampler2D tex;

varying vec2 texcoord;

void main() {
    // Alpha-test cutout foliage (leaves, grass, ...) so it casts a
    // correctly shaped shadow instead of a solid quad.
    if (texture2D(tex, texcoord).a < 0.1) discard;
    gl_FragColor = vec4(1.0);
}
