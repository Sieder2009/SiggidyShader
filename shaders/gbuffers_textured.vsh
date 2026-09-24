#version 120

varying vec2 texcoord;
varying vec4 vColor;
varying vec3 viewPos;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
}
