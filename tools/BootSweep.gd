extends Node

# 부팅 스윕(2026-08-25 신설) · 전 라우트 × 전 방을 실제 Stage로 인스턴스화해 맵 구성
# 붕괴(스폰 크래시·플레이어 미생성·빌더 에러)를 잡는다. 자주 안 가는 맵의 회귀 감시자.
# 실행: godot --headless --path . tools/boot_sweep.tscn
# 실패 시 [BOOT] FAIL 줄 + 종료 코드 1. 스크립트 에러 자체는 콘솔의 SCRIPT ERROR로 드러난다.

func _ready() -> void:
	GameState.persist_blocked = true   # 하니스 의무 플래그
	await get_tree().process_frame
	var fails: int = 0
	var booted: int = 0
	for r in RouteData.ALL_ROUTES:
		var route: Dictionary = r
		var rid: String = str(route.get("id", ""))
		# 라우트가 유효한 첫 스테이지 인덱스를 찾는다(없으면 1 폴백).
		var stage_idx: int = 1
		for s in 15:
			if RouteData._stage_in_range(route, s):
				stage_idx = s
				break
		var seg_total: int = MapData.segment_count(rid)
		for seg in seg_total:
			GameState.start_main_game()
			GameState.player_level = 99   # 레벨업 오버레이 pause 차단(하니스 표준 가드)
			GameState.seen_enemies = ["patrol", "sniper", "drone", "bomber", "shield", "jammer", "elite", "caller"]
			GameState.current_stage = stage_idx
			GameState.record_route_choice(route, "")
			GameState.current_segment = seg
			var stage: Node = (load("res://scenes/stage.tscn") as PackedScene).instantiate()
			add_child(stage)
			for i in 25:
				await get_tree().process_frame
			var p: Node = get_tree().get_first_node_in_group("player")
			if p == null or not is_instance_valid(stage) or not stage.is_inside_tree():
				fails += 1
				print("[BOOT] FAIL ", rid, " seg", seg, " (player=", p != null, ")")
			else:
				booted += 1
			# 잔여 상태 청소 · 다음 맵 부팅이 이전 맵의 pause/time_scale에 안 끌려가게.
			get_tree().paused = false
			Engine.time_scale = 1.0
			GameState.restrict_combat_input = false
			stage.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
	print("[BOOT] done maps=", booted, " fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
