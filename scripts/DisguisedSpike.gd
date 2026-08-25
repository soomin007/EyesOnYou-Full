extends Node2D
class_name DisguisedSpike
# ─── §4 거짓 렌더(라이벌 VEIL) · 가시 함정을 "안전한 바닥"으로 위장 ───
# 가짜 VEIL이 렌더를 강탈해 진짜 가시를 숨긴다(플레이어에겐 평범한 바닥으로 보임).
# 위장한 적(Enemy.disguise_as)의 함정 버전 · 같은 §4.1 공정 규칙을 따른다:
#   ① 항상 tell(바닥 위 붉은 지직거림 _FloorGlitch, 원거리 가독) · 주의 깊으면 항상 알아챔.
#   ② 신뢰가 지각을 산다 · register_band=="warm"이면 리빌 반경이 넓어져 더 일찍 드러남.
#   ③ 드물어야 무섭다 · 맵당 소수(MapData deceit_spikes).
#   ④ 하드하되 fair · 데미지 zone은 처음부터 활성(밟으면 실제 피해). 단 위 tell이 항상 있으니
#      "속았다"는 내 부주의 탓이지 운빨이 아니다. 밟는 순간에도 정체가 드러난다(거짓이 노출됨).
#
# 사용법(Stage): _build_spike로 진짜 가시(시각+데미지 zone)를 만든 뒤 시각 노드만 넘겨 숨기고,
#   이 노드를 가시 중심(center_x, base_y)에 add_child. 근접/밟기 시 reveal()로 진짜 모습 복원.

const REVEAL_RANGE: float = 150.0        # 근접 리빌 기본 반경(적 70보다 큼 · 밟기 전 알 기회)
const REVEAL_RANGE_WARM_BONUS: float = 60.0   # 신뢰 warm이면 더 일찍 드러남(§4.1 "신뢰가 지각을 산다")

var _revealed: bool = false
var _visuals: Array = []          # 숨겨둘 진짜 가시 시각(CanvasItem) · 리빌 시 노출
var _tell: Node2D = null          # 항상 켜진 지직거림 tell
var _player: Node2D = null
var band_w: float = 120.0         # 위장 바닥 폭(tell 밴드 폭)

# Stage가 만든 진짜 가시 시각 노드들을 넘겨받아 숨기고, tell을 켠다.
func setup(visual_nodes: Array, w: float) -> void:
	band_w = w
	_visuals = visual_nodes
	for n in _visuals:
		if is_instance_valid(n) and n is CanvasItem:
			(n as CanvasItem).visible = false   # 위장 = 안전한 바닥처럼(가시 숨김)
	_tell = _FloorGlitch.new()
	_tell.owner_ref = self
	_tell.band_w = band_w
	add_child(_tell)

func _find_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	var arr: Array = get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		_player = arr[0]
	return _player

func _process(_delta: float) -> void:
	if _revealed:
		return
	var p: Node2D = _find_player()
	if p == null:
		return
	var extra: float = REVEAL_RANGE_WARM_BONUS if GameState.veil_register_band() == "warm" else 0.0
	if global_position.distance_to(p.global_position) < REVEAL_RANGE + extra:
		reveal()

# 진짜 가시 노출 · 근접(위) 또는 밟는 순간(Stage._on_spike_touched)에 호출.
func reveal() -> void:
	if _revealed:
		return
	_revealed = true
	for n in _visuals:
		if is_instance_valid(n) and n is CanvasItem:
			var ci: CanvasItem = n
			ci.visible = true
			# 언마스크 · 짧은 바이올렛 글리치 플래시(위장 적 _reveal_disguise와 동형 톤).
			ci.modulate = Color(1.8, 1.4, 1.9)
			ci.create_tween().tween_property(ci, "modulate", Color(1, 1, 1), 0.25)
	SfxPlayer.play_at("bestiary_first_seen", global_position)
	if _tell != null:
		_tell.queue_free()
		_tell = null

# ─── 바닥 위 붉은 지직거림 tell · Enemy._GlitchTell을 가로 밴드(바닥)로 변형 ───
# "이 바닥은 뭔가 이상하다"가 멀리서도 읽히게. 거리·신뢰로 강도. 위장이 풀리기 전까지 항상 켜짐.
class _FloorGlitch extends Node2D:
	var owner_ref: Node = null
	var band_w: float = 120.0
	var t: float = 0.0
	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
	func _draw() -> void:
		var beat: float = fmod(t, 1.4)
		if beat > 0.5:
			return   # 주기적 번쩍(0.5s/1.4s) · 위장 적 tell과 같은 리듬
		var vis: float = 1.0 - (beat / 0.5)
		var mul: float = 0.7
		if owner_ref != null and owner_ref.has_method("_find_player"):
			var pl: Node = owner_ref.call("_find_player")
			if pl != null and is_instance_valid(pl):
				var d: float = (owner_ref as Node2D).global_position.distance_to((pl as Node2D).global_position)
				mul = clamp(1.0 - d / 850.0, 0.55, 1.0)
				if GameState.veil_register_band() == "warm":
					mul = min(1.0, mul + 0.25)
		var a: float = vis * mul
		if a < 0.04:
			return
		var red := Color(1.0, 0.18, 0.30, a)
		var hw: float = band_w * 0.5
		# 거짓 바닥 패치 붉은 외곽선 · "여기가 렌더가 강탈된 자리"
		draw_rect(Rect2(-hw - 2.0, -14.0, band_w + 4.0, 16.0), Color(red.r, red.g, red.b, a), false, 2.5)
		# 바닥선 위 붉은 채움 밴드(옅게) · 크로매틱 오프셋으로 지직
		var ox: float = sin(t * 40.0) * 3.0
		draw_rect(Rect2(-hw + ox, -8.0, band_w, 8.0), Color(red.r, red.g, red.b, a * 0.40), true)
		# 스캔라인 지직거림 · 밴드 폭을 좌우로 훑는 세로 결
		for i in range(6):
			var xx: float = -hw + float((int(t * 120.0) + i * int(band_w / 6.0)) % int(max(1.0, band_w)))
			draw_line(Vector2(xx, -13.0), Vector2(xx, 0.0), Color(red.r, red.g, red.b, a), 1.6)
