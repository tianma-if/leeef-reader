#version 320 es

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform vec2 u_fold_center;
uniform vec2 u_normal;
uniform vec2 u_tangent;
uniform float u_radius;
uniform float u_direction;
uniform sampler2D u_current_page;
uniform sampler2D u_next_page;

layout(location = 0) out vec4 frag_color;

const float PI = 3.14159265358979323846;

bool inside_page(vec2 p) {
  return p.x >= 0.0 && p.y >= 0.0 && p.x <= u_size.x && p.y <= u_size.y;
}

vec2 texture_uv(vec2 geometry_position) {
  vec2 uv = geometry_position / u_size;
  if (u_direction < 0.0) {
    uv.x = 1.0 - uv.x;
  }
  return clamp(uv, vec2(0.0), vec2(1.0));
}

void main() {
  vec2 screen = FlutterFragCoord().xy;
  vec2 geometry = screen;
  if (u_direction < 0.0) {
    geometry.x = u_size.x - geometry.x;
  }

  vec2 from_fold = geometry - u_fold_center;
  float along_axis = dot(from_fold, u_tangent);
  float projected_normal = dot(from_fold, u_normal);

  // Invert the visible half of the cylindrical fold. The solution using
  // PI-asin() is the half facing the viewer and therefore occludes the front.
  bool has_back = false;
  float angle = 0.0;
  float source_distance = 0.0;
  if (projected_normal >= 0.0 && projected_normal <= u_radius) {
    float cylinder_t = clamp(projected_normal / u_radius, 0.0, 1.0);
    angle = PI - cylinder_t * (1.25 + 0.3207963 * cylinder_t);
    source_distance = u_radius * angle;
    has_back = true;
  } else if (projected_normal < 0.0) {
    angle = PI;
    source_distance = PI * u_radius - projected_normal;
    has_back = true;
  }

  vec2 back_source =
    u_fold_center + u_tangent * along_axis + u_normal * source_distance;
  has_back = has_back && inside_page(back_source);

  vec2 base_uv = screen / u_size;
  vec4 color;
  if (has_back) {
    vec4 ink = texture(u_current_page, texture_uv(back_source));
    float grazing = abs(sin(angle));
    float paper_light = 0.79 + grazing * 0.11;
    vec3 warm_paper = vec3(1.0, 0.965, 0.875);
    color = vec4(mix(ink.rgb * paper_light, warm_paper, 0.36), ink.a);

    float edge_distance = min(
      min(back_source.x, u_size.x - back_source.x),
      min(back_source.y, u_size.y - back_source.y)
    );
    float edge_highlight = 1.0 - smoothstep(0.0, 2.2, edge_distance);
    color.rgb = mix(color.rgb, vec3(1.0, 0.99, 0.94), edge_highlight * 0.72);
  } else if (projected_normal <= 0.0 && inside_page(geometry)) {
    color = texture(u_current_page, base_uv);
  } else {
    color = texture(u_next_page, base_uv);
    float shadow_distance = max(projected_normal - u_radius, 0.0);
    float contact_shadow = 1.0 - smoothstep(
      0.0,
      max(u_radius * 0.9, 1.0),
      shadow_distance
    );
    color.rgb *= 1.0 - contact_shadow * 0.13;
  }

  // A narrow soft crease makes the sheet read as paper rather than a wipe.
  float crease = 1.0 - smoothstep(
    0.0,
    max(u_radius * 0.42, 1.0),
    abs(projected_normal - u_radius)
  );
  color.rgb = mix(color.rgb, vec3(1.0, 0.985, 0.92), crease * 0.08);
  frag_color = color;
}
