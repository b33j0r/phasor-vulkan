#version 450

layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUV;

layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 0) uniform sampler2D texSampler;
layout(set = 0, binding = 1) uniform LightUBO { vec4 lightDir; } ubo;

void main() {
    // Directional lighting from uniform (direction points from light toward scene)
    vec3 lightDir = normalize(ubo.lightDir.xyz);
    vec3 normal = normalize(fragNormal);
    float diff = max(dot(normal, -lightDir), 0.0);

    // Ambient + diffuse lighting
    float ambient = 0.4;
    float lighting = ambient + (1.0 - ambient) * diff;

    // Sample texture and multiply with vertex color
    vec4 texColor = texture(texSampler, fragUV);
    vec3 baseColor = texColor.rgb * fragColor.rgb;

    outColor = vec4(baseColor * lighting, texColor.a * fragColor.a);
}
