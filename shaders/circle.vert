#version 450

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec4 inColor;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec2 fragUV; // UV coords for circle SDF

void main() {
    gl_Position = vec4(inPos, 1.0);
    fragColor = inColor;

    // Compute which corner of the quad this vertex represents
    // Vertex pattern: 0=p1, 1=p2, 2=p3, 3=p3, 4=p4, 5=p1
    // UV mapping: p1=(-1,-1), p2=(1,-1), p3=(1,1), p4=(-1,1)
    int idx = gl_VertexIndex % 6;
    if (idx == 0 || idx == 5) {
        fragUV = vec2(-1.0, -1.0); // p1: bottom-left
    } else if (idx == 1) {
        fragUV = vec2(1.0, -1.0);  // p2: bottom-right
    } else if (idx == 2 || idx == 3) {
        fragUV = vec2(1.0, 1.0);   // p3: top-right
    } else {
        fragUV = vec2(-1.0, 1.0);  // p4: top-left
    }
}
