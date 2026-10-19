// gbuffers_water.vsh - vertex shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_water.vsh, shaders/world-1/gbuffers_water.vsh
// and shaders/world1/gbuffers_water.vsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"

attribute vec4 mc_Entity;

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
// 1.0 for real water. This stage also draws every other translucent block
// (stained glass, ice, slime, honey, nether portal, ...), which must not
// get water's waves and sky mirror.
varying float vIsWater;

void main() {
    gl_Position = ftransform();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;

    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);
    worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
    topFace = step(0.5, gl_Normal.y);
    vIsWater = (int(mc_Entity.x + 0.5) == ID_WATER) ? 1.0 : 0.0;
}
