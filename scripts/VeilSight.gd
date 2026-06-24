class_name VeilSight
extends Control

# ─── VEIL 시야 마킹 (시야=신뢰 파일럿, v3 §2) ───────────────────────
# "VEIL이 요원 대신 본다"를 *플레이로 실연*한다. 핵심은 레이더가 아니라
# "누군가 너를 위해 짚어준다"로 읽히게 하는 것:
#   - 마커는 등장 시 페이드인(+수축) → "방금 VEIL이 짚었다"는 인상
#   - 새 화면 밖 위협은 VEIL이 *말로 방향을 짚는다*(veil_calls_threat) → 시스템 표시가 아닌 누군가의 봄
#   - ACT3 진입(begin_degradation)에 마커가 일제히 흔들리고 일부는 영영 꺼진다 → 역전이 화면에서
# 화면 안 = 은은한 시안 다이아몬드(요원도 봄), 화면 밖 = 또렷한 가장자리 화살표(VEIL만 봄 ← 핵심 가치).
# 공격 임박(조준/돌진/폭탄)은 경고 주황으로 펄스.
#
# 확장 이력: 저격수·공중만 → 전 적 마킹 + 공격 경고 펄스. 그러나 "레이더로 읽힌다 / ACT3 역전을
# 모르겠다"는 피드백으로 (A) 작가성 입히기(페이드인·말걸기) + (B) degradation을 자막 트리거에
# 동기화해 같은 맵 안에서 안정→붕괴 대비를 만든다.

signal veil_calls_threat(text: String)

var player: Node2D = null

const DETECT_RADIUS: float = 1400.0           # 이 안의 위협을 VEIL이 본다 (≈ 화면 한 칸)
const CALM: Color = Color(0.42, 0.86, 1.0)    # 평시 — VEIL 시안 (자막 색과 통일감)
const WARN: Color = Color(1.0, 0.55, 0.22)    # 공격 임박 — 경고 주황
const EDGE_MARGIN: float = 48.0               # 화면 밖 화살표가 가장자리에서 떨어지는 여백
const RETICLE_R: float = 17.0
const FADE_IN: float = 0.35                    # 마커가 "짚어지는" 등장 시간
const CALL_COOLDOWN: float = 18.0             # VEIL이 말로 짚는 최소 간격 (노이즈 방지)
const MIN_CALL_TIME: float = 7.0             # 맵 진입 멘트 보호 — 이 전엔 말 안 함
const GLITCH_DUR: float = 1.2                # 역전 순간 일제 붕괴 연출 길이
const BLIND_PCT: int = 50                    # degradation 중 VEIL이 영영 못 보는 위협 비율(%) — 페널티 강화

# 화면 비네트 — 적 수가 적어 마커만으론 약하니 화면 전체로 "VEIL의 봄/안 봄"을 항상 체감시킨다.
# 기본: 테두리에 은은한 VEIL 시안(함께 본다). degradation: 어둡게 + 안쪽으로 좁아짐(시야 축소 = 페널티).
const VIG_RADIUS_FAR: float = 0.55            # 기본 — 반경 큼(얇은 가장자리 테두리)
const VIG_RADIUS_NEAR: float = 0.32           # degradation — 반경 작음(중앙만 보이는 시야 축소)
const VIG_CALM_A: float = 0.10                # 기본 시안 테두리 알파 (은은하게 — 너무 진하지 않게)
const VIG_DARK_A: float = 0.66                # degradation 검정 비네트 알파

var _t: float = 0.0
var _seen: Dictionary = {}                    # instance_id → 처음 본 _t (페이드인용)
var _degrade_t: float = -1.0                  # >=0 이면 ACT3 degradation 진행 중 (시작 시각)
var _intro_called: bool = false               # "표시해 둘게요" 메타 소개 1회
var _last_call_t: float = -999.0
var _vignette: ColorRect = null               # 비네트 표면 (셰이더가 색/반경/디더를 계산)
var _vig_mat: ShaderMaterial = null
var _vig: float = 0.0                          # 0=기본(시안 테두리) → 1=degradation(검정 축소)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# CanvasLayer의 자식이라 anchor가 부모(레이어) 크기를 못 받는다 → 뷰포트 크기로 직접 맞춘다.
	# (안 하면 self.size=0 → 비네트 TextureRect가 늘어나지 못하고 native 320×200으로 좌상단에만 그려짐.)
	# 해상도 변경/창 리사이즈에도 size_changed로 다시 맞춘다.
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_build_vignette()
	# 이전 맵에서 이미 시야가 붕괴했다면 이 맵도 처음부터 어두운 상태로(전환 애니 없이 즉시).
	if GameState.veil_degraded:
		_degrade_t = _t
		_vig = 1.0
		_update_vignette(0.0)

func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size

# 화면 비네트 — 셰이더로 픽셀 단위 계산(텍스처 업스케일 밴딩 없음 + 디더).
# 기본=시안 테두리(VEIL이 함께 본다), degradation=검정 + 반경 축소(시야 좁아짐). vig 유니폼이 전환.
func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = load("res://assets/shaders/veil_vignette.gdshader")
	_vig_mat.set_shader_parameter("calm_color", Color(CALM.r, CALM.g, CALM.b, VIG_CALM_A))
	_vig_mat.set_shader_parameter("dark_color", Color(0.0, 0.0, 0.02, VIG_DARK_A))
	_vig_mat.set_shader_parameter("radius_far", VIG_RADIUS_FAR)
	_vig_mat.set_shader_parameter("radius_near", VIG_RADIUS_NEAR)
	_vig_mat.set_shader_parameter("vig", 0.0)
	_vig_mat.set_shader_parameter("time", 0.0)
	_vignette.material = _vig_mat
	add_child(_vignette)

func _update_vignette(delta: float) -> void:
	if _vig_mat == null:
		return
	var target: float = 1.0 if _is_degraded() else 0.0
	_vig = move_toward(_vig, target, delta * 1.4)
	_vig_mat.set_shader_parameter("vig", _vig)
	_vig_mat.set_shader_parameter("time", _t)

# ACT3 자막("여기서부터는 잘 안 보여요")과 동기 호출 — 그 순간 마커가 무너진다.
func begin_degradation() -> void:
	if _degrade_t >= 0.0:
		return
	_degrade_t = _t
	# 한 번 붕괴하면 이후 맵에서도 어두운 상태로 시작(사용자 피드백: 다음 맵 가도 어두운 채로).
	GameState.veil_degraded = true

func _is_degraded() -> bool:
	return _degrade_t >= 0.0

func _process(delta: float) -> void:
	_t += delta
	_scan_for_call()
	_update_vignette(delta)
	queue_redraw()

# 화면 밖에 새로 나타난 위협을 VEIL이 말로 짚는다(레이더 아님의 핵심). 쿨다운/진입보호로 절제.
func _scan_for_call() -> void:
	if player == null or not is_instance_valid(player):
		return
	if _t < MIN_CALL_TIME or (_t - _last_call_t) < CALL_COOLDOWN:
		return
	var xform: Transform2D = get_viewport().get_canvas_transform()
	var view: Vector2 = get_viewport_rect().size
	var ppos: Vector2 = player.global_position
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node2D):
			continue
		var en: Node2D = e as Node2D
		if not is_instance_valid(en) or bool(en.get("dead")):
			continue
		var wpos: Vector2 = en.global_position
		if ppos.distance_to(wpos) > DETECT_RADIUS:
			continue
		var id: int = en.get_instance_id()
		if _seen.has(id):
			continue   # 이미 본 위협 — 새로 짚을 게 없음
		var spos: Vector2 = xform * wpos
		var off: bool = spos.x < 0.0 or spos.x > view.x or spos.y < 0.0 or spos.y > view.y
		if off:
			_call_threat(spos, view * 0.5)
			return   # 한 번에 하나만 — _seen 등록은 _draw가 한다

func _call_threat(spos: Vector2, center: Vector2) -> void:
	_last_call_t = _t
	var dir_txt: String = _direction_word(spos - center)
	# 어투를 신뢰 밴드로 맞춘다(단일 문자열이라 코드 분기). degraded는 항상 막판=WARM.
	var band: String = GameState.veil_register_band()
	var line: String
	if not _intro_called:
		_intro_called = true
		if band == "warm":
			line = "위험한 건 제가 먼저 볼게요. 화면 끝에 띄워둘게요. 요원은 앞만 봐요."
		else:
			line = "위험한 건 제가 먼저 확인하겠습니다. 화면 끝에 띄워둘 테니, 요원은 전방만 보십시오."
	elif _is_degraded():
		line = dir_txt + " 어딘가... 저도 잘 안 보여요. 직접 살펴요."
	elif band == "cold":
		line = dir_txt + ", 표시하겠습니다."
	else:
		line = dir_txt + ", 표시해 둘게요."
	veil_calls_threat.emit(line)

# 화면 중심 대비 위협 방향 → 8방위 한국어 (화면 좌표: y 아래가 +)
func _direction_word(d: Vector2) -> String:
	if d.length() < 1.0:
		return "가까이"
	var deg: float = rad_to_deg(atan2(d.y, d.x))
	if deg >= -22.5 and deg < 22.5:
		return "오른쪽"
	elif deg >= 22.5 and deg < 67.5:
		return "오른쪽 아래"
	elif deg >= 67.5 and deg < 112.5:
		return "아래쪽"
	elif deg >= 112.5 and deg < 157.5:
		return "왼쪽 아래"
	elif deg >= 157.5 or deg < -157.5:
		return "왼쪽"
	elif deg >= -157.5 and deg < -112.5:
		return "왼쪽 위"
	elif deg >= -112.5 and deg < -67.5:
		return "위쪽"
	else:
		return "오른쪽 위"

func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var xform: Transform2D = get_viewport().get_canvas_transform()
	var view: Vector2 = get_viewport_rect().size
	var center: Vector2 = view * 0.5
	var ppos: Vector2 = player.global_position
	var degraded: bool = _is_degraded()
	# 역전 순간 일제 붕괴 — 전환 직후 잠깐 전체 마커가 강하게 흔들리고 흐려진다.
	var glitch: float = 0.0
	if degraded:
		var since: float = _t - _degrade_t
		if since < GLITCH_DUR:
			glitch = 1.0 - (since / GLITCH_DUR)
	var alive: Dictionary = {}
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node2D):
			continue
		var en: Node2D = e as Node2D
		if not is_instance_valid(en) or bool(en.get("dead")):
			continue
		var wpos: Vector2 = en.global_position
		if ppos.distance_to(wpos) > DETECT_RADIUS:
			continue
		var id: int = en.get_instance_id()
		alive[id] = true
		if not _seen.has(id):
			_seen[id] = _t
		# degradation 중 일부 위협은 VEIL이 영영 못 본다 = 요원이 직접 봐야 함 (역전의 실물)
		if degraded and (id % 100) < BLIND_PCT:
			continue
		var danger: bool = en.has_method("veil_is_telegraphing") and en.veil_is_telegraphing()
		var col: Color = WARN if danger else CALM
		# 등장 페이드인 — "방금 짚어진" 느낌
		var appear: float = clamp((_t - float(_seen[id])) / FADE_IN, 0.0, 1.0)
		var alpha_mul: float = appear
		if degraded:
			var phase: float = float(id % 997) * 0.0131
			# 주기의 ~45%는 VEIL이 못 봄 → 마커 꺼짐 (평시 대비 확실히 더 자주)
			if fmod(_t * 0.9 + phase, 1.0) < 0.45:
				continue
			alpha_mul *= clamp(0.45 + 0.3 * sin(_t * 6.0 + phase), 0.18, 0.72)
		if glitch > 0.0:
			alpha_mul *= 1.0 - 0.6 * glitch * (0.5 + 0.5 * sin(_t * 40.0 + float(id)))
		if danger:
			alpha_mul *= 0.7 + 0.3 * sin(_t * 11.0)
		var jitter: Vector2 = Vector2.ZERO
		if glitch > 0.0:
			jitter = Vector2(sin(_t * 37.0 + float(id)), cos(_t * 41.0 + float(id))) * 6.0 * glitch
		var spos: Vector2 = xform * wpos + jitter
		var on_screen: bool = spos.x >= 0.0 and spos.x <= view.x and spos.y >= 0.0 and spos.y <= view.y
		if on_screen:
			# 화면 안 — 요원도 볼 수 있으니 평시엔 은은, 위험할 땐 또렷.
			var rc: Color = col
			rc.a *= (0.92 if danger else 0.62) * alpha_mul
			_draw_reticle(spos, rc, danger, appear)
		else:
			# 화면 밖 — VEIL의 봄이 빛나는 곳. 또렷하게.
			var ec: Color = col
			ec.a *= alpha_mul
			_draw_edge_arrow(spos, center, view, ec)
	# 사라진 적 정리 (메모리 — _seen 무한 증가 방지)
	if _seen.size() > alive.size():
		for k in _seen.keys():
			if not alive.has(k):
				_seen.erase(k)

func _draw_reticle(pos: Vector2, col: Color, danger: bool, appear: float) -> void:
	# 등장 시 살짝 크게 시작해 수축 — 짚어지는 동작감.
	var grow: float = 1.0 + (1.0 - appear) * 0.35
	var r: float = (RETICLE_R + (4.0 if danger else 0.0)) * grow
	var pts: PackedVector2Array = PackedVector2Array([
		pos + Vector2(0.0, -r),
		pos + Vector2(r, 0.0),
		pos + Vector2(0.0, r),
		pos + Vector2(-r, 0.0),
		pos + Vector2(0.0, -r),
	])
	draw_polyline(pts, col, 2.0 if danger else 1.6)

func _draw_edge_arrow(spos: Vector2, center: Vector2, view: Vector2, col: Color) -> void:
	# 위협 방향으로 화면 가장자리(여백 inset)에 클램프한 점 + 그 방향을 가리키는 삼각형.
	var edge: Vector2 = Vector2(
		clamp(spos.x, EDGE_MARGIN, view.x - EDGE_MARGIN),
		clamp(spos.y, EDGE_MARGIN, view.y - EDGE_MARGIN),
	)
	var dir: Vector2 = spos - center
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var tip: Vector2 = edge + dir * 13.0
	var a: Vector2 = edge - dir * 6.0 + perp * 9.0
	var b: Vector2 = edge - dir * 6.0 - perp * 9.0
	draw_colored_polygon(PackedVector2Array([tip, a, b]), col)
	var dot: Color = col
	dot.a *= 0.7
	draw_circle(edge - dir * 7.0, 3.0, dot)
