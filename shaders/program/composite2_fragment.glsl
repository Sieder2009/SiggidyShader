// composite2.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/composite2.fsh, shaders/world-1/composite2.fsh
// and shaders/world1/composite2.fsh, which only set AURORA_WORLD (see lib/common.glsl).

// Temporal anti-aliasing. Every frame is drawn a fraction of a pixel shifted
// (taaJitter() in the gbuffers vertex shaders); this pass blends it with the
// accumulated history of the previous frames, looked up where each pixel WAS
// last frame. Over a few frames every pixel collects samples from several
// positions inside it: smooth edges, calm leaves and fences, and the noise of
// SSAO, clouds, light shafts and reflections averaged away.
// Runs after composite1, on the tonemapped picture, so very bright pixels
// can't dominate the blend. The whole pass is switched off with the
// TEMPORAL_AA option (program.composite2.enabled in shaders.properties).

#include "/lib/common.glsl"

uniform sampler2D colortex0; // this frame
uniform sampler2D colortex2; // surface data (to recognise the hand)
uniform sampler2D colortex4; // history: last frame's result
uniform sampler2D depthtex0;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 previousCameraPosition;

varying vec2 texcoord;

// Where this pixel's surface was on screen last frame: back to a world
// position, corrected by how far the camera moved, then through last frame's
// camera. The sky is infinitely far away - only the camera's turning moves
// it, not its movement.
vec2 previousUV(float depth) {
    vec4 view = gbufferProjectionInverse * vec4(vec3(texcoord, depth) * 2.0 - 1.0, 1.0);
    vec3 scenePos = (gbufferModelViewInverse * vec4(view.xyz / view.w, 1.0)).xyz;
    if (depth < 1.0) scenePos += cameraPosition - previousCameraPosition;
    vec4 prevClip = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(scenePos, 1.0));
    return prevClip.xy / prevClip.w * 0.5 + 0.5;
}

void main() {
    vec3 current = texture2D(colortex0, texcoord).rgb;
    vec3 color = current;

#ifdef AURORA_TAA
    // The range of colors around this pixel right now. History outside that
    // range belongs to something that has moved away or changed (a mob
    // walking past, the waves, a light switching on): clamping it into the
    // range is what keeps TAA from leaving ghostly trails.
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
    vec3 minColor = current;
    vec3 maxColor = current;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            if (x == 0 && y == 0) continue;
            vec3 c = texture2D(colortex0, texcoord + vec2(float(x), float(y)) * texel).rgb;
            minColor = min(minColor, c);
            maxColor = max(maxColor, c);
        }
    }

    // The first-person hand moves with the camera: it stays where it is.
    float depth = texture2D(depthtex0, texcoord).r;
    bool hand = materialOf(texture2D(colortex2, texcoord)) == MAT_HAND;
    vec2 prevUV = hand ? texcoord : previousUV(depth);

    float blend = TAA_BLEND;
    // Nothing to blend with where the pixel was off screen last frame.
    if (prevUV.x < 0.0 || prevUV.x > 1.0 || prevUV.y < 0.0 || prevUV.y > 1.0) blend = 0.0;
    // Fast movement: lean a little more on the current frame.
    float motion = length((prevUV - texcoord) * vec2(viewWidth, viewHeight));
    blend *= 1.0 - clamp(motion * 0.01, 0.0, 0.25);

    vec3 history = clamp(texture2D(colortex4, prevUV).rgb, minColor, maxColor);
    color = mix(current, history, blend);
#endif

    /* DRAWBUFFERS:04 */
    gl_FragData[0] = vec4(color, 1.0);
    gl_FragData[1] = vec4(color, 1.0);
}
