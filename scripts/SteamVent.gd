class_name SteamVent
extends Node2D

# 냉각 시설 시그니처 해저드 — 바닥/파이프에서 주기적으로 수직 증기 기둥이 분출한다.
# 사이클: 대기 → 텔레그래프(바닥 일렁임, 곧 분출 경고) → 분출(데미지) → 냉각(대기).
# 위상 오프셋으로 인접 분출구가 엇갈려 터져 "타이밍 보고 지나가기"를 만든다. 파괴 불가.

const TELEGRAPH: float = 0.7
const BURST: float = 0.9
const COOLDOWN: float = 1.6
const PERIOD: float = TELEGRAPH + BURST + COOLDOWN

const WIDTH: float = 64.0
const COL: Color = Color(0.62, 0.92, 1.0)   # 냉각 시안-화이트 증기
const WARN: Color = Color(1.0, 0.55, 0.2)   # 위험 경고색(호박/주황) — "기류"가 아니라 "해로움"으로 읽히게

@export var height: float = 260.0
@export var phase: float = 0.0   # 0~1 사이클 위상 오프셋 (분출구 엇갈림)
@export var damage: int = 1
# >0: 분출 시 증기 위로 이어지는 옅은 열기둥 높이 — 플레이어 피해는 없고(짙은 증기만 위험)
# 기계 과열 판정(SENTINEL 실속 유인, 2026-08-22 카운터플레이)에만 쓰인다. 판정에 쓰이는 만큼
# 화면에도 그린다(화면=판정 일치).
@export var plume_height: float = 0.0

var _t: float = 0.0
var _hit_this_burst: bool = false

func is_bursting() -> bool:
	var ct: float = fmod(_t, PERIOD)
	return ct >= TELEGRAPH and ct < TELEGRAPH + BURST

func _ready() -> void:
	z_index = 1
	add_to_group("steam_vent")
	_t = phase * PERIOD

func _process(delta: float) -> void:
	_t += delta
	var ct: float = fmod(_t, PERIOD)
	var bursting: bool = ct >= TELEGRAPH and ct < TELEGRAPH + BURST
	if not bursting:
		_hit_this_burst = false
	elif not _hit_this_burst:
		_check_hit()
	queue_redraw()

func _check_hit() -> void:
	for n in get_tree().get_nodes_in_group("player"):
		if not (n is Node2D):
			continue
		var p: Node2D = n as Node2D
		var dx: float = absf(p.global_position.x - global_position.x)
		# 분출구는 global_position(바닥)에서 위로 height만큼이 위험 구간.
		var up: float = global_position.y - p.global_position.y
		if dx <= WIDTH * 0.5 and up >= -24.0 and up <= height:
			if p.has_method("take_hit"):
				p.take_hit(damage)
				_hit_this_burst = true
				SfxPlayer.play_at("spike_hit", global_position)
			return

# 상시 지면 노즐 + 호박 위험 줄무늬 — 분출 안 할 때도 "여기 해저드"를 항상 보이게(피드백: 위치 모르고
# 진입해 맞음). 분출 임박/중엔 줄무늬가 밝아진다.
func _draw_base_marker(ct: float) -> void:
	var hot: float = 0.0
	if ct < TELEGRAPH:
		hot = 0.4 + 0.6 * (ct / TELEGRAPH)
	elif ct < TELEGRAPH + BURST:
		hot = 1.0
	# 노즐 본체(금속)
	draw_rect(Rect2(-WIDTH * 0.5, -11.0, WIDTH, 11.0), Color(0.22, 0.23, 0.27))
	# 호박/검정 위험 줄무늬(항상 보이되 임박 시 밝게)
	var stripe_a: float = 0.4 + 0.5 * hot
	var sw: float = 9.0
	var x: float = -WIDTH * 0.5
	var idx: int = 0
	while x < WIDTH * 0.5 - 0.5:
		if idx % 2 == 0:
			draw_rect(Rect2(x, -9.0, sw, 7.0), Color(WARN.r, WARN.g, WARN.b, stripe_a))
		x += sw
		idx += 1

func _draw() -> void:
	var ct: float = fmod(_t, PERIOD)
	_draw_base_marker(ct)
	if ct < TELEGRAPH:
		# 텔레그래프 — 경고색(주황)으로 곧 분출을 알린다. 시안 김이 아니라 *위험* 신호.
		var warn: float = ct / TELEGRAPH
		for i in 4:
			var yy: float = -float(i) * 16.0 - 6.0
			var w: float = WIDTH * (0.32 + 0.1 * float(i))
			var a: float = (0.16 + 0.34 * warn) * (1.0 - float(i) * 0.2)
			draw_rect(Rect2(-w * 0.5, yy, w, 12.0), Color(WARN.r, WARN.g, WARN.b, a))
		return
	if ct < TELEGRAPH + BURST:
		# 분출 — 수직 증기 기둥. 위로 갈수록 옅게, 좌우로 흔들린다.
		var bt: float = (ct - TELEGRAPH) / BURST
		var intensity: float = sin(bt * PI)   # 0→1→0 분출 강도
		var steps: int = int(height / 14.0)
		for i in steps:
			var f: float = float(i) / float(maxi(1, steps))
			var yy: float = -f * height
			var jitter: float = sin(_t * 22.0 + f * 9.0) * (3.0 + 6.0 * f)
			var w: float = WIDTH * (1.0 - 0.4 * f) * (0.7 + 0.3 * intensity)
			var a: float = (0.5 * (1.0 - f) + 0.15) * intensity
			draw_rect(Rect2(-w * 0.5 + jitter, yy - 8.0, w, 14.0), COL * Color(1.0, 1.0, 1.0, a))
		# 노즐 베이스 — 분출구 입구 밝게 + 경고색 핫코어(해로움 신호).
		draw_rect(Rect2(-WIDTH * 0.5, -10.0, WIDTH, 10.0), COL * Color(1.0, 1.0, 1.0, 0.5 * intensity))
		draw_rect(Rect2(-WIDTH * 0.42, -7.0, WIDTH * 0.84, 6.0), Color(WARN.r, WARN.g, WARN.b, 0.55 * intensity))
		# 열기둥 — 짙은 증기 위로 이어지는 옅은 아지랑이(플레이어 무해 · 기계 과열 판정 구간).
		# 짙은 기둥과 재질이 다르게: 폭 좁고 훨씬 옅으며 위로 갈수록 잦아든다.
		if plume_height > 0.0:
			var psteps: int = int(plume_height / 26.0)
			for i in psteps:
				var f2: float = float(i) / float(maxi(1, psteps))
				var yy2: float = -height - f2 * plume_height
				var jit2: float = sin(_t * 9.0 + f2 * 6.0) * (4.0 + 8.0 * f2)
				var w2: float = WIDTH * 0.55 * (1.0 - 0.25 * f2)
				var a2: float = (0.07 + 0.15 * (1.0 - f2)) * intensity
				draw_rect(Rect2(-w2 * 0.5 + jit2, yy2 - 12.0, w2, 20.0), COL * Color(1.0, 1.0, 1.0, a2))
			# 열기둥 중심선 — 아지랑이 한 줄기(끝까지 이어져 "닿는 높이"가 읽히게).
			draw_line(Vector2(0.0, -height), Vector2(sin(_t * 5.0) * 6.0, -height - plume_height),
				COL * Color(1.0, 1.0, 1.0, 0.14 * intensity), 3.0)
