// Color regions of the rider and bike (T-106a3, REQ-D3D-09 p.6, REQ-AVT-02; art bible "Rider" ->
// "Appearance slots", "Color regions in glTF"). The region code is in UV0: U is the column of the
// 32-column atlas (region k = floor(U * 32)), V is the tone in the Blender convention flipped by
// glTF: tone = 0.6 + 0.8 * (1 - UV.y). Region colors are the appearance palette — a material
// parameter (sRGB), so a color change is a palette write, not a mesh rebuild. Mirror for tests
// and the artist atlas: `RiderRegions.preview_color` / `RiderPalette.albedo`.
#ifndef RIDER_REGIONS_INC
#define RIDER_REGIONS_INC

const int RIDER_REGION_COUNT = 32;
const int RIDER_LENS = 19;
const float RIDER_LENS_HIGHLIGHT_V = 0.75;
const float RIDER_TONE_MIN = 0.6;
const float RIDER_TONE_SPAN = 0.8;

int rider_region(vec2 uv) {
	return clamp(int(floor(uv.x * float(RIDER_REGION_COUNT))), 0, RIDER_REGION_COUNT - 1);
}

// Tone V in the Blender convention (0 — atlas bottom).
float rider_tone_v(vec2 uv) {
	return 1.0 - uv.y;
}

#endif
