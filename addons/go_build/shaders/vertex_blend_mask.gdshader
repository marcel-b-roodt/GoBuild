// GoBuild Vertex Colour Blend Shader
//
// Mixes two albedo textures using vertex colour as a blend mask.
// The R channel of the vertex colour controls the mix between Texture 1 (R=0)
// and Texture 2 (R=1).
//
// Usage:
//   1. Assign this shader material to a GoBuildMesh material slot.
//   2. Set texture_1 and texture_2 to your two albedo textures.
//   3. Paint vertex colours — the R channel blends between the two textures.
//   4. Optionally use G/B/A channels for roughness, metallic, emission masks.
//
shader_type spatial;

uniform sampler2D texture_1 : repeat_disable, filter_linear_mipmap;
uniform sampler2D texture_2 : repeat_disable, filter_linear_mipmap;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float blend = COLOR.r;
	vec4 t1 = texture(texture_1, UV);
	vec4 t2 = texture(texture_2, UV);
	vec3 albedo = mix(t1.rgb, t2.rgb, blend);
	float alpha = mix(t1.a, t2.a, blend);

	ALBEDO = albedo;
	ALPHA = alpha;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}