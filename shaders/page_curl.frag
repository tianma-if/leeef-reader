#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uProgress;
uniform float uDirection;
uniform float uTouchY;
uniform sampler2D uCurrentPage;
uniform sampler2D uNextPage;

out vec4 fragColor;

vec2 directedUV(vec2 uv) {
  return uDirection > 0.0 ? uv : vec2(1.0 - uv.x, uv.y);
}


bool insidePage(vec2 uv) {
  return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 local = directedUV(uv);
  float progress = clamp(uProgress, 0.0, 1.0);
  vec4 currentColor = texture(uCurrentPage, uv);
  vec4 nextColor = texture(uNextPage, uv);

  if (progress <= 0.001) {
    fragColor = currentColor;
    return;
  }
  if (progress >= 0.999) {
    fragColor = nextColor;
    return;
  }

  // Treat the page as a sheet pulled from its lower outside corner. The fold
  // axis is the perpendicular bisector between the corner and the moving
  // touch point, so changing either x or y produces a genuinely oblique curl.
  vec2 corner = vec2(1.0, 0.94);
  vec2 touch = vec2(1.0 - 1.34 * progress, uTouchY);
  vec2 pull = corner - touch;
  float pullLength = max(length(pull), 0.0001);
  vec2 normal = pull / pullLength;
  vec2 tangent = vec2(-normal.y, normal.x);
  vec2 foldCenter = (corner + touch) * 0.5;

  float tangentDistance = dot(local - foldCenter, tangent);
  float bow = 0.035 * sin(3.14159265 * progress) *
      (1.0 - min(abs(tangentDistance), 1.0));
  float signedDistance = dot(local - foldCenter, normal) + bow;

  // The first part of the folded sheet wraps around a cylinder. Once half a
  // cylinder is used, the remaining sheet continues as a softly lit back face.
  float radius = clamp(pullLength * 0.16, 0.025, 0.115);
  float flatBackLength = max(pullLength - 3.14159265 * radius, 0.0);
  float flapExtent = radius + flatBackLength;

  if (signedDistance > 0.0) {
    float castShadow = mix(
      0.70,
      1.0,
      smoothstep(0.0, radius * 2.4, signedDistance)
    );
    fragColor = vec4(nextColor.rgb * castShadow, nextColor.a);
    return;
  }

  float behindFold = -signedDistance;
  if (behindFold > flapExtent) {
    float contactShadow = 1.0 - 0.12 *
        (1.0 - smoothstep(flapExtent, flapExtent + radius, behindFold));
    fragColor = vec4(currentColor.rgb * contactShadow, currentColor.a);
    return;
  }

  float sourceDistance;
  float light;
  if (behindFold <= radius) {
    float cylinderX = clamp(behindFold / radius, 0.0, 1.0);
    float angle = 3.14159265 - asin(cylinderX);
    sourceDistance = radius * angle;
    float roundLight = sqrt(max(1.0 - cylinderX * cylinderX, 0.0));
    light = 0.64 + 0.38 * roundLight;
    light += 0.12 * pow(max(1.0 - abs(cylinderX - 0.72) * 5.0, 0.0), 2.0);
  } else {
    sourceDistance = 3.14159265 * radius + behindFold - radius;
    light = 0.80 + 0.08 * smoothstep(radius, flapExtent, behindFold);
  }

  vec2 sourceLocal = local + normal * (behindFold + sourceDistance);
  if (!insidePage(sourceLocal)) {
    fragColor = currentColor;
    return;
  }

  vec2 sourceUV = directedUV(sourceLocal);
  vec4 pageInk = texture(uCurrentPage, sourceUV);
  vec3 paperBack = mix(pageInk.rgb, vec3(0.965, 0.945, 0.895), 0.20);
  float edge = smoothstep(0.0, 0.008, behindFold) *
      smoothstep(flapExtent, flapExtent - 0.008, behindFold);
  fragColor = vec4(paperBack * light * edge, pageInk.a);
}
