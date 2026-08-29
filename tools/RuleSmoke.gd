extends Node

# 규칙 스모크(2026-08-29 신설) · 실플레이 규칙 3종을 실제 Stage 인스턴스에서 단언한다.
#   ① 저격 조준 고정: 고정 뒤 위로 비키면 빗나감 / 제자리면 명중 · 사거리 600 · 거치대 하향 사각
#   ② 도전방: 피격 = 시간 -5(강제 종료 아님) · 비상등 8개 · 시간 초과 = 실패 플래그 + 암전 걷힘 +
#      방 계속 + 완수 프리미엄 없음
#   ③ 방류구: 판정 시작 = 플랜지 입구(기단·급수관 위 무피격) · 하우징/절연 포스트 z = 캐릭터 뒤
#   ④ 이동 발판 탑승: 수평 리프트 위 정지 플레이어의 상대 위치 한 주기 흔들림 0(엔진 1스텝 지연 보정) ·
#      수직 리프트는 접지 유지(floor lost 0) + 윗면 오차 ≤ 3.5px
#   ⑤ 14-1 컷씬 게이트: 첫 진입은 인트로 컷씬(세계 정지) · 사망 재시작(본 컷씬)은 정지 없음
# 실행: godot --headless --path . --audio-driver Dummy tools/rule_smoke.tscn (종료 코드 0 = 전부 PASS)
const STAGE_SCENE: String = "res://scenes/stage.tscn"
var fails: int = 0

func _check(label: String, ok: bool, detail: String = "") -> void:
	print("[RULE] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1

func _boot(route_id: String, stage_idx: int) -> Node:
	GameState.start_main_game()
	GameState.current_stage = stage_idx
	GameState.seen_enemies = ["patrol", "sniper", "drone", "bomber", "shield", "jammer", "elite", "caller"]
	GameState.player_level = 99
	var route: Dictionary = {}
	for r in RouteData.ALL_ROUTES:
		var rd: Dictionary = r
		if str(rd.get("id", "")) == route_id:
			route = rd
	GameState.record_route_choice(route, "")
	GameState.current_segment = 0
	var stage: Node = (load(STAGE_SCENE) as PackedScene).instantiate()
	add_child(stage)
	for i in 40:
		await get_tree().process_frame
	return stage

func _ready() -> void:
	GameState.persist_blocked = true
	# 감시견 · 어떤 이유로든 60s 안에 못 끝나면 종료(멈춤 방지).
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[RULE] WATCHDOG timeout")
		get_tree().quit(2))
	await _discharge_case()
	await _sniper_case()
	await _challenge_case()
	await _platform_case()
	await _rival_cutscene_case()
	print("[RULE] %s" % ("ALL PASS" if fails == 0 else "%d FAIL" % fails))
	get_tree().quit(0 if fails == 0 else 1)

func _sniper_case() -> void:
	var stage: Node = await _boot("route_pump_station", 1)
	var p: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var sniper: Node = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if int(e.get("enemy_type")) == 1 and sniper == null and absf((e as Node2D).global_position.x - 1500.0) < 5.0:
			sniper = e
		else:
			e.set("harmless", true)
	_check("저격수 확보(1500)", sniper != null)
	if sniper == null:
		stage.queue_free()
		return
	# 방류구(880 → 910..1390 물길)는 체력 계측을 오염시키니 제거. 거치대 저격의 바로 밑은 사각이라
	# 250px 떨어진 지상(1250 · 하향 46° = 사각 50° 밖)에 세운다. 1050은 스텝 발판(1150)에 가려진다.
	for j in get_tree().get_nodes_in_group("discharge_jet"):
		j.queue_free()
	await get_tree().process_frame
	p.global_position = Vector2(1250.0, 600.0)
	p.set("velocity", Vector2.ZERO)
	var hp0: int = GameState.player_hp
	# 케이스 1 · 고정 순간 위로 비킨다 → 빗나가야 한다.
	var locked: bool = false
	var t0: float = 0.0
	while t0 < 6.0:
		await get_tree().physics_frame
		t0 += get_physics_process_delta_time()
		p.global_position.x = 1250.0
		if sniper.get("aim_lock_point") != Vector2.INF:
			locked = true
			break
	_check("조준 고정 발생(6s 내)", locked, "t=%.2f" % t0)
	if locked:
		p.global_position = Vector2(1250.0, 380.0)
		p.set("velocity", Vector2(0.0, -300.0))
		var fired: bool = false
		var t1: float = 0.0
		while t1 < 1.0:
			await get_tree().physics_frame
			t1 += get_physics_process_delta_time()
			if sniper.get("aim_line") == null:
				fired = true
				break
		_check("고정 뒤 발사됨", fired)
		_check("비킨 뒤 빗나감(hp 유지)", GameState.player_hp == hp0, "hp %d→%d" % [hp0, GameState.player_hp])
	# 케이스 2 · 제자리 → 명중.
	await get_tree().create_timer(0.8).timeout
	p.global_position = Vector2(1250.0, 600.0)
	var hp1: int = GameState.player_hp
	var t2: float = 0.0
	while t2 < 7.0 and GameState.player_hp == hp1:
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
		p.global_position = Vector2(1250.0, 600.0)
	_check("제자리면 명중(hp -1)", GameState.player_hp == hp1 - 1, "hp %d→%d t=%.2f" % [hp1, GameState.player_hp, t2])
	var es: GDScript = load("res://scripts/Enemy.gd")
	_check("사거리 상수 600", float(es.get("SNIPER_RANGE")) == 600.0 and float(es.get("NEST_SNIPER_RANGE")) == 600.0)
	stage.queue_free()
	await get_tree().process_frame

func _challenge_case() -> void:
	var stage: Node = await _boot("route_blackout", 3)
	var p: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.set("harmless", true)
	stage.call("_start_challenge_run")
	await get_tree().create_timer(1.5).timeout   # 암전 페이드 인 완료 후(실플레이 순서)
	_check("도전 활성", bool(stage.get("challenge_active")))
	var t_before: float = float(stage.get("challenge_time_remaining"))
	var hp0: int = GameState.player_hp
	p.call("take_hit", 1)
	await get_tree().process_frame
	var t_after: float = float(stage.get("challenge_time_remaining"))
	_check("피격 = 시간 -5", absf((t_before - t_after) - 5.0) < 0.2, "%.1f→%.1f" % [t_before, t_after])
	_check("피격 = 체력 감소(강제 종료 아님)", GameState.player_hp == hp0 - 1 and not bool(stage.get("challenge_failed")), "hp %d→%d failed=%s" % [hp0, GameState.player_hp, str(stage.get("challenge_failed"))])
	var lamps: Node = stage.get_node_or_null("ChallengeLamps")
	_check("비상등 레이어(가시 4구덩이 × 2)", lamps != null and lamps.get_child_count() == 8, "n=%d" % (lamps.get_child_count() if lamps != null else -1))
	# 시간 초과 → 실패 = 보너스 상실 + 조명 복구, 방은 계속.
	stage.set("challenge_time_remaining", 0.05)
	await get_tree().create_timer(0.3).timeout
	_check("시간 초과 = 실패 플래그", bool(stage.get("challenge_failed")) and GameState.challenge_failed_this_stage)
	_check("골 미도달(방 계속)", not bool(stage.get("goal_reached")))
	await get_tree().create_timer(1.6).timeout
	var dark: Control = stage.get("challenge_dark_root")
	_check("암전 걷힘", dark == null or dark.modulate.a < 0.05, "a=%.2f" % (dark.modulate.a if dark != null else -1.0))
	GameState.on_stage_clear()
	_check("실패한 도전 = 완수 프리미엄 없음", not GameState.last_clear_challenge)
	stage.queue_free()
	await get_tree().process_frame

func _discharge_case() -> void:
	var dj := DischargeJet.new()
	add_child(dj)
	dj.setup({"x": 500.0, "dir": 1, "len": 480.0, "phase": 0.0}, 600.0)
	var fp := FakePlayer.new()
	fp.add_to_group("player")
	add_child(fp)
	await get_tree().process_frame
	var cases: Array = [
		["기단 위(along 10)", Vector2(510, 600), 0],
		["급수관 뒤(along -5)", Vector2(495, 600), 0],
		["플랜지 입구(along 30)", Vector2(530, 600), 1],
		["물길 중간(along 200)", Vector2(700, 600), 1],
		["물길 끝(along 510)", Vector2(1010, 600), 1],
		["물길 끝 너머(along 520)", Vector2(1020, 600), 0],
		["거치대 위(along 200, y-130)", Vector2(700, 470), 0],
	]
	for c in cases:
		var cs: Array = c
		dj._state = DischargeJet.S.JET
		dj._t = 0.65   # reach = 전장
		dj._hit_this_jet = false
		fp.hits = 0
		fp.global_position = cs[1]
		dj._check_hit()
		_check("방류구 %s" % cs[0], fp.hits == int(cs[2]), "hits=%d expect=%d" % [fp.hits, int(cs[2])])
	_check("방류구 하우징 z = 캐릭터 뒤", dj.z_index == 1 and dj._housing.z_index + dj.z_index == -1)
	var arc := ElectricArc.new()
	add_child(arc)
	arc.setup(200.0, 400.0, 600.0)
	_check("절연 포스트 z = 캐릭터 뒤", arc.z_index == 1 and arc._posts.z_index + arc.z_index == -1)
	fp.queue_free()
	dj.queue_free()
	arc.queue_free()
	await get_tree().process_frame

class FakePlayer extends Node2D:
	var hits: int = 0
	var clear_protect: bool = false
	func take_hit(d: int) -> void:
		hits += d

func _platform_case() -> void:
	# 막4 2번째 스테이지로 부팅(막 진입 잠금 컷씬의 시간 감속·pause 회피).
	var stage: Node = await _boot("route_freight_lift", 10)
	var p: CharacterBody2D = get_tree().get_first_node_in_group("player") as CharacterBody2D
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.set("harmless", true)
	var hp: Node2D = null
	var vp: Node2D = null
	for m in get_tree().get_nodes_in_group("moving_platform"):
		var fx: float = float(m.get("_from").x)
		if absf(fx - 800.0) < 1.0:
			hp = m
		elif absf(fx - 1330.0) < 1.0:
			vp = m
	_check("이동 발판 확보(수평 800 · 수직 1330)", hp != null and vp != null)
	if hp == null or vp == null:
		stage.queue_free()
		return
	# 수평 리프트 · 한 주기(5s) 상대 x 흔들림.
	p.global_position = hp.global_position + Vector2(0.0, -14.0)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.5).timeout
	var off0: float = p.global_position.x - hp.global_position.x
	var worst: float = 0.0
	var t: float = 0.0
	while t < 5.2:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		worst = maxf(worst, absf(p.global_position.x - hp.global_position.x - off0))
	_check("수평 리프트 탑승 흔들림 ≤ 0.05px", worst <= 0.05, "worst=%.2f" % worst)
	# 수직 리프트 · 접지 유지 + 윗면 오차.
	p.global_position = vp.global_position + Vector2(0.0, -14.0)
	p.velocity = Vector2.ZERO
	await get_tree().create_timer(0.5).timeout
	var lost: int = 0
	var worst_y: float = 0.0
	var t2: float = 0.0
	while t2 < 4.6:
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
		if not p.is_on_floor():
			lost += 1
		worst_y = maxf(worst_y, absf(p.global_position.y - (vp.global_position.y - 12.0)))
	_check("수직 리프트 접지 유지 · 윗면 오차 ≤ 3.5px", lost == 0 and worst_y <= 3.5, "lost=%d worst_y=%.2f" % [lost, worst_y])
	stage.queue_free()
	await get_tree().process_frame

func _rival_cutscene_case() -> void:
	# 첫 진입 · 1.0s 뒤 인트로 컷씬이 세계를 멈춘다.
	var stage: Node = await _boot("route_core_recovery", 13)
	GameState.rival_cutscenes_seen_run = []
	await get_tree().create_timer(1.6, true).timeout
	_check("14-1 첫 진입 = 인트로 컷씬(pause)", get_tree().paused and GameState.rival_cutscenes_seen_run.has("intro"))
	get_tree().paused = false
	GameState.restrict_combat_input = false
	stage.queue_free()
	await get_tree().process_frame
	# 사망 재시작 · 이미 본 컷씬은 생략(정지 없음).
	var stage2: Node = await _boot("route_core_recovery", 13)
	GameState.rival_cutscenes_seen_run = ["intro", "p2", "p3"]
	await get_tree().create_timer(1.6, true).timeout
	_check("14-1 재시작 = 컷씬 생략(pause 없음)", not get_tree().paused)
	get_tree().paused = false
	GameState.restrict_combat_input = false
	stage2.queue_free()
	await get_tree().process_frame
