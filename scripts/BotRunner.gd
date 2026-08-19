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
	{"rid": "route_substation",     "tags": ["원거리", "드론", "노출", "전투"], "risk": 3, "stage": 4},
	{"rid": "route_warehouse",      "tags": ["근접전", "전투"], "risk": 2, "stage": 3},
	# 방 체인 확산 1호(2026-08-18) — 창고와 함께 체인 목표 밴드(막2~3 90~120s) 검증 대상.
	{"rid": "route_cooling",        "tags": ["전투", "드론", "함정"], "risk": 2, "stage": 4},
	# 배치 2(2026-08-18) — 막2~3 미확산 우선 체인화 3맵.
	{"rid": "route_control_corridor", "tags": ["전투"], "risk": 3, "stage": 6},
	{"rid": "route_server_hall",      "tags": ["전투"], "risk": 3, "stage": 6},
	{"rid": "route_demolition_zone", "tags": ["근접전", "어두운_환경", "전투"], "risk": 2, "stage": 1},
	# 표준 조우 벤치(MapData._bot_bench · 게임 미노출): 평지 3웨이브, 빌드 화력의 순수 비교.
	{"rid": "route_bot_bench",      "tags": ["전투"], "risk": 2, "stage": 3},
	# 막5 벤치(stage 12) — 막 진행 적 강화(HP·사격 빈도) + 실전형 조우(저격·드론 혼성) 검증.
	# 실런의 만렙 빌드가 실제로 만나는 조우는 이쪽(만렙이 stage 3에 있는 조합은 실런에 없다).
	{"rid": "route_bot_bench_late", "tags": ["전투", "원거리"], "risk": 2, "stage": 12},
	# datacenter는 스위트에서 제외(2026-08-18): 수직 지형이라 봇이 상층 드론을 못 잡고
	# 90s 타임아웃까지 대치(데드락). 전멸형 대표는 벤치가 맡는다 · 참고치 가치 낮음.
]
# 방당 타임아웃 — 단일방 시절 90이었으나 체인 방 확대 + 봇의 전멸 성향(대공·크로스 시도
# 포함)으로 base의 정직한 완주가 90을 넘기 시작(창고 방2 실측 97s). 120은 실패 판정이
# 아니라 측정 상한: 넘으면 그 방 설계나 봇 기법에 구조 문제가 있다는 신호.
const TIMEOUT_GAME_S: float = 120.0
const HP_POOL: int = 30   # 사망 중단 없이 받은 피해를 지표로 잰다
const ONLY_MAP: String = ""   # ""이면 전체 · 진단 시 rid 지정(콤마로 여러 개)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 3.0
	# 배속에 맞춰 물리 틱도 3배 — 게임초당 물리 delta를 1/60로 보존한다. 이거 없이 scale 3만
	# 올리면 물리 delta 0.05로 양자화가 거칠어져 명중률·회피가 실플레이와 다르게 측정된다
	# (2026-08-18 실측: 변전소 발사 98→187 · 벤치 피탄 9→15로 오염).
	Engine.physics_ticks_per_second = 180
	# 봇이 쓰는 플레이 습관 프로필을 결과 해석용으로 남긴다(src=default는 실플레이 표본 0 =
	# 사용자 스타일 근사 기본값 · user는 실측 누적치). 프로필이 바뀌면 계측 이력 비교에 주의.
	var prof: Dictionary = GameState.get_playstyle()
	print("[BOT] profile src=%s dash_pm=%.1f jump_pm=%.1f air=%.2f dist=%.0f hunt=%.2f gren_pm=%.1f dmg_pm=%.1f stages=%d" % [
		("user" if int(prof.get("stages", 0)) > 0 else "default"),
		float(prof.get("dash_pm", 0.0)), float(prof.get("jump_pm", 0.0)),
		float(prof.get("air_shot_ratio", 0.0)), float(prof.get("avg_fire_dist", 0.0)),
		float(prof.get("hunt_ratio", 0.0)), float(prof.get("grenade_pm", 0.0)),
		float(prof.get("dmg_pm", 0.0)), int(prof.get("stages", 0))])
	await get_tree().process_frame
	for b in BUILDS:
		for m in MAPS:
			if ONLY_MAP != "" and not (str(m.get("rid")) in ONLY_MAP.split(",")):
				continue
			await _run_one(b, m)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print("[BOT] SUITE DONE")
	get_tree().quit(0)

func _run_one(build: Dictionary, m: Dictionary) -> void:
	GameState.reset()
	for eid in ["patrol", "shield", "sniper", "drone", "bomber", "elite", "jammer"]:
		GameState.mark_enemy_seen(eid)
	GameState.playground_active = true   # 골 도달 = 세계 정지(계측 종료 신호) + 습관 기록 제외
	GameState.bot_headless = true        # 방 체인 씬 전환 생략 · 러너가 방을 직접 띄운다
	GameState.skills = (build.get("skills", {}) as Dictionary).duplicate()
	GameState.skills["dash"] = 1
	GameState.skills["double_jump"] = 1
	# 레벨업 오버레이(일시정지) 차단 — pause 중엔 골 Area 판정이 없어 가짜 TIMEOUT이 난다
	# (2026-08-18 배치 2에서 실측: 체인·밀도 증가로 XP가 level 30 문턱을 넘기 시작).
	# level 99 + 폴링마다 XP 0 리셋의 이중 방어.
	GameState.player_level = 99
	GameState.player_max_hp = HP_POOL
	GameState.player_hp = HP_POOL
	var rid: String = str(m.get("rid"))
	GameState.current_route_id = rid
	GameState.current_route_tags = m.get("tags")
	GameState.current_route_risk = int(m.get("risk"))
	GameState.current_route_reward_type = ""   # 봇 계측은 종류 효과 미사용
	GameState.current_stage = int(m.get("stage"))
	# 방 체인 — 방마다 새 Stage를 띄워 순서대로 주파, 지표는 체인 합산(한 스테이지 = 한 행).
	var seg_total: int = MapData.segment_count(rid)
	var kills0: int = GameState.kills_total
	var enemies_total: int = 0
	var shots_total: int = 0
	var dmg_total: int = 0
	var seg_times: Array = []   # 방별 소요(진단: 어느 방이 시간을 먹는가)
	var timed_out: bool = false
	# 게임 시간 = 폴링 대기(게임초 단위)의 누적. "실측 × 현재 time_scale" 방식은 슬로모/연출이
	# scale을 바꾸는 순간 전체 구간이 왜곡된다(2026-08-18 변전소 가짜 TIMEOUT의 원인).
	var game_time: float = 0.0
	for seg in seg_total:
		GameState.current_segment = seg
		# Player._exit_tree(슬로모 안전망)가 방/런 정리마다 time_scale을 1.0으로 되돌린다 ·
		# 방마다 다시 고정(계측 속도 유지 · 시간 계산은 위 누적 방식이라 어차피 불변).
		Engine.time_scale = 3.0
		var st: Node = load("res://scenes/stage.tscn").instantiate()
		add_child(st)
		await get_tree().create_timer(0.5, true).timeout
		game_time += 0.5
		enemies_total += _alive_enemies()
		var bot := BotDriver.new()
		bot.setup(st)
		add_child(bot)
		var seg_time: float = 0.0
		var done: bool = false
		while not done:
			await get_tree().create_timer(0.25, true).timeout
			seg_time += 0.25
			game_time += 0.25
			# 게임 내 슬로모/연출·Player._exit_tree 안전망이 scale을 내려도 계측 속도 유지.
			# 게임 시간 계산은 위 누적 방식이라 scale과 무관하게 정확하다.
			Engine.time_scale = 3.0
			GameState.player_xp = 0   # 레벨업 문턱 차단(위 주석 · 이중 방어의 두 번째)
			# 사망 불가 리필 · 받은 피해는 누적 계측(1차 스위트가 창고에서 봇 사망 → Death 씬이
			# 러너를 교체해 중단된 사고 방지, 2026-08-18).
			if GameState.player_hp < HP_POOL:
				dmg_total += HP_POOL - GameState.player_hp
				GameState.player_hp = HP_POOL
			if not is_instance_valid(st):
				print("[BOT] build=%s map=%s DEATH-ABORT" % [str(build.get("name")), rid])
				return
			var arena_clear: bool = str(st.get("_goal_type")) == "ENEMY_CLEAR" \
				and seg_time > 4.0 and bool(st.call("_can_arena_clear"))
			if bool(st.get("goal_reached")) or arena_clear:
				done = true
			elif seg_time > TIMEOUT_GAME_S:
				done = true
				timed_out = true
		seg_times.append("%.1f" % seg_time)
		var p: Node = get_tree().get_first_node_in_group("player")
		if p != null:
			shots_total += int(p.get("shots_fired"))   # Player는 방마다 새로 = 방별 발포 합산
		bot.stop()
		bot.queue_free()
		get_tree().paused = false
		st.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		if timed_out:
			break
	# 처치 = GameState 카운터 기준(웨이브 맵에서 초기 대비 계산은 음수가 나온다 · 1차 스위트 교훈).
	var kills: int = GameState.kills_total - kills0
	print("[BOT] build=%s map=%s s%d time=%.1f%s dmg=%d kills=%d/%d shots=%d segt=%s" % [
		str(build.get("name")), rid, int(m.get("stage")), game_time,
		("(TIMEOUT)" if timed_out else ""), dmg_total, kills, enemies_total, shots_total,
		"+".join(seg_times)])
	GameState.playground_active = false

func _alive_enemies() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node2D and not bool((e as Node2D).get("dead")):
			n += 1
	return n
