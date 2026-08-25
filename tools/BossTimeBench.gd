extends Node

# SENTINEL 전투 시간 벤치(2026-08-25 신설 · sentinel_rework §8 목표 60~90s 검증).
# 이동 AI 없이 "전 시간 명중 지속 화력"을 모델로 보스에 직접 타격을 넣어 격파까지의
# 게임 시간을 잰다 = 실플레이 시간의 하한(실전은 회피·이동으로 더 길다).
# 배기(창 상한·강제 배출)·페이즈 전환 무적·위장 자폭·재점화가 전부 실코드로 굴러간다.
# 실행: godot --headless --path . tools/boss_time_bench.tscn
# 변형: 기본 연사(0.42s/1) · 강화 연사(0.24s/1) · 고화력(0.42s/2) × 성장 보너스 0/16.

const VARIANTS: Array = [
	{"label": "기본(0.42s x1)", "interval": 0.42, "dmg": 1, "bonus": 0},
	{"label": "연사(0.24s x1)", "interval": 0.24, "dmg": 1, "bonus": 0},
	{"label": "고화력(0.42s x2)", "interval": 0.42, "dmg": 2, "bonus": 0},
	{"label": "만렙 근사(0.24s x2 +16)", "interval": 0.24, "dmg": 2, "bonus": 16},
]
const TIME_CAP: float = 300.0

func _ready() -> void:
	GameState.persist_blocked = true
	await get_tree().process_frame
	for v in VARIANTS:
		var d: Dictionary = v
		var secs: float = await _run_variant(float(d["interval"]), int(d["dmg"]), int(d["bonus"]))
		print("[BENCH] %s → %.1fs" % [str(d["label"]), secs])
	print("[BENCH] DONE")
	get_tree().quit(0)

func _run_variant(interval: float, dmg: int, bonus: int) -> float:
	GameState.start_main_game()
	GameState.player_level = 99
	GameState.seen_enemies = ["patrol", "sniper", "drone", "bomber", "shield", "jammer", "elite", "caller"]
	GameState.current_stage = 8
	var route: Dictionary = {}
	for r in RouteData.ALL_ROUTES:
		if str((r as Dictionary).get("id", "")) == "route_lab":
			route = r
	GameState.record_route_choice(route, "")
	var stage: Node = (load("res://scenes/stage.tscn") as PackedScene).instantiate()
	add_child(stage)
	for i in 40:
		await get_tree().process_frame
	var boss: Node = stage.get("boss")
	if boss == null:
		stage.queue_free()
		return -1.0
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null:
		p.set("clear_protect", true)
	boss.set("intro_hold", false)
	stage.set("_boss_intro_skip", true)
	if bonus > 0:
		boss.call("apply_hp_bonus", bonus)
	for i in 10:
		await get_tree().process_frame
	var t: float = 0.0
	var acc: float = 0.0
	while not bool(boss.get("dead")) and t < TIME_CAP:
		await get_tree().physics_frame
		var dt: float = get_physics_process_delta_time()
		t += dt
		acc += dt
		if acc >= interval and is_instance_valid(boss):
			acc = 0.0
			boss.call("take_damage", dmg, 0)
	get_tree().paused = false
	Engine.time_scale = 1.0
	GameState.restrict_combat_input = false
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return t
