extends Node

# 인스타 홍보용 스크린샷 하니스 v2 — "게임의 본질"을 자연스러운 프레이밍으로 잡는다.
#  설계 철학(사용자 피드백):
#   - 줌인 없음. 게임 기본 카메라 그대로(캐릭터는 맥락 속 작게, 레벨/HUD 전체가 보이게).
#   - VEIL 자막은 지우지 않고 화면의 주인공으로 — 이 게임의 정체성은 VEIL과의 관계다.
#   - 억지 액션을 지어내지 말고, 게임 고유 시스템/서사 모먼트를 포착한다:
#       VEIL 위협 콜아웃 / 첫 조우 도감 카드 / 시야 붕괴(역전) / 보스 / 엔딩 단말기 / 맵 분위기.
#   - 풀 HUD(스킬 목록·진행도·VEIL 게이지)도 구도의 일부.
# 실행: Godot_..._console.exe --path . res://scenes/ig_shotter.tscn --gen

const STAGE_SCENE: String = "res://scenes/stage.tscn"
const OUT_DIR: String = "res://poster_out/ig"
const SHOT_W: int = 1920
const SHOT_H: int = 1080

const K_PATROL: int = 0
const K_SNIPER: int = 1
const K_DRONE: int = 2
const K_BOMBER: int = 3
const K_SHIELD: int = 4

# 풍부한 HUD를 위한 대표 빌드(SKILL 목록이 꽉 차게). 시작 스킬(대시·이중점프)에 더해진다.
const RICH_SKILLS: Dictionary = {
	"fire_boost": 2, "multishot": 2, "explosive": 1,
	"glide": 2, "dash_boost": 1, "hp": 1, "shield": 1, "barrier": 1,
}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_set_high_res()
	_run.call_deferred()

func _set_high_res() -> void:
	var win: Window = get_window()
	win.mode = Window.MODE_WINDOWED
	win.borderless = true
	# content_scale를 설계 기준(1280x720)으로 고정 → 게임 기본 프레이밍 그대로, 1.5배 선명.
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(1280, 720)
	win.size = Vector2i(SHOT_W, SHOT_H)
	win.position = Vector2i(0, 0)
	# 물리 보간 OFF — 캡처 순간 잔상(반투명/흐릿) 방지.
	get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _run() -> void:
	await _wait(8)
	# VEIL과의 만남 → 위협 마킹(도움) → 도감 → 시야 붕괴(역전)·보스 → 맵 분위기 → 시스템 → 엔딩.
	await _shot_veil_intro()
	await _shot_veil_threat()
	await _shot_enemy_card()
	await _shot_boss_degradation()
	await _shot_map_datacenter()
	await _shot_map_cooling()
	await _shot_map_rooftops()
	await _shot_route_fork()
	await _shot_skilltree()
	await _shot_ending_terminal()
	print("IG SHOTS DONE")
	if "--gen" in OS.get_cmdline_args():
		await get_tree().create_timer(0.3).timeout
		get_tree().quit()

# ─── 공통 ─────────────────────────────────────────────────────

func _new_game(stage_idx: int, skills: Dictionary, story: bool = false) -> void:
	get_tree().paused = false  # 이전 도감 카드 등에서 carry된 pause 차단
	GameState.start_main_game()
	GameState.story_mode = story
	GameState.current_stage = stage_idx
	GameState.seen_enemies = ["patrol", "sniper", "drone", "bomber", "shield"]
	for k in skills.keys():
		GameState.skills[k] = int(skills[k])

func _load_stage(rid: String, stage_idx: int, skills: Dictionary, story: bool = false) -> Node:
	_new_game(stage_idx, skills, story)
	var route: Dictionary = _find_route(rid)
	if route.is_empty():
		print("IG SKIP (no route): ", rid)
		return null
	GameState.record_route_choice(route, "")
	var packed: PackedScene = load(STAGE_SCENE) as PackedScene
	if packed == null:
		return null
	var stage: Node = packed.instantiate()
	add_child(stage)
	await _wait(30)
	return stage

func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

func _enemies() -> Array:
	return get_tree().get_nodes_in_group("enemy")

# 플레이어를 자연 위치로 옮기고 카메라(자식)를 줌 변경 없이 스냅. 줌은 게임 기본값 유지.
func _place_player(stage: Node, pos: Vector2, facing: int = 1) -> void:
	var p: Node2D = _player()
	if p == null:
		return
	p.set("facing", facing)
	p.set("velocity", Vector2.ZERO)
	p.set("invuln", 999.0)
	p.global_position = pos
	p.reset_physics_interpolation()
	var cam: Camera2D = stage.get("camera")
	if cam != null and is_instance_valid(cam):
		cam.position_smoothing_enabled = false
		cam.reset_smoothing()
		cam.reset_physics_interpolation()
	await _wait(8)

# VEIL 자막 한 줄(서사). 기존 자동 자막을 비우고 의도한 한 줄만 — 깔끔하게 VEIL을 살린다.
func _say(stage: Node, text: String) -> void:
	stage.call("_purge_subtitles")
	stage.call("_show_veil_subtitle", text, 8.0, false, true)

# 저격수 조준 — 실제 게임처럼 사선(LoS) 트인 경우에만 붉은 조준선(벽 관통 금지).
func _aim_if_los(sniper: Node, do_fire: bool = false) -> bool:
	if sniper == null or not is_instance_valid(sniper):
		return false
	var p: Node2D = _player()
	if p == null:
		return false
	if not bool(sniper.call("_has_line_of_sight", p)):
		return false
	sniper.set("aim_los_clear", true)
	sniper.call("_start_aim")
	sniper.call("_update_aim")
	if do_fire:
		sniper.call("_fire_at_player")
	sniper.set_physics_process(false)
	return true

func _aim_all_snipers(do_fire: bool = false) -> int:
	var n: int = 0
	for e in _enemies():
		if int(e.get("enemy_type")) == K_SNIPER:
			if _aim_if_los(e, do_fire):
				n += 1
	return n

# 캡처 직전 고정 — 무적 점멸로 인한 반투명 차단 + 투사체 정지로 또렷한 프레임.
func _freeze_for_capture(stage: Node) -> void:
	var p: Node2D = _player()
	for n in stage.get_children():
		if n == p:
			continue
		if n is CollisionObject2D:
			(n as Node).set_physics_process(false)
			(n as Node).set_process(false)
	if p != null and is_instance_valid(p):
		p.set("invuln", 0.0)
		var vis: Variant = p.get("visual")
		if vis != null:
			(vis as CanvasItem).modulate.a = 1.0
		p.set_physics_process(false)

# ─── 1. VEIL과의 만남 — 튜토리얼 인트로(레이더 눈 + 통신 연결 자막) ──
func _shot_veil_intro() -> void:
	get_tree().paused = false
	GameState.start_main_game()
	var packed: PackedScene = load("res://scenes/tutorial.tscn") as PackedScene
	if packed == null:
		return
	var tut: Node = packed.instantiate()
	add_child(tut)
	# VEIL 눈 등장 이징(~0.9s) + 인트로 자막 페이드인.
	await _wait(95)
	await _capture("veil_intro", tut)

# ─── 2. VEIL이 위협을 짚어준다 — 감시탑, 실제 저격 사선 + VEIL 콜아웃 ──
func _shot_veil_threat() -> void:
	var stage: Node = await _load_stage("route_watchtower", 2, RICH_SKILLS)
	if stage == null:
		return
	# 중층 정찰단 발판 — 좌측 둥지 저격수가 사선을 가로지른다(기본 카메라, 맥락 전체).
	_place_player(stage, Vector2(620.0, 1148.0), -1)
	await _wait(8)
	_aim_all_snipers(false)  # 사선 트인 저격수 조준선
	_say(stage, "위험한 건 제가 먼저 확인하겠습니다. 화면 끝에 띄워둘 테니, 요원은 전방만 보십시오.")
	await _wait(14)
	_freeze_for_capture(stage)
	await _capture("veil_threat", stage)

# ─── 3. 첫 조우 도감 카드 — 게임이 알아서 띄우는 적 소개 ──────────
func _shot_enemy_card() -> void:
	var stage: Node = await _load_stage("route_watchtower", 2, RICH_SKILLS)
	if stage == null:
		return
	_place_player(stage, Vector2(620.0, 1148.0), -1)
	await _wait(8)
	_aim_all_snipers(false)  # 배경에 저격 사선
	# 첫 조우 카드(저격수) — 실제 게임의 도감 시스템.
	BestiaryOverlay.show_card(stage, "sniper")
	await _wait(12)
	await _capture("enemy_card_sniper", stage)
	get_tree().paused = false  # 카드가 pause했으니 해제

# ─── 4. 시야 붕괴(역전) + 보스 — VEIL이 "이제 안 보여요" ─────────
func _shot_boss_degradation() -> void:
	GameState.veil_degraded = true  # 시야 붕괴 — 화면이 어두워지고 마커가 무너진다
	var stage: Node = await _load_stage("route_lab", 5, RICH_SKILLS)
	if stage == null:
		GameState.veil_degraded = false
		return
	await _wait(20)  # 보스 호버 안착
	var boss: Node = get_tree().get_first_node_in_group("boss")
	if boss != null and is_instance_valid(boss):
		boss.set("hp", 12)
		boss.set("phase", 2)
		boss.call("_summon_minions", 2)
		var bvis: Variant = boss.get("visual")
		if bvis != null:
			(bvis as Node2D).self_modulate = Color(1.2, 0.85, 0.65)
	var p: Node2D = _player()
	p.set("invuln", 999.0)
	p.set("facing", 1)
	p.global_position = Vector2(720.0, 698.0)
	p.reset_physics_interpolation()
	await _wait(14)
	_say(stage, "오른쪽 어딘가... 저도 잘 안 보여요. 직접 살펴요.")
	await _wait(12)
	_freeze_for_capture(stage)
	await _capture("boss_sentinel", stage)
	GameState.veil_degraded = false

# ─── 5. 데이터 센터 — 드론(위) + 저격(같은 층) 동시 고위험 ───────
func _shot_map_datacenter() -> void:
	var stage: Node = await _load_stage("route_datacenter", 4, RICH_SKILLS)
	if stage == null:
		return
	stage.call("_spawn_wave", 1)  # 저격 둘 + 드론
	await _wait(14)
	var p: Node2D = _player()
	p.set("invuln", 999.0)
	p.global_position = Vector2(620.0, 760.0)
	p.reset_physics_interpolation()
	await _wait(8)
	_aim_all_snipers(false)  # 사선 트인 저격수 조준선
	_say(stage, "데이터 센터예요. 드론·저격 동시에 와요. 한 번에 정리해야 빠져요.")
	await _wait(14)
	_freeze_for_capture(stage)
	await _capture("map_datacenter", stage)

# ─── 6. 냉각 시설 — 증기·드론·게이트·스카이라인(맵 분위기) ───────
func _shot_map_cooling() -> void:
	var stage: Node = await _load_stage("route_cooling", 3, RICH_SKILLS)
	if stage == null:
		return
	# XP 발판(1180,440) — 머리 위 드론, 게이트 오브, 도시 배경이 한 화면에.
	_place_player(stage, Vector2(1180.0, 430.0), 1)
	await _wait(10)
	_say(stage, "여긴 서버를 식히는 곳이에요. ...저도 이런 데 어딘가 있겠죠. 바닥 증기 조심해요.")
	await _wait(14)
	_freeze_for_capture(stage)
	await _capture("map_cooling", stage)

# ─── 7. 외벽 옥상 — 밤하늘 아래 수직 등반(맵 분위기) ─────────────
func _shot_map_rooftops() -> void:
	var stage: Node = await _load_stage("route_rooftops", 0, {"multishot": 1, "dash_boost": 1})
	if stage == null:
		return
	# 분기 옥상(640,2040) 부근 — 등반 동선·발판·별 배경이 자연스럽게.
	_place_player(stage, Vector2(640.0, 2010.0), 1)
	await _wait(10)
	_say(stage, "옥상이 출구예요. 멈추면 저격에 잡혀요. 계속 움직여요.")
	await _wait(14)
	_freeze_for_capture(stage)
	await _capture("map_rooftops", stage)

# ─── 8. 루트 분기 — 스토리 stage1(지하철 vs 감시탑, 위험 대비) ──
func _shot_route_fork() -> void:
	_new_game(1, {}, true)
	var packed: PackedScene = load("res://scenes/route_map.tscn") as PackedScene
	if packed == null:
		return
	var rm: Node = packed.instantiate()
	add_child(rm)
	await _wait(44)
	await _capture("route_fork", rm)

# ─── 9. 스킬트리 — 진행된 빌드 ──────────────────────────────────
func _shot_skilltree() -> void:
	_new_game(3, {
		"fire_boost": 2, "multishot": 2, "glide": 2,
		"dash_boost": 1, "hp": 1, "shield": 1,
	})
	var o: Node = SkillTreeOverlay.open(self)
	await _wait(26)
	await _capture("skilltree", o)

# ─── 10. 엔딩 단말기 — ??? 격리 서버실, ONLINE 단말기로 ──────────
func _shot_ending_terminal() -> void:
	_new_game(6, RICH_SKILLS)  # STAGE 7/7
	var route: Dictionary = _find_route("route_hidden")
	if route.is_empty():
		return
	GameState.record_route_choice(route, "")
	var packed: PackedScene = load(STAGE_SCENE) as PackedScene
	if packed == null:
		return
	var stage: Node = packed.instantiate()
	add_child(stage)
	await _wait(34)
	# 켜진(ONLINE) 첫 단말기(x1500) 앞 — 트리거 전 위치(x1340)에서 안내 문구가 보이게.
	_place_player(stage, Vector2(1340.0, 540.0), 1)
	await _wait(56)  # 안내 페이드인(1.0s + 0.6s) 경과
	_freeze_for_capture(stage)
	await _capture("ending_terminal", stage)

# ─── 캡처/유틸 ────────────────────────────────────────────────

func _capture(shot_name: String, node: Node) -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var tex: Texture2D = get_viewport().get_texture()
	if tex != null:
		var img: Image = tex.get_image()
		if img != null:
			var path: String = OUT_DIR + "/" + shot_name + ".png"
			img.save_png(path)
			print("IG SAVED: ", ProjectSettings.globalize_path(path), "  ", img.get_width(), "x", img.get_height())
	get_tree().paused = false
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
