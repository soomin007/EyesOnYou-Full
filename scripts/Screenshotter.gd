extends Node

# 포스터용 실제 게임 스크린샷 캡처 하니스.
#  - action: Stage를 빌드 후 플레이어를 적 근처로 옮기고 다중사격을 부여해 발사시켜, 부채꼴 탄이
#            날아가는 순간을 포착(전투 액션 컷).
#  - plain : 스폰 직후 프레임(분위기 컷).
#  - tutorial: 튜토리얼 씬을 띄워 VEIL 눈 + 인트로 자막이 보이는 프레임.
# 도감 첫 조우 카드가 화면을 가리지 않게 seen_enemies를 미리 채운다.
# 실행: godot --path . --resolution 1280x720 res://scenes/screenshotter.tscn --gen

const STAGE_SCENE: String = "res://scenes/stage.tscn"
const TUTORIAL_SCENE: String = "res://scenes/tutorial.tscn"
const OUT_DIR: String = "res://poster_out/shots"

const TARGETS: Array = [
	{"rid": "route_subway", "stage": 2, "mode": "action"},
	{"rid": "route_datacenter", "stage": 4, "mode": "action"},
	{"rid": "route_watchtower", "stage": 2, "mode": "action"},
	{"rid": "route_rooftops", "stage": 0, "mode": "plain"},
]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run.call_deferred()

func _run() -> void:
	# 핵심 시스템 — 맵 선택 + 스킬 트리(전투 외 게임의 두 기둥).
	await _capture_routemap()
	await _capture_skilltree()
	# 전투 액션 + 분위기.
	for entry in TARGETS:
		var d: Dictionary = entry
		await _capture_stage(str(d["rid"]), int(d["stage"]), str(d["mode"]))
	await _capture_tutorial()
	print("SHOTS DONE")
	if "--gen" in OS.get_cmdline_args():
		await get_tree().create_timer(0.2).timeout
		get_tree().quit()

# 맵 선택 화면(Dead Cells식 노드맵). 불변식: route_history.size() == current_stage.
func _capture_routemap() -> void:
	GameState.start_main_game()
	GameState.current_stage = 1
	GameState.route_history = ["route_back_alley"]
	var packed: PackedScene = load("res://scenes/route_map.tscn") as PackedScene
	if packed == null:
		print("SHOT SKIP (no route_map scene)")
		return
	var rm: Node = packed.instantiate()
	add_child(rm)
	await _wait(44)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	_save("routemap", rm)

# 스킬 트리 오버레이 — 대표 빌드를 채워 보유/다음/잠김이 보이게.
func _capture_skilltree() -> void:
	GameState.start_main_game()
	GameState.skills["fire_boost"] = 2
	GameState.skills["glide"] = 1
	GameState.skills["hp"] = 1
	GameState.skills["multishot"] = 1
	var o: Node = SkillTreeOverlay.open(self)
	await _wait(24)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	_save("skilltree", o)

func _capture_stage(rid: String, stage_idx: int, mode: String) -> void:
	GameState.start_main_game()
	GameState.current_stage = stage_idx
	GameState.seen_enemies = ["patrol", "sniper", "drone", "bomber", "shield"]
	# 액션 컷용 화력 — 부채꼴 다중사격 + 사격 강화로 탄이 화면에 많이 보이게.
	if mode == "action":
		GameState.skills["multishot"] = 2
		GameState.skills["fire_boost"] = 1
	var route: Dictionary = _find_route(rid)
	if route.is_empty():
		print("SHOT SKIP (no route): ", rid)
		return
	GameState.record_route_choice(route, "")

	var packed: PackedScene = load(STAGE_SCENE) as PackedScene
	if packed == null:
		print("SHOT SKIP (no scene): ", rid)
		return
	var stage: Node = packed.instantiate()
	add_child(stage)

	# 빌드 + 카메라 정착.
	await _wait(34)

	if mode == "action":
		await _setup_action()

	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	_save(rid, stage)

func _setup_action() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	var enemies: Array = get_tree().get_nodes_in_group("enemy")
	if player == null or enemies.is_empty():
		return
	# 플레이어와 가장 가까운 적 — 그 왼쪽 210px, 같은 높이로 옮겨 카메라에 둘 다 담기게.
	var ppos: Vector2 = player.global_position
	var target: Node = enemies[0]
	var best: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var dd: float = ppos.distance_to((e as Node2D).global_position)
		if dd < best:
			best = dd
			target = e
	var tp: Vector2 = (target as Node2D).global_position
	player.set("facing", 1)
	(player as Node2D).global_position = tp + Vector2(-210.0, 0.0)
	# 카메라 정착.
	await _wait(26)
	# 1차 발사(부채꼴 5발) → 잠깐 뒤 2차 → 탄이 두 거리대에 흩어진 순간 캡처.
	player.call("_try_attack")
	await _wait(7)
	player.call("_try_attack")
	await _wait(4)

func _capture_tutorial() -> void:
	GameState.start_main_game()
	var packed: PackedScene = load(TUTORIAL_SCENE) as PackedScene
	if packed == null:
		print("SHOT SKIP (no tutorial scene)")
		return
	var tut: Node = packed.instantiate()
	add_child(tut)
	# VEIL 눈 등장 이징(~0.9s) + 인트로 자막 페이드인 후.
	await _wait(95)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	_save("tutorial", tut)

func _save(shot_name: String, node: Node) -> void:
	var tex: Texture2D = get_viewport().get_texture()
	if tex != null:
		var img: Image = tex.get_image()
		if img != null:
			var path: String = OUT_DIR + "/shot_" + shot_name + ".png"
			img.save_png(path)
			print("SHOT SAVED: ", ProjectSettings.globalize_path(path))
	if is_instance_valid(node):
		node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _wait(frames: int) -> void:
	var i: int = 0
	while i < frames:
		await get_tree().process_frame
		i += 1

func _find_route(rid: String) -> Dictionary:
	for r in RouteData.ALL_ROUTES:
		var rd: Dictionary = r
		if str(rd.get("id", "")) == rid:
			return rd
	return {}
