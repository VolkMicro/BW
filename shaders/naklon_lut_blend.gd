class_name NaklonLutBlend
extends RefCounted
## Optional helper for whichever package wires Environment post-processing
## (per docs/systems/OWNERSHIP.md that's package Q, environment/). Package D
## does not touch environment/world_environment.tres itself — this is just
## the CPU-side blend math, ready to call from wherever the Environment
## resource actually lives.
##
## Godot's Environment.adjustment_color_correction can only hold ONE texture
## at a time, and there is no built-in way to cross-fade two LUT textures on
## the GPU without a custom post shader. The two supported ways to use the
## static LUTs in materials/luts/ are:
##
##  1. POLE-SNAPPED (cheapest, no script needed): swap the texture on
##     `Naklon.pole_crossed` — assign naklon_lut_mercy_1d.png when pole == -1,
##     naklon_lut_cruelty_1d.png when pole == 1, naklon_lut_neutral_1d.png
##     (or just disable color correction) when pole == 0.
##
##  2. CONTINUOUS (this helper): call NaklonLutBlend.blended(Naklon.unit())
##     from a `Naklon.naklon_changed` handler and assign the result to
##     `environment.adjustment_color_correction`. This does a pixel-for-pixel
##     CPU lerp between the two 256x4 curve strips — 1024 pixels, trivial
##     cost — and is safe to call every time Naklon changes because that
##     signal only fires on player action, never per-frame. Do NOT call it
##     from _process()/_physics_process().
##
## Either way, also set `environment.adjustment_use_1d_color_correction = true`
## and `environment.adjustment_enabled = true` once.

const MERCY_PATH := "res://materials/luts/naklon_lut_mercy_1d.png"
const CRUELTY_PATH := "res://materials/luts/naklon_lut_cruelty_1d.png"

## Returns a freshly built ImageTexture blending the mercy and cruelty 1D
## LUT strips by `t` (pass Naklon.unit(): 0 = full mercy, 1 = full cruelty).
static func blended(t: float) -> ImageTexture:
	var mercy_tex: Texture2D = load(MERCY_PATH)
	var cruelty_tex: Texture2D = load(CRUELTY_PATH)
	var mercy_img: Image = mercy_tex.get_image()
	var cruelty_img: Image = cruelty_tex.get_image()
	var w := mercy_img.get_width()
	var h := mercy_img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	var tt := clampf(t, 0.0, 1.0)
	for y in h:
		for x in w:
			var a := mercy_img.get_pixel(x, y)
			var b := cruelty_img.get_pixel(x, y)
			out.set_pixel(x, y, a.lerp(b, tt))
	return ImageTexture.create_from_image(out)
