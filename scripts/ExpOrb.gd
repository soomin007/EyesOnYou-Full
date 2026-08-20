extends Node2D

const PICKUP_RANGE: float = 220.0
# 흡인 가속(2026-08-20 사용자 "딸려올 때 가속 붙으면서 빨려들어왔으면") — 잡히는 순간은
# 잔잔하게 시작해 붙을수록 급가속. 이탈하면 리셋.
const ATTRACT_SPEED_START: float = 320.0
const ATTRACT_ACCEL: float = 2600.0
const ATTRACT_SPEED_MAX: float = 1500.0
const VALUE: int = 1

@onready var sprite: ColorRect = $Sprite

var collected: bool = false
var spawn_anim_t: float = 0.0
var bounce_velocity: Vector2 = Vector2.ZERO
var _attract_v: float = 0.0   # 현재 흡인 속도(가속 누적)
# 흡인 반경 — 기본 PICKUP_RANGE. 글라이드 게이트 오브는 작게(44) 설정.
var attract_range: float = PICKUP_RANGE
# 획득 시 부여 경험치 — 게이트 오브는 더 높게(글라이드 투자 보상). Stage._spawn_orb이 set.
var value: int = VALUE
# 글라이드 게이트 보상 여부 — true면 벽/바닥 너머로는 흡인되지 않는다(직접 알코브에 도달해야 획득).
var is_gate: bool = false
# 미리 배치된 보상(분기·게이트·레버) 여부 — 클리어 환급(Stage._begin_clear_sequence) 제외 대상.
# 배치 보상은 "가서 먹어야" 의미가 있다(안 먹으면 그냥 잃음). 환급은 처치 드롭 전용(2026-08-11).
var placed: bool = false

func _ready() -> void:
	add_to_group("exp_orb")
	bounce_velocity = Vector2(randf_range(-80.0, 80.0), randf_range(-220.0, -120.0))

func _process(delta: float) -> void:
	if collected:
		return
	spawn_anim_t += delta
	if spawn_anim_t < 0.45:
		bounce_velocity.y += 900.0 * delta
		position += bounce_velocity * delta
		return
	var player := _find_player()
	if player == null:
		return
	var to: Vector2 = player.global_position - global_position
	if to.length() < 18.0:
		_collect()
		return
	if to.length() < attract_range:
		# 게이트 보상은 벽/바닥 너머로 끌려오지 않게 — 사이에 막힌 지형이 있으면 흡인 보류.
		# (흡인 반경을 줄여도 직선거리만 보면 아래/옆 메인 경로에서 빨려올 수 있어, LoS로 확실히 차단.)
		if is_gate and not _has_clear_path(player):
			return
		# 빨려드는 가속 — 이동량은 남은 거리로 클램프(고속 오버슈트로 주변을 도는 것 방지).
		_attract_v = minf(maxf(_attract_v, ATTRACT_SPEED_START) + ATTRACT_ACCEL * delta, ATTRACT_SPEED_MAX)
		position += to.normalized() * minf(_attract_v * delta, to.length())
	else:
		_attract_v = 0.0

# 오브 → 플레이어 직선에 막힌 지형(layer 1: 발판/바닥)이 없는지. 게이트 오브 흡인 게이팅용.
func _has_clear_path(p: Node2D) -> bool:
	var world := get_world_2d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, p.global_position, 1)
	var result: Dictionary = world.direct_space_state.intersect_ray(query)
	return result.is_empty()

func _find_player() -> Node2D:
	var nodes := get_tree().get_nodes_in_group("player")
	if nodes.size() == 0:
		return null
	return nodes[0] as Node2D

func _collect() -> void:
	collected = true
	SfxPlayer.play("xp_collect")
	var leveled_up: bool = GameState.add_xp(value)
	get_tree().call_group("stage", "_on_xp_collected", leveled_up)
	queue_free()
