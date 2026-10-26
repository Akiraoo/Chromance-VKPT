#version 460

// Draws nothing. Used for particles the pack hides (the dark specks vanilla scatters under water).

layout(location = 0) out vec4 fragColor;

void main() {
    discard;
}
