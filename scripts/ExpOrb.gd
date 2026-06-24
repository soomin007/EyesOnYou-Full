extends Node2D

const PICKUP_RANGE: float = 220.0
const ATTRACT_SPEED: float = 480.0
const VALUE: int = 1

@onready var sprite: ColorRect = $Sprite

var collected: bool = false
var spawn_anim_t: float = 0.0
var bounce_velocity: Vector2 = Vector2.ZERO
# 흡인 반경 — 기본 PICKUP_RANGE. 글라이드 게이트 오브는 작게(44) 설정.
var attract_range: float = PICKUP_RANGE
# 획득 시 부여 경험치 — 게이트 오브는 더 높게(글라이드 투자 보상). Stage._spawn_orb이 set.
var value: int = VALUE
# 글라이드 게이트 보상 여부 — true면 벽/바닥 너머로는 흡인되지 않는다(직접 알코브에 도달해야 획득).
var is_gate: bool = false

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
		position += to.normalized() * ATTRACT_SPEED * delta

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
