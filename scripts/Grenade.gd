class_name Grenade
extends Area2D

# 플레이어 투척 폭발물(explosive 스킬). 포물선으로 날아가 벽/바닥/엄폐물/적에 닿거나 퓨즈가 다하면 폭발.
# 폭발 = 반경 내 적을 거리순 최대 max_hits체에 데미지(몰살 방지) + 확산 링 연출. 파라미터(반경/데미지/
# 최대타수)는 Player가 스킬 티어로 세팅한다. 중력은 Player와 동일해 조준 궤도 미리보기와 실제 비행이 일치.
#
# 엄폐 게임플레이의 핵심 도구: 총알은 엄폐물에 막히지만 수류탄은 포물선으로 넘겨 숨은 채 먼 적을 친다.

const GRAVITY: float = 1400.0   # Player.GRAVITY와 동일 — 미리보기 궤도와 실제 비행 일치
const FUSE: float = 2.5         # 아무것도 안 맞아도 이 시간 뒤 폭발

var velocity: Vector2 = Vector2.ZERO
var radius: float = 180.0
var damage: int = 2
var max_hits: int = 3
var _fuse: float = FUSE
var _dead: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4  # 벽/발판/엄폐물/바닥 + 적
	body_entered.connect(_on_body_entered)
	z_index = 2
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 6.0
	col.shape = shape
	add_child(col)
	# 외형 — 작은 어두운 구체 + 앰버 안전핀
	var b := ColorRect.new()
	b.color = Color(0.16, 0.17, 0.14)
	b.size = Vector2(12.0, 12.0)
	b.position = Vector2(-6.0, -6.0)
	add_child(b)
	var pin := ColorRect.new()
	pin.color = Color(0.90, 0.70, 0.25)
	pin.size = Vector2(4.0, 4.0)
	pin.position = Vector2(-2.0, -9.0)
	add_child(pin)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	velocity.y += GRAVITY * delta
	position += velocity * delta
	rotation += delta * 7.0
	_fuse -= delta
	if _fuse <= 0.0:
		explode()

func _on_body_entered(body: Node) -> void:
	if _dead:
		return
	# 원웨이 발판은 통과(발판 위 적에게 넘기게). 바닥은 group "ground"(platform 아님)라 여기서 폭발.
	if body.is_in_group("platform"):
		return
	explode()

func explode() -> void:
	if _dead:
		return
	_dead = true
	var center: Vector2 = global_position
	SfxPlayer.play_at("bomb_explode", center)
	# 반경 내 적을 거리순 최대 max_hits체 (몰살 방지). AoE라 방패 방향 무시(1인자 take_damage).
	var in_range: Array = []
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Node2D):
			continue
		var e := n as Node2D
		var d: float = e.global_position.distance_to(center)
		if d <= radius and e.has_method("take_damage"):
			in_range.append({"e": e, "d": d})
	in_range.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var hits: int = 0
	for item in in_range:
		if hits >= max_hits:
			break
		var it: Dictionary = item
		var e2: Node2D = it["e"]
		e2.take_damage(damage)
		hits += 1
	_spawn_blast(center)
	queue_free()

# 확산 링 — 수류탄이 free돼도 남게 부모(Stage)에 붙인다.
func _spawn_blast(center: Vector2) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var blast := Polygon2D.new()
	blast.color = Color(1.0, 0.55, 0.30, 0.85)
	blast.z_index = 3
	var pts: Array = []
	for i in 28:
		var a: float = float(i) * TAU / 28.0
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	blast.polygon = PackedVector2Array(pts)
	blast.global_position = center
	blast.scale = Vector2(0.2, 0.2)
	host.add_child(blast)
	var tw := blast.create_tween()
	tw.set_parallel(true)
	tw.tween_property(blast, "scale", Vector2(1.0, 1.0), 0.30)
	tw.tween_property(blast, "modulate", Color(1, 1, 1, 0), 0.45)
	tw.chain().tween_callback(blast.queue_free)
