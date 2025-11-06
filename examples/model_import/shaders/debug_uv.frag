#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec3 fragNormal;

layout(location = 0) out vec4 outColor;

void main() {
    // UV gradient: red = U, green = V, blue = 0
    outColor = vec4(fragUV.x, fragUV.y, 0.0, 1.0);
}
