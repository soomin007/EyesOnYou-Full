class_name DrawnWatcher
extends Node2D

# 구형 렌더 문법의 병사 실루엣 · 잔류 탈출(§3.2) 길가의 배웅 실루엣 전용.
# 2026-09-04 P3 B안 개편으로 FalseVeil._FakeMarker에서 분리(P3의 '가짜' 어휘 전면 폐지 ·
# 본체 통지 경로 삭제). 디더 스캔라인으로 짜인 옛 렌더러풍 병사가 서서 플레이어를 겨눈다.
# 콜리전 없음 · 쏘면 탄이 통과하며 렌더가 찢겼다 재조립(2회면 흩어진다). MapData "fake_watchers".
# "대기열 등록 #N" 라벨과 발사 없는 조준 점선은 스폰/사격 예고로 오독돼 제거(실플레이 2026-08-13).

var lifetime: float = 99999.0
var t: float = 0.0
var erasing: bool = false
var tear_hits: int = 0           # 탄 통과 누적 · 2회면 그림이 못 버티고 흩어진다
var _erase_t: float = 0.0
var _slip_burst_t: float = 0.0   # 탄 통과 순간의 찢김(회복되는 약한 tear)
var _aim_to: Vector2 = Vector2.ZERO

func _ready() -> void:
	z_index = 6

func _process(delta: float) -> void:
	t += delta
	_slip_burst_t = maxf(0.0, _slip_burst_t - delta)
	if erasing:
		_erase_t += delta
		if _erase_t > 0.4:
			queue_free()
			return
	elif t >= lifetime:
		erase()
	var tree := get_tree()
	if tree != null:
		# 겨누는 척 · 실루엣이 플레이어를 계속 향한다(발사는 없다).
		var arr := tree.get_nodes_in_group("player")
		if arr.size() > 0:
			_aim_to = (arr[0] as Node2D).global_position - global_position
		# 탄이 실루엣을 지나가면 렌더가 찢겼다 재조립 · "쏘면 뚫리는 그림"을 즉석에서 학습.
		if not erasing and _slip_burst_t <= 0.0:
			for b in tree.get_nodes_in_group("player_bullet"):
				if b is Node2D:
					var lp: Vector2 = (b as Node2D).global_position - global_position
					if absf(lp.x) < 26.0 and lp.y > -60.0 and lp.y < 6.0:
						_slip_burst_t = 0.32
						tear_hits += 1
						if tear_hits >= 2:
							erase()
						break
	queue_redraw()

func erase() -> void:
	if erasing:
		return
	erasing = true
	_erase_t = 0.0

func _draw() -> void:
	var appear: float = clampf(t / 0.3, 0.0, 1.0)
	var a: float = appear
	if erasing:
		a = maxf(0.0, 1.0 - _erase_t / 0.4)
	var vi := Color(0.82, 0.58, 1.0, 0.9 * a)
	# 글리치 슬립 · 드물게(1.7s 주기) 한순간 실루엣이 옆으로 밀린다(구형 렌더의 미끄러짐).
	var slip: float = 3.0 if fmod(t, 1.7) < 0.1 else 0.0
	# 소멸 = 슬라이스 흩어짐 / 탄 통과 = 같은 문법의 약한 찢김(회복됨).
	var tear: float = 0.0
	if erasing:
		tear = _erase_t / 0.4
	elif _slip_burst_t > 0.0:
		tear = 0.35 * (_slip_burst_t / 0.32)
	# ① 병사 실루엣(발 기준, 높이 ~52) · 2px 가로 스트립 디더(CRT 짜임).
	var seg_defs: Array = [
		{"y0": -52.0, "y1": -40.0, "hw": 6.0},    # 머리
		{"y0": -40.0, "y1": -16.0, "hw": 9.0},    # 몸통
		{"y0": -16.0, "y1": 0.0, "hw": 7.0},      # 다리
	]
	for sd_raw in seg_defs:
		var sd: Dictionary = sd_raw
		var y: float = float(sd.get("y0", 0.0))
		var y1: float = float(sd.get("y1", 0.0))
		var hw: float = float(sd.get("hw", 6.0))
		while y < y1:
			var band_off: float = slip + tear * (24.0 if fmod(y, 8.0) < 4.0 else -24.0)
			draw_rect(Rect2(Vector2(-hw + band_off, y), Vector2(hw * 2.0, 2.0)),
				Color(vi.r, vi.g, vi.b, 0.55 * a), true)
			y += 4.0
	# 팔(총 든 자세) · 조준 방향으로 뻗은 짧은 스트립(발사는 없다 · 긴 조준선은 제거).
	var aim_dir: Vector2 = _aim_to.normalized() if _aim_to.length() > 1.0 else Vector2.RIGHT
	var shoulder := Vector2(0.0, -32.0)
	draw_line(shoulder, shoulder + aim_dir * 14.0, Color(vi.r, vi.g, vi.b, 0.55 * a), 3.0)
	# ② 표적 브래킷(굵음 = 구형 문법) · 실루엣을 감싼다.
	var bw: float = 22.0
	var top: float = -58.0
	var arm: float = 10.0
	for corner in [Vector2(-bw, top), Vector2(bw, top), Vector2(-bw, 0.0), Vector2(bw, 0.0)]:
		var c: Vector2 = corner
		var sx: float = -1.0 if c.x > 0.0 else 1.0
		var sy: float = 1.0 if c.y < -20.0 else -1.0
		draw_line(c, c + Vector2(sx * arm, 0.0), vi, 4.0)
		draw_line(c, c + Vector2(0.0, sy * arm), vi, 4.0)
	# ③ 스캔라인 스윕 + 깜빡이는 커서(1.6Hz 소면적 · 광과민성 기준 내).
	var scan: float = fmod(t, 1.4) / 1.4
	var sy2: float = lerpf(top + 4.0, -4.0, scan)
	draw_line(Vector2(-bw + 3.0, sy2), Vector2(bw - 3.0, sy2), Color(vi.r, vi.g, vi.b, 0.40 * a), 1.5)
	if fmod(t, 0.62) < 0.34:
		draw_line(Vector2(-8.0, 10.0), Vector2(8.0, 10.0), vi, 3.0)
