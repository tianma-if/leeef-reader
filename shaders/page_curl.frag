#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uProgress;
uniform float uDirection;
uniform sampler2D uCurrentPage;
uniform sampler2D uNextPage;

out vec4 fragColor;

vec2 directedUV(vec2 uv) {
  return uDirection > 0.0 ? uv : vec2(1.0 - uv.x, uv.y);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 local = directedUV(uv);
  float progress = clamp(uProgress, 0.0, 1.0);
  float fold = 1.0 - progress;
  float curlWidth = mix(0.16, 0.08, progress);
  float distanceFromFold = local.x - fold;

  if (distanceFromFold <= 0.0) {
    fragColor = texture(uCurrentPage, uv);
    return;
  }

  if (distanceFromFold >= curlWidth) {
    vec4 nextColor = texture(uNextPage, uv);
    float shadowFade = smoothstep(
      0.0,
      curlWidth * 2.0,
      distanceFromFold - curlWidth
    );
    float shadow = mix(0.80, 1.0, shadowFade);
    fragColor = vec4(nextColor.rgb * shadow, nextColor.a);
    return;
  }

  float t = distanceFromFold / curlWidth;
  // A parabolic half-wave is visually close to sin(pi * t) and avoids a
  // transcendental operation for every pixel in the curl strip.
  float arc = 4.0 * t * (1.0 - t);
  float sampleX = clamp(fold - t * curlWidth * 0.82, 0.0, 1.0);
  vec2 foldedLocal = vec2(sampleX, clamp(local.y + arc * 0.012, 0.0, 1.0));
  vec2 foldedUV = directedUV(foldedLocal);
  vec4 pageColor = texture(uCurrentPage, foldedUV);
  vec4 nextColor = texture(uNextPage, uv);

  float edgeLight = 0.78 + 0.30 * arc;
  vec3 paperBack = mix(pageColor.rgb, vec3(0.94, 0.92, 0.86), 0.34);
  float reveal = smoothstep(0.72, 1.0, t);
  vec3 curlColor = paperBack * edgeLight;
  fragColor = vec4(mix(curlColor, nextColor.rgb, reveal), 1.0);
}
