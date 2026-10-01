extends SceneTree
var checks := 0
var failures := []
var output := "res://../artifacts/m9/"
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr(label)
func snapshot(main: Node) -> Dictionary:
	return {"bomb":main.combat.bomb.state_model.at(main.controller.clock.current_time),"counts":main.combat.counts.duplicate(true),"status":main.combat.flashed.current.duplicate(true),"kills":main.combat.recent_kills.map(func(e):return e.id)}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1440,900)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main); await process_frame
	check(main.open_replay(output+"ancient.json"),"JSON scene loads")
	var times := [0.0,9.99,10.0,10.01,300.0,500.0,900.0,1800.0]
	# Every actual event, with a post-event offset, exercises utility and bomb intervals.
	for event in main.controller.replay.events:
		if event.type in ["bomb_plant","bomb_defuse","bomb_explode","bomb_pickup","bomb_drop","flash","fire","smoke"]: times.append(minf(event.time+0.2,main.controller.clock.duration))
	var expected := []
	for time in times:
		main.controller.clock.seek(time); expected.append(snapshot(main))
	check(main.open_replay(output+"ancient.replay"),"Binary scene loads")
	for i in times.size():
		main.controller.clock.seek(times[i])
		check(snapshot(main)==expected[i],"Combat seek parity " + str(times[i]))
	main.controller.clock.seek(500)
	main.debug_overlay.hide()
	main.combat_panel.current_tab=0
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"binary-scene.png")
	main.controller.clock.seek(9.9);main.controller.clock.play()
	await create_timer(0.3).timeout
	main.controller.clock.pause()
	check(main.controller.clock.current_time>10.0,"Playback crosses chunk boundary")
	check(main.open_replay(output+"late-corruption.replay"),"Late corruption opens initial window")
	main.controller.clock.seek(main.controller.clock.duration)
	check(not main.controller.load_error.is_empty() and not main.controller.clock.is_playing,"Corruption pauses with error")
	check(main.controller.current_states.is_empty() and not main.combat.visible,"Corruption hides stale state")
	check(main.open_replay("res://data/mock_replay.json"),"Legacy mock reload works")
	var f:=FileAccess.open(output+"scene-report.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("M9 scene ",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
