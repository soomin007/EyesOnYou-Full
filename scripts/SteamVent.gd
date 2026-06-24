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

@export var height: float = 260.0
@export var phase: float = 0.0   # 0~1 사이클 위상 오프셋 (분출구 엇갈림)
@export var damage: int = 1

var _t: float = 0.0
var _hit_this_burst: bool = false

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

func _draw() -> void:
	var ct: float = fmod(_t, PERIOD)
	if ct < TELEGRAPH:
		# 텔레그래프 — 바닥에서 옅은 김이 점점 또렷해진다(곧 분출 경고).
		var warn: float = ct / TELEGRAPH
		for i in 4:
			var yy: float = -float(i) * 16.0 - 6.0
			var w: float = WIDTH * (0.32 + 0.1 * float(i))
			var a: float = (0.10 + 0.20 * warn) * (1.0 - float(i) * 0.2)
			draw_rect(Rect2(-w * 0.5, yy, w, 12.0), COL * Color(1.0, 1.0, 1.0, a))
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
		# 노즐 베이스 — 분출구 입구 밝게.
		draw_rect(Rect2(-WIDTH * 0.5, -10.0, WIDTH, 10.0), COL * Color(1.0, 1.0, 1.0, 0.5 * intensity))
