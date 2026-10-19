// gbuffers_terrain.vsh - vertex shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/gbuffers_terrain.vsh, shaders/world-1/gbuffers_terrain.vsh
// and shaders/world1/gbuffers_terrain.vsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"

attribute vec4 mc_Entity;      // .x = block ID from block.properties
attribute vec4 mc_midTexCoord; // center of this block's texture in the atlas

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 vColor;
varying vec3 viewPos;
varying vec3 viewNormal;
varying float vFoliage;  // 1 = plant/leaves (soft, two-sided lighting)
varying float vEmissive; // see emissiveKindOf() in common.glsl

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor   = gl_Color;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);

    int blockId = int(mc_Entity.x + 0.5);
    vFoliage = foliageOf(blockId);
    vEmissive = emissiveKindOf(blockId);

    gl_Position = ftransform();
    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;

    // Waving plants: only vertices that actually move leave ftransform()'s
    // invariant path, so nothing else can z-fight against other passes.
    // Must stay in lockstep with shadow.vsh.
    float wave = waveAmount(blockId, gl_MultiTexCoord0.t < mc_midTexCoord.t);
    if (wave > 0.0) {
        vec3 playerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
        playerPos += windOffset(playerPos + cameraPosition, wave);
        viewPos = (gbufferModelView * vec4(playerPos, 1.0)).xyz;
        gl_Position = gl_ProjectionMatrix * vec4(viewPos, 1.0);
    }
}
