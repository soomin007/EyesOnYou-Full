extends Node

# 방 체인 스크린샷 하니스(2026-08-18, room_chain_expansion 검증용) — rid+stage+segment 단위로
# Stage를 띄워 분위기 컷을 저장한다. 배경 신설 검증([[new-map-always-full-background]])에
# 배치마다 재사용. 실행(창모드 · 반드시 무음으로 — 사용자 작업 중 소리 노출 방지):
#   godot --path . --audio-driver Dummy --resolution 1280x720 res://scenes/chain_shotter.tscn
# TARGETS만 바꿔 쓰면 된다. x를 주면 플레이어를 그 x로 옮겨 방 중반 배경을 담는다.

const STAGE_SCENE: String = "res://scenes/stage.tscn"
const OUT_DIR: String = "res://poster_out/chain_shots"

const TARGETS: Array = [
	{"rid": "route_subway",           "stage": 1, "seg": 1, "x": 900.0},
	{"rid": "route_subway",           "stage": 1, "seg": 1, "x": 2600.0},
	{"rid": "route_control_corridor", "stage": 6, "seg": 2, "x": 2150.0},
	{"rid": "route_warehouse",        "stage": 4, "seg": 0, "x": 1200.0},
	{"rid": "route_warehouse",        "stage": 4, "seg": 2, "x": 1400.0},
	{"rid": "route_escape_destroy",   "stage": 15, "seg": 0, "x": -1.0},
]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run.call_deferred()

func _run() -> void:
	for entry in TARGETS:
		var d: Dictionary = entry
		await _capture(str(d["rid"]), int(d["stage"]), int(d["seg"]), float(d.get("x", -1.0)),
			int(d.get("wait", 0)))
	print("CHAIN SHOTS DONE")
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()

func _capture(rid: String, stage_idx: int, seg: int, px: float, extra_wait: int = 0) -> void:
	GameState.start_main_game()
	GameState.current_stage = stage_idx
	GameState.seen_enemies = ["patrol", "sniper", "drone", "bomber", "shield", "jammer", "elite"]
	var route: Dictionary = {}
	for r in RouteData.ALL_ROUTES:
		if str((r as Dictionary).get("id", "")) == rid:
			route = r
			break
	if route.is_empty():
		print("SHOT SKIP (no route): ", rid)
		return
	GameState.disposal_choice = "destroy"   # 탈출 4종 캡처용(일반 맵엔 무해)
	GameState.record_route_choice(route, "")
	GameState.current_segment = seg   # record_route_choice 뒤에 — 체인 방 선택
	var stage: Node = (load(STAGE_SCENE) as PackedScene).instantiate()
	add_child(stage)
	await _wait(30)
	if px >= 0.0:
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null:
			(player as Node2D).global_position.x = px
		await _wait(24)   # 카메라 정착
	if extra_wait > 0:
		await _wait(extra_wait)   # 시간형 연출(추격·낙하물) 진행 대기
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var tex: Texture2D = get_viewport().get_texture()
	if tex != null:
		var img: Image = tex.get_image()
		if img != null:
			var path: String = "%s/%s_seg%d.png" % [OUT_DIR, rid, seg]
			img.save_png(path)
			print("SHOT SAVED: ", ProjectSettings.globalize_path(path))
	stage.queue_free()
	GameState.current_segment = 0
	await get_tree().process_frame
	await get_tree().process_frame

func _wait(frames: int) -> void:
	var i: int = 0
	while i < frames:
		await get_tree().process_frame
		i += 1
