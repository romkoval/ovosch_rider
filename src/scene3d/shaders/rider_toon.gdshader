// Rider and bike toon material (T-106a3, REQ-D3D-09 p.6-7, REQ-D3D-07; art bible "Rider"): one
// material for all 10 mesh nodes, the outline is `next_pass` (`rider_outline.gdshader`). A face's
// color is its region (UV0, `rider_regions.gdshaderinc`) looked up in the appearance palette:
// linear albedo = min(1, tone * to_linear(palette[k])); faces of the lens (region 19) with
// V >= 0.75 take `lens_highlight` flat, without tone. Vertex colors are not used. Light — the
// shared two-tone toon light; the rim is additive (`toon_light.gdshaderinc`), so it shows on
// a black jersey too.
shader_type spatial;
render_mode cull_back;

#include "res://src/scene3d/shaders/toon_light.gdshaderinc"
#include "res://src/scene3d/shaders/render_look.gdshaderinc"
#include "res://src/scene3d/shaders/rider_regions.gdshaderinc"

// Appearance palette: 32 region colors, sRGB (alpha unused). Default — preset `classic`.
uniform vec4 palette[32];
// Lens highlight color (region 19, V >= 0.75), sRGB.
uniform vec4 lens_highlight = vec4(0.42, 0.44, 0.50, 1.0);

varying vec3 v_albedo;

void vertex() {
	int k = rider_region(UV);
	float v = rider_tone_v(UV);
	vec3 lin;
	if (k == RIDER_LENS && v >= RIDER_LENS_HIGHLIGHT_V) {
		lin = look_to_linear(lens_highlight.rgb);
	} else {
		lin = min(vec3(1.0), (RIDER_TONE_MIN + RIDER_TONE_SPAN * v) * look_to_linear(palette[k].rgb));
	}
	// Same renderer alignment as vertex colors of the world (T-102, `render_look.gdshaderinc`).
	v_albedo = look_vertex_color(lin);
}

void fragment() {
	ALBEDO = v_albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
