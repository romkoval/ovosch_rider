// Rider and bike outline (T-106a3, REQ-D3D-07 "Outline", REQ-D3D-09 p.7): inverted hull, second
// pass of the rider material. Vertices move along the smoothed outline normal (TANGENT, average
// over all vertices at one position — `MeshKit.finalize_regions`; skinning moves it with the
// bone), so hard edges and region seams do not tear the outline. Thickness `outline_width` m x
// the outline weight of the vertex region (`region_outline`, table of regions: 0 for 18, 19,
// 20, 25, 28, 29) — weight 0 collapses the vertex, the pass draws nothing there.
// Compatibility: its skinning (Godot 4.7, transform feedback) hands the scene shader a wrong
// TANGENT for skinned meshes (constant per bone — checked on the mannequin), so there the hull
// uses NORMAL as before T-106a3 (no smoothing at hard edges; region seams do not tear it: the
// duplicated vertices keep their normals). Forward+ and Mobile skin TANGENT in the skeleton
// compute shader together with NORMAL.
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
#include "res://src/scene3d/shaders/render_look.gdshaderinc"
#include "res://src/scene3d/shaders/rider_regions.gdshaderinc"

uniform vec4 outline_color : source_color = vec4(0.07, 0.06, 0.09, 1.0);
uniform float outline_width = 0.011;
// Outline weight per region (0-31).
uniform float region_outline[32];

void vertex() {
	float w = region_outline[rider_region(UV)];
	if (w < 0.01) {
		VERTEX = vec3(0.0);
	} else {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 dir = NORMAL;
#else
		vec3 dir = normalize(TANGENT);
#endif
		VERTEX += dir * outline_width * w;
	}
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
