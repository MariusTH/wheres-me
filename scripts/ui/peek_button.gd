class_name PeekButton
extends Control
## A button with someone hiding behind it. Hover it (or focus or touch it) and
## they pop up over its top edge, grip the edge with both hands and wiggle;
## leave and they duck back down. Now and then they sneak a quick look on their
## own (the menu calls [method sneak]). Each pop brings a new face, unless a
## fixed look is given (the menu uses your own avatar for "Play with friends").
##
## [member reveal] sets how far they come up: 1.0 is head and shoulders, about
## 0.35 is only a hat and hair. The difficulty picker uses it to hint how much
## of the hider shows on each level.

## Space above the button the peeker can rise into.
const ROOM := 50.0
const PEEKER_SIZE := Vector2(80, 124)
## Character scale; the head is about 30 units tall, so ~38 px.
const ART_SCALE := 1.25
## Feet offset below the top of the button when fully hidden / fully up.
const HIDDEN_FEET := 96.0
const UP_FEET := 50.0

var button: Button
var reveal := 1.0
var fixed_look: Dictionary = {}

var _peeker: Peeker
var _hands: Hands
var _rng := RandomNumberGenerator.new()
var _move: Tween
var _wiggle: Tween
## 0 = hidden, 1 = fully up (scaled by reveal).
var _amount := 0.0
var _held := false


## Wraps [param btn] (already built, with its own min height).
static func wrap(btn: Button, p_reveal: float = 1.0, p_fixed_look: Dictionary = {}) -> PeekButton:
	var p := PeekButton.new()
	p.button = btn
	p.reveal = p_reveal
	p.fixed_look = p_fixed_look
	return p


func _ready() -> void:
	_rng.randomize()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(button.custom_minimum_size.x, button.custom_minimum_size.y + ROOM)
	size_flags_horizontal = button.size_flags_horizontal
	size_flags_vertical = button.size_flags_vertical
	button.size_flags_vertical = Control.SIZE_FILL

	_peeker = Peeker.new()
	_peeker.size = PEEKER_SIZE
	_peeker.pivot_offset = Vector2(PEEKER_SIZE.x / 2.0, PEEKER_SIZE.y - 40.0)
	add_child(_peeker)

	add_child(button)
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.offset_top = ROOM

	_hands = Hands.new()
	_hands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hands.size = Vector2(PEEKER_SIZE.x + 8, 18)
	_hands.modulate.a = 0.0
	add_child(_hands)

	button.mouse_entered.connect(pop)
	button.mouse_exited.connect(duck)
	button.focus_entered.connect(pop)
	button.focus_exited.connect(duck)
	button.button_down.connect(_on_down)
	resized.connect(_place)
	_new_face()
	_place()


## Pops up and stays up (until [method duck]).
func pop() -> void:
	if _held or button.disabled:
		return
	_held = true
	if _amount < 0.05:
		_new_face()
	_go(1.0, 0.32, Tween.TRANS_BACK)
	_start_wiggle()


## Ducks back behind the button.
func duck() -> void:
	if button.has_focus() and get_viewport().gui_get_hovered_control() == button:
		return
	_held = false
	_stop_wiggle()
	_go(0.0, 0.18, Tween.TRANS_QUAD)


## A quick look over the edge: up a little, glance both ways, back down.
func sneak() -> void:
	if _held or _amount > 0.05 or not is_visible_in_tree():
		return
	_new_face()
	_kill(_move)
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	_move = create_tween()
	_move.tween_method(_set_amount, 0.0, 0.55, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_move.tween_property(_peeker, "rotation", 0.18 * side, 0.25).set_trans(Tween.TRANS_SINE)
	_move.tween_interval(0.35)
	_move.tween_property(_peeker, "rotation", -0.18 * side, 0.35).set_trans(Tween.TRANS_SINE)
	_move.tween_interval(0.3)
	_move.tween_property(_peeker, "rotation", 0.0, 0.15)
	_move.tween_method(_set_amount, 0.55, 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func is_up() -> bool:
	return _held


func _on_down() -> void:
	# A tap on a phone: jump all the way up with a little hop.
	pop()
	_kill(_move)
	_move = create_tween()
	_move.tween_method(_set_amount, _amount, 1.15, 0.1).set_ease(Tween.EASE_OUT)
	_move.tween_method(_set_amount, 1.15, 1.0, 0.15).set_ease(Tween.EASE_IN)


func _go(target: float, time: float, trans: Tween.TransitionType) -> void:
	_kill(_move)
	_move = create_tween()
	_move.tween_method(_set_amount, _amount, target, time).set_trans(trans) \
		.set_ease(Tween.EASE_OUT if target > _amount else Tween.EASE_IN)
	if target == 0.0:
		_move.parallel().tween_property(_peeker, "rotation", 0.0, time)


func _start_wiggle() -> void:
	_stop_wiggle()
	var tilt := 0.07 + _rng.randf() * 0.05
	_wiggle = create_tween().set_loops()
	_wiggle.tween_property(_peeker, "rotation", tilt, 0.45).set_trans(Tween.TRANS_SINE)
	_wiggle.tween_property(_peeker, "rotation", -tilt, 0.45).set_trans(Tween.TRANS_SINE)


func _stop_wiggle() -> void:
	_kill(_wiggle)
	_wiggle = null


func _kill(t: Tween) -> void:
	if t and t.is_valid():
		t.kill()


func _set_amount(v: float) -> void:
	_amount = v
	_place()


## Picks a new person and a new spot along the top edge (away from the
## rounded corners).
func _new_face() -> void:
	if fixed_look.is_empty():
		_peeker.look = AvatarKit.normalize(AvatarKit.random_look(_rng))
	else:
		_peeker.look = fixed_look
	_peeker.flip = _rng.randf() < 0.5
	_peeker.across = _rng.randf_range(0.18, 0.82)
	_hands.skin = PlaceholderArt.col(_peeker.look.get("skin"), Color("f1c27d"))
	_hands.queue_redraw()


func _place() -> void:
	if _peeker == null:
		return
	var w := maxf(size.x, PEEKER_SIZE.x)
	var cx := clampf(w * _peeker.across, PEEKER_SIZE.x / 2.0 + 10.0, w - PEEKER_SIZE.x / 2.0 - 10.0)
	var feet := ROOM + lerpf(HIDDEN_FEET, UP_FEET + (1.0 - reveal) * (HIDDEN_FEET - UP_FEET) * 0.6, _amount)
	_peeker.position = Vector2(cx - PEEKER_SIZE.x / 2.0, feet - (PEEKER_SIZE.y - Peeker.FOOT_MARGIN))
	# Hands only show once the head is clear of the edge, and only when the
	# whole head comes up (not on the hat-only levels).
	_hands.position = Vector2(cx - _hands.size.x / 2.0, ROOM - 8.0)
	_hands.modulate.a = clampf((_amount - 0.6) / 0.3, 0.0, 1.0) if reveal > 0.7 else 0.0


## The hiding person (drawn behind the button, clipped by the wrapper).
class Peeker:
	extends Control
	const FOOT_MARGIN := 4.0
	var look: Dictionary = {}:
		set(value):
			look = value
			queue_redraw()
	var flip := false
	## Where along the button's top edge they hide (0..1).
	var across := 0.5

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if look.is_empty():
			return
		PlaceholderArt.draw_character(self, look, flip, Vector2(size.x / 2.0, size.y - FOOT_MARGIN), PeekButton.ART_SCALE)
		draw_set_transform(Vector2.ZERO)


## Two little hands gripping the top edge of the button.
class Hands:
	extends Control
	var skin := Color("f1c27d")

	func _draw() -> void:
		for x: float in [10.0, size.x - 10.0]:
			var c := Vector2(x, size.y / 2.0 + 1.0)
			draw_circle(c, 8.0, skin)
			draw_arc(c, 8.0, PI, TAU, 14, UiKit.INK, 2.0, true)
			# Knuckle lines.
			for k: float in [-3.0, 0.0, 3.0]:
				draw_line(c + Vector2(k, -1.0), c + Vector2(k, 3.5), Color(UiKit.INK, 0.6), 1.0, true)
