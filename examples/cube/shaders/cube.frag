#version 450

layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec3 fragNormal;

layout(location = 0) out vec4 outColor;

void main() {
    // Simple directional lighting
    vec3 lightDir = normalize(vec3(0.5, -0.7, 0.3));
    vec3 normal = normalize(fragNormal);
    float diff = max(dot(normal, -lightDir), 0.0);

    // Ambient + diffuse lighting
    float ambient = 0.4;
    float lighting = ambient + (1.0 - ambient) * diff;

    // Use vertex color directly (no texture)
    outColor = vec4(fragColor.rgb * lighting, fragColor.a);
}
