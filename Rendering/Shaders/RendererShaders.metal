#include <metal_stdlib>
using namespace metal;

struct VertexIn {
  float2 position [[attribute(0)]];
  float2 uv [[attribute(1)]];
};

struct VertexOut {
  float4 position [[position]];
  float2 uv;
};

vertex VertexOut vertexQuad(VertexIn in [[stage_in]]) {
  VertexOut out;
  out.position = float4(in.position, 0.0, 1.0);
  out.uv = in.uv;
  return out;
}

struct GradientUniforms {
  float4 startColor;
  float4 endColor;
  float2 direction;
  float2 padding;
};

fragment float4 fragmentBackground(
  VertexOut in [[stage_in]],
  constant GradientUniforms &uniforms [[buffer(0)]]
) {
  float2 dir = uniforms.direction;
  if (length(dir) < 0.0001) {
    dir = float2(1.0, 0.0);
  } else {
    dir = normalize(dir);
  }
  float t = dot(in.uv - 0.5, dir) + 0.5;
  t = clamp(t, 0.0, 1.0);
  float4 color = mix(uniforms.startColor, uniforms.endColor, t);
  color.rgb *= color.a;
  return color;
}

struct TextureUniforms {
  float opacity;
  float3 padding;
};

struct RoundedRectUniforms {
  float2 size;
  float cornerRadius;
  float edgeSoftness;
};

struct ColorUniforms {
  float4 color;
};

float roundedRectMask(float2 uv, float2 size, float radius, float softness) {
  if (radius <= 0.0 && softness <= 0.0) {
    return 1.0;
  }
  float2 halfSize = size * 0.5;
  float2 p = uv * size;
  float2 q = abs(p - halfSize) - (halfSize - radius);
  float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
  float edge = max(softness, 0.001);
  return 1.0 - smoothstep(0.0, edge, dist);
}

fragment float4 fragmentTexturedRounded(
  VertexOut in [[stage_in]],
  texture2d<float> tex [[texture(0)]],
  sampler samp [[sampler(0)]],
  constant TextureUniforms &textureUniforms [[buffer(0)]],
  constant RoundedRectUniforms &roundUniforms [[buffer(1)]]
) {
  float4 color = tex.sample(samp, in.uv);
  color.rgb *= textureUniforms.opacity;
  color.a *= textureUniforms.opacity;
  float mask = roundedRectMask(in.uv, roundUniforms.size, roundUniforms.cornerRadius, roundUniforms.edgeSoftness);
  return float4(color.rgb * mask, color.a * mask);
}

fragment float4 fragmentSolidRounded(
  VertexOut in [[stage_in]],
  constant ColorUniforms &colorUniforms [[buffer(0)]],
  constant RoundedRectUniforms &roundUniforms [[buffer(1)]]
) {
  float mask = roundedRectMask(in.uv, roundUniforms.size, roundUniforms.cornerRadius, roundUniforms.edgeSoftness);
  float4 color = colorUniforms.color;
  color.rgb *= color.a;
  return float4(color.rgb * mask, color.a * mask);
}
