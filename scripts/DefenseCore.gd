class_name DefenseCore
extends Node2D

# 아레나 방어 기믹 — 지켜야 할 코어(반응로/데이터 코어). 코어를 둘러싼 침입 구역(dome) 안에 적이
# 머물면 코어 HP가 깎이고, 0이 되면 방어 실패(스테이지 실패)다.
#
# 핵심: 적 AI를 건드리지 않는다. 잡몹은 원래 "플레이어를 쫓는" AI 그대로다. 플레이어가 코어 곁(아레나
# 중앙)에 서면 적이 자연히 dome 안으로 몰려든다 → 플레이어는 자리를 비우지 못하고 양 측면을 막아야 한다.
# 이것이 "자리를 지키는" 손맛 = datacenter처럼 자유롭게 사냥하는 kill-all ARENA와 정반대의 정체성이다.
#
# 침입 판정: dome(수평 반경 + 지면 밴드) 안의 "enemy" 그룹 적 수를 세어, 수 × drain_per_sec × delta
# 만큼 HP 감소. 넘어오는 적을 밀어내거나(kite) 빨리 처치해 dome를 비워야 한다. 높은 발판의 저격/드론은
# 지면 밴드 밖이라 코어를 깎지 못하고 "플레이어만 견제" → 근접(patrol/bomber/shield) = 코어 위협,
# 원거리 = 플레이어 압박으로 역할이 갈린다.
#
# 클리어는 웨이브 전멸(ENEMY_CLEAR)이 담당하고, 이 코어는 "실패 조건"만 얹는다.
#
# 사용: MapData 맵의 "defense_core" = {pos(지면 접점=하단 중앙), hp?, radius?, drain?}.

signal breached                        # 코어 HP 0 — 방어 실패
signal engaged_changed(active: bool)   # dome 안에 적이 생김/사라짐 (Stage 경보 연출용)

const COL_SAFE: Color = Color(0.40, 0.85, 0.95)    # 시안 — 정상
const COL_ALERT: Color = Color(0.98, 0.35, 0.30)   # 적색 — 침입 중
const BAND_UP: float = 150.0           # dome 지면 밴드: 코어 원점(지면) 위로 이만큼까지가 "지면 적"
const BAND_DOWN: float = 50.0          # 원점 아래 여유(적 콜리전 중심 편차)

var max_hp: float = 120.0
var _hp: float = 120.0
var breach_radius: float = 360.0       # dome 수평 반경
var drain_per_sec: float = 6.0         # 적 1기당 초당 감소량

var _dead: bool = false                # 함락 또는 확보(secured) — 더는 처리 안 함
var _engaged: bool = false             # 현재 dome 안에 적이 있는가
var _pulse_t: float = 0.0
var _tag: Label = null

func setup(hp: float, radius: float, drain: float) -> void:
	max_hp = maxf(hp, 10.0)
	_hp = max_hp
	breach_radius = maxf(radius, 80.0)
	drain_per_sec = maxf(drain, 0.5)
	z_index = -1   # 배우(플레이어/적, z=0) 뒤 — 적이 코어 앞에 겹쳐 보이게. 배경(-12..-20)보다는 앞.
	_build_tag()

func _build_tag() -> void:
	# 코어 상단 라벨 — 프로젝트 기본 테마 폰트(한글 지원) 상속.
	_tag = Label.new()
	_tag.text = "코어"
	_tag.add_theme_font_size_override("font_size", 18)
	_tag.add_theme_color_override("font_color", COL_SAFE)
	_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_tag.add_theme_constant_override("outline_size", 4)
	_tag.position = Vector2(-24.0, -178.0)
	add_child(_tag)

func _hp_ratio() -> float:
	return clampf(_hp / max_hp, 0.0, 1.0)

# ─── 침입 판정 + 드레인 ────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _dead or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var count: int = 0
	for e in tree.get_nodes_in_group("enemy"):
		if e == null or not (e is Node2D):
			continue
		if e.get("harmless"):   # 속성 없으면 null(=falsy) → bool(null) 크래시 회피(null-safe truthiness)
			continue   # 스폰 직후 무해 상태 등 — 위협 없으면 코어도 안 깎음
		var ep: Vector2 = (e as Node2D).global_position
		var dx: float = absf(ep.x - global_position.x)
		var dy: float = ep.y - global_position.y   # 코어 원점=지면. 지면 적은 dy≈-20..-40, 높은 발판 적은 큰 음수
		if dx <= breach_radius and dy >= -BAND_UP and dy <= BAND_DOWN:
			count += 1
	var now_engaged: bool = count > 0
	if now_engaged != _engaged:
		_engaged = now_engaged
		engaged_changed.emit(_engaged)
	if count > 0:
		_hp -= drain_per_sec * float(count) * delta
		if _hp <= 0.0:
			_hp = 0.0
			_dead = true
			breached.emit()
	_pulse_t += delta
	_update_tag_color()
	queue_redraw()

func _update_tag_color() -> void:
	if _tag == null:
		return
	_tag.add_theme_color_override("font_color", COL_ALERT if _engaged else COL_SAFE)

# 클리어(웨이브 전멸) 시 Stage가 호출 — 드레인 정지 + 확보 상태로 굳힘.
func set_secured() -> void:
	_dead = true
	_engaged = false
	if _tag != null:
		_tag.add_theme_color_override("font_color", COL_SAFE)
	queue_redraw()

# ─── 렌더 ──────────────────────────────────────────────────────
func _draw() -> void:
	var col: Color = COL_ALERT if _engaged else COL_SAFE
	_draw_dome(col)
	_draw_core_body(col)
	_draw_hp_bar()

func _draw_dome(col: Color) -> void:
	# 침입 구역 — 지면에 얹힌 반원형(반타원) 반투명 필드 + 경계 아크. 침입 중엔 붉게 빠르게 맥동.
	var rx: float = breach_radius
	var ry: float = breach_radius * 0.52
	var speed: float = 6.0 if _engaged else 2.2
	var pulse: float = 0.5 + 0.5 * sin(_pulse_t * speed)
	var fill_a: float = (lerp(0.07, 0.17, pulse)) if _engaged else (lerp(0.045, 0.085, pulse))
	var seg: int = 26
	var fill := PackedVector2Array()
	for i in seg + 1:
		var a: float = PI * float(i) / float(seg)   # 0..PI (윗 반원)
		fill.append(Vector2(-cos(a) * rx, -sin(a) * ry))
	fill.append(Vector2(rx, 0.0))
	fill.append(Vector2(-rx, 0.0))
	draw_colored_polygon(fill, Color(col.r, col.g, col.b, fill_a))
	# 경계 아크
	var arc := PackedVector2Array()
	for i in seg + 1:
		var a2: float = PI * float(i) / float(seg)
		arc.append(Vector2(-cos(a2) * rx, -sin(a2) * ry))
	draw_polyline(arc, Color(col.r, col.g, col.b, 0.5), 2.0, true)
	# 지면 경계 라인(양 끝 표시)
	draw_line(Vector2(-rx, 3.0), Vector2(rx, 3.0), Color(col.r, col.g, col.b, 0.35), 2.0)
	# 지면 위험 셰브런 — dome 안쪽 양옆에 방향 표시(여기를 비워라)
	_draw_chevrons(col)

func _draw_chevrons(col: Color) -> void:
	var cc := Color(col.r, col.g, col.b, 0.22)
	var rx: float = breach_radius
	for side in [-1.0, 1.0]:
		var base_x: float = side * (rx * 0.78)
		for k in 3:
			var ox: float = base_x - side * float(k) * 22.0
			var pts := PackedVector2Array([
				Vector2(ox, -6.0), Vector2(ox + side * 12.0, -18.0), Vector2(ox, -30.0)])
			draw_polyline(pts, cc, 3.0, true)

func _draw_core_body(col: Color) -> void:
	# 받침대
	draw_rect(Rect2(Vector2(-48.0, -34.0), Vector2(96.0, 34.0)), Color(0.16, 0.18, 0.22))
	draw_rect(Rect2(Vector2(-48.0, -34.0), Vector2(96.0, 34.0)), Color(0.05, 0.05, 0.07), false, 2.0)
	# 기둥
	draw_rect(Rect2(Vector2(-30.0, -134.0), Vector2(60.0, 102.0)), Color(0.13, 0.15, 0.19))
	draw_rect(Rect2(Vector2(-30.0, -134.0), Vector2(60.0, 102.0)), Color(0.05, 0.05, 0.07), false, 2.0)
	# 기둥 발광 슬릿(코어 색)
	draw_rect(Rect2(Vector2(-4.0, -128.0), Vector2(8.0, 40.0)), Color(col.r, col.g, col.b, 0.5))
	# 코어 오브 — 발광(HP 낮을수록 어두워짐)
	var glow: float = 0.5 + 0.5 * sin(_pulse_t * 4.0)
	var life: float = lerp(0.35, 1.0, _hp_ratio())
	var oc: Color = col
	draw_circle(Vector2(0.0, -88.0), 27.0, Color(oc.r, oc.g, oc.b, 0.18 * life))
	draw_circle(Vector2(0.0, -88.0), 16.0, Color(oc.r, oc.g, oc.b, lerp(0.45, 0.92, glow) * life))
	draw_circle(Vector2(0.0, -88.0), 8.0, Color(1.0, 1.0, 1.0, lerp(0.55, 0.92, glow) * life))

func _draw_hp_bar() -> void:
	var ratio: float = _hp_ratio()
	var bw: float = 150.0
	var bh: float = 12.0
	var bx: float = -bw * 0.5
	var by: float = -158.0
	# 테두리/배경
	draw_rect(Rect2(Vector2(bx - 2.0, by - 2.0), Vector2(bw + 4.0, bh + 4.0)), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(Vector2(bx, by), Vector2(bw, bh)), Color(0.10, 0.10, 0.12))
	# 채움 — 초록→노랑→빨강
	var fill_c: Color
	if ratio > 0.5:
		fill_c = Color(0.40, 0.85, 0.55)
	elif ratio > 0.25:
		fill_c = Color(0.95, 0.80, 0.30)
	else:
		fill_c = Color(0.95, 0.35, 0.30)
	draw_rect(Rect2(Vector2(bx, by), Vector2(bw * ratio, bh)), fill_c)
	# 10칸 구분선
	for i in range(1, 10):
		var sx: float = bx + bw * float(i) / 10.0
		draw_line(Vector2(sx, by), Vector2(sx, by + bh), Color(0.0, 0.0, 0.0, 0.4), 1.0)
