extends Node

# 불변식 스윕(2026-08-25 신설) · 런 상태 기계의 규칙을 헤드리스에서 전수 단언하는 QA 도구.
# 배경: 사망 후퇴가 route_history를 안 잘라 맵 풀이 말라붙던 진행 불가 버그(2026-08-25
# 사용자 보고)는 "상태 불변식 위반"인데 어떤 하니스도 감시하지 않았다. 이 도구가 그 감시자.
# 실행: godot --headless --path . tools/invariant_sweep.tscn
# 전 항목 PASS면 [SWEEP] ALL PASS + 종료 코드 0, 위반 시 항목별 FAIL + 종료 코드 1.
# 검사 항목:
#   A. 전 스테이지 사망 불변식 · 어느 스테이지에서 죽어도 (stage = 막 시작) ∧
#      (route_history.size == stage) ∧ (그 자리 풀 ≥ 1) ∧ (hp = 실효 최대).
#   B. 전 스테이지 풀 하한 · 처리 4종 각각의 그리디 완주에서 s0~s13 풀이 비지 않는다.
#   C. 잠금·HP 하한 · 어떤 최대 HP(3~6)·막에서도 실효 최대 ≥ 2, 잠금 수 정합.
#   D. 런 직렬화 왕복 · _store/_restore가 핵심 필드를 보존한다(인메모리 · 디스크 무접촉).
#   E. 오버레이 pause 복원 · 컷씬/문서가 닫힌 뒤 pause=false, time_scale=1.
# 새 상태 규칙이 생기면 여기에 단언을 추가한다(known_issues 재발 방지의 실행형).

var fails: int = 0

func _check(check_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[SWEEP] PASS ", check_name)
	else:
		fails += 1
		print("[SWEEP] FAIL ", check_name, "  ", detail)

func _ready() -> void:
	GameState.persist_blocked = true   # 하니스 의무 플래그 · user:// 오염 금지
	await get_tree().process_frame
	_sweep_death_invariant()
	_sweep_pool_floor()
	_sweep_hp_locks()
	_sweep_run_roundtrip()
	await _sweep_overlay_pause()
	print("[SWEEP] ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# 그리디 진행 · stage까지 풀 첫 후보를 실제 선택 경로(record_route_choice)로 고르며
# 진행한다. 실런과 같은 파생 집계·막 경계 검문이 함께 굴러간다. 풀이 빈 스테이지는 -1 반환.
func _greedy_to(stage: int) -> int:
	GameState.route_history = []
	GameState.current_route_id = ""
	for s in stage:
		GameState.current_stage = s
		var pool: Array = RouteData.get_route_pool_for_stage(s, GameState.route_history)
		if pool.is_empty():
			return s
		GameState.record_route_choice(pool[0], "")
		GameState.current_stage = s + 1
		if GameState.is_act_start(s + 1):
			GameState.capture_act_checkpoint()
	GameState.current_stage = stage
	return -1

# A. 전 스테이지 사망 불변식 · 위치·기록·풀·HP에 더해 파생 집계(공격성)와 직전 맵 표지가
# 막 시작 시점으로 함께 되감기는지(감사 A-1/A-2)까지 단언한다.
func _sweep_death_invariant() -> void:
	var bad: Array = []
	for s in 14:
		GameState.start_main_game()
		GameState.disposal_choice = "extract"
		var act_s: int = GameState.act_start_stage(GameState.act_for_stage(s))
		var exp_aggr: int = 0
		var boot_fail: bool = false
		for t in s:
			GameState.current_stage = t
			var pool0: Array = RouteData.get_route_pool_for_stage(t, GameState.route_history)
			if pool0.is_empty():
				boot_fail = true
				break
			GameState.record_route_choice(pool0[0], "")
			GameState.current_stage = t + 1
			if GameState.is_act_start(t + 1):
				GameState.capture_act_checkpoint()
			if t + 1 == act_s:
				exp_aggr = GameState.aggression_score
		if boot_fail:
			bad.append("s%d 풀 소진(그리디)" % s)
			continue
		GameState.current_stage = s
		GameState.register_death()
		var pool: Array = RouteData.get_route_pool_for_stage(GameState.current_stage, GameState.route_history)
		var exp_rid: String = str(GameState.route_history.back()) if not GameState.route_history.is_empty() else ""
		if GameState.current_stage != act_s:
			bad.append("s%d stage %d != 막시작 %d" % [s, GameState.current_stage, act_s])
		elif GameState.route_history.size() != GameState.current_stage:
			bad.append("s%d hist %d != stage %d" % [s, GameState.route_history.size(), GameState.current_stage])
		elif pool.is_empty():
			bad.append("s%d 사망 후 풀 0" % s)
		elif GameState.player_hp != GameState.effective_max_hp():
			bad.append("s%d hp %d != 실효 %d" % [s, GameState.player_hp, GameState.effective_max_hp()])
		elif GameState.current_route_id != exp_rid:
			bad.append("s%d rid '%s' != 기록 끝 '%s'" % [s, GameState.current_route_id, exp_rid])
		elif GameState.aggression_score != exp_aggr:
			bad.append("s%d 공격성 %d != 막시작 %d(이중 집계)" % [s, GameState.aggression_score, exp_aggr])
	_check("A. 전 스테이지 사망 불변식(s0~13 · 파생 집계 포함)", bad.is_empty(), str(bad))
	# 14-1 예외 · 보스전 사망은 제자리(리셋은 페이즈만).
	GameState.start_main_game()
	_greedy_to(13)
	GameState.current_stage = 14
	GameState.route_history.append("route_core_recovery")
	GameState.current_route_id = "route_core_recovery"
	GameState.rival_phase_reached = 2
	GameState.register_death()
	_check("A2. 14-1 사망 = 제자리", GameState.current_stage == 14,
		"stage=%d" % GameState.current_stage)

# B. 처리 4종 그리디 완주 풀 하한.
func _sweep_pool_floor() -> void:
	for disposal in ["extract", "destroy", "conceal", "leave"]:
		GameState.start_main_game()
		GameState.disposal_choice = disposal
		var empty_at: int = _greedy_to(14)
		_check("B. 그리디 완주 풀 하한(%s)" % disposal, empty_at < 0,
			"stage %d 풀 0" % empty_at)

# C. 잠금·HP 하한.
func _sweep_hp_locks() -> void:
	GameState.start_main_game()
	var bad: Array = []
	for max_hp in [3, 4, 5, 6]:
		GameState.player_max_hp = max_hp
		GameState.rival_locks_broken = 0
		for act in 5:
			GameState.current_stage = GameState.act_start_stage(act)
			var eff: int = GameState.effective_max_hp()
			var locks: int = GameState.rival_locks_active()
			if eff < 2:
				bad.append("max%d act%d 실효 %d" % [max_hp, act + 1, eff])
			if eff + locks != max_hp and locks < (1 if act >= 3 else 0):
				bad.append("max%d act%d 잠금 정합 locks=%d" % [max_hp, act + 1, locks])
	_check("C. 실효 최대 HP ≥ 2 (max 3~6 × 전 막)", bad.is_empty(), str(bad))

# D. 런 직렬화 왕복(인메모리).
func _sweep_run_roundtrip() -> void:
	GameState.start_main_game()
	GameState.current_stage = 7
	GameState.route_history = []
	for i in 7:
		GameState.route_history.append("r%d" % i)
	GameState.score = 1234
	GameState.skills["fire_boost"] = 2
	GameState.player_max_hp = 4
	GameState.player_hp = 2
	GameState.disposal_choice = "conceal"
	var cf := ConfigFile.new()
	GameState._store_run_state(cf, "run")
	GameState.start_main_game()   # 상태 오염(리셋)
	GameState._restore_run_state(cf, "run")
	var ok: bool = GameState.current_stage == 7 \
		and GameState.route_history.size() == 7 \
		and GameState.score == 1234 \
		and int(GameState.skills.get("fire_boost", 0)) == 2 \
		and GameState.player_max_hp == 4 and GameState.player_hp == 2 \
		and GameState.disposal_choice == "conceal"
	_check("D. 런 직렬화 왕복", ok,
		"stage=%d hist=%d score=%d" % [GameState.current_stage, GameState.route_history.size(), GameState.score])

# E. 오버레이 pause/time_scale 복원.
func _sweep_overlay_pause() -> void:
	GameState.start_main_game()
	# 컷씬 · 열고 전체 건너뛰기 → pause 복원.
	var sd := StoryDialogue.new()
	sd.open([{"who": "veil", "text": "점검용 문장입니다."}])
	add_child(sd)
	await get_tree().process_frame
	var paused_mid: bool = get_tree().paused
	sd.call("_skip_all")
	await get_tree().create_timer(0.5).timeout
	_check("E1. 컷씬 pause 복원", paused_mid and not get_tree().paused,
		"mid=%s after=%s" % [paused_mid, get_tree().paused])
	# 문서 오버레이 · 열고 닫기 → pause 복원(_start_finalize 내부 1.4s 대기 포함 여유).
	var doc := ArcturusDocumentOverlay.new()
	add_child(doc)
	doc.show_doc([{"text": "점검", "kind": "title"}])
	await get_tree().create_timer(0.5).timeout
	var paused_doc: bool = get_tree().paused
	doc.call("_start_finalize")
	await get_tree().create_timer(2.9).timeout
	_check("E2. 문서 pause 복원", paused_doc and not get_tree().paused,
		"mid=%s after=%s" % [paused_doc, get_tree().paused])
	_check("E3. time_scale 복원", is_equal_approx(Engine.time_scale, 1.0),
		"time_scale=%f" % Engine.time_scale)
