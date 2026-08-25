extends Node

# 점프 도달 스윕(2026-08-25 사용자 "점프 최대 높이로만 아슬아슬하게 닿는 발판 완화").
# 전 라우트 × 전 방의 발판마다 "아래에서 올라올 최단 상승폭"을 계산해, 2단 점프 이론
# 최대(≈192px = 1단 104 + 2단 88)에 아슬아슬하게 걸리는 구간을 전수 보고한다.
# 실행: godot --headless --path . tools/jump_reach_sweep.tscn
#  - [TIGHT] 176~192px: 프레임 완벽에 가까운 입력만 닿는 구간(완화 대상)
#  - [OVER]  192px 초과: 맨 점프 불가(글라이드 T2/이동 발판/의도 확인 후 판단)
# 후보 판정: 아래 발판/지면의 x구간을 ±150px 넓혀 대상 x구간과 겹치면 도약 후보로 본다.

const APEX_DOUBLE: float = 192.0
const TIGHT_FROM: float = 176.0
const H_REACH: float = 150.0

func _ready() -> void:
	GameState.persist_blocked = true
	await get_tree().process_frame
	var tight: int = 0
	var over: int = 0
	for r in RouteData.ALL_ROUTES:
		var route: Dictionary = r
		var rid: String = str(route.get("id", ""))
		for seg in MapData.segment_count(rid):
			GameState.current_segment = seg
			var layout: Dictionary = MapData.get_layout(rid)
			var plats: Array = layout.get("platforms", [])
			var ground_y: float = float(layout.get("ground_y", MapData.GROUND_Y_DEFAULT))
			for i in plats.size():
				var p: Dictionary = plats[i]
				var pos: Vector2 = p.get("pos", Vector2.ZERO)
				var w: float = float(p.get("w", 100.0))
				var t_min: float = pos.x - w * 0.5 - H_REACH
				var t_max: float = pos.x + w * 0.5 + H_REACH
				# 지면에서의 상승폭이 기본 후보.
				var best: float = ground_y - pos.y
				var best_from: String = "지면(y%.0f)" % ground_y
				for j in plats.size():
					if j == i:
						continue
					var q: Dictionary = plats[j]
					var qpos: Vector2 = q.get("pos", Vector2.ZERO)
					if qpos.y <= pos.y:
						continue
					var qw: float = float(q.get("w", 100.0))
					if qpos.x + qw * 0.5 < t_min or qpos.x - qw * 0.5 > t_max:
						continue
					var climb: float = qpos.y - pos.y
					if climb < best:
						best = climb
						best_from = "발판(%.0f,%.0f)" % [qpos.x, qpos.y]
				if best > APEX_DOUBLE:
					over += 1
					print("[OVER]  %s seg%d 발판(%.0f,%.0f w%.0f) 최단 상승 %.0fpx ← %s" %
						[rid, seg, pos.x, pos.y, w, best, best_from])
				elif best > TIGHT_FROM:
					tight += 1
					print("[TIGHT] %s seg%d 발판(%.0f,%.0f w%.0f) 최단 상승 %.0fpx ← %s" %
						[rid, seg, pos.x, pos.y, w, best, best_from])
	print("[JUMP-SWEEP] tight=%d over=%d" % [tight, over])
	get_tree().quit(0)
