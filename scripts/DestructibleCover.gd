class_name DestructibleCover
extends StaticBody2D

# 부서지는 엄폐물(정비 차량) — 적 탄을 막지만 피격마다 HP가 줄고 균열, 0에서 파괴된다.
#
# 솔리드(layer 1): 플레이어·양측 탄이 모두 막힌다. 저격수 LoS(Enemy._has_line_of_sight, raycast mask 1)를
# 차단하므로 엄폐 뒤에 붙으면 저격이 발사를 보류(안전) → 넘어갈 때만 노출된다. 발사 함정(BulletTrap) 탄이
# LoS 무관하게 통로를 훑어 먼 쪽 차량부터 침식 → "머물면 엄폐가 깨진다" 압박(목표 근처가 점점 노출).
#
# 데미지 채널: 적 탄이 StaticBody2D에 부딪히면 EnemyBullet이 hit_by_bullet()을 호출한다(플레이어 탄은
# 호출 안 함 — 아군 사격은 엄폐를 갉지 않고 막히기만). 원웨이 발판이 아니라 두 방향 솔리드라 "platform"
# 그룹엔 넣지 않는다(넣으면 원웨이 통과가 되어 탄·플레이어가 뚫음).
#
# 사용: MapData 맵의 "destructible_covers" 배열 항목 1개 = {pos(바닥 접점=하단 중앙), w, h, hp}.

const COL_BODY: Color = Color(0.21, 0.23, 0.27)
const COL_CABIN: Color = Color(0.32, 0.42, 0.50, 0.85)
const COL_TRIM: Color = Color(0.86, 0.63, 0.20)   # 앰버 — 엄폐물 신호(MovingPlatform과 같은 계열)
const COL_WHEEL: Color = Color(0.06, 0.06, 0.07)
const COL_EDGE: Color = Color(0.10, 0.10, 0.12)
const COL_CRACK: Color = Color(0.02, 0.02, 0.03, 0.92)

var _hp: int = 3
var _max_hp: int = 3
var _w: float = 96.0
var _h: float = 72.0
var _art: Node2D = null
var _col: CollisionShape2D = null
var _dead: bool = false
var _shake_tw: Tween = null

# 그리기 전용 자식 — StaticBody도 _draw가 있지만, 흔들림 오프셋을 아트에만 주려고 분리한다.
class _CoverArt extends Node2D:
	var host: Object = null
	func _draw() -> void:
		if host != null and host.has_method("_render_art"):
			host.call("_render_art", self)

func setup(w: float, h: float, hp: int) -> void:
	_w = maxf(w, 32.0)
	_h = maxf(h, 32.0)
	_max_hp = maxi(hp, 1)
	_hp = _max_hp
	collision_layer = 1   # 월드 — 플레이어·적탄·플레이어탄(모두 mask 1)이 충돌
	collision_mask = 0
	_build_collision()
	_build_art()

func _build_collision() -> void:
	_col = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(_w, _h)
	_col.shape = shape
	_col.position = Vector2(0.0, -_h * 0.5)  # origin=바닥 접점, 위로 _h 뻗음
	add_child(_col)

func _build_art() -> void:
	_art = _CoverArt.new()
	_art.host = self
	add_child(_art)

func _hp_ratio() -> float:
	return float(_hp) / float(_max_hp)

# EnemyBullet이 StaticBody 충돌 시 호출 — 데미지 1 + 균열/흔들림, 0에서 파괴.
func hit_by_bullet() -> void:
	if _dead:
		return
	_hp -= 1
	SfxPlayer.play_at("bullet_impact_wall", global_position)
	if _art != null:
		_art.queue_redraw()
		# 짧은 피격 흔들림(아트만).
		if _shake_tw != null and _shake_tw.is_valid():
			_shake_tw.kill()
		_art.position = Vector2(3.0, 0.0)
		_shake_tw = _art.create_tween()
		_shake_tw.tween_property(_art, "position", Vector2.ZERO, 0.12)
	if _hp <= 0:
		_break()

func _break() -> void:
	_dead = true
	# 즉시 차단 해제 — 더는 엄폐/충돌하지 않게. 물리 flush 중 충돌 회피 위해 disabled는 deferred.
	collision_layer = 0
	if _col != null:
		_col.set_deferred("disabled", true)
	SfxPlayer.play_at("enemy_death", global_position)  # 붕괴음(기존 sfx 재사용)
	# 잔해 낙하 페이드 후 제거.
	var tw := create_tween()
	if _art != null:
		tw.tween_property(_art, "modulate:a", 0.0, 0.35)
		tw.parallel().tween_property(_art, "position:y", 12.0, 0.35)
	else:
		tw.tween_interval(0.35)
	tw.tween_callback(queue_free)

# _CoverArt._draw에서 호출 — 차량 아트 + 피해 균열.
func _render_art(art: Node2D) -> void:
	var hw: float = _w * 0.5
	var ratio: float = _hp_ratio()
	# 본체(피해로 어두워짐)
	var body_col: Color = COL_BODY.darkened((1.0 - ratio) * 0.35)
	art.draw_rect(Rect2(Vector2(-hw, -_h), Vector2(_w, _h)), body_col)
	# 캐빈 창(가로 스트립)
	var cab_y: float = -_h + _h * 0.20
	art.draw_rect(Rect2(Vector2(-hw + _w * 0.12, cab_y), Vector2(_w * 0.76, _h * 0.26)), COL_CABIN)
	# 상단 앰버 트림 — "엄폐물" 신호
	art.draw_rect(Rect2(Vector2(-hw, -_h), Vector2(_w, 5.0)), COL_TRIM)
	# 바퀴(하단 양쪽)
	art.draw_circle(Vector2(-hw + _w * 0.22, -6.0), 9.0, COL_WHEEL)
	art.draw_circle(Vector2(hw - _w * 0.22, -6.0), 9.0, COL_WHEEL)
	# 테두리
	art.draw_rect(Rect2(Vector2(-hw, -_h), Vector2(_w, _h)), COL_EDGE, false, 1.5)
	# 균열 — 받은 피해 수만큼(결정적: idx로 분산).
	var dmg: int = _max_hp - _hp
	for i in dmg:
		_draw_crack(art, i)

func _draw_crack(art: Node2D, idx: int) -> void:
	var hw: float = _w * 0.5
	# 시작 x를 idx로 분산(양옆으로 번갈아).
	var t: float = float(idx + 1) / float(_max_hp + 1)
	var sx: float = lerp(-hw * 0.62, hw * 0.62, t)
	var pts := PackedVector2Array([
		Vector2(sx, -_h * 0.92),
		Vector2(sx + _w * 0.09, -_h * 0.62),
		Vector2(sx - _w * 0.07, -_h * 0.36),
		Vector2(sx + _w * 0.06, -_h * 0.10),
	])
	art.draw_polyline(pts, COL_CRACK, 1.8, true)
