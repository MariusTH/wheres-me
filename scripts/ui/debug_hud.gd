class_name DebugHud
extends Control
## Map debug view: seed stepping and generation stats.

func _ready() -> void:
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(layout: TownLayout) -> void:
	var v := UiKit.vbox(8)
	v.add_child(UiKit.label("Map debug view", 24))
	v.add_child(UiKit.label("%s v%d · generator v%d · seed %d" % [layout.map_id, layout.map_version, layout.generator_version, layout.map_seed], 15, UiKit.MUTED))
	v.add_child(UiKit.label("%d objects · %d people · %d shortfalls" % [layout.objects.size(), layout.count_people(), layout.shortfalls.size()], 15))
	var row := UiKit.hbox(8)
	row.add_child(UiKit.button("Seed -1", func() -> void: AppState.start_debug(maxi(0, layout.map_seed - 1))))
	row.add_child(UiKit.button("Seed +1", func() -> void: AppState.start_debug(layout.map_seed + 1)))
	row.add_child(UiKit.button("Menu", func() -> void: AppState.go_menu(), UiKit.MUTED))
	v.add_child(row)
	v.add_child(UiKit.label("F1 cycles overlay: shapes → + IDs/depth order → off", 13, UiKit.MUTED))
	var p := UiKit.panel(v)
	p.position = Vector2(12, 12)
	add_child(p)
