extends Node

# 포탑(BulletTrap) 사선 전수 스윕 · 전 라우트·전 방의 포탑 발사 경로가 플랫폼 슬래브에
# 얼마 만에 막히는지 기하로 검사한다(발판이 탄을 먹는 배치 금지 · known_issues "가로 포탑
# 높이" 항목의 수직 확장판). 지면·외벽에 끝나는 것은 정상이라 보고하지 않고, **플랫폼**에
# 막히는 경우만 거리와 함께 찍는다. 실행:
#   godot --headless --path . res://tools/trap_sweep.tscn
# 기하 상수는 실제 코드와 동기: 슬래브 = pos.y ± 12(Stage._build_platform shape 24),
# 탄 스폰 = 포탑 + dir*14(BulletTrap._fire_one), 사거리 = 460 * 1.6 = 736(LINE_LEN).

const SLAB_HALF: float = 12.0
const SPAWN_OFF: float = 14.0
const RANGE: float = 736.0

func _ready() -> void:
	GameState.persist_blocked = true   # 실사용자 저장 파일 보호 · 하니스 공통
	var findings: int = 0
	for r in RouteData.ALL_ROUTES:
		var route: Dictionary = r
		var rid: String = str(route.get("id", ""))
		var raw: Dictionary = MapData._layout_raw(rid)
		var segs: Array = raw.get("segments", [raw])
		for si in segs.size():
			var seg: Dictionary = segs[si]
			findings += _sweep_segment(rid, si, seg, segs.size())
	print("[SWEEP] DONE findings=%d" % findings)
	get_tree().quit()

func _sweep_segment(rid: String, si: int, seg: Dictionary, seg_n: int) -> int:
	var hits: int = 0
	var plats: Array = seg.get("platforms", [])
	for t in seg.get("traps", []):
		var trap: Dictionary = t
		var tx: float = float(trap.get("x", 0.0))
		var ty: float = float(trap.get("y", 0.0))
		var dv: Vector2 = _dir_vec(str(trap.get("dir", "down")))
		var spawn: Vector2 = Vector2(tx, ty) + dv * SPAWN_OFF
		var best: float = RANGE
		var blocker: String = ""
		for p in plats:
			var pd: Dictionary = p
			var pp: Vector2 = pd.get("pos", Vector2.ZERO)
			var hw: float = float(pd.get("w", 220.0)) * 0.5
			var d: float = _ray_vs_rect(spawn, dv,
				Rect2(pp.x - hw, pp.y - SLAB_HALF, hw * 2.0, SLAB_HALF * 2.0))
			if d >= 0.0 and d < best:
				best = d
				blocker = "플랫폼(%.0f,%.0f w%.0f)" % [pp.x, pp.y, hw * 2.0]
		if blocker != "":
			hits += 1
			print("[SWEEP] %s 방%d/%d 포탑(%.0f,%.0f,%s) → %.0fpx에서 %s에 막힘" % [
				rid, si + 1, seg_n, tx, ty, str(trap.get("dir", "down")), best, blocker])
	return hits

func _dir_vec(d: String) -> Vector2:
	match d:
		"up": return Vector2.UP
		"left": return Vector2.LEFT
		"right": return Vector2.RIGHT
		_: return Vector2.DOWN

# 축 정렬 레이 vs 사각형 · 진행 방향으로 rect에 닿기까지의 거리(안 닿으면 -1).
func _ray_vs_rect(origin: Vector2, dv: Vector2, rect: Rect2) -> float:
	if dv.y != 0.0:
		if origin.x < rect.position.x or origin.x > rect.end.x:
			return -1.0
		var edge_y: float = rect.end.y if dv.y < 0.0 else rect.position.y
		var dist: float = (edge_y - origin.y) * signf(dv.y)
		if rect.position.y <= origin.y and origin.y <= rect.end.y:
			return 0.0   # 스폰 지점이 이미 슬래브 안
		return dist if dist >= 0.0 and dist <= RANGE else -1.0
	if origin.y < rect.position.y or origin.y > rect.end.y:
		return -1.0
	var edge_x: float = rect.end.x if dv.x < 0.0 else rect.position.x
	var dist_x: float = (edge_x - origin.x) * signf(dv.x)
	if rect.position.x <= origin.x and origin.x <= rect.end.x:
		return 0.0
	return dist_x if dist_x >= 0.0 and dist_x <= RANGE else -1.0
