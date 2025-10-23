#version 450

layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec2 fragUV;

layout(location = 0) out vec4 outColor;

void main() {
    // SDF circle: distance from center
    float dist = length(fragUV);

    // Discard pixels outside circle (with antialiasing)
    float alpha = smoothstep(1.0, 0.98, dist);

    if (alpha < 0.01) {
        discard;
    }

    outColor = vec4(fragColor.rgb, fragColor.a * alpha);
}
