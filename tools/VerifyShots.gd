extends Node

# 검증 갤러리 샷 하니스(2026-08-23 신설 · 재사용) — TARGETS를 순회하며 스테이지를 부팅하고
# 연출/상태를 세팅한 뒤 스크린샷을 user://verify_shots/에 남긴다. 갤러리(HTML)는 세션이
# 이 이미지를 수집해 만든다. 실행:
#   godot --path . --audio-driver Dummy --resolution 1280x720 --windowed res://tools/verify_shots.tscn
# TARGETS 원소: {id, route, seg?, stage?, setup?(콜백 문자열), wait?(초)}
# setup 종류: "" 없음 · "dash"(대시+잔상) · "cutscene_lock"(잠금 컷씬) · "doc"(서버 로그 문서) ·
#   "death"(사망 화면 진입 직전 상태는 씬 전환이라 제외 — Death 씬 직접 부팅) 등 아래 match 참조.

const STAGE_SCENE: String = "res://scenes/stage.tscn"

const TARGETS: Array = [
	{"id": "dash_afterimage", "route": "route_back_alley", "stage": 1, "setup": "dash"},
	{"id": "lock_cutscene_act4", "route": "route_pump_station", "stage": 8, "setup": "cutscene_lock"},
	{"id": "hp_lock_hud", "route": "route_pump_station", "stage": 8, "setup": "hud_lock"},
	{"id": "server_log_doc", "route": "route_server_hall", "seg": 1, "stage": 7, "setup": "doc"},
	{"id": "server_room2_wall", "route": "route_server_hall", "seg": 1, "stage": 7, "setup": ""},
	{"id": "cooling_room1_no_lever", "route": "route_cooling", "seg": 0, "stage": 7, "setup": ""},
	{"id": "demolition_turret_gap", "route": "route_demolition_zone", "seg": 0, "stage": 1, "setup": "cam_1190"},
	{"id": "debris_platform_land", "route": "route_demolition_zone", "seg": 0, "stage": 1, "setup": "debris_wait"},
	{"id": "kill_burst", "route": "route_back_alley", "stage": 1, "setup": "kill"},
	{"id": "land_dust", "route": "route_back_alley", "stage": 1, "setup": "land"},
	{"id": "routemap_heal_reward", "route": "", "setup": "routemap"},
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("user://verify_shots")
	_run.call_deferred()

func _run() -> void:
	for entry in TARGETS:
		var d: Dictionary = entry
		await _shot(d)
	print("[VERIFY] DONE")
	get_tree().quit()

func _shot(d: Dictionary) -> void:
	var id: String = str(d.get("id", "shot"))
	var setup: String = str(d.get("setup", ""))
	if setup == "routemap":
		await _shot_routemap(id)
		return
	GameState.start_main_game()
	GameState.current_stage = int(d.get("stage", 1))
	GameState.current_segment = int(d.get("seg", 0))
	GameState.seen_enemies = ["patrol", "sniper", "drone", "bomber", "shield", "jammer", "elite", "caller"]
	GameState.player_level = 99   # 레벨업 오버레이 pause 차단(하니스 표준 가드)
	var route: Dictionary = {}
	for r in RouteData.ALL_ROUTES:
		var rd: Dictionary = r
		if str(rd.get("id", "")) == str(d.get("route", "")):
			route = rd
			break
	if route.is_empty():
		print("[VERIFY] skip(no route): ", id)
		return
	GameState.record_route_choice(route, "")
	GameState.current_segment = int(d.get("seg", 0))
	var stage: Node = (load(STAGE_SCENE) as PackedScene).instantiate()
	add_child(stage)
	for i in 40:
		await get_tree().process_frame
	var p: Node = get_tree().get_first_node_in_group("player")
	match setup:
		"dash":
			GameState.skills["dash_boost"] = 2
			if p != null:
				p.call("_on_skills_changed")
				p.set("facing", 1)
				p.set("dash_timer", 0.18)
			for i in 8:
				await get_tree().process_frame
		"cutscene_lock":
			stage.call("_play_rival_lock_beat", 4, 0)
			for i in 70:
				await get_tree().process_frame
		"hud_lock":
			# 막4 진입 상태 = 잠금 1 — 하트 곁 ×가 보이는 HUD.
			stage.call("_refresh_hud")
			for i in 5:
				await get_tree().process_frame
		"doc":
			var doc := ArcturusDocumentOverlay.new()
			stage.add_child(doc)
			doc.show_doc(stage.call("_server_log_doc_lines"))
			for i in 1050:
				await get_tree().process_frame
		"cam_1190":
			if p is Node2D:
				(p as Node2D).global_position = Vector2(1120.0, 560.0)
			for i in 30:
				await get_tree().process_frame
		"debris_wait":
			if p is Node2D:
				(p as Node2D).global_position = Vector2(900.0, 560.0)
			# 낙석 사이클이 발판 착지를 보일 때까지 잠깐 관찰(예고 마커가 착지면에 찍히는 프레임).
			for i in 260:
				await get_tree().process_frame
		"kill":
			# 가장 가까운 적을 강제 처치 — 파편 버스트 프레임.
			var best: Node2D = null
			for e in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(e) and e is Node2D and e.get("enemy_type") != null:
					best = e as Node2D
					break
			if best != null and p is Node2D:
				(p as Node2D).global_position = best.global_position + Vector2(-160.0, 0.0)
				best.call("take_damage", 99, 1)
			for i in 6:
				await get_tree().process_frame
		"land":
			if p is Node2D:
				(p as Node2D).global_position += Vector2(0.0, -240.0)
				p.set("velocity", Vector2(0, 900.0))
			for i in 26:
				await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://verify_shots/%s.png" % id)
	print("[VERIFY] saved ", id)
	get_tree().paused = false
	GameState.restrict_combat_input = false
	Engine.time_scale = 1.0
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _shot_routemap(id: String) -> void:
	GameState.start_main_game()
	GameState.current_stage = 5
	var rm: Node = (load("res://scenes/route_map.tscn") as PackedScene).instantiate()
	add_child(rm)
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://verify_shots/%s.png" % id)
	print("[VERIFY] saved ", id)
	rm.queue_free()
	await get_tree().process_frame
