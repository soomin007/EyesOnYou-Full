class_name SkillIcon
extends Control

# 스킬 선택 카드용 절차적 아이콘 — 자산 없이 _draw 도형으로 스킬별 글리프를 그린다.
# 색은 계열(전투 빨강 / 이동 시안 / 생존 초록)로 통일해 아이콘만 봐도 계열이 읽히게.
# skill_id로 모양을 고르고, 모르는 id는 일반 글리프로 폴백.

# 계열 색은 단일 소스(SkillTreeData) 참조 — 트리/카드 어디서나 같은 색.
const FAMILY_COLORS: Dictionary = SkillTreeData.FAMILY_COLORS

var skill_id: String = ""
var family: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 * 0.72
	if r < 4.0:
		return
	var col: Color = FAMILY_COLORS.get(family, Color(0.85, 0.88, 0.92))
	match skill_id:
		"fire_boost": _icon_fire_boost(c, r, col)
		"multishot": _icon_multishot(c, r, col)
		"explosive": _icon_explosive(c, r, col)
		"glide": _icon_glide(c, r, col)
		"dash_boost", "dash": _icon_dash(c, r, col)
		"double_jump": _icon_double_jump(c, r, col)
		"hp": _icon_hp(c, r, col)
		"shield": _icon_shield(c, r, col)
		"barrier": _icon_barrier(c, r, col)
		_: _icon_generic(c, r, col)

# ── 전투 ──────────────────────────────────────────
func _icon_fire_boost(c: Vector2, r: float, col: Color) -> void:
	# 탄환 + 명중 임팩트(우측 방사선) — "사격 강화"
	draw_line(c + Vector2(-r * 0.9, 0.0), c + Vector2(r * 0.15, 0.0), col, 4.0, true)
	var tip: Vector2 = c + Vector2(r * 0.15, 0.0)
	draw_colored_polygon(PackedVector2Array([
		tip + Vector2(0.0, -5.0), tip + Vector2(0.0, 5.0), c + Vector2(r * 0.55, 0.0)]), col)
	for ang in [-0.7, 0.0, 0.7]:
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + Vector2(r * 0.7, 0.0) + d * 3.0, c + Vector2(r * 0.7, 0.0) + d * r * 0.5, col, 1.5, true)

func _icon_multishot(c: Vector2, r: float, col: Color) -> void:
	# 한 점에서 부채꼴 3발 — "삼연사"
	var origin: Vector2 = c + Vector2(-r * 0.85, 0.0)
	for ang in [-0.52, 0.0, 0.52]:
		var d := Vector2(cos(ang), sin(ang))
		var endp: Vector2 = origin + d * r * 1.7
		draw_line(origin, endp, col, 2.0, true)
		draw_colored_polygon(_arrow_head(origin, endp, 5.0), col)

func _icon_explosive(c: Vector2, r: float, col: Color) -> void:
	# 폭발 — 8 스파이크 + 중심 코어
	for i in 8:
		var ang: float = float(i) / 8.0 * TAU
		var d := Vector2(cos(ang), sin(ang))
		var rr: float = r * (1.0 if i % 2 == 0 else 0.62)
		draw_line(c + d * r * 0.28, c + d * rr, col, 2.0, true)
	draw_circle(c, r * 0.24, col)

# ── 이동 ──────────────────────────────────────────
func _icon_glide(c: Vector2, r: float, col: Color) -> void:
	# 완만한 활강 곡선 + 우하향 화살표 — "공중 활강"
	var pts := PackedVector2Array()
	for i in 9:
		var f: float = float(i) / 8.0
		var x: float = lerpf(-r, r, f)
		var y: float = -r * 0.55 + r * 0.9 * f * f
		pts.append(c + Vector2(x, y))
	draw_polyline(pts, col, 2.0, true)
	var endp: Vector2 = c + Vector2(r, -r * 0.55 + r * 0.9)
	draw_colored_polygon(_arrow_head(pts[7], endp, 5.0), col)

func _icon_dash(c: Vector2, r: float, col: Color) -> void:
	# 이중 쉐브론 + 좌측 모션 라인 — "대시"
	for k in 2:
		var ox: float = -r * 0.15 + float(k) * r * 0.55
		draw_polyline(PackedVector2Array([
			c + Vector2(ox - r * 0.3, -r * 0.6), c + Vector2(ox + r * 0.4, 0.0), c + Vector2(ox - r * 0.3, r * 0.6)]),
			col, 2.5, true)
	for i in 3:
		var yy: float = -r * 0.42 + float(i) * r * 0.42
		draw_line(c + Vector2(-r * 0.95, yy), c + Vector2(-r * 0.55, yy), col * Color(1, 1, 1, 0.5), 1.5, true)

func _icon_double_jump(c: Vector2, r: float, col: Color) -> void:
	# 두 개의 상향 쉐브론 — "이중점프"
	for k in 2:
		var oy: float = r * 0.42 - float(k) * r * 0.6
		draw_polyline(PackedVector2Array([
			c + Vector2(-r * 0.6, oy), c + Vector2(0.0, oy - r * 0.5), c + Vector2(r * 0.6, oy)]),
			col, 2.5, true)

# ── 생존 ──────────────────────────────────────────
func _icon_hp(c: Vector2, r: float, col: Color) -> void:
	# 하트 — "최대 체력"
	var pts := PackedVector2Array()
	for i in 28:
		var th: float = float(i) / 28.0 * TAU
		var x: float = 16.0 * pow(sin(th), 3.0)
		var y: float = 13.0 * cos(th) - 5.0 * cos(2.0 * th) - 2.0 * cos(3.0 * th) - cos(4.0 * th)
		pts.append(c + Vector2(x, -y) * (r / 17.0))
	draw_colored_polygon(pts, col)

func _icon_shield(c: Vector2, r: float, col: Color) -> void:
	# 방패 형태 — "비상 부활"(shield 라인, 생존)
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.8, -r * 0.7), c + Vector2(r * 0.8, -r * 0.7),
		c + Vector2(r * 0.8, r * 0.2), c + Vector2(0.0, r * 1.0), c + Vector2(-r * 0.8, r * 0.2)])
	draw_polyline(_closed(pts), col, 2.0, true)
	draw_line(c + Vector2(0.0, -r * 0.4), c + Vector2(0.0, r * 0.55), col * Color(1, 1, 1, 0.55), 1.5, true)

func _icon_barrier(c: Vector2, r: float, col: Color) -> void:
	# 육각 에너지막 — "에너지 방어막"
	draw_polyline(_closed(_hexagon(c, r)), col, 2.0, true)
	draw_polyline(_closed(_hexagon(c, r * 0.5)), col * Color(1, 1, 1, 0.5), 1.5, true)

func _icon_generic(c: Vector2, r: float, col: Color) -> void:
	draw_arc(c, r * 0.8, 0.0, TAU, 24, col, 2.0, true)
	draw_circle(c, r * 0.2, col)

# ── 헬퍼 ──────────────────────────────────────────
func _arrow_head(from_p: Vector2, to_p: Vector2, sz: float) -> PackedVector2Array:
	var dir: Vector2 = (to_p - from_p).normalized()
	var perp := Vector2(-dir.y, dir.x)
	return PackedVector2Array([to_p, to_p - dir * sz * 1.6 + perp * sz, to_p - dir * sz * 1.6 - perp * sz])

func _hexagon(c: Vector2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang: float = float(i) / 6.0 * TAU - PI / 2.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	return pts

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if pts.size() > 0:
		out.append(pts[0])
	return out
