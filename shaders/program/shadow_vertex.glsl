// shadow.vsh - vertex shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/shadow.vsh, shaders/world-1/shadow.vsh
// and shaders/world1/shadow.vsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

uniform mat4 shadowModelViewInverse;

varying vec2 texcoord;

void main() {
    gl_Position = ftransform();

    // Waving plants cast waving shadows: the exact same windOffset() as
    // gbuffers_terrain.vsh, applied in the same (player) space, so a plant
    // and its shadow move together.
    float wave = waveAmount(int(mc_Entity.x + 0.5), gl_MultiTexCoord0.t < mc_midTexCoord.t);
    if (wave > 0.0) {
        vec3 playerPos = (shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
        playerPos += windOffset(playerPos + cameraPosition, wave);
        gl_Position = shadowProjection * (shadowModelView * vec4(playerPos, 1.0));
    }

    gl_Position.xyz = distortShadowClip(gl_Position.xyz);
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
