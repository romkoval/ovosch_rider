class_name RiderPalette
extends RefCounted
## Appearance palette of the rider material (T-106a3, REQ-D3D-09 p.6-7, REQ-AVT-02 p.1-2; art
## bible "Rider" -> "Appearance slots"). The rider toon material (`rider_toon.gdshader`) holds
## 32 region colors (`palette`, sRGB; stored as `PackedVector4Array` — the type of a `vec4[]`
## uniform: a `PackedColorArray` value is lost by `Resource.duplicate` in Godot 4.7) and the
## lens highlight color (`lens_highlight`, sRGB, stored as `Vector4` for the same reason); the
## outline pass holds the outline weight per region (`region_outline`). Writing a region color
## changes the color of that region's faces only — the meshes are not rebuilt.
##
## Jersey patterns: `jersey_regions` maps slot values to the colors of regions 3-7 by the
## pattern table of the spec. The 3D layer does not depend on `src/profiles/`: the input is a
## dictionary "slot -> value" where the pattern is a string and colors are `Color` (sRGB);
## T-109 builds it from `RiderLook`. Build time only, not per frame.

const PALETTE_PARAM: StringName = &"palette"
const LENS_HIGHLIGHT_PARAM: StringName = &"lens_highlight"
const OUTLINE_PARAM: StringName = &"region_outline"
const COUNT: int = 32
const LENS: int = 19
const LENS_HIGHLIGHT_V: float = 0.75
const TONE_MIN: float = 0.6
const TONE_SPAN: float = 0.8

const JERSEY_PATTERN: String = "jersey.pattern"
const JERSEY_MAIN: String = "jersey.main"
const JERSEY_ACCENT1: String = "jersey.accent1"
const JERSEY_ACCENT2: String = "jersey.accent2"
const DEFAULT_PATTERN: String = "side_panels"
## First jersey pattern region (3 sides, 4 band, 5 shoulders, 6 cuffs, 7 collar).
const JERSEY_FIRST: int = 3
const JERSEY_MAIN_REGION: int = 2
## The bottle takes `jersey.accent2` (table of regions).
const BOTTLE_REGION: int = 31
## Pattern -> source of regions 3-7: `main`, `a1` (accent1), `a2` (accent2).
const PATTERN_SOURCES: Dictionary = {
	"solid": ["main", "main", "main", "a1", "a1"],
	"side_panels": ["a1", "main", "main", "a2", "a2"],
	"chest_band": ["main", "a1", "main", "a1", "a2"],
	"shoulder_yoke": ["a2", "main", "a1", "a1", "a1"],
}


## Colors of regions 3-7 for `values` ("jersey.pattern" — string, unknown -> `side_panels`;
## "jersey.main"/"accent1"/"accent2" — `Color`, missing -> white/red/blue of `classic`).
static func jersey_regions(values: Dictionary) -> Array[Color]:
	var pattern: Variant = values.get(JERSEY_PATTERN, DEFAULT_PATTERN)
	if not (pattern is String and PATTERN_SOURCES.has(pattern)):
		pattern = DEFAULT_PATTERN
	var src: Dictionary = {
		"main": _color(values, JERSEY_MAIN, Color(0.95, 0.95, 0.96)),
		"a1": _color(values, JERSEY_ACCENT1, Color(0.86, 0.14, 0.16)),
		"a2": _color(values, JERSEY_ACCENT2, Color(0.18, 0.28, 0.72)),
	}
	var out: Array[Color] = []
	for key in PATTERN_SOURCES[pattern]:
		out.append(src[key])
	return out


## Copy of `palette` with the jersey written from `values`: region 2 (main), 3-7 by the
## pattern, 31 (bottle) = accent2.
static func with_jersey(palette: PackedColorArray, values: Dictionary) -> PackedColorArray:
	var out: PackedColorArray = palette.duplicate()
	var cols: Array[Color] = jersey_regions(values)
	for i in cols.size():
		out[JERSEY_FIRST + i] = cols[i]
	out[JERSEY_MAIN_REGION] = _color(values, JERSEY_MAIN, Color(0.95, 0.95, 0.96))
	out[BOTTLE_REGION] = _color(values, JERSEY_ACCENT2, Color(0.18, 0.28, 0.72))
	return out


## Palette of `material` as colors (sRGB).
static func palette_of(material: ShaderMaterial) -> PackedColorArray:
	var out := PackedColorArray()
	var stored: Variant = material.get_shader_parameter(PALETTE_PARAM)
	if stored is PackedVector4Array:
		for v in stored as PackedVector4Array:
			out.append(Color(v.x, v.y, v.z, v.w))
	return out


static func lens_highlight_of(material: ShaderMaterial) -> Color:
	var v: Variant = material.get_shader_parameter(LENS_HIGHLIGHT_PARAM)
	return Color(v.x, v.y, v.z, v.w) if v is Vector4 else Color.BLACK


## Write the palette (32 colors, sRGB) and the lens highlight into `material`.
static func write(material: ShaderMaterial, palette: PackedColorArray, lens_highlight: Color) -> void:
	assert(palette.size() == COUNT, "RiderPalette: %d colors, expected %d" % [palette.size(), COUNT])
	material.set_shader_parameter(PALETTE_PARAM, _to_vec4(palette))
	material.set_shader_parameter(LENS_HIGHLIGHT_PARAM, Vector4(lens_highlight.r, lens_highlight.g,
		lens_highlight.b, lens_highlight.a))


## Write the color of region `code` only.
static func write_region(material: ShaderMaterial, code: int, color: Color) -> void:
	var palette: PackedColorArray = palette_of(material)
	palette[code] = color
	material.set_shader_parameter(PALETTE_PARAM, _to_vec4(palette))


## Outline weight of region `code` in the outline pass of `material`.
static func outline_weight(material: ShaderMaterial, code: int) -> float:
	var weights: PackedFloat32Array = (material.next_pass as ShaderMaterial).get_shader_parameter(OUTLINE_PARAM)
	return weights[code]


## Albedo of the rider shader before light (sRGB) for region `code` and tone V (Blender
## convention): min(1, tone * to_linear(c)) in linear space, back to sRGB; lens faces with
## V >= 0.75 — the highlight color without tone. Mirror of `rider_toon.gdshader` (and of
## `RiderRegions.preview_color`, the artist atlas).
static func albedo(palette: PackedColorArray, lens_highlight: Color, code: int, v: float) -> Color:
	if code == LENS and v >= LENS_HIGHLIGHT_V:
		return Color(lens_highlight.r, lens_highlight.g, lens_highlight.b)
	var lin: Color = palette[code].srgb_to_linear() * (TONE_MIN + TONE_SPAN * v)
	return Color(minf(lin.r, 1.0), minf(lin.g, 1.0), minf(lin.b, 1.0)).linear_to_srgb()


static func _to_vec4(palette: PackedColorArray) -> PackedVector4Array:
	var out := PackedVector4Array()
	for c in palette:
		out.append(Vector4(c.r, c.g, c.b, c.a))
	return out


static func _color(values: Dictionary, key: String, fallback: Color) -> Color:
	var c: Variant = values.get(key, fallback)
	return c if c is Color else fallback
