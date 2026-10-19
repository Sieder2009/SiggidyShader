// final.fsh - fragment shader body, shared by all dimensions.
// Compiled through the thin wrappers shaders/final.fsh, shaders/world-1/final.fsh
// and shaders/world1/final.fsh, which only set AURORA_WORLD (see lib/common.glsl).

#include "/lib/common.glsl"

// Exposure/tonemap/saturation now live in composite1.fsh (right after
// bloom, while the image is still linear HDR) - this stage only does
// screen-space antialiasing, vignette and dither, all of which want to run
// on the final, already-tonemapped LDR image.

#define ENABLE_FXAA // Cheap edge antialiasing on the final image. Off in Low/Potato profiles.
#define FXAA_STRENGTH 0.75 // [0.25 0.5 0.75 1.0]

#define VIGNETTE_STRENGTH 0.25  // [0.0 0.1 0.15 0.2 0.25 0.35 0.5]

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

#ifdef ENABLE_FXAA
// Lightweight edge antialiasing, loosely modelled on the well known public
// FXAA algorithm (Timothy Lottes / NVIDIA's FXAA whitepaper): find the local
// contrast in a 3x3 luma neighbourhood, decide whether the edge runs mostly
// horizontally or vertically, then blend a little along it. Deliberately
// skips FXAA's usual iterative end-of-edge search to stay simple and cheap -
// most jaggies are still caught, at a small, fixed, per-pixel cost.
vec3 fxaaLite(vec2 uv, vec3 colorCenter) {
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);

    vec3 colorN = texture2D(colortex0, uv + vec2(0.0,  texel.y)).rgb;
    vec3 colorS = texture2D(colortex0, uv + vec2(0.0, -texel.y)).rgb;
    vec3 colorE = texture2D(colortex0, uv + vec2( texel.x, 0.0)).rgb;
    vec3 colorW = texture2D(colortex0, uv + vec2(-texel.x, 0.0)).rgb;

    float lumaC = luma(colorCenter);
    float lumaN = luma(colorN);
    float lumaS = luma(colorS);
    float lumaE = luma(colorE);
    float lumaW = luma(colorW);

    float lumaMin = min(lumaC, min(min(lumaN, lumaS), min(lumaE, lumaW)));
    float lumaMax = max(lumaC, max(max(lumaN, lumaS), max(lumaE, lumaW)));
    float range = lumaMax - lumaMin;

    // Flat area - skip the rest entirely. The common case for most pixels.
    if (range < max(0.0312, lumaMax * 0.125)) return colorCenter;

    vec3 colorNE = texture2D(colortex0, uv + vec2( texel.x,  texel.y)).rgb;
    vec3 colorNW = texture2D(colortex0, uv + vec2(-texel.x,  texel.y)).rgb;
    vec3 colorSE = texture2D(colortex0, uv + vec2( texel.x, -texel.y)).rgb;
    vec3 colorSW = texture2D(colortex0, uv + vec2(-texel.x, -texel.y)).rgb;

    float lumaNE = luma(colorNE);
    float lumaNW = luma(colorNW);
    float lumaSE = luma(colorSE);
    float lumaSW = luma(colorSW);

    float edgeHorizontal = abs(lumaNW + lumaSW - 2.0 * lumaW) +
                            abs(lumaN  + lumaS  - 2.0 * lumaC) * 2.0 +
                            abs(lumaNE + lumaSE - 2.0 * lumaE);
    float edgeVertical   = abs(lumaNW + lumaNE - 2.0 * lumaN) +
                            abs(lumaW  + lumaE  - 2.0 * lumaC) * 2.0 +
                            abs(lumaSW + lumaSE - 2.0 * lumaS);
    bool isHorizontalEdge = edgeHorizontal >= edgeVertical;

    // Step perpendicular to the edge, toward whichever side has the larger
    // luma gradient (the direction the true edge more likely leans toward).
    vec2 edgeStep = isHorizontalEdge ? vec2(0.0, texel.y) : vec2(texel.x, 0.0);
    float gradient1 = isHorizontalEdge ? abs(lumaS - lumaC) : abs(lumaW - lumaC);
    float gradient2 = isHorizontalEdge ? abs(lumaN - lumaC) : abs(lumaE - lumaC);
    float stepSign = gradient1 >= gradient2 ? -1.0 : 1.0;

    vec3 blended = texture2D(colortex0, uv + edgeStep * stepSign * 0.5).rgb;
    vec3 average4 = (colorN + colorS + colorE + colorW) * 0.25;

    float blendFactor = clamp(range / max(lumaMax, 0.0001), 0.0, 1.0) * FXAA_STRENGTH;
    return mix(colorCenter, mix(average4, blended, 0.5), blendFactor);
}
#endif

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;

#ifdef ENABLE_FXAA
    color = fxaaLite(texcoord, color);
#endif

    float dist = distance(texcoord, vec2(0.5));
    float vignette = smoothstep(0.3, 0.6, dist) * VIGNETTE_STRENGTH;
    color *= (1.0 - vignette);

    // Dither right before the image is quantized to the display's 8 bit
    // buffer, to break up banding in smooth gradients (sky, fog, vignette).
    color += (ditherPattern(gl_FragCoord.xy) - 0.5) * (1.0 / 255.0);

    gl_FragColor = vec4(color, 1.0);
}
