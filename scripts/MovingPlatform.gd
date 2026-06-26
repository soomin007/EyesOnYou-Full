class_name MovingPlatform
extends AnimatableBody2D

# 두 점 사이를 핑퐁 왕복하며 위에 탄 플레이어를 운반하는 발판 (이동 발판 기믹).
# AnimatableBody2D를 _physics_process에서 position으로 직접 이동 → 엔진이 그 트랜스폼 변화에서 발판
# 속도를 계산하고, CharacterBody2D가 on_floor 시 move_and_slide에서 그 속도를 상속받아 자동으로 실린다.
# (주의: sync_to_physics=true면 트랜스폼이 물리 서버에서 *역동기화*돼 직접 set이 덮어써져 안 움직임 —
#  AnimationPlayer로 애니메이트할 때만 켤 것. 여기선 끈다.)
# 정적 발판과 구분되게 앰버 코션 엣지로 "움직인다"를 시각 신호로 준다.
#
# 사용: MapData 맵의 "moving_platforms" 배열 항목 1개 = {from, to, w, cycle, phase?}.
#   from/to : 발판 *중심*의 양 끝 월드좌표
#   w       : 발판 폭(px)
#   cycle   : 한 끝→반대 끝→다시 1회 왕복 소요(초). 클수록 느림(타이밍 읽기 쉬움)
#   phase   : 0~1 시작 위상(여러 발판을 엇갈리게)

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _cycle: float = 4.0
var _phase: float = 0.0
var _w: float = 160.0
var _t: float = 0.0

func setup(from: Vector2, to: Vector2, w: float, cycle: float, phase: float = 0.0) -> void:
	_from = from
	_to = to
	_w = w
	_cycle = maxf(cycle, 0.6)
	_phase = phase
	collision_layer = 1   # 월드(플레이어 mask 1이 충돌)
	collision_mask = 0
	sync_to_physics = false  # 직접 position 이동 — true면 물리서버 역동기화로 안 움직임(위 주석)
	add_to_group("platform")
	add_to_group("moving_platform")
	_build_collision()
	_build_visual()
	position = _from.lerp(_to, _tri(_phase))

func _build_collision() -> void:
	var col := CollisionShape2D.new()
	col.one_way_collision = true   # 위에서만 착지(정적 발판과 동일)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(_w, 24.0)
	col.shape = shape
	add_child(col)

func _build_visual() -> void:
	var hw: float = _w * 0.5
	# 본체(어두운 금속) / 상단 앰버 패널 / 하단 그림자
	_rect(Vector2(-hw, -8.0), Vector2(_w, 16.0), Color(0.17, 0.15, 0.11))
	_rect(Vector2(-hw, -12.0), Vector2(_w, 4.0), Color(0.86, 0.63, 0.20))
	_rect(Vector2(-hw, 8.0), Vector2(_w, 4.0), Color(0.05, 0.05, 0.04))
	# 좌우 끝 코션 캡(움직임 신호)
	_rect(Vector2(-hw, -12.0), Vector2(12.0, 24.0), Color(0.86, 0.63, 0.20, 0.5))
	_rect(Vector2(hw - 12.0, -12.0), Vector2(12.0, 24.0), Color(0.86, 0.63, 0.20, 0.5))

func _rect(pos: Vector2, size: Vector2, color: Color) -> void:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)

# 0..1 톱니 위상 u → 0→1→0 삼각(핑퐁). smoothstep으로 양 끝 감속(타이밍 읽기 쉽게).
func _tri(u: float) -> float:
	var x: float = fmod(u, 1.0) * 2.0
	if x > 1.0:
		x = 2.0 - x
	return smoothstep(0.0, 1.0, x)

func _physics_process(delta: float) -> void:
	_t += delta
	var u: float = _phase + _t / _cycle
	position = _from.lerp(_to, _tri(u))
