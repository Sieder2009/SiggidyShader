#version 120

#include "/lib/common.glsl"

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();
    gl_Position.xyz = distortShadowClip(gl_Position.xyz);
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
