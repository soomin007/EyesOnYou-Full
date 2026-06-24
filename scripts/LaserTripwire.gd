class_name LaserTripwire
extends Node2D

# 레이저 탐지선 — 플레이어가 가로지르면 같은 trigger_id의 포탑(BulletTrap, triggered 모드)을
# 일제히 발사시킨다. 자신은 총알을 쏘지 않는 순수 탐지기(침투물 분위기의 레이저 detector).
# 포탑과 분리 배치 — 탐지선을 밟으면 "다른 곳"의 포탑들이 불을 뿜는다.

const COL_LASER: Color = Color(1.0, 0.28, 0.24)
const COL_ALARM: Color = Color(1.0, 0.5, 0.2)

var direction: Vector2 = Vector2.DOWN   # 빔이 뻗는 방향
var length: float = 240.0
var trigger_id: String = ""
var cooldown: float = 2.2
var _cd: float = 0.0
var _flash: float = 0.0
var _player: Node2D = null

func setup(dir: Vector2, len: float, tid: String, cd: float = 2.2) -> void:
	direction = dir.normalized()
	length = maxf(40.0, len)
	trigger_id = tid
	cooldown = maxf(0.5, cd)

func _ready() -> void:
	add_to_group("laser_tripwire")
	z_index = 2

func _get_player() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
	if _cd > 0.0:
		_cd -= delta
	elif _crossed():
		_trip()
	queue_redraw()

func _crossed() -> bool:
	var p := _get_player()
	if p == null:
		return false
	var rel: Vector2 = p.global_position - global_position
	var along: float = rel.dot(direction)
	var perp: float = absf(rel.dot(Vector2(-direction.y, direction.x)))
	return along >= 0.0 and along <= length and perp <= 16.0

func _trip() -> void:
	_cd = cooldown
	_flash = 0.45
	for t in get_tree().get_nodes_in_group("bullet_trap"):
		if t is BulletTrap and (t as BulletTrap).trigger_id == trigger_id:
			(t as BulletTrap).trigger_fire()

func _draw() -> void:
	var a: float = 0.55
	if _flash > 0.0:
		a = 0.55 + 0.4 * (_flash / 0.45)   # 발동 순간 번쩍
	elif _cd > 0.0:
		a = 0.22                            # 쿨다운 중 흐림(꺼진 듯)
	var col: Color = (COL_ALARM if _flash > 0.0 else COL_LASER) * Color(1, 1, 1, a)
	var endp: Vector2 = direction * length
	draw_line(Vector2.ZERO, endp, col, 1.5 + 1.5 * _flash / 0.45 if _flash > 0.0 else 1.5, true)
	# 양 끝 이미터 점.
	draw_circle(Vector2.ZERO, 3.5, col)
	draw_circle(endp, 3.5, col)
