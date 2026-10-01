extends SceneTree
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label);printerr(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var fixture_root: String = OS.get_environment("M9_PROJECT").path_join("artifacts/m9/") if OS.has_feature("standalone") else "res://../artifacts/m9/"
	var output: String = OS.get_environment("M9_PROJECT").path_join("artifacts/m92/") if OS.has_feature("standalone") else "res://../artifacts/m92/"
	var clock=load("res://scripts/core/ReplayClock.gd").new()
	clock.configure(120)
	var ui=load("res://scripts/ui/TimelineUI.gd").new()
	root.add_child(ui)
	ui.bind_clock(clock)
	ui.bind_rounds([{"type":"bomb_reset","time":10.0},{"type":"bomb_reset","time":40.0},{"type":"bomb_reset","time":40.0},{"type":"bomb_reset","time":90.0},{"type":"bomb_plant","time":25.0}])
	check(ui.round_navigation.starts==[10.0,40.0,90.0],"Use only recorded starts and coalesce duplicate ticks")
	check(ui.previous_round_button.disabled and not ui.next_round_button.disabled,"Before first round availability")
	ui.next_round_button.pressed.emit()
	check(clock.current_time==10 and not clock.is_playing,"Next button reaches first recorded start while paused")
	check(ui.previous_round_button.disabled,"No invented previous round at zero")
	clock.seek(55);clock.set_speed(2);clock.play()
	ui.previous_round_button.pressed.emit()
	check(clock.current_time==10 and clock.is_playing and clock.playback_speed==2,"Previous round preserves playback and speed")
	ui.next_round_button.pressed.emit()
	check(clock.current_time==40,"Next at exact start reaches next round")
	ui.previous_round_button.pressed.emit()
	check(clock.current_time==10,"Previous at exact boundary skips current round")
	clock.pause();clock.seek(119)
	check(ui.next_round_button.disabled,"No next button after final start")
	ui.back_15_button.pressed.emit()
	check(clock.current_time==104 and not clock.is_playing,"Back 15 while paused")
	clock.seek(5);clock.play();ui.back_15_button.pressed.emit()
	check(clock.current_time==0 and clock.is_playing,"Back 15 clamps at start and keeps playing")
	check(ui.back_15_button.disabled,"Back 15 disabled at start")
	clock.seek(115);ui.forward_15_button.pressed.emit()
	check(clock.current_time==120 and not clock.is_playing,"Forward 15 clamps at end and pauses")
	check(ui.forward_15_button.disabled,"Forward 15 disabled at end")
	clock.seek(50);ui._on_drag_started()
	var before:float=clock.current_time
	ui.skip_seconds(15);ui.jump_round(1)
	check(clock.current_time==before and ui.back_15_button.disabled,"Drag blocks navigation")
	ui._on_drag_ended(false)
	check(not ui.back_15_button.disabled,"Navigation resumes after dragging")
	ui.show_error("synthetic unreadable block")
	ui.skip_seconds(15);ui.jump_round(-1);clock.state_changed.emit()
	check(clock.current_time==before and ui.play_button.disabled and ui.next_round_button.disabled,"Error keeps all navigation disabled")
	ui.bind_clock(clock);clock.play();ui._on_drag_started();ui.show_error("synthetic error during drag");ui._on_drag_ended(false)
	check(not clock.is_playing,"Failed drag does not restart playback")
	ui.bind_clock(clock);ui.bind_rounds([])
	check(ui.previous_round_button.disabled and ui.next_round_button.disabled and not ui.forward_15_button.disabled,"Legacy replay keeps relative skip without inventing rounds")
	ui.queue_free();await process_frame
	root.size=Vector2i(1280,800)
	var main=load("res://scenes/Main.tscn").instantiate()
	root.add_child(main);await process_frame
	main.debug_overlay.hide()
	for fixture in ["ancient","mirage"]:
		check(main.open_replay(fixture_root+fixture+".replay"),"Real fixture loads")
		var timeline=main.timeline
		check(timeline.round_navigation.starts.size()==(21 if fixture=="ancient" else 10),"Real round marker count")
		main.controller.clock.pause()
		timeline.next_round_button.pressed.emit()
		check(main.controller.clock.current_time==timeline.round_navigation.starts[0],"Real first round button")
		timeline.next_round_button.pressed.emit()
		check(main.controller.clock.current_time==timeline.round_navigation.starts[1],"Real next round button")
		var target:float=main.controller.clock.current_time+15
		timeline.forward_15_button.pressed.emit()
		check(main.controller.clock.current_time==target and main.controller.load_error.is_empty(),"Real cross-window 15-second skip")
		timeline.previous_round_button.pressed.emit()
		check(main.controller.clock.current_time==timeline.round_navigation.starts[0],"Real previous round after seek")
		main.controller.clock.seek(minf(timeline.round_navigation.starts[2]+45,main.controller.clock.duration))
		for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
			root.size=dimensions;await process_frame;await process_frame
			for button in [timeline.previous_round_button,timeline.next_round_button,timeline.back_15_button,timeline.forward_15_button,timeline.speed_buttons[-1]]:
				var rect:Rect2=button.get_global_rect()
				check(rect.position.x>=0 and rect.end.x<=root.get_visible_rect().size.x,"Controls fit viewport")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+fixture+"-navigation-"+str(dimensions.x)+".png")
	var file:=FileAccess.open(output+("navigation-installed-report.json" if OS.has_feature("standalone") else "navigation-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("Playback navigation checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
