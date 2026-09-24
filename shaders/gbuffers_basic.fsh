#version 120

// Used for untextured geometry (selection outlines, world border, ...).
// Left unshaded on purpose - low risk, purely cosmetic elements.

varying vec4 vColor;

void main() {
    gl_FragColor = vColor;
}
