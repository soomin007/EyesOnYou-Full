extends Node

# 규칙 스모크(2026-08-29 신설) · 실플레이 규칙 3종을 실제 Stage 인스턴스에서 단언한다.
#   ① 저격 조준 고정: 고정 뒤 위로 비키면 빗나감 / 제자리면 명중 · 사거리 600 · 거치대 하향 사각
#   ② 도전방: 피격 = 시간 -5(강제 종료 아님) · 비상등 8개 · 시간 초과 = 실패 플래그 + 암전 걷힘 +
#      방 계속 + 완수 프리미엄 없음
#   ③ 방류구: 판정 시작 = 플랜지 입구(기단·급수관 위 무피격) · 하우징/절연 포스트 z = 캐릭터 뒤
#   ④ 이동 발판 탑승: 수평 리프트 위 정지 플레이어의 상대 위치 한 주기 흔들림 0(엔진 1스텝 지연 보정) ·
#      수직 리프트는 접지 유지(floor lost 0) + 윗면 오차 ≤ 3.5px
#   ⑤ 14-1 컷씬 게이트: 첫 진입은 인트로 컷씬(세계 정지) · 사망 재시작(본 컷씬)은 정지 없음
#   ⑥ 사망 한 박자: 죽는 순간 time_scale이 내려갔다가 실시간 ~0.9s 뒤 1.0 복원(씬 전환은 하니스가 차단)
#   ⑦ P3 짝 규칙(A안): 실체화 창마다 진짜·가짜 눈이 플레이어가 닿을 수 있는 자리 둘에 동시에 서고,
#      진짜는 요원을 똑바로 본다 · 다음 창의 진짜 자리는 직전과 다르다
#   ⑧ 문서 서식: 종이/콘솔/뷰어 3양식이 행마다 컨테이너·타이핑 라벨을 1:1로 갖고, 실측 높이가 0보다 크며
#      종이 높이 = 행 합 · 종이 문서엔 장(section) 3개 · 글자 없는 행(괘선·장 경계·게이지)은 정적 판정
#   ⑨ 설정 디버그 탭 "문서 열람": 잠금 해제 상태의 설정에 문서 버튼 3개 · 각 버튼이 해당 양식 오버레이를 열고
#      (행 > 0 · pause · layer 60) 닫으면 pause 해제 + 노드 제거 · 타이틀 메인 메뉴엔 문서 버튼 없음 ·
#      Stage 래퍼와 VeilDialogue 단일 소스가 같은 행 수
# 실행: godot --headless --path . --audio-driver Dummy tools/rule_smoke.tscn (종료 코드 0 = 전부 PASS)
const STAGE_SCENE: String = "res://scenes/stage.tscn"
var fails: int = 0

func _check(label: String, ok: bool, detail: String = "") -> void:
	print("[RULE] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		fails += 1

func _boot(route_id: String, stage_idx: int, pre: Callable = Callable()) -> Node:
	GameState.start_main_game()
	GameState.current_stage = stage_idx
	if pre.is_valid():
		pre.call()
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
	await _death_beat_case()
	await _p3_pair_case()
	await _doc_format_case()
	await _settings_docs_case()
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

func _death_beat_case() -> void:
	var stage: Node = await _boot("route_back_alley", 1)
	stage.set("death_transition_enabled", false)
	var p: Node = get_tree().get_first_node_in_group("player")
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.set("harmless", true)
	GameState.player_hp = 1
	p.set("invuln", 0.0)
	p.call("take_hit", 1)
	await get_tree().create_timer(0.15, true, false, true).timeout   # 실시간 0.15s
	_check("사망 순간 슬로모 진입(time_scale < 0.3)", Engine.time_scale < 0.3 and bool(stage.get("_death_beat_active")), "ts=%.2f" % Engine.time_scale)
	await get_tree().create_timer(1.4, true, false, true).timeout    # 실시간 1.4s · 박자 종료 후
	_check("박자 종료 후 time_scale 1.0 복원", is_equal_approx(Engine.time_scale, 1.0), "ts=%.2f" % Engine.time_scale)
	Engine.time_scale = 1.0
	stage.queue_free()
	await get_tree().process_frame

func _p3_pair_case() -> void:
	var stage: Node = await _boot("route_core_recovery", 13, func() -> void:
		GameState.rival_phase_reached = 2
		GameState.rival_cutscenes_seen_run = ["intro", "p2", "p3"])
	var p: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	p.set("clear_protect", true)
	# 본체 등장 대기(deferred 3.6s 유예 시작).
	var fv: Node = null
	var t0: float = 0.0
	while t0 < 4.0 and fv == null:
		await get_tree().create_timer(0.1).timeout
		t0 += 0.1
		fv = stage.get("_false_veil")
	_check("P3 본체 등장", fv != null)
	if fv == null:
		stage.queue_free()
		return
	# 요원을 좌 상단 데크(450,736)에 세운다 · 짝은 이 데크 근처 둘이어야 한다.
	p.global_position = Vector2(450.0, 736.0)
	var prev_real: Vector2 = Vector2.INF
	for w in 2:
		# 실체(SOLID=2) 진입 대기.
		var t: float = 0.0
		while t < 14.0 and int(fv.get("state")) != 2:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			p.global_position = Vector2(450.0, 736.0)
		var solid: bool = int(fv.get("state")) == 2
		_check("창 %d · 실체화 도달" % (w + 1), solid, "t=%.1f" % t)
		if not solid:
			break
		var real_pos: Vector2 = (fv as Node2D).global_position
		var decoy: Node2D = fv.get("_decoy") as Node2D
		var ref: Vector2 = p.global_position + Vector2(0.0, -30.0)
		var dx: float = absf(real_pos.x - ref.x)
		var dy: float = absf(real_pos.y - ref.y)
		_check("창 %d · 진짜가 닿는 자리(dx ≤ 520 · dy ≤ 220)" % (w + 1), dx <= 520.0 and dy <= 220.0, "dx=%.0f dy=%.0f" % [dx, dy])
		_check("창 %d · 가짜 눈 동반(닿는 자리 · 진짜와 ≥ 90px)" % (w + 1),
			decoy != null and is_instance_valid(decoy) and absf(decoy.global_position.x - ref.x) <= 520.0
			and decoy.global_position.distance_to(real_pos) >= 90.0,
			"" if decoy == null else str(decoy.global_position))
		var gaze: Vector2 = fv.get("_gaze")
		var to_p: Vector2 = (p.global_position - real_pos).normalized()
		_check("창 %d · 진짜 시선 = 요원 방향" % (w + 1), gaze.length() > 4.0 and gaze.normalized().dot(to_p) > 0.9, "dot=%.2f" % gaze.normalized().dot(to_p))
		if w == 1:
			_check("창 2 · 진짜 자리가 직전과 다름", real_pos.distance_to(prev_real) > 60.0, "%s vs %s" % [str(prev_real), str(real_pos)])
		prev_real = real_pos
		# 잠복 복귀 대기.
		var t2: float = 0.0
		while t2 < 6.0 and int(fv.get("state")) == 2:
			await get_tree().physics_frame
			t2 += get_physics_process_delta_time()
			p.global_position = Vector2(450.0, 736.0)
	stage.queue_free()
	await get_tree().process_frame

# ⑧ 문서 서식 · 3양식을 실제 Stage 위에서 열어 행 배치 정합을 단언한다(타이핑은 기다리지 않는다).
func _doc_format_case() -> void:
	var stage: Node = await _boot("route_back_alley", 1)
	var specs: Array = [
		{"style": "paper", "fn": "_arcturus_document_lines", "sections": 3},
		{"style": "terminal", "fn": "_server_log_doc_lines", "sections": 0},
		{"style": "drive", "fn": "_lab_recovery_doc_lines", "sections": 0},
	]
	for sp_raw in specs:
		var sp: Dictionary = sp_raw
		var style: String = str(sp["style"])
		var doc := ArcturusDocumentOverlay.new()
		doc.style = style
		stage.add_child(doc)
		doc.show_doc(stage.call(str(sp["fn"])))
		await get_tree().process_frame
		var rows: Array = doc.get("rows")
		var labels: Array = doc.get("labels")
		var ld: Array = doc.get("lines_data")
		_check("%s · 행/라벨/데이터 1:1" % style, rows.size() == ld.size() and labels.size() == ld.size(),
			"rows=%d labels=%d lines=%d" % [rows.size(), labels.size(), ld.size()])
		var sum_h: float = 0.0
		var all_pos: bool = true
		var sections: int = 0
		var statics: int = 0
		var typed: int = 0
		for i in rows.size():
			var r: Control = rows[i]
			var d: Dictionary = ld[i]
			if r.size.y <= 0.0 or labels[i] == null:
				all_pos = false
			# 행은 위에서부터 빈틈 없이 쌓인다.
			if absf(r.position.y - sum_h) > 0.5:
				all_pos = false
			sum_h += r.size.y
			if str(d.get("kind", "")) == "section":
				sections += 1
			if bool(doc.call("_is_static_row", i)):
				statics += 1
			else:
				typed += 1
		_check("%s · 행 높이 > 0 · 빈틈 없이 쌓임" % style, all_pos)
		var paper: Control = doc.get("paper")
		_check("%s · 종이 높이 = 행 합(또는 화면 하한)" % style, absf(paper.size.y - maxf(sum_h, 720.0 - 64.0 * 2.0)) < 1.0,
			"paper=%.0f sum=%.0f" % [paper.size.y, sum_h])
		_check("%s · 장(section) 수 %d" % [style, int(sp["sections"])], sections == int(sp["sections"]), "got %d" % sections)
		# 글자 없는 행(blank·rule·sheet·bar·redacted 제외)은 정적, 문구 행은 타이핑 대상.
		var expect_static: int = 0
		for d2_raw in ld:
			var d2: Dictionary = d2_raw
			var k: String = str(d2.get("kind", "body"))
			if k == "blank" or k == "rule" or k == "sheet" or k == "bar":
				expect_static += 1
		_check("%s · 정적 행 = 글자 없는 행(%d)" % [style, expect_static], statics == expect_static, "statics=%d typed=%d" % [statics, typed])
		# 첫 행이 정적(뷰어의 게이지)이어도 타이핑 상태가 멈추지 않고 delay로 넘어간다.
		if bool(doc.call("_is_static_row", 0)):
			pass
		doc.call("_start_finalize")
		doc.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	stage.queue_free()
	await get_tree().process_frame

# ⑨ 설정 디버그 탭 문서 열람 · Stage 없이 VeilDialogue 단일 소스로 3양식이 열린다. 타이틀 메인 메뉴에는
# 문서 버튼이 없어야 한다(메뉴 버튼으로 냈다가 회수 · 2026-08-30 사용자 지정 자리 = 디버그 탭).
func _settings_docs_case() -> void:
	var title: Node = (load("res://scenes/title.tscn") as PackedScene).instantiate()
	add_child(title)
	for i in 10:
		await get_tree().process_frame
	var menu_btns: Array = []
	_collect_buttons(title.get("buttons_box"), menu_btns, "")
	var has_doc_btn: bool = false
	for b in menu_btns:
		if (b as Button).text == "문서 열람":
			has_doc_btn = true
	_check("타이틀 메인 메뉴에 '문서 열람' 버튼 없음(버튼 %d개)" % menu_btns.size(), not has_doc_btn)
	title.queue_free()
	await get_tree().process_frame
	GameState.debug_unlocked = true
	var settings: Node = (load(SceneRouter.SETTINGS) as PackedScene).instantiate()
	add_child(settings)
	for i in 10:
		await get_tree().process_frame
	var doc_btns: Array = []
	_collect_buttons(settings, doc_btns, "doc_style")
	_check("설정 디버그 탭 문서 버튼 3개", doc_btns.size() == 3, str(doc_btns.size()))
	var styles: Array = ["paper", "terminal", "drive"]
	for i in 3:
		if i >= doc_btns.size():
			break
		(doc_btns[i] as Button).pressed.emit()
		await get_tree().process_frame
		var doc: Node = settings.get_node_or_null("DebugDoc")
		var ok: bool = doc != null and str(doc.get("style")) == str(styles[i]) and (doc.get("rows") as Array).size() > 0 and get_tree().paused
		var lay: CanvasLayer = null if doc == null else (doc.get("layer") as CanvasLayer)
		ok = ok and lay != null and lay.layer == 60
		_check("문서 열람 %s · 오버레이 열림(행 %s · pause · layer %s)" % [styles[i], "-" if doc == null else str((doc.get("rows") as Array).size()), "-" if lay == null else str(lay.layer)], ok)
		if doc != null:
			doc.call("_start_finalize")   # 실제 닫기 경로 · 1.4s 홀드 + 0.9s 페이드 뒤 finished
			var tc: float = 0.0
			while tc < 4.0 and settings.get_node_or_null("DebugDoc") != null:
				await get_tree().create_timer(0.1, true).timeout
				tc += 0.1
		_check("문서 열람 %s · 닫힘 후 pause 해제 + 노드 제거(재열람 가능)" % styles[i], not get_tree().paused and settings.get_node_or_null("DebugDoc") == null)
	settings.queue_free()
	await get_tree().process_frame
	# 단일 소스 정합 · Stage 래퍼와 같은 행 수.
	_check("아카이브 단일 소스 31행", VeilDialogue.get_arcturus_archive_lines().size() == 31, str(VeilDialogue.get_arcturus_archive_lines().size()))
	_check("서버 로그 단일 소스 10행", VeilDialogue.get_server_log_lines().size() == 10, str(VeilDialogue.get_server_log_lines().size()))
	get_tree().paused = false

# 서브트리의 Button을 모은다 · meta_key가 비어 있지 않으면 그 메타가 있는 버튼만.
func _collect_buttons(n: Node, out: Array, meta_key: String) -> void:
	if n == null:
		return
	if n is Button and (meta_key == "" or n.has_meta(meta_key)):
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out, meta_key)
