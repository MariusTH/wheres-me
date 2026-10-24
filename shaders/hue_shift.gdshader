shader_type canvas_item;
// Rotates the hue of decoy critters (see WorldObjectData.hue) so only the
// hidden critter keeps its original colours. Alpha is untouched.

uniform float hue : hint_range(0.0, 1.0) = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	// Shift the sprite only, then apply COLOR, so markers and the red
	// wrong-guess flash keep their colours (untextured draws sample white).
	vec4 t = texture(TEXTURE, UV);
	vec3 hsv = rgb2hsv(t.rgb);
	hsv.x = fract(hsv.x + hue);
	COLOR = vec4(hsv2rgb(hsv), t.a) * COLOR;
}
