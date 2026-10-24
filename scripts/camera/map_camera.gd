class_name MapCamera
extends Camera2D
## Drag to pan, wheel / pinch to zoom, clamped to the map. A press-release
## without significant movement is reported as a tap in world coordinates.
## If drag_interceptor claims a press (e.g. it landed on the hider's avatar),
## that drag moves the object instead of the map.

signal tapped(world_position: Vector2)
signal hovered(world_position: Vector2)
signal object_dragged(world_position: Vector2)
signal object_released(world_position: Vector2)

const MAX_ZOOM := 2.5
const ZOOM_STEP := 1.12
const TAP_MAX_MOVE := 10.0

var bounds: Rect2 = Rect2()
var min_zoom: float = 0.4
## (world_position: Vector2) -> bool. True = this press drags an object.
var drag_interceptor: Callable = Callable()

var _pressing := false
var _moved := false
var _press_pos := Vector2.ZERO
var _touches: Dictionary = {}
var _pinching := false
var _dragging_object := false


func setup(world_bounds: Rect2) -> void:
	bounds = world_bounds
	var vp := get_viewport_rect().size
	min_zoom = maxf(vp.x / bounds.size.x, vp.y / bounds.size.y)
	make_current()
	set_view(bounds.get_center(), 1.0)


func set_view(center: Vector2, z: float) -> void:
	zoom = Vector2.ONE * clampf(z, min_zoom, MAX_ZOOM)
	position = center
	_clamp()


## Converts a viewport (screen) position to world coordinates.
func screen_to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func zoom_at(screen: Vector2, factor: float) -> void:
	var before := screen_to_world(screen)
	var z := clampf(zoom.x * factor, min_zoom, MAX_ZOOM)
	zoom = Vector2(z, z)
	var half := get_viewport_rect().size / 2.0
	position = before - (screen - half) / z
	_clamp()


func _clamp() -> void:
	var half := get_viewport_rect().size / (2.0 * zoom.x)
	var lo := bounds.position + half
	var hi := bounds.end - half
	position.x = bounds.get_center().x if lo.x > hi.x else clampf(position.x, lo.x, hi.x)
	position.y = bounds.get_center().y if lo.y > hi.y else clampf(position.y, lo.y, hi.y)
	force_update_scroll()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		if _touches.size() >= 2:
			_pinching = true
			_moved = true
			_dragging_object = false
		elif _touches.is_empty():
			_pinching = false
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _touches.size() >= 2 and _touches.has(d.index):
			var other: Vector2 = Vector2.ZERO
			for k: int in _touches:
				if k != d.index:
					other = _touches[k]
					break
			var old_dist := (_touches[d.index] as Vector2).distance_to(other)
			var new_dist := d.position.distance_to(other)
			_touches[d.index] = d.position
			if old_dist > 1.0:
				zoom_at((d.position + other) / 2.0, new_dist / old_dist)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_at(mb.position, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(mb.position, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_pressing = true
					_moved = _pinching
					_press_pos = mb.position
					_dragging_object = (not _pinching and mb.button_index == MOUSE_BUTTON_LEFT
						and drag_interceptor.is_valid() and drag_interceptor.call(screen_to_world(mb.position)))
				elif _pressing:
					_pressing = false
					if _dragging_object:
						_dragging_object = false
						if _moved:
							object_released.emit(screen_to_world(mb.position))
							get_viewport().set_input_as_handled()
							return
					if not _moved and mb.button_index == MOUSE_BUTTON_LEFT:
						tapped.emit(screen_to_world(mb.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressing and _dragging_object and not _pinching:
			if _moved or mm.position.distance_to(_press_pos) > TAP_MAX_MOVE:
				_moved = true
				object_dragged.emit(screen_to_world(mm.position))
		elif _pressing and not _pinching:
			if not _moved and mm.position.distance_to(_press_pos) > TAP_MAX_MOVE:
				_moved = true
				position -= (mm.position - _press_pos) / zoom.x
			elif _moved:
				position -= mm.relative / zoom.x
			_clamp()
		elif not _pressing:
			hovered.emit(screen_to_world(mm.position))
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		zoom_at(mg.position, mg.factor)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		position += pg.delta * 12.0 / zoom.x
		_clamp()
