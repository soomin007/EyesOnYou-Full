extends Node2D

# HP 회복 픽업 — 분기 보상으로 맵에 미리 배치된다 (적 처치 드롭 아님).
# 플레이어가 가까이 오면 잡아당겨 흡수, HP 1 회복.

const PICKUP_RANGE: float = 200.0
const ATTRACT_SPEED: float = 380.0
const HEAL_AMOUNT: int = 1

@onready var sprite: ColorRect = $Sprite

var collected: bool = false

func _ready() -> void:
	add_to_group("hp_orb")

func _process(delta: float) -> void:
	if collected:
		return
	var player := _find_player()
	if player == null:
		return
	var target: Vector2 = player.global_position + Vector2(0, -28)
	var to: Vector2 = target - global_position
	if to.length() < 22.0:
		_collect()
		return
	if to.length() < PICKUP_RANGE:
		position += to.normalized() * ATTRACT_SPEED * delta

func _find_player() -> Node2D:
	var nodes := get_tree().get_nodes_in_group("player")
	if nodes.size() == 0:
		return null
	return nodes[0] as Node2D

func _collect() -> void:
	collected = true
	SfxPlayer.play("hp_collect")
	GameState.heal_player(HEAL_AMOUNT)
	queue_free()
