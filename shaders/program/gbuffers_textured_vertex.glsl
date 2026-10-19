// gbuffers_textured.vsh - vertex shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_textured.vsh, shaders/world-1/gbuffers_textured.vsh
// and shaders/world1/gbuffers_textured.vsh, which only set AURORA_WORLD (see lib/common.glsl).

varying vec2 texcoord;
varying vec4 vColor;
varying vec3 viewPos;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
}
