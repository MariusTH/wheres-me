class_name PaperOverlay
extends Node2D
## Storybook maps only: re-grades the rendered town (slight desaturation, warm
## sepia inks) and adds a faint watercolour-paper grain over everything,
## ground and objects alike, so code-drawn people and painted houses read as
## one illustration. Fixed to the world (the paper
## does not slide when the camera pans). Purely cosmetic: never part of
## visibility checks, never takes input.

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.1;
uniform float desaturate = 0.12;
varying vec2 world;

void vertex() {
	world = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	// One shared grade: slightly desaturated, warm, inks lifted to sepia
	// rather than black, so every layer reads as the same watercolour.
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desaturate);
	c = mix(vec3(0.2, 0.13, 0.1), vec3(1.0, 0.98, 0.94), c);
	float bloom = noise(world / 420.0) * 0.6 + noise(world / 150.0) * 0.4;
	float grain = noise(world / 3.0) * 0.5 + noise(world / 9.0) * 0.5;
	c *= 1.0 - strength * (bloom * 0.7 + grain * 0.5);
	COLOR = vec4(c, 1.0);
}
"""

var _rect: Rect2


func setup(bounds: Rect2) -> void:
	_rect = bounds
	z_index = 100
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	material = mat
	queue_redraw()


func _draw() -> void:
	draw_rect(_rect, Color.WHITE)
