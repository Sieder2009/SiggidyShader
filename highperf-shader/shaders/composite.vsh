#version 120

// Trivialer Fullscreen-Pass-Through, notwendig als Begleiter zu composite.fsh.
varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
