#version 120

// Identisch zum Overworld-Pendant (shaders/composite.vsh) - trivialer
// Fullscreen-Pass-Through, notwendiger Begleiter zu composite.fsh.
varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
