class_name CycleShutter
extends AnimatableBody2D

# 지하 주차장 시그니처 해저드 · 차단 셔터(map_identity_rework §8, 2026-08-17).
# 통로를 막는 셔터가 주기로 여닫힌다: 열림 → 경고(램프 호박) → 하강 → 닫힘 → 상승.
# 회피가 아니라 "타이밍 대기"의 룰 · 피해 없음. 안전 센서: 하강 중 문 아래 사람이 있으면
# 내려오다 멈춘다(실제 셔터 문법 · 끼임/밀림 물리 예외 원천 차단).
# 광과민: 램프는 색 전환 유지(점멸 없음) · 문은 연속 이동.
#
# 사용: MapData "shutters" = [{x, open?, closed?, phase?}]. Stage가 ground_y에 배치.

const DOOR_W: float = 26.0
const DOOR_H: float = 290.0
const MOVE_SPEED: float = 330.0
const WARN_DUR: float = 1.0    # 열림 상태 마지막 1s = 경고(램프 호박)

enum S { OPEN, CLOSING, CLOSED, OPENING }

var open_dur: float = 3.4
var closed_dur: float = 2.6
var ground_y: float = 600.0

var _state: int = S.OPEN
var _t: float = 0.0
var _k: float = 0.0          # 0 = 완전 개방(문이 위) / 1 = 완전 폐쇄(문이 바닥)
var _top_y: float = 0.0      # 개방 시 문 중심 y

func setup(cfg: Dictionary, g_y: float) -> void:
	# sync_to_physics를 position 대입보다 먼저 꺼야 한다 · 기본값(true) 상태로 한 물리 틱을
	# 지나면 물리 서버가 트랜스폼을 (0,0)으로 역동기화해 x가 증발한다(MovingPlatform 주석과
	# 동일 함정 · 2026-08-17 하니스에서 재확인).
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	ground_y = g_y
	open_dur = float(cfg.get("open", 3.4))
	closed_dur = float(cfg.get("closed", 2.6))
	position = Vector2(float(cfg.get("x", 0.0)), 0.0)
	_t = fmod(float(cfg.get("phase", 0.0)) * (open_dur + closed_dur), open_dur)
	_top_y = ground_y - 280.0 - DOOR_H * 0.5   # 개방 시 문 하단 = 지면-280(점프 정점 위)
	add_to_group("cycle_shutter")
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(DOOR_W, DOOR_H)
	col.shape = shape
	add_child(col)
	_apply()

func _apply() -> void:
	# 문 중심 y · _k 보간(하단이 top-280 → 지면).
	position.y = lerpf(_top_y, ground_y - DOOR_H * 0.5, _k)

func _player_under_door() -> bool:
	var p: Node = get_tree().get_first_node_in_group("player")
	if not (p is Node2D):
		return false
	var pos: Vector2 = (p as Node2D).global_position
	return absf(pos.x - position.x) < DOOR_W * 0.5 + 22.0 and pos.y > _top_y

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t += delta
	match _state:
		S.OPEN:
			if _t >= open_dur:
				_state = S.CLOSING
				_t = 0.0
				SfxPlayer.play_at("drop_platform_descend", global_position, -8.0)
		S.CLOSING:
			# 안전 센서 · 문 아래 사람이 있으면 하강 정지(대기).
			if not _player_under_door():
				_k = minf(1.0, _k + MOVE_SPEED * delta / (ground_y - 280.0 - _top_y + DOOR_H * 0.5))
				_apply()
			if _k >= 1.0:
				_state = S.CLOSED
				_t = 0.0
		S.CLOSED:
			if _t >= closed_dur:
				_state = S.OPENING
				_t = 0.0
				SfxPlayer.play_at("gate_unlock", global_position, -12.0)
		S.OPENING:
			_k = maxf(0.0, _k - MOVE_SPEED * delta / (ground_y - 280.0 - _top_y + DOOR_H * 0.5))
			_apply()
			if _k <= 0.0:
				_state = S.OPEN
				_t = 0.0
	queue_redraw()

func _draw() -> void:
	# 상부 하우징 · 문이 감겨 들어가는 박스(월드 y 고정 → 로컬로 역보정).
	var housing_top: float = _top_y - DOOR_H * 0.5 - 14.0 - position.y
	draw_rect(Rect2(Vector2(-DOOR_W * 0.5 - 8.0, housing_top), Vector2(DOOR_W + 16.0, 16.0)), Color(0.16, 0.17, 0.21))
	# 문 본체 · 슬랫(가로 줄) 셔터.
	draw_rect(Rect2(Vector2(-DOOR_W * 0.5, -DOOR_H * 0.5), Vector2(DOOR_W, DOOR_H)), Color(0.20, 0.21, 0.25))
	var sy: float = -DOOR_H * 0.5 + 10.0
	while sy < DOOR_H * 0.5 - 4.0:
		draw_rect(Rect2(Vector2(-DOOR_W * 0.5 + 2.0, sy), Vector2(DOOR_W - 4.0, 2.0)), Color(0.10, 0.11, 0.14))
		sy += 18.0
	draw_rect(Rect2(Vector2(-DOOR_W * 0.5, DOOR_H * 0.5 - 5.0), Vector2(DOOR_W, 5.0)), Color(0.32, 0.34, 0.40))
	# 상태 램프 · 하우징 곁(녹=개방 / 호박=곧 닫힘 / 적=폐쇄) · 색 전환만(점멸 없음).
	var lamp_col := Color(0.35, 0.9, 0.5)
	if _state == S.OPEN and _t > open_dur - WARN_DUR:
		lamp_col = Color(1.0, 0.75, 0.3)
	elif _state != S.OPEN:
		lamp_col = Color(0.95, 0.3, 0.25)
	draw_circle(Vector2(DOOR_W * 0.5 + 16.0, housing_top + 8.0), 5.0, lamp_col)
