class_name BotRunner
extends Node2D

# 밸런스 계측 스위트 · 빌드 프리셋 × 맵을 BotDriver로 자동 주파해 지표를 찍는다.
# 실행: godot --path . --audio-driver Dummy scenes/bot_runner.tscn
# 출력: [BOT] build=<이름> map=<맵> time=<게임초> dmg=<받은 피해> kills=<처치>/<총원> shots=<발사>
# time_scale 3으로 돌려 실시간의 1/3에 계측(게임 시간 기준 지표는 동일).

const BUILDS: Array = [
	{"name": "base", "skills": {}},
	{"name": "mid",  "skills": {"fire_boost": 1, "multishot": 1}},
	# max = 사용자가 지적한 풀빌드 그대로: 오연사+사거리(multishot 3) × 피해+관통(fire_boost 3)
	# × 유도(glide 3 · 공중 사격 한정). 초기 스위트는 glide가 빠져 유도를 아예 못 쟀다(2026-08-18).
	{"name": "max",  "skills": {"fire_boost": 3, "multishot": 3, "glide": 3}},
]
const MAPS: Array = [
	{"rid": "route_substation",     "tags": ["원거리", "드론", "노출", "전투"], "risk": 3, "reward": 3, "stage": 4},
	{"rid": "route_warehouse",      "tags": ["근접전", "전투"], "risk": 2, "reward": 3, "stage": 3},
	{"rid": "route_demolition_zone", "tags": ["근접전", "어두운_환경", "전투"], "risk": 2, "reward": 2, "stage": 1},
	# 표준 조우 벤치(MapData._bot_bench · 게임 미노출): 평지 3웨이브, 빌드 화력의 순수 비교.
	{"rid": "route_bot_bench",      "tags": ["전투"], "risk": 2, "reward": 2, "stage": 3},
	# 전멸형(웨이브) · 수직 지형이라 봇 등반 한계로 참고치만(드론·상층 저격 상대 불가).
	{"rid": "route_datacenter",     "tags": ["전투", "드론", "원거리"], "risk": 3, "reward": 3, "stage": 6},
]
const TIMEOUT_GAME_S: float = 90.0
const HP_POOL: int = 30   # 사망 중단 없이 받은 피해를 지표로 잰다
const ONLY_MAP: String = ""   # ""이면 전체 · 특정 맵만 진단할 때 rid 지정

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 3.0
	await get_tree().process_frame
	for b in BUILDS:
		for m in MAPS:
			if ONLY_MAP != "" and str(m.get("rid")) != ONLY_MAP:
				continue
			await _run_one(b, m)
	Engine.time_scale = 1.0
	print("[BOT] SUITE DONE")
	get_tree().quit(0)

func _run_one(build: Dictionary, m: Dictionary) -> void:
	GameState.reset()
	for eid in ["patrol", "shield", "sniper", "drone", "bomber", "elite"]:
		GameState.mark_enemy_seen(eid)
	GameState.playground_active = true   # 골 도달 = 세계 정지(계측 종료 신호로 활용)
	GameState.skills = (build.get("skills", {}) as Dictionary).duplicate()
	GameState.skills["dash"] = 1
	GameState.skills["double_jump"] = 1
	GameState.player_level = 30          # 레벨업 오버레이(일시정지) 방지 · 문턱이 높아 미발동
	GameState.player_max_hp = HP_POOL
	GameState.player_hp = HP_POOL
	GameState.current_route_id = str(m.get("rid"))
	GameState.current_route_tags = m.get("tags")
	GameState.current_route_risk = int(m.get("risk"))
	GameState.current_route_reward = int(m.get("reward"))
	GameState.current_stage = int(m.get("stage"))
	GameState.current_segment = 0
	var st: Node = load("res://scenes/stage.tscn").instantiate()
	add_child(st)
	await get_tree().create_timer(0.5, true).timeout
	var kills0: int = GameState.kills_total
	var enemies0: int = _alive_enemies()
	var bot := BotDriver.new()
	bot.setup(st)
	add_child(bot)
	var t_real0: float = Time.get_ticks_msec() / 1000.0
	var done: bool = false
	var timed_out: bool = false
	var dmg_total: int = 0
	while not done:
		await get_tree().create_timer(0.25, true).timeout
		# 사망 불가 리필 · 받은 피해는 누적 계측(1차 스위트가 창고에서 봇 사망 → Death 씬이
		# 러너를 교체해 중단된 사고 방지, 2026-08-18).
		if GameState.player_hp < HP_POOL:
			dmg_total += HP_POOL - GameState.player_hp
			GameState.player_hp = HP_POOL
		if not is_instance_valid(st):
			print("[BOT] build=%s map=%s DEATH-ABORT" % [str(build.get("name")), str(m.get("rid"))])
			return
		var game_elapsed: float = (Time.get_ticks_msec() / 1000.0 - t_real0) * Engine.time_scale
		var arena_clear: bool = str(st.get("_goal_type")) == "ENEMY_CLEAR" \
			and game_elapsed > 4.0 and bool(st.call("_can_arena_clear"))
		if bool(st.get("goal_reached")) or arena_clear:
			done = true
		elif game_elapsed > TIMEOUT_GAME_S:
			done = true
			timed_out = true
	var game_time: float = (Time.get_ticks_msec() / 1000.0 - t_real0) * Engine.time_scale
	var p: Node = get_tree().get_first_node_in_group("player")
	var shots: int = int(p.get("shots_fired")) if p != null else -1
	var dmg: int = dmg_total
	# 처치 = GameState 카운터 기준(웨이브 맵에서 초기 대비 계산은 음수가 나온다 · 1차 스위트 교훈).
	var kills: int = GameState.kills_total - kills0
	print("[BOT] build=%s map=%s time=%.1f%s dmg=%d kills=%d/%d shots=%d" % [
		str(build.get("name")), str(m.get("rid")), game_time,
		("(TIMEOUT)" if timed_out else ""), dmg, kills, enemies0, shots])
	bot.stop()
	bot.queue_free()
	get_tree().paused = false
	st.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.playground_active = false

func _alive_enemies() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node2D and is_instance_valid(e) and not bool((e as Node2D).get("dead")):
			n += 1
	return n
