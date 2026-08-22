class_name DischargeJet
extends Node2D

# 배수 펌프장 시그니처 해저드 · 방류 사이클(2026-08-22 사용자 "펌프장 컨셉을 모르겠다" 3회째).
# 지면의 방류구(배관 입구)가 주기적으로 수평 물줄기를 뿜는다. "물을 퍼내는 시설"이 배경이
# 아니라 플레이가 된다. 사이클: 대기 → 예고(입구가 덜컹거리며 물이 샌다) → 방류(수평 물줄기,
# 지상 피해) → 대기. SteamVent(수직 상승)·CondensateDrip(수직 낙하)과 축이 다른 수평 문법 —
# 회피 = 물길 밖으로 비키거나 발판 위로 오른다(펌프장의 상부 거치대가 회피처가 되는 이유).
# 시설 유닛은 방수 설계라 무피해(환경 내성 캐논 · ElectricArc 절연과 동일 결). 파괴 불가.
# 광과민: 점멸 없음 · 예고는 램프로 진해진다.
#
# 사용: MapData "discharge_jets" = [{x, dir(1|-1), len, phase?, dmg?}]. Stage가 ground_y 전달.

enum S { IDLE, TELE, JET }

const IDLE_DUR: float = 2.6
const TELE_DUR: float = 0.9
const JET_DUR: float = 1.3
const PERIOD: float = IDLE_DUR + TELE_DUR + JET_DUR

const MOUTH_Y: float = 46.0        # 물줄기 축(지면 위 높이) — 지상에 서 있으면 맞는 허리 높이
const BAND_H: float = 96.0         # 지상 판정 높이(이 위 발판은 안전)
const COL: Color = Color(0.62, 0.92, 1.0)   # 물(응축수 낙수와 동일 계열)
const WARN: Color = Color(1.0, 0.55, 0.2)   # 예고 경고색(증기 노즐과 동형)

var jet_dir: int = 1               # 1=오른쪽으로 뿜음, -1=왼쪽
var length: float = 480.0
var damage: int = 1

var _state: int = S.IDLE
var _t: float = 0.0
var _hit_this_jet: bool = false

func setup(cfg: Dictionary, g_y: float) -> void:
	position = Vector2(float(cfg.get("x", 0.0)), g_y)
	jet_dir = 1 if int(cfg.get("dir", 1)) >= 0 else -1
	length = maxf(float(cfg.get("len", 480.0)), 120.0)
	damage = int(cfg.get("dmg", 1))
	z_index = 1
	add_to_group("discharge_jet")
	_t = fmod(float(cfg.get("phase", 0.0)), 1.0) * PERIOD
	# 위상 오프셋으로 임의 상태에서 시작해도 사이클 정합 유지.
	if _t >= IDLE_DUR + TELE_DUR:
		_state = S.JET
		_t -= IDLE_DUR + TELE_DUR
	elif _t >= IDLE_DUR:
		_state = S.TELE
		_t -= IDLE_DUR

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t += delta
	match _state:
		S.IDLE:
			if _t >= IDLE_DUR:
				_state = S.TELE
				_t = 0.0
		S.TELE:
			if _t >= TELE_DUR:
				_state = S.JET
				_t = 0.0
				_hit_this_jet = false
				SfxPlayer.play_at("hatch_open", global_position, -8.0)
		S.JET:
			_check_hit()
			if _t >= JET_DUR:
				_state = S.IDLE
				_t = 0.0
	queue_redraw()

func _check_hit() -> void:
	if _hit_this_jet:
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D) or bool(p.get("clear_protect")):
		return
	var rel: Vector2 = (p as Node2D).global_position - global_position
	var along: float = rel.x * float(jet_dir)
	# 물줄기 구간 안 + 지상 높이(발판 위는 안전)만 — 화면=판정 일치.
	if along >= -10.0 and along <= length and rel.y > -BAND_H and rel.y <= 8.0:
		if p.has_method("take_hit"):
			p.call("take_hit", damage)
			_hit_this_jet = true
			SfxPlayer.play_at("spike_hit", (p as Node2D).global_position)

# ─── 렌더 ──────────────────────────────────────────────────────
func _draw() -> void:
	_draw_outlet()
	if _state == S.TELE:
		_draw_telegraph()
	elif _state == S.JET:
		_draw_jet()

# 방류구 하우징(상시) — 콘크리트 기단 + 수직 급수관 + 입구 플랜지. 위치가 항상 보인다.
func _draw_outlet() -> void:
	var d: float = float(jet_dir)
	# 예고~방류 동안 경고 줄무늬가 달아오른다(램프).
	var hot: float = 0.0
	if _state == S.TELE:
		hot = 0.4 + 0.6 * (_t / TELE_DUR)
	elif _state == S.JET:
		hot = 1.0
	# 기단(콘크리트).
	draw_rect(Rect2(Vector2(-26.0, -14.0), Vector2(52.0, 14.0)), Color(0.20, 0.22, 0.24))
	# 수직 급수관(배경 대구경 파이프에서 내려온 결).
	draw_rect(Rect2(Vector2(-11.0, -84.0), Vector2(22.0, 70.0)), Color(0.16, 0.21, 0.24))
	draw_rect(Rect2(Vector2(-11.0, -84.0), Vector2(5.0, 70.0)), Color(0.24, 0.30, 0.33))
	# 입구 엘보 + 플랜지(방류 방향).
	draw_rect(Rect2(Vector2(minf(0.0, d * 24.0), -MOUTH_Y - 14.0), Vector2(24.0, 28.0)), Color(0.19, 0.25, 0.28))
	draw_rect(Rect2(Vector2(minf(d * 24.0, d * 30.0), -MOUTH_Y - 17.0), Vector2(6.0, 34.0)), Color(0.28, 0.35, 0.38))
	# 경고 줄무늬 칼라(플랜지 둘레) — 항상 보이되 임박 시 밝게.
	var stripe_a: float = 0.35 + 0.55 * hot
	for i in 3:
		var yy: float = -MOUTH_Y - 12.0 + float(i) * 10.0
		draw_rect(Rect2(Vector2(minf(d * 24.0, d * 30.0) + 1.0, yy),
			Vector2(4.0, 6.0)), Color(WARN.r, WARN.g, WARN.b, stripe_a))

func _draw_telegraph() -> void:
	var d: float = float(jet_dir)
	var k: float = _t / TELE_DUR
	var mouth := Vector2(d * 30.0, -MOUTH_Y)
	# 덜컹거림 — 플랜지 앞에서 물이 새며 방울이 흘러내린다(점멸 없음 · 새는 양이 램프로 는다).
	var jitter: float = sin(_t * 34.0) * 1.5 * k
	for i in 3:
		var drip_y: float = -MOUTH_Y + 8.0 + float(i) * 12.0 * k
		draw_circle(Vector2(d * (32.0 + jitter), drip_y), 2.0 + 1.2 * k, Color(COL.r, COL.g, COL.b, 0.55))
	# 물길 예고 — 뿜을 구간이 바닥선으로 칠해진다(어디까지 오는지 미리 보인다 · 램프로 진해짐).
	draw_rect(Rect2(Vector2(minf(mouth.x, mouth.x + d * length), -7.0), Vector2(length, 5.0)),
		Color(WARN.r, WARN.g, WARN.b, 0.22 + 0.38 * k))

func _draw_jet() -> void:
	var d: float = float(jet_dir)
	var bt: float = _t / JET_DUR
	var power: float = sin(bt * PI)            # 0→1→0 세기 엔벨로프(완만)
	var mouth := Vector2(d * 30.0, -MOUTH_Y)
	var reach: float = length * minf(1.0, bt * 6.0)   # 첫 0.2s에 물줄기가 뻗어나간다
	# 연속 물줄기 — 겉(넓고 옅음)/중간/심(밝음) 3겹의 이어진 띠. 끝으로 갈수록 살짝 처진다.
	for layer in [[34.0, 0.30], [18.0, 0.55], [9.0, 0.85]]:
		var l: Array = layer
		var h: float = float(l[0]) * (0.7 + 0.3 * power)
		var a: float = float(l[1]) * (0.5 + 0.5 * power)
		var seg: int = maxi(int(reach / 60.0), 1)
		var pts := PackedVector2Array()
		for i in seg + 1:
			var f: float = float(i) / float(seg)
			pts.append(Vector2(mouth.x + d * reach * f,
				mouth.y + 7.0 * f * f + sin(_t * 16.0 - f * 5.0) * 1.6 * f))
		draw_polyline(pts, Color(COL.r, COL.g, COL.b, a), h, true)
	# 흐름 하이라이트 — 물살을 따라 밝은 조각이 흘러간다(수류 방향 가시).
	var flow: float = fmod(_t * 620.0, 84.0)
	var cx: float = flow
	while cx < reach - 8.0:
		var f2: float = cx / maxf(reach, 1.0)
		draw_rect(Rect2(Vector2(mouth.x + d * cx - (0.0 if d > 0 else 26.0), mouth.y - 2.5 + 7.0 * f2 * f2),
			Vector2(26.0, 5.0)), Color(0.92, 1.0, 1.0, 0.65 * power * (1.0 - 0.4 * f2)))
		cx += 84.0
	# 착수 지점 — 물줄기 끝의 튐(어디까지 위험한지 화면으로 보인다).
	var endp := Vector2(mouth.x + d * reach, mouth.y + 8.0)
	for i in 4:
		var sx: float = endp.x + d * float(i) * 7.0
		var sy: float = endp.y + 10.0 - float(i) * 9.0 * power
		draw_circle(Vector2(sx, sy), 2.6 * power + 0.8, Color(COL.r, COL.g, COL.b, 0.55 * power))
	draw_circle(endp, 6.0 * power + 2.0, Color(0.85, 0.95, 1.0, 0.35 * power))
	# 바닥 물보라 — 물줄기 아래 지면을 따라 얇은 미스트.
	draw_rect(Rect2(Vector2(minf(mouth.x, mouth.x + d * reach), -8.0), Vector2(reach, 6.0)),
		Color(COL.r, COL.g, COL.b, 0.20 * power))
