class_name WaterLevel
extends Node2D

# 하수도 시그니처 해저드 · 수위 변화(map_identity_rework §5 "하수도 = 수위 변화", 2026-08-17).
# 정체성: 옛 배수로의 펌프가 아직 살아 있어 오수가 주기적으로 차오른다. 수면 아래 완전히
# 잠기면 부식 피해 틱 · 높은 발판/상층으로 대피하는 수직 stop-and-go 리듬(빔 니치의 수평
# 리듬·열차의 순간 회피와 다른 "느린 호흡" 문법).
# 공정성: 수면 상승 자체가 긴 텔레그래프(2초+ 눈에 보이는 상승) + 상승 시작 배수음.
# 잠긴 채 강행 돌파도 선택지(피해 감수 = 리스크 교환). 광과민 기준 준수(점멸 없음,
# 수면 물결은 완만한 사인 1개).
#
# 사용: MapData "water_level" = {low_y, high_y, rise?, hold_high?, fall?, hold_low?,
#   dmg?, dmg_interval?, start_delay?}. y는 월드 좌표(작을수록 높음). low_y를 바닥 아래로
#   두면 물이 완전히 빠진 상태가 존재한다.

enum S { LOW, RISING, HIGH, FALLING }

var low_y: float = 800.0
var high_y: float = 500.0
var rise_dur: float = 2.4
var hold_high: float = 4.0
var fall_dur: float = 2.0
var hold_low: float = 6.0
var dmg: int = 1
var dmg_interval: float = 1.6
var world_w: float = 2200.0
var world_h: float = 720.0

var surface_y: float = 800.0
var _state: int = S.LOW
var _t: float = 0.0
var _sub_t: float = -1.0        # 잠수 경과(-1 = 물 밖) · 유예 0.9s 후 dmg_interval마다 틱
var _wave_t: float = 0.0

func setup(cfg: Dictionary, w: float, h: float) -> void:
	low_y = float(cfg.get("low_y", low_y))
	high_y = float(cfg.get("high_y", high_y))
	rise_dur = float(cfg.get("rise", rise_dur))
	hold_high = float(cfg.get("hold_high", hold_high))
	fall_dur = float(cfg.get("fall", fall_dur))
	hold_low = float(cfg.get("hold_low", hold_low))
	dmg = int(cfg.get("dmg", dmg))
	dmg_interval = float(cfg.get("dmg_interval", dmg_interval))
	world_w = w
	world_h = h
	surface_y = low_y
	# 첫 상승은 이르게 · 기믹을 초반에 한 번 보여준다(열차 첫 조우와 동형).
	_t = hold_low - float(cfg.get("start_delay", 2.6))
	z_index = 5   # 반투명 수체 · 잠긴 대상이 물 너머로 보이는 게 정보(가림이 아니라 상태 표시)
	add_to_group("water_level")

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t += delta
	_wave_t += delta
	match _state:
		S.LOW:
			surface_y = low_y
			if _t >= hold_low:
				_state = S.RISING
				_t = 0.0
				SfxPlayer.play("drop_platform_descend", -6.0)
		S.RISING:
			surface_y = lerpf(low_y, high_y, minf(1.0, _t / rise_dur))
			if _t >= rise_dur:
				_state = S.HIGH
				_t = 0.0
		S.HIGH:
			surface_y = high_y
			if _t >= hold_high:
				_state = S.FALLING
				_t = 0.0
		S.FALLING:
			surface_y = lerpf(high_y, low_y, minf(1.0, _t / fall_dur))
			if _t >= fall_dur:
				_state = S.LOW
				_t = 0.0
	_check_player(delta)
	queue_redraw()

func _check_player(delta: float) -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D):
		return
	if bool(p.get("clear_protect")):
		_sub_t = -1.0
		return
	# 완전 잠수 판정 · 발 기준점이 수면보다 24px 아래(머리까지 잠김)일 때만.
	if (p as Node2D).global_position.y > surface_y + 24.0:
		if _sub_t < 0.0:
			_sub_t = 0.0
			return
		var before: float = _sub_t
		_sub_t += delta
		# 유예 0.9s 후 dmg_interval마다 1틱(스치는 입수는 무피해 · 체류가 피해).
		var k0: int = int(floor((before - 0.9) / dmg_interval))
		var k1: int = int(floor((_sub_t - 0.9) / dmg_interval))
		if _sub_t >= 0.9 and k1 > k0:
			if p.has_method("take_hit"):
				p.call("take_hit", dmg)
			SfxPlayer.play_at("spike_hit", (p as Node2D).global_position, -4.0)
	else:
		_sub_t = -1.0

func _draw() -> void:
	if surface_y >= world_h + 200.0:
		return
	var bob: float = sin(_wave_t * 1.3) * 3.0   # 완만한 수면 물결(점멸 아님)
	var top: float = surface_y + bob
	# 수체 · 수면부터 월드 바닥까지 반투명 오수 톤(어두운 배경에서도 잠김이 읽히는 대비).
	draw_rect(Rect2(Vector2(-200.0, top), Vector2(world_w + 400.0, world_h - top + 300.0)),
		Color(0.14, 0.38, 0.34, 0.42))
	# 수면 직하 어두운 띠 · 깊이감 + 경계 강조.
	draw_rect(Rect2(Vector2(-200.0, top), Vector2(world_w + 400.0, 12.0)), Color(0.10, 0.28, 0.25, 0.5))
	# 수면 라인 + 밝은 하이라이트(수직 맵 비네트 위에서도 읽히는 대비).
	draw_rect(Rect2(Vector2(-200.0, top - 10.0), Vector2(world_w + 400.0, 6.0)), Color(0.55, 0.90, 0.80, 0.22))
	draw_rect(Rect2(Vector2(-200.0, top - 4.0), Vector2(world_w + 400.0, 4.0)), Color(0.60, 0.95, 0.85, 0.9))
	# 상승 중 표면 거품 점 · 상승 중임이 수면만 봐도 읽히게.
	if _state == S.RISING:
		var n: int = int(world_w / 240.0)
		for i in n:
			var fx: float = 120.0 + float(i) * 240.0 + fmod(_wave_t * 60.0, 240.0)
			draw_circle(Vector2(fx, top - 6.0), 2.5, Color(0.75, 0.92, 0.85, 0.5))
