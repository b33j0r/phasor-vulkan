#version 450

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec4 inColor;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec2 fragUV; // UV coords for circle SDF

void main() {
    gl_Position = vec4(inPos, 1.0);
    fragColor = inColor;

    // Compute which corner of the quad this vertex represents
    // Create UV coords -1 to 1 based on vertex index pattern: 0,1,2 / 2,3,0
    fragUV = vec2(
        (gl_VertexIndex % 3 == 1 || gl_VertexIndex == 4) ? 1.0 : -1.0,
        (gl_VertexIndex >= 2 && gl_VertexIndex <= 4) ? 1.0 : -1.0
    );
}
