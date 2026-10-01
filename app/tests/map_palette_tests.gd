extends SceneTree
var failures := []
var checks := 0
const Colors = preload("res://scripts/config/ScenePalette.gd")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label);printerr(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,800)
	var main=load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.debug_overlay.hide()
	for fixture in ["ancient", "mirage"]:
		check(main.open_replay("res://../artifacts/m9/"+fixture+".replay"),fixture+" opens")
		main.controller.clock.seek(minf(500,main.controller.clock.duration))
		var snapshot:Dictionary=main.controller.current_states.duplicate(true)
		var geometry:int=main.map_manager.triangles
		check(main.map_manager.model!=null,fixture+" prepared geometry present")
		for index in 3:
			main.apply_scene_palette(index)
			var preset:Dictionary=Colors.preset(index)
			check(main.get_node("WorldEnvironment").environment.background_color==preset.background,"Coordinated background")
			for opacity in [1.0,0.5]:
				main.map_manager.set_opacity(opacity)
				var color:Color=main.map_manager.cutaway_material.get_shader_parameter("map_color")
				check(color.is_equal_approx(Color(preset.map,opacity)),"Cutaway shader color and transparency")
				check(main.map_manager.material.albedo_color.is_equal_approx(Color(preset.map,opacity)),"Standard material matches shader")
			main.map_manager.set_cutaway(false,main.map_manager.cutaway_height)
			check(main.map_manager.triangles==geometry,"Changing color preserves geometry")
			main.map_manager.set_cutaway(true,main.map_manager.cutaway_height)
			main.map_manager.set_opacity(1.0)
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../artifacts/m92/"+fixture+"-palette-"+str(index)+".png")
			check(main.controller.current_states==snapshot,"Palette preserves player facts and time")
		main.reload_map()
		check(main.map_manager.material.albedo_color.is_equal_approx(Colors.preset(2).map),"Reload retains palette")
	check(main.open_replay("res://data/mock_replay.json"),"Fallback replay opens")
	for index in 3:
		main.apply_scene_palette(index)
		check(main.get_node("TestPlane").material_override.albedo_color.is_equal_approx(Colors.preset(index).ground),"Fallback plane follows palette")
	var file:=FileAccess.open("res://../artifacts/m92/palette-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("Palette checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
