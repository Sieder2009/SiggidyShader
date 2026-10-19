// gbuffers_entities.vsh - vertex shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_entities.vsh, shaders/world-1/gbuffers_entities.vsh
// and shaders/world1/gbuffers_entities.vsh, which only set AURORA_WORLD (see lib/common.glsl).

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;

void main() {
    gl_Position = ftransform();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);
}
