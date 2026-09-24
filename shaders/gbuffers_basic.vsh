#version 120

varying vec4 vColor;

void main() {
    gl_Position = ftransform();
    vColor = gl_Color;
}
