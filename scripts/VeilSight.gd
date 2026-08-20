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
const RECON_RADIUS_MUL: float = 2.5           # 정찰 보상 탐지 반경 배수
# 정찰 보상 활성(이 스테이지 한정) — _ready에서 GameState 캡처. 시각 마커에만 적용,
# 음성 위협 콜은 근접 밴드 규칙(240px) 유지.
var _recon: bool = false
# 전파 간섭 펄스(중계소 · Interference가 매 틱 세팅) — 0~1, 마커 알파를 깎는다. recon은 관통.
var interference: float = 0.0
const CALM: Color = Color(0.42, 0.86, 1.0)    # 평시 — VEIL 시안 (자막 색과 통일감)
const WARN: Color = Color(1.0, 0.55, 0.22)    # 공격 임박 — 경고 주황
const RIVAL: Color = Color(0.80, 0.34, 0.98)  # 재머 마커 — 라이벌 바이올렛(안티-VEIL, rival_veil_concept §5)
const EDGE_MARGIN: float = 24.0               # 화면 밖 화살표가 가장자리에서 떨어지는 여백 (피드백: 더 붙게 48→24)
# 존재감 1차 패스(2026-08-21 사용자 "플레이 중 마커가 눈에 잘 안 들어온다" · 승인 방향 ⓐ):
# 크기 17→20 · 선 1.6→2.2 · 평시 알파 0.62→0.78 + 등장 핑 링 + 위험 이중 링. 재머·간섭·정찰
# 콘텐츠가 전부 "마커가 보인다/안 보인다"의 대비에 기대므로 기반 가시성이 먼저다.
const RETICLE_R: float = 20.0
const FADE_IN: float = 0.5                     # 마커가 "그어지는" 등장 시간(스트로크 연출, 인지 강화 ②)
const CALL_COOLDOWN: float = 18.0             # VEIL이 말로 짚는 최소 간격 (노이즈 방지)
const CALL_BAND: float = 240.0                # 위협 콜 대상 = 화면 밖 이 거리 이내(조우 직전만 말로)
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
var _jam_intro_called: bool = false           # 재밍 필드 첫 진입 시 VEIL 반응 1회(맵당)
var _tag_id: int = -1                         # 런 첫 마커 서명 태그 대상(인지 강화 ①)
var _tag_until: float = -1.0
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
	# 정찰 보상(reward_type "recon") — 이 스테이지 한정 마킹 강화: 탐지 반경 2.5배 +
	# 재밍·붕괴 블라인드 관통. GameState 플래그를 _ready에서 캡처(degraded와 동형 패턴).
	_recon = GameState.veilsight_recon_active
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
	# 재밍 필드 안 = VEIL 없는 날것 시야 → 붕괴 비네트(어둠+시야 축소)를 켠다.
	var jam: float = _player_jam_intensity()
	var deg_target: float = 1.0 if _is_degraded() else 0.0
	var target: float = max(deg_target, jam)
	# 재밍 진입은 빠르게 붕괴시킨다 — 통과 중(빠르게 지나감)에도 확실히 어두워지게(피드백: 옅은 틴트만 보였음).
	var rate: float = 1.4
	if target > _vig and jam > deg_target:
		rate = 5.0
	_vig = move_toward(_vig, target, delta * rate)
	_vig_mat.set_shader_parameter("vig", _vig)
	_vig_mat.set_shader_parameter("time", _t)
	# 재밍이 자연 붕괴보다 지배적이면 어둠을 바이올렛으로(라이벌의 소행) + 자연 붕괴보다 진하게(블랙아웃 체감).
	var violet: float = clamp(jam - deg_target, 0.0, 1.0)
	var dc: Color = Color(0.0, 0.0, 0.02, VIG_DARK_A).lerp(Color(0.09, 0.01, 0.14, 0.92), violet)
	_vig_mat.set_shader_parameter("dark_color", dc)
	# 저-vig 색(calm_color)도 재밍 땐 어둠으로 당긴다 — 안 그러면 낮은 강도에서 시안(평시 VEIL색) 비네트가
	# 오히려 진해져 "VEIL이 강해진" 느낌이 든다(피드백). 재밍은 시안 단계를 건너뛰고 처음부터 어둡게.
	var base_calm: Color = Color(CALM.r, CALM.g, CALM.b, VIG_CALM_A)
	# smoothstep으로 재밍 들자마자(violet 0.10 이내) 시안→어둠 완료 — 테두리에서 시안이 강해지는 순간 제거(피드백).
	var cc: Color = base_calm.lerp(Color(0.09, 0.01, 0.14, VIG_DARK_A * 0.6), smoothstep(0.0, 0.10, violet))
	_vig_mat.set_shader_parameter("calm_color", cc)
	# 재밍은 시야를 훨씬 더 조인다(사용자: "확 줄어들어야"). 자연 붕괴(0.32)보다 작은 반경. 완전 근접(violet=1)
	# 에서도 너무 답답하지 않게 0.24(aspect 보정으로 가로가 좁아지므로 0.20보다 키움).
	_vig_mat.set_shader_parameter("radius_near", lerp(VIG_RADIUS_NEAR, 0.24, violet))
	# 붕괴 시 시야 중심을 화면 중심이 아니라 플레이어 캐릭터에 맞춘다(사용자 요청). vig만큼 화면중심→플레이어로 보간.
	var pc: Vector2 = Vector2(0.5, 0.5)
	var vsize: Vector2 = get_viewport_rect().size
	if vsize.y > 0.0:
		_vig_mat.set_shader_parameter("aspect", vsize.x / vsize.y)   # 원에 가깝게(가로 납작 보정)
	if player != null and is_instance_valid(player) and vsize.x > 0.0 and vsize.y > 0.0:
		var sp: Vector2 = get_viewport().get_canvas_transform() * (player.global_position + Vector2(0.0, -24.0))
		pc = Vector2(0.5, 0.5).lerp(Vector2(sp.x / vsize.x, sp.y / vsize.y), _vig)
	_vig_mat.set_shader_parameter("vig_center", pc)

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
	_scan_for_jam()
	_update_vignette(delta)
	queue_redraw()

# 활성(미파괴) 재머 목록 — 마커 소등/서사 반응 판정용. group "jammer".
func _active_jammers() -> Array:
	var out: Array = []
	for j in get_tree().get_nodes_in_group("jammer"):
		if j is Node2D and is_instance_valid(j) and not (j as Node2D).get("dead"):
			out.append(j)
	return out

# 플레이어가 재머 반경 안에 얼마나 깊이 있는가 (0=밖, 1=중심). 재머 = 라이벌이 강제하는 "VEIL 없는
# 날것 시야"(§3 진실의 삼각형: 블랙아웃) → 이 값으로 시야 붕괴 비네트를 켜고 마커를 지운다.
func _player_jam_intensity() -> float:
	if player == null or not is_instance_valid(player):
		return 0.0
	var out: float = 0.0
	var ppos: Vector2 = player.global_position
	for j in get_tree().get_nodes_in_group("jammer"):
		if not (j is Node2D) or not is_instance_valid(j) or (j as Node2D).get("dead"):
			continue
		var jn: Node2D = j as Node2D
		var r: float = 340.0
		if jn.has_method("jam_radius"):
			r = jn.call("jam_radius")
		# 반경 대부분을 "붕괴"로 평탄화 — 바깥 35%만 감쇠. 통과 중에도 확실히 붕괴에 든다(피드백).
		out = max(out, clamp((r - jn.global_position.distance_to(ppos)) / (r * 0.35), 0.0, 1.0))
	return out

# 적이 어떤 활성 재머의 반경 안인가 — 그 안 적은 VEIL이 못 봐서 마커를 그리지 않는다(플레이어 위치 무관).
func _enemy_in_jam(en: Node2D, jammers: Array) -> bool:
	if jammers.is_empty():
		return false
	var epos: Vector2 = en.global_position
	for j in jammers:
		var jn: Node2D = j as Node2D
		var r: float = 340.0
		if jn.has_method("jam_radius"):
			r = jn.call("jam_radius")
		if jn.global_position.distance_to(epos) <= r:
			return true
	return false

# 재밍 필드에 처음 들어서면 VEIL이 1회 반응(작가성) — "여기는 제 시야가 안 닿아요".
func _scan_for_jam() -> void:
	if _jam_intro_called or player == null or not is_instance_valid(player):
		return
	if _t < MIN_CALL_TIME:
		return
	var jammers: Array = _active_jammers()
	if jammers.is_empty():
		return
	var ppos: Vector2 = player.global_position
	for j in jammers:
		var jn: Node2D = j as Node2D
		var r: float = 340.0
		if jn.has_method("jam_radius"):
			r = jn.call("jam_radius")
		if jn.global_position.distance_to(ppos) <= r:
			_jam_intro_called = true
			_last_call_t = _t   # 위협 콜과 겹치지 않게 쿨다운 공유
			var band: String = GameState.veil_register_band()
			var line: String
			if band == "warm":
				line = "여기... 제 시야가 안 닿아요. 뭔가가 가로막고 있어요. 조심해요."
			else:
				line = "이 구역, 시야가 차단됩니다. 무언가 개입하고 있습니다. 직접 확인하십시오."
			veil_calls_threat.emit(line)
			return

# 화면 밖에 새로 나타난 위협을 VEIL이 말로 짚는다(레이더 아님의 핵심). 쿨다운/진입보호로 절제.
func _scan_for_call() -> void:
	if player == null or not is_instance_valid(player):
		return
	if _t < MIN_CALL_TIME or (_t - _last_call_t) < CALL_COOLDOWN:
		return
	if _player_jam_intensity() > 0.35:
		return   # 재밍 구역 안 = VEIL 없음 → 말로도 못 짚는다
	if interference > 0.5 and not _recon:
		return   # 간섭 펄스 절정 — 마커와 같이 음성도 잠깐 끊긴다(무해 · 지나간다)
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
		if en.is_in_group("jammer"):
			continue   # 재머 = VEIL 맹점(§1). 마커도 없고 말로도 안 짚는다
		if en.has_meta("no_marker"):
			continue   # 14-1 P3 무표시 위협(§7.2) — 거짓 VEIL이 가린 신호. 말로도 못 짚는다
		var spos: Vector2 = xform * wpos
		var off: bool = spos.x < 0.0 or spos.x > view.x or spos.y < 0.0 or spos.y > view.y
		# 곧 보일 것만 말로 짚는다(화면 밖 CALL_BAND px 이내) — 감지 반경(1400) 전체를 짚으면
		# 플레이어가 볼 수 없는 것을 너무 미리 처리해 대사가 헛돈다(2026-08-15 실플레이 지적).
		# 멀리 있는 위협은 화살표(시각)가 계속 담당하고, 말은 조우 직전에 붙는다.
		var near_view: bool = spos.x > -CALL_BAND and spos.x < view.x + CALL_BAND \
			and spos.y > -CALL_BAND and spos.y < view.y + CALL_BAND
		if off and near_view:
			_call_threat(spos, view * 0.5)
			return   # 한 번에 하나만 — _seen 등록은 _draw가 한다

func _call_threat(spos: Vector2, center: Vector2) -> void:
	_last_call_t = _t
	var dir_txt: String = _direction_word(spos - center)
	# 어투를 신뢰 밴드로 맞춘다(단일 문자열이라 코드 분기). degraded는 항상 막판=WARM.
	var band: String = GameState.veil_register_band()
	var line: String
	# 소개 멘트는 런당 1회(GameState 플래그) — 인스턴스 변수(맵당 재생성)였을 땐 맵마다
	# 첫 위협에서 재생돼 "뜬금없이 자주 나온다"는 피드백(2026-08-14).
	if not GameState.veilsight_intro_shown:
		GameState.veilsight_intro_shown = true
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
	# 재밍 구역: 적이 그 안이면 VEIL이 못 봄(마커 없음, 플레이어 위치 무관) + 플레이어가 그 안이면 남은 마커도 사라짐.
	var jammers: Array = _active_jammers()
	var jam: float = _player_jam_intensity()
	var alive: Dictionary = {}
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node2D):
			continue
		var en: Node2D = e as Node2D
		if not is_instance_valid(en) or bool(en.get("dead")):
			continue
		var wpos: Vector2 = en.global_position
		if ppos.distance_to(wpos) > DETECT_RADIUS * (RECON_RADIUS_MUL if _recon else 1.0):
			continue
		var id: int = en.get_instance_id()
		alive[id] = true
		if not _seen.has(id):
			_seen[id] = _t
		if en.is_in_group("jammer"):
			continue   # 재머 = VEIL 맹점(§1). 마커 없음 — 밝은 본체+필드 링으로 직접 보인다
		if en.has_meta("no_marker"):
			continue   # 14-1 P3 무표시 위협(§7.2) — 거짓 VEIL이 신호를 가림. 스프라이트로만 보인다
		if _enemy_in_jam(en, jammers) and not _recon:
			continue   # 재밍 구역 안 적은 VEIL이 못 봄 — 마커 없음. 정찰 보상은 관통(사전 좌표 확보 서사)
		# degradation 중 일부 위협은 VEIL이 영영 못 본다 = 요원이 직접 봐야 함 (역전의 실물)
		if degraded and (id % 100) < BLIND_PCT and not _recon:
			continue
		var danger: bool = en.has_method("veil_is_telegraphing") and en.veil_is_telegraphing()
		var col: Color = WARN if danger else CALM
		# 등장 = 스트로크(다이아몬드가 한 획씩 그어짐). 알파는 먼저 차올라 긋는 선이 보이게.
		var appear: float = clamp((_t - float(_seen[id])) / FADE_IN, 0.0, 1.0)
		var intf: float = 0.0 if _recon else interference   # 간섭 펄스 · 정찰 보상은 관통
		var alpha_mul: float = clampf(appear * 2.2, 0.0, 1.0) * (1.0 - jam) * (1.0 - intf)
		if alpha_mul <= 0.01:
			continue
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
		# ① 런 첫 마커 서명(인지 강화 2026-08-14) — 첫 표식 옆에 1회 "VEIL" 태그를 붙여
		# 마커·화살표가 시스템 UI가 아니라 VEIL의 행동임을 못박는다. 소개 대사와 별개의 시각 서명.
		# 화면 안 마커에만 — 화면 밖 화살표에 붙이면 서명 순간을 플레이어가 못 본다(2026-08-15 지적).
		if not GameState.veilsight_tag_shown and on_screen:
			GameState.veilsight_tag_shown = true
			_tag_id = id
			_tag_until = _t + 2.4
		if on_screen:
			# 화면 안 — 평시에도 읽히게, 위험할 땐 확실하게(존재감 1차 패스 2026-08-21).
			var rc: Color = col
			rc.a *= (1.0 if danger else 0.78) * alpha_mul
			_draw_reticle(spos, rc, danger, appear)
		else:
			# 화면 밖 — VEIL의 봄이 빛나는 곳. 또렷하게.
			var ec: Color = col
			ec.a *= alpha_mul
			_draw_edge_arrow(spos, center, view, ec)
		if id == _tag_id and _t < _tag_until:
			var anchor: Vector2 = spos if on_screen else Vector2(
				clampf(spos.x, EDGE_MARGIN + 26.0, view.x - EDGE_MARGIN - 64.0),
				clampf(spos.y, EDGE_MARGIN + 34.0, view.y - EDGE_MARGIN - 16.0))
			_draw_veil_tag(anchor, alpha_mul)
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
	var width: float = 2.6 if danger else 2.2
	# 등장 핑 — 짚는 순간 퍼지는 옅은 링(1회성 · 존재감 1차 패스). 광과민: 점멸 아님, 단조 확장.
	if appear < 1.0:
		var ping_a: float = (1.0 - appear) * 0.35
		draw_arc(pos, r * (1.0 + (1.0 - appear) * 1.2), 0.0, TAU, 28,
			Color(col.r, col.g, col.b, ping_a), 1.5, true)
	# 위험 이중 링 — 경고 주황 마커는 바깥 링이 하나 더 둘러져 한눈에 "임박"으로 읽힌다.
	if danger:
		draw_arc(pos, r + 6.0, 0.0, TAU, 30, Color(col.r, col.g, col.b, col.a * 0.5), 1.5, true)
		draw_circle(pos, 3.0, Color(col.r, col.g, col.b, col.a * 0.6))
	# 등장 중엔 한 획씩 그어지는 스트로크(인지 강화 ② — "시스템 표시"가 아니라 "누가 그려줌").
	if appear < 1.0:
		_draw_partial_polyline(pts, appear, col, width)
	else:
		draw_polyline(pts, col, width)

# 폴리라인을 전체 길이의 f(0~1) 비율까지만 그린다 — 손으로 긋는 등장 연출.
func _draw_partial_polyline(pts: PackedVector2Array, f: float, col: Color, width: float) -> void:
	var total: float = 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var budget: float = total * clampf(f, 0.0, 1.0)
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in pts.size() - 1:
		var seg: float = pts[i].distance_to(pts[i + 1])
		if seg <= 0.001:
			continue
		if budget >= seg:
			out.append(pts[i + 1])
			budget -= seg
		else:
			out.append(pts[i].lerp(pts[i + 1], budget / seg))
			break
	if out.size() >= 2:
		draw_polyline(out, col, width)

# 런 첫 마커 서명 — 마커 옆 짧은 연결선 + "VEIL" 텍스트. 마지막 0.6s 동안 페이드아웃.
func _draw_veil_tag(anchor: Vector2, alpha_mul: float) -> void:
	var a: float = clampf((_tag_until - _t) / 0.6, 0.0, 1.0) * clampf(alpha_mul * 1.6, 0.0, 1.0)
	if a <= 0.02:
		return
	var f: Font = get_theme_default_font()
	if f == null:
		return
	var base: Vector2 = anchor + Vector2(16.0, -20.0)
	draw_line(anchor + Vector2(10.0, -10.0), base + Vector2(-2.0, 4.0),
		Color(CALM.r, CALM.g, CALM.b, 0.5 * a), 1.0)
	draw_string(f, base, "VEIL", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13,
		Color(CALM.r, CALM.g, CALM.b, a))

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
	# 확대(존재감 1차 패스 2026-08-21) — 화면 밖 화살표는 VEIL의 핵심 가치라 더 커도 된다.
	var tip: Vector2 = edge + dir * 17.0
	var a: Vector2 = edge - dir * 7.0 + perp * 11.0
	var b: Vector2 = edge - dir * 7.0 - perp * 11.0
	draw_colored_polygon(PackedVector2Array([tip, a, b]), col)
	var dot: Color = col
	dot.a *= 0.7
	draw_circle(edge - dir * 8.0, 3.6, dot)
