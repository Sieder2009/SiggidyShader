#version 120

#include "/lib/common.glsl"

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;
varying vec3 worldPos;
// 1.0 for an upward-facing quad (top of water), 0.0 otherwise. Computed
// from the OBJECT-SPACE normal (gl_Normal), which for axis-aligned terrain
// reliably means "world up" - unlike the view-space normal, whose .y
// component depends on camera pitch and would give the wrong answer.
varying float topFace;

void main() {
    gl_Position = ftransform();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);
    worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
    topFace = step(0.5, gl_Normal.y);
}
