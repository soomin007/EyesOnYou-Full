class_name DefenseCore
extends Node2D

# 아레나 방어 기믹 · 지켜야 할 코어(반응로/데이터 코어). 코어를 둘러싼 침입 구역(dome) 안에 적이
# 머물면 코어 HP가 깎이고, 0이 되면 방어 실패(스테이지 실패)다.
#
# 핵심: 적 AI를 건드리지 않는다. 잡몹은 원래 "플레이어를 쫓는" AI 그대로다. 플레이어가 코어 곁(아레나
# 중앙)에 서면 적이 자연히 dome 안으로 몰려든다 → 플레이어는 자리를 비우지 못하고 양 측면을 막아야 한다.
# 이것이 "자리를 지키는" 손맛 = datacenter처럼 자유롭게 사냥하는 kill-all ARENA와 정반대의 정체성이다.
#
# 침입 판정(2026-08-12 재설계 · 사용자: "반경에 들어오기만 해도 깎이는 것보다 애들이 코어를
# 공격하는 게 낫다"): dome(수평 반경 + 지면 밴드) 안의 "enemy"는 각자 와인드업 게이지를 채우고,
# hit_interval마다 코어를 **직접 타격**한다(1피해 + 스파크 + 타격음 + 코어 흔들림). 진입 즉시는
# 무피해 · 와인드업 예고(적 머리 위 게이지)를 보고 요격할 시간이 있고, 밀어내면(kite/이탈)
# 와인드업이 리셋돼 "쫓아내기"가 유효한 수비가 된다. 인과가 보이는 이산 타격 = 오라 드레인 대체.
# 높은 발판의 저격/드론은 지면 밴드 밖이라 코어를 못 때리고 "플레이어만 견제" → 근접 = 코어 위협,
# 원거리 = 플레이어 압박으로 역할이 갈린다.
#
# 클리어는 웨이브 전멸(ENEMY_CLEAR)이 담당하고, 이 코어는 "실패 조건"만 얹는다.
#
# 사용: MapData 맵의 "defense_core" = {pos(지면 접점=하단 중앙), hp?, radius?, interval?}.

signal breached                        # 코어 HP 0 · 방어 실패
signal engaged_changed(active: bool)   # dome 안에 적이 생김/사라짐 (Stage 경보 연출용)

const COL_SAFE: Color = Color(0.40, 0.85, 0.95)    # 시안 · 정상
const COL_ALERT: Color = Color(0.98, 0.35, 0.30)   # 적색 · 침입 중
const BAND_UP: float = 150.0           # dome 지면 밴드: 코어 원점(지면) 위로 이만큼까지가 "지면 적"
const BAND_DOWN: float = 50.0          # 원점 아래 여유(적 콜리전 중심 편차)

var max_hp: float = 14.0
var _hp: float = 14.0
var breach_radius: float = 360.0       # dome 수평 반경
var hit_interval: float = 1.5          # 적 1기의 타격 주기(진입 후 첫 타격까지 = 와인드업)

var _dead: bool = false                # 함락 또는 확보(secured) · 더는 처리 안 함
var _engaged: bool = false             # 현재 dome 안에 적이 있는가
var _pulse_t: float = 0.0
var _tag: Label = null
var _windup: Dictionary = {}           # enemy instance_id → 와인드업 누적(밴드 안에서만 증가)
var _attackers: Array = []             # [{rel: Vector2, prog: float}] · 예고 게이지 렌더용
var _hits: Array = []                  # [{side: float, t: float}] · 타격 스파크(짧게 페이드)
var _shake_t: float = 0.0              # 피격 흔들림 잔여 시간

func setup(hp: float, radius: float, interval: float) -> void:
	max_hp = maxf(hp, 3.0)
	_hp = max_hp
	breach_radius = maxf(radius, 80.0)
	hit_interval = maxf(interval, 0.5)
	z_index = -1   # 배우(플레이어/적, z=0) 뒤 · 적이 코어 앞에 겹쳐 보이게. 배경(-12..-20)보다는 앞.
	_build_tag()

func _build_tag() -> void:
	# 코어 상단 라벨 · 프로젝트 기본 테마 폰트(한글 지원) 상속.
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

# ─── 침입 판정 + 타격 ──────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _dead or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var count: int = 0
	var seen: Dictionary = {}
	_attackers.clear()
	for e in tree.get_nodes_in_group("enemy"):
		if e == null or not (e is Node2D):
			continue
		if e.get("harmless"):   # 속성 없으면 null(=falsy) → bool(null) 크래시 회피(null-safe truthiness)
			continue   # 스폰 직후 무해 상태 등 · 위협 없으면 타격도 없음
		var ep: Vector2 = (e as Node2D).global_position
		var dx: float = absf(ep.x - global_position.x)
		var dy: float = ep.y - global_position.y   # 코어 원점=지면. 지면 적은 dy≈-20..-40, 높은 발판 적은 큰 음수
		if dx <= breach_radius and dy >= -BAND_UP and dy <= BAND_DOWN:
			count += 1
			var eid: int = (e as Node).get_instance_id()
			var acc: float = float(_windup.get(eid, 0.0)) + delta
			if acc >= hit_interval:
				acc -= hit_interval
				_strike(ep)
			seen[eid] = true
			_windup[eid] = acc
			_attackers.append({"rel": ep - global_position, "prog": acc / hit_interval})
	# 이탈/사망한 적의 와인드업 리셋 · 밀어내면 처음부터. keys()는 복사본이라 순회 중 erase 안전.
	for k in _windup.keys():
		if not seen.has(k):
			_windup.erase(k)
	var now_engaged: bool = count > 0
	if now_engaged != _engaged:
		_engaged = now_engaged
		engaged_changed.emit(_engaged)
	# 타격 이펙트 페이드/흔들림 감쇠.
	_shake_t = maxf(0.0, _shake_t - delta)
	var i: int = _hits.size() - 1
	while i >= 0:
		var h: Dictionary = _hits[i]
		h["t"] = float(h.get("t", 0.0)) + delta
		if float(h["t"]) > 0.35:
			_hits.remove_at(i)
		i -= 1
	_pulse_t += delta
	_update_tag_color()
	queue_redraw()

# 한 대 · 인과가 보이는 이산 피해(스파크 + 타격음 + 흔들림). breach는 여기서만 발생.
func _strike(attacker_pos: Vector2) -> void:
	if _dead:
		return
	_hp -= 1.0
	_shake_t = 0.22
	_hits.append({"side": signf(attacker_pos.x - global_position.x), "t": 0.0})
	SfxPlayer.play_at("bullet_impact_wall", global_position, 3.0)
	if _hp <= 0.0:
		_hp = 0.0
		_dead = true
		breached.emit()

func _update_tag_color() -> void:
	if _tag == null:
		return
	_tag.add_theme_color_override("font_color", COL_ALERT if _engaged else COL_SAFE)

# 클리어(웨이브 전멸) 시 Stage가 호출 · 드레인 정지 + 확보 상태로 굳힘.
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
	_draw_windups()
	_draw_hit_sparks()

# 와인드업 예고 · 밴드 안 적 머리 위에 차오르는 게이지 아크(가득 = 타격). 요격 우선순위가 보인다.
func _draw_windups() -> void:
	for a_raw in _attackers:
		var a: Dictionary = a_raw
		var rel: Vector2 = a.get("rel", Vector2.ZERO)
		var prog: float = clampf(float(a.get("prog", 0.0)), 0.0, 1.0)
		if prog <= 0.02:
			continue
		var p: Vector2 = rel + Vector2(0.0, -74.0)
		var warn := Color(0.98, 0.45, 0.28, 0.5 + 0.4 * prog)
		draw_arc(p, 11.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 20, warn, 3.0, true)
		if prog > 0.8:
			draw_circle(p, 3.5, warn)

# 타격 스파크 · 코어 기둥의 맞은 면에서 튀는 파편 선(0.35s 페이드). 광과민성 기준 준수(점멸 아님).
func _draw_hit_sparks() -> void:
	for h_raw in _hits:
		var h: Dictionary = h_raw
		var t: float = float(h.get("t", 0.0))
		var k: float = clampf(t / 0.35, 0.0, 1.0)
		var side: float = float(h.get("side", 1.0))
		if side == 0.0:
			side = 1.0
		var origin := Vector2(34.0 * side, -62.0)
		var a: float = (1.0 - k) * 0.9
		var col := Color(1.0, 0.72, 0.35, a)
		for j in 4:
			var ang: float = -PI * 0.5 + (float(j) - 1.5) * 0.5 + side * 0.4
			var dir := Vector2(cos(ang), sin(ang))
			var r0: float = 6.0 + 20.0 * k
			draw_line(origin + dir * r0, origin + dir * (r0 + 9.0), col, 2.0)
		draw_circle(origin, 5.0 * (1.0 - k) + 1.0, Color(1.0, 0.85, 0.55, a))

func _draw_dome(col: Color) -> void:
	# 침입 구역 · 지면에 얹힌 반원형(반타원) 반투명 필드 + 경계 아크. 침입 중엔 붉게 빠르게 맥동.
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
	# 지면 위험 셰브런 · dome 안쪽 양옆에 방향 표시(여기를 비워라)
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
	# 피격 흔들림 · 밝기 점멸이 아니라 위치 미세 진동(광과민성 기준). _draw 끝에서 transform 복원.
	var off := Vector2(sin(_pulse_t * 70.0) * 4.0 * (_shake_t / 0.22), 0.0)
	draw_set_transform(off, 0.0, Vector2.ONE)
	# 받침대
	draw_rect(Rect2(Vector2(-48.0, -34.0), Vector2(96.0, 34.0)), Color(0.16, 0.18, 0.22))
	draw_rect(Rect2(Vector2(-48.0, -34.0), Vector2(96.0, 34.0)), Color(0.05, 0.05, 0.07), false, 2.0)
	# 기둥
	draw_rect(Rect2(Vector2(-30.0, -134.0), Vector2(60.0, 102.0)), Color(0.13, 0.15, 0.19))
	draw_rect(Rect2(Vector2(-30.0, -134.0), Vector2(60.0, 102.0)), Color(0.05, 0.05, 0.07), false, 2.0)
	# 기둥 발광 슬릿(코어 색)
	draw_rect(Rect2(Vector2(-4.0, -128.0), Vector2(8.0, 40.0)), Color(col.r, col.g, col.b, 0.5))
	# 코어 오브 · 발광(HP 낮을수록 어두워짐)
	var glow: float = 0.5 + 0.5 * sin(_pulse_t * 4.0)
	var life: float = lerp(0.35, 1.0, _hp_ratio())
	var oc: Color = col
	draw_circle(Vector2(0.0, -88.0), 27.0, Color(oc.r, oc.g, oc.b, 0.18 * life))
	draw_circle(Vector2(0.0, -88.0), 16.0, Color(oc.r, oc.g, oc.b, lerp(0.45, 0.92, glow) * life))
	draw_circle(Vector2(0.0, -88.0), 8.0, Color(1.0, 1.0, 1.0, lerp(0.55, 0.92, glow) * life))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_hp_bar() -> void:
	var ratio: float = _hp_ratio()
	var bw: float = 150.0
	var bh: float = 12.0
	var bx: float = -bw * 0.5
	var by: float = -158.0
	# 테두리/배경
	draw_rect(Rect2(Vector2(bx - 2.0, by - 2.0), Vector2(bw + 4.0, bh + 4.0)), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(Vector2(bx, by), Vector2(bw, bh)), Color(0.10, 0.10, 0.12))
	# 채움 · 초록→노랑→빨강
	var fill_c: Color
	if ratio > 0.5:
		fill_c = Color(0.40, 0.85, 0.55)
	elif ratio > 0.25:
		fill_c = Color(0.95, 0.80, 0.30)
	else:
		fill_c = Color(0.95, 0.35, 0.30)
	draw_rect(Rect2(Vector2(bx, by), Vector2(bw * ratio, bh)), fill_c)
	# 칸 구분선 · 이산 타격이라 1피해 = 1칸으로 읽히게(HP가 크면 10칸 폴백).
	var segs: int = int(round(max_hp)) if max_hp <= 24.0 else 10
	for i in range(1, segs):
		var sx: float = bx + bw * float(i) / float(segs)
		draw_line(Vector2(sx, by), Vector2(sx, by + bh), Color(0.0, 0.0, 0.0, 0.4), 1.0)
