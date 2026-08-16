class_name MapData
extends RefCounted

# 25개 맵의 세계 형태 + platform/적 spawn/보상/함정 통합 명세.
# 명세: docs/design/world_layout.md
# (A2 신규(2026-06-25): 막1 parking_lot/demolition_zone/pump_station/perimeter, 막2 substation/
#  testing_grounds/relay_station/warehouse/checkpoint/condenser/gauntlet, 막3 전투 control_corridor.)
#
# 각 layout 반환 구조:
#   "world_type":   String  ("HORIZONTAL" / "VERTICAL_UP" / "VERTICAL_DOWN" / "ARENA")
#   "world_size":   Vector2
#   "player_start": Vector2
#   "goal_type":    String  ("POSITION" / "ENEMY_CLEAR" / "SEQUENCE")
#   "goal_pos":     Vector2 (goal_type == POSITION일 때만 의미)
#   "camera_mode":  String  ("HORIZONTAL" / "VERTICAL" / "FIXED")
#   "platforms":    Array of {"pos": Vector2, "w": float}
#   "enemies":      Dictionary of {kind: Array of Vector2}
#   "rewards":      Dictionary of {"xp_orbs": Array of Vector2, "hp_pickups": Array of Vector2}
#   "spikes":       Array of {"x": float, "y": float}  (y 생략 가능)
#   "waves":        Array of wave configs (ARENA 전용, 선택)
#   "boss":         Dictionary (lab 전용 — boss 행동 명세, 선택)
#   "easter_egg":   Dictionary (ward 전용 — 잠긴 문 트리거)

const GROUND_Y_DEFAULT: float = 600.0

# 방 체인(map_identity_rework §2) · 라우트 layout이 "segments" 배열을 가지면 한 스테이지가
# 방 여러 개로 구성된다. GameState.current_segment가 가리키는 방의 layout을 돌려주고,
# segment_index/segment_count 메타를 얹는다(Stage가 골 도달 시 다음 방 전환 판단에 사용).
# 호출처(Stage 전역 다수)는 수정 없이 현재 방 기준으로 동작한다.
static func get_layout(route_id: String) -> Dictionary:
	var data: Dictionary = _layout_raw(route_id)
	var segs: Array = data.get("segments", [])
	if segs.is_empty():
		return data
	var idx: int = clampi(GameState.current_segment, 0, segs.size() - 1)
	var seg: Dictionary = segs[idx]
	var out: Dictionary = seg.duplicate()
	out["segment_index"] = idx
	out["segment_count"] = segs.size()
	return out

static func _layout_raw(route_id: String) -> Dictionary:
	match route_id:
		"route_back_alley": return _back_alley()
		"route_rooftops":   return _rooftops()
		"route_sewers":     return _sewers()
		"route_subway":     return _subway()
		"route_cooling":    return _cooling()
		"route_watchtower": return _watchtower()
		"route_ward":       return _ward()
		"route_datacenter": return _datacenter()
		"route_escape":     return _escape()
		"route_escape_extract": return _escape_extract()
		"route_escape_destroy": return _escape_destroy()
		"route_escape_conceal": return _escape_conceal()
		"route_escape_leave":   return _escape_leave()
		"route_lab":        return _lab()
		"route_core_recovery": return _core_recovery()
		"route_hidden":     return _hidden()
		"route_blackout":   return _blackout()
		"route_server_hall": return _server_hall()
		"route_parking_lot": return _parking_lot()
		"route_substation":  return _substation()
		"route_testing_grounds": return _testing_grounds()
		"route_demolition_zone": return _demolition_zone()
		"route_pump_station":  return _pump_station()
		"route_relay_station": return _relay_station()
		"route_warehouse":     return _warehouse()
		"route_checkpoint":    return _checkpoint()
		"route_control_corridor": return _control_corridor()
		"route_condenser":     return _condenser()
		"route_perimeter":     return _perimeter()
		"route_gauntlet":      return _gauntlet()
		"route_freight_lift":  return _freight_lift()
		"route_car_cover":     return _car_cover()
		"route_collapse":      return _collapse()
		"route_core_defense":  return _core_defense()
		"route_scanner_sweep": return _scanner_sweep()
		"route_holdout":       return _holdout()
	return {}

# ─── 1. 외곽 진입로 (HORIZONTAL, 짧음) ─────────────────────────
static func _back_alley() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2800.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			{"pos": Vector2(400, 520),  "w": 160.0},
			{"pos": Vector2(700, 460),  "w": 160.0},
			{"pos": Vector2(1100, 520), "w": 180.0},
			{"pos": Vector2(1500, 460), "w": 160.0},
			{"pos": Vector2(1900, 520), "w": 180.0},
			{"pos": Vector2(2300, 460), "w": 160.0},
		],
		"enemies": {
			"patrol": [Vector2(600, 600.0), Vector2(1300, 600.0), Vector2(2100, 600.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"rewards": {"xp_orbs": [], "hp_pickups": []},
		"spikes": [],
	}

# ─── 2. 외벽 옥상 (VERTICAL_UP) — 옥상답게 + 비밀 통로 ────────
# 점프 파라미터: 1단 ~104px / 2단 ~190px.
# "옥상답게" — 좁은 발판 zigzag 사다리 → 넓은 옥상 슬랩(roof slab) + 그 사이를 잇는
# 비상사다리/HVAC/안테나 형태의 좁은 step. 발판 종류로 옥상 구조 모사.
# 사용자 피드백: "외벽 옥상도 점프 노가다 심함, 드론은 초반이라 부담스럽다"
# → 발판 25 → 22로 줄이고, 비밀 통로 추가, 드론 제거.
static func _rooftops() -> Dictionary:
	return {
		"world_type":   "VERTICAL_UP",
		"world_size":   Vector2(1280.0, 2500.0),
		"player_start": Vector2(640.0, 2350.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(640.0, 200.0),
		"camera_mode":  "VERTICAL",
		"platforms": [
			# 점프 등급: S = 단순점프(Δ≤95), D = 더블점프 여유(Δ~130). Δ160(빠듯) 없음.
			# 2026-06-24 2차: "등반이 길고 발판이 많다" 피드백 → 맵 높이 압축(상승 2850→2150, 발판 솎음).
			# 지상(2350) → 저층 옥상(2125)
			{"pos": Vector2(560, 2255), "w": 220.0},  # Δ95 (S) 비상사다리
			{"pos": Vector2(640, 2125), "w": 480.0},  # Δ130 (D) — ROOF 1 (저층 옥상, patrol)

			# R1 → 중층 옥상(1905)
			{"pos": Vector2(440, 1995), "w": 180.0},  # Δ130 (D) HVAC 박스
			{"pos": Vector2(640, 1905), "w": 440.0},  # Δ90 (S) — ROOF 2 (중층 옥상)

			# R2 → 분기 옥상(1685)
			{"pos": Vector2(820, 1775), "w": 180.0},  # Δ130 (D) 스카이라이트
			{"pos": Vector2(640, 1685), "w": 520.0},  # Δ90 (S) — ROOF 3 (분기점, patrol)

			# 비밀 통로 — ROOF 3에서 우측 더블점프 → 안테나 → 비밀 옥상. XP 2 + HP 1 보너스.
			{"pos": Vector2(1130, 1765), "w": 100.0}, # 안테나 발판
			{"pos": Vector2(1180, 1865), "w": 140.0}, # 비밀 옥상 끝 — XP 2 + HP 1

			# 분기 우측(XP)
			{"pos": Vector2(940, 1555), "w": 200.0},  # Δ130 (D)
			{"pos": Vector2(1060, 1465), "w": 180.0}, # Δ90 (S) — XP 끝

			# 분기 좌측(HP)
			{"pos": Vector2(340, 1555), "w": 200.0},  # Δ130 (D)
			{"pos": Vector2(220, 1465), "w": 180.0},  # Δ90 (S) — HP 끝

			# 합류
			{"pos": Vector2(560, 1335), "w": 440.0},  # Δ130 (D) — ROOF 4 합류

			# 상층 — sniper post 2개 + 슬랩. S/D 리듬.
			{"pos": Vector2(720, 1205), "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(620, 1115), "w": 400.0},  # Δ90 (S) — ROOF 5 (sniper post 1)
			{"pos": Vector2(760, 985),  "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(640, 895),  "w": 360.0},  # Δ90 (S) — 슬랩
			{"pos": Vector2(540, 765),  "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(640, 675),  "w": 400.0},  # Δ90 (S) — ROOF 6 (sniper post 2, HP 보상)
			{"pos": Vector2(540, 545),  "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(640, 455),  "w": 360.0},  # Δ90 (S) — 슬랩
			{"pos": Vector2(560, 325),  "w": 240.0},  # Δ130 (D) — 골 직전 (→ goal 200, Δ125)

			# 저격 둥지 — 메인 경로 밖 측면 단독 발판(올라설 필요 없음, 회피 전용).
			{"pos": Vector2(1150, 1065), "w": 64.0},  # 둥지(중상층) — 우측 (ROOF 5 근처). +20 올림: 앞 발판서 서서 쏘면 발밑 통과(빗맞음)
			{"pos": Vector2(130, 625),   "w": 64.0},  # 둥지(상층) — 좌측 (ROOF 6 근처). +20 올림: 총구선이 저격수 발밑을 지나 애매하게 안 맞음
		],
		# 저격수가 전부 측면 단독 둥지(회피 전용) — VEIL "못 잡는 적 안내"(_tick_avoid_warning)가 이 플래그로 발화.
		"nest_snipers": true,
		"enemies": {
			# stage 0~1 등장 — 드론 제거. 저격수는 메인 옥상 발판이 아닌 측면 단독 둥지에서 사선 확보
			# (사용자 피드백: patrol과 같은 평범한 발판에 섞이지 않게). 엇갈린 좌/우.
			"patrol": [Vector2(640, 2095.0), Vector2(640, 1655.0), Vector2(560, 1305.0)],
			"sniper": [
				Vector2(1150, 1037.0),  # 둥지(중상층, ROOF 5 근처) — 발판과 함께 +20 올림
				Vector2(130, 597.0),    # 둥지(상층, ROOF 6 근처) — 발판과 함께 +20 올림
			],
			"drone":  [],
			"bomber": [], "shield": [],
		},
		"rewards": {
			# 일반 분기 — 우측 XP 2, 좌측 HP 1
			# 비밀 옥상 — XP 2 + HP 1 보너스
			# 상층 sniper post — ROOF 5에 XP 2(보너스), ROOF 6에 HP 1(보스 보충)
			"xp_orbs":    [
				Vector2(1040, 1435.0), Vector2(1080, 1435.0),   # 분기 우 XP 끝(1465) 위
				Vector2(1160, 1835.0), Vector2(1200, 1835.0),   # 비밀 옥상(1865) 위
				Vector2(620, 1085.0), Vector2(660, 1085.0),     # ROOF 5(1115) 보너스
			],
			# 글라이드 게이트 없음 — stage 0 맵이라 글라이드 미보유.
			"hp_pickups": [
				Vector2(220, 1435.0),    # 분기 좌 HP 끝(1465) 위
				Vector2(1180, 1835.0),   # 비밀 옥상
				Vector2(640, 645.0),     # ROOF 6(675) 보충
			],
		},
		"spikes": [],
	}

# ─── 3. 지하 인입로 (VERTICAL_DOWN) ───────────────────────────
# 위에서 아래로 내려감 — 분기 좌(적 많음/XP) vs 우(가시 함정/HP)
# 가시는 우측 통로의 다른 y에 분산 배치 (이전엔 spike y 버그로 모두 GROUND_Y에 겹침)
static func _sewers() -> Dictionary:
	return {
		"world_type":   "VERTICAL_DOWN",
		"world_size":   Vector2(1280.0, 2400.0),
		"player_start": Vector2(640.0, 160.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(640.0, 2250.0),
		"camera_mode":  "VERTICAL",
		"platforms": [
			# 진입 → 상층 (낙하)
			{"pos": Vector2(560, 280), "w": 200.0},
			{"pos": Vector2(560, 460), "w": 160.0},
			{"pos": Vector2(480, 640), "w": 240.0},  # 분기점
			# 좌측 — 넓은 통로 (적 + XP)
			{"pos": Vector2(280, 800),  "w": 220.0},
			{"pos": Vector2(200, 960),  "w": 220.0},
			{"pos": Vector2(260, 1120), "w": 220.0},
			{"pos": Vector2(200, 1280), "w": 240.0},
			# 우측 — 좁은 파이프 (가시 + HP). 발판 폭 80으로 좁힘 — 가시
			# 사이 통과를 빠듯하게 만들어 위협을 의미있게.
			{"pos": Vector2(960, 800),  "w": 80.0},
			{"pos": Vector2(960, 960),  "w": 80.0},
			{"pos": Vector2(960, 1120), "w": 80.0},
			{"pos": Vector2(960, 1280), "w": 120.0},  # 끝 — 안전
			# 중앙 낙하 캐치 — 분기 사이(좌 x170~390 / 우 x920~1000)의 빈 중앙으로 떨어져도
			# 맨 밑까지 추락하지 않게(사용자 보고). 한 번에 ~3칸 이상 못 떨어지도록 보강.
			# 보상 높이(y1240)에 닿아 좌우 분기로 복귀 가능.
			{"pos": Vector2(640, 1000), "w": 160.0},
			{"pos": Vector2(640, 1240), "w": 160.0},
			# 합류
			{"pos": Vector2(580, 1440), "w": 240.0},
			{"pos": Vector2(480, 1620), "w": 220.0},
			{"pos": Vector2(580, 1800), "w": 240.0},  # 하층 - bomber 자리
			# 하층 → 바닥
			{"pos": Vector2(480, 1980), "w": 220.0},
			{"pos": Vector2(580, 2160), "w": 280.0},  # 골 직전
		],
		"enemies": {
			# 좌측 통로 patrol — 발판 위 (y = platform y - 30 ≈ 발판 위 서있는 위치)
			"patrol": [Vector2(280, 770.0), Vector2(200, 930.0), Vector2(260, 1090.0)],
			"sniper": [],
			"drone":  [],
			# bomber: 합류점 직후 좁은 통로 압박
			"bomber": [Vector2(480, 1410.0), Vector2(580, 1770.0), Vector2(480, 1950.0)],
			"shield": [],
		},
		"rewards": {
			# 좌측 (patrol+XP 통로) — XP 2개. patrol 처치 XP가 추가로 붙음.
			"xp_orbs": [
				Vector2(200, 1240.0), Vector2(240, 1240.0),
				# 우측 (가시+위험) 끝 — XP 3개 + HP. 가시 dmg 2를 감수한 만큼
				# patrol 통로보다 의미있게 큰 보상.
				Vector2(940, 1240.0), Vector2(980, 1240.0), Vector2(1020, 1240.0),
			],
			"hp_pickups": [Vector2(960, 1240.0)],
		},
		# 가시 — 사용자 피드백 "누가 가시를 매달아놓냐"로 mid-air 배치 폐지.
		# 모든 가시는 발판 위(base_y = platform.y - 12)에 일부 폭만 차지.
		# 안전 착지 영역과 가시 영역이 좌우로 나뉘어 정밀 점프 요구.
		"spikes": [
			# 분기점 발판(480, 640, w=240) 좌측 절반 — 분기 결정 전 위협.
			{"x": 400.0, "y": 628.0, "w": 60.0},
			# 좌측 끝 발판(200, 1280, w=240) 좌측 — patrol 통로 끝 위협. 우측 안전.
			{"x": 140.0, "y": 1268.0, "w": 60.0},
			# 합류부(580, 1440, w=240) 좌측 — 양 분기 끝에서 진입 시 위협. dmg 2.
			{"x": 500.0, "y": 1428.0, "w": 60.0, "dmg": 2},
			# 하층 발판(580, 1800, w=240) 좌측 — bomber 자리와 함께 압박. dmg 2.
			{"x": 500.0, "y": 1788.0, "w": 60.0, "dmg": 2},
			# 골 직전 발판(580, 2160, w=280) 좌측 — 마지막 함정. dmg 2.
			{"x": 480.0, "y": 2148.0, "w": 80.0, "dmg": 2},
		],
	}

# ─── 4. 폐쇄 지하철 · **노선 체인 3방**(map_identity_rework §4, 2026-08-16 재설계) ─────
# 정체성 = "SILO-7이 덮어쓴 폐역"(캐논). 지하철에서만 가능한 것 = 열차와 선로:
# 방1 승강장(전투·개찰 잔해) → 방2 선로(무인 화물 열차 해저드 = 시그니처) → 방3 환승홀
# (정차 차량 지붕 + 하향 포탑 + 트립와이어 = 원 지하철 전투 문법 압축). 낮은 천장(480) 유지.
# 원 맵의 "끝 ~1000px 공백"(7/2 정리 잔재)은 체인 재구성으로 해소.
static func _subway() -> Dictionary:
	return {"segments": [_subway_platform(), _subway_tracks(), _subway_transfer()]}

# 방1 · 승강장. 폐역 홀 전투: 개찰 잔해 허들 + 경비. 승강장 단(낮은 발판)이 지형.
static func _subway_platform() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2000.0, 480.0),
		"player_start": Vector2(140.0, 380.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(1900.0, 380.0),
		"camera_mode":  "HORIZONTAL",
		"ground_y":     420.0,
		"ambience":     "subway_platform",
		"indoor_env":   "interior",
		"platforms": [
			{"pos": Vector2(700, 340),  "w": 260.0},   # 승강장 단
			{"pos": Vector2(1350, 340), "w": 260.0},
		],
		"hurdles": [
			{"x": 520.0,  "w": 40.0, "h": 70.0},   # 개찰구 잔해
			{"x": 1120.0, "w": 40.0, "h": 70.0},
		],
		"enemies": {
			"patrol": [Vector2(650, 420.0), Vector2(1500, 420.0)],
			"sniper": [], "drone": [], "bomber": [],
			"shield": [Vector2(1000, 420.0)],
		},
		"rewards": {"xp_orbs": [Vector2(1330, 310.0), Vector2(1370, 310.0)], "hp_pickups": []},
		"spikes": [],
	}

# 방2 · 선로. 시그니처 = 무인 화물 열차(TrainHazard): 신호등 적색 전환(2.2s 예고) 후 고속 통과,
# 대뎀 2 + 넉백(즉사 아님, 사용자 확정). 대피 = 벽감(cover_niches) / 승강장 조각 단차 / 타이밍 점프.
static func _subway_tracks() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3000.0, 480.0),
		"player_start": Vector2(140.0, 380.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2880.0, 380.0),
		"camera_mode":  "HORIZONTAL",
		"ground_y":     420.0,
		"ambience":     "subway_tracks",
		"indoor_env":   "interior",
		"train_hazard": {"interval": 8.5, "telegraph": 2.2, "speed": 2400.0, "dmg": 2, "lights": [500.0, 1300.0, 2100.0, 2800.0]},
		"cover_niches": [650.0, 1350.0, 2050.0, 2700.0],
		"niche_half":   90.0,
		"platforms": [
			# 승강장 조각 단차 · 열차 대역(바닥 위 130px) 밖 = 세이프.
			{"pos": Vector2(950, 270),  "w": 220.0},
			{"pos": Vector2(2400, 270), "w": 220.0},
		],
		"enemies": {
			"patrol": [Vector2(1700, 420.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"route_lines": [
			{"x": 260.0, "who": "veil", "text": "선로가 아직 살아 있어요. 신호가 붉어지면 열차입니다. 벽감이나 단 위로.", "dur": 3.6},
		],
		"rewards": {
			# 위험 보상 · 벽감 사이 선로 위(열차 리스크를 지나야 먹는다).
			"xp_orbs":    [Vector2(1000, 390.0), Vector2(1750, 390.0), Vector2(2450, 390.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		# 자동 가시 폴백 차단 · 열차+벽감 리듬이 시그니처라 가시 소음 금지(벽감 옆 가시 오염 방지).
		"no_spike_fallback": true,
	}

# 방3 · 환승홀. 원 지하철의 전투 문법 압축: 정차 차량 지붕 + 하향 포탑 + 트립와이어.
static func _subway_transfer() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2600.0, 480.0),
		"player_start": Vector2(140.0, 380.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2480.0, 380.0),
		"camera_mode":  "HORIZONTAL",
		"ground_y":     420.0,
		"ambience":     "subway_transfer",
		"indoor_env":   "interior",
		"platforms": [
			# 정차 차량 지붕 2량 + 진입 발판 + 지면 잔해
			{"pos": Vector2(600, 220),  "w": 700.0},
			{"pos": Vector2(1700, 220), "w": 700.0},
			{"pos": Vector2(560, 320),  "w": 60.0},
			{"pos": Vector2(1660, 320), "w": 60.0},
			{"pos": Vector2(1380, 380), "w": 100.0},
		],
		"enemies": {
			"patrol": [Vector2(800, 420.0), Vector2(2000, 420.0)],
			"sniper": [Vector2(900, 200.0)],
			"drone":  [], "bomber": [],
			"shield": [Vector2(1500, 420.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(2000, 200.0), Vector2(2050, 200.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		# 하향 포탑 + 탐지선 · 원 지하철 배치 압축(x1350 레이저 → 앞쪽 1550/1780 일제 발사).
		"traps": [
			{"x": 700,  "y": 238.0, "dir": "down", "interval": 1.6, "phase": 0.0},
			{"x": 1550, "y": 238.0, "dir": "down", "mode": "triggered", "trigger_id": "tw1", "burst": 3},
			{"x": 1780, "y": 238.0, "dir": "down", "mode": "triggered", "trigger_id": "tw1", "burst": 3},
			{"x": 2100, "y": 238.0, "dir": "down", "interval": 1.6, "phase": 0.6},
		],
		"tripwires": [
			{"x": 1350, "y": 235.0, "dir": "down", "len": 200.0, "trigger_id": "tw1", "cooldown": 2.4},
		],
	}

# ─── 5. 냉각 시설 (VERTICAL_UP, 지그재그 파이프 + 비밀 스팟) ──
# 냉각 시설 (HORIZONTAL) — 전면 리뉴얼(2026-06-14). 서사 훅: SILO-7이 서버(=VEIL의 하드웨어)를
# 식히는 냉각 플랜트. 시그니처 해저드 = **증기 분출구(SteamVent)**: 바닥에서 주기적으로 수직 증기가
# 뿜어져 타이밍 보고 지나간다. 드론이 주력(상성=글라이드) → 떠서 증기 넘고 드론 잡는 글라이드 학습 맵.
# 글라이드 게이트는 새 레이아웃이라 *진짜로* 고립(삼단점프=글라이드 T2로만 닿는 알코브).
static func _cooling() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 파이프 발판 — 증기 분출구를 넘거나 드론을 피하는 위치.
			{"pos": Vector2(620, 460),  "w": 180.0},
			{"pos": Vector2(1180, 440), "w": 200.0},  # XP
			{"pos": Vector2(1560, 380), "w": 160.0},
			{"pos": Vector2(1900, 460), "w": 180.0},
			# 글라이드 게이트 — 런치(2120,420) 위 240px 고립 알코브(2120,180). 더블점프(190) 못 닿고
			# 삼단점프(글라이드 T2, ~280)로만. 주변 240px 안에 다른 발판 없음 → 진짜 글라이드 전용.
			{"pos": Vector2(2120, 420), "w": 160.0},  # 게이트 런치
			{"pos": Vector2(2120, 180), "w": 120.0},  # 게이트 알코브 (XP 3)
			{"pos": Vector2(2600, 440), "w": 180.0},
			{"pos": Vector2(2980, 470), "w": 200.0},  # 골 직전
		],
		# 증기 분출구 — 바닥(GROUND_Y)에서 위로 h만큼 주기 분출. phase 생략 시 Stage가 x로 분산(엇갈림).
		"steam_vents": [
			{"x": 380,  "h": 300.0},
			{"x": 900,  "h": 260.0},
			{"x": 1380, "h": 320.0},
			{"x": 1760, "h": 280.0},
			{"x": 2360, "h": 300.0},
			{"x": 2820, "h": 260.0},
		],
		"enemies": {
			"patrol": [Vector2(820, 540.0), Vector2(2500, 540.0)],
			"sniper": [],
			# 드론 — 머리 위 호버(상성=글라이드). 통로 위를 점한다.
			"drone":  [Vector2(1180, 250.0), Vector2(1900, 240.0), Vector2(2700, 260.0)],
			"bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1160, 410.0), Vector2(1200, 410.0), Vector2(2580, 410.0)],
			# 글라이드 게이트 알코브(2120,180) — 흡인 반경 축소(직접 도달 필요). XP 3.
			"gate_orbs":  [Vector2(2095, 158.0), Vector2(2120, 158.0), Vector2(2145, 158.0)],
			"hp_pickups": [Vector2(2980, 440.0)],
		},
		"spikes": [],
	}

# ─── 6. 감시탑 (VERTICAL_UP, 외부/내부 분기 + 비밀 통로) ───────
# 점프 파라미터: 1단 ~104px / 2단 ~190px. 발판 32 → 23으로 단축.
# 외부(저격 노출+XP) / 내부(안전+HP) 분기 + 후방 비밀 통로(보너스). 옥상보다 위협 ↑.
static func _watchtower() -> Dictionary:
	return {
		"world_type":   "VERTICAL_UP",
		"world_size":   Vector2(1280.0, 2500.0),
		"player_start": Vector2(640.0, 2350.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(640.0, 200.0),
		"camera_mode":  "VERTICAL",
		"platforms": [
			# 점프 등급: S=단순점프(Δ≤95), D=더블점프 여유(Δ~130). Δ160/180(빠듯) 제거.
			# 2026-06-24: rooftops와 동일 기준 + 높이 압축(상승 2850→2150). 글라이드 게이트만 의도적 Δ220 유지.
			# 지상(2350) → 분기점(2125)
			{"pos": Vector2(560, 2255), "w": 280.0},  # Δ95 (S)
			{"pos": Vector2(640, 2125), "w": 360.0},  # Δ130 (D) — 분기점, patrol 자리

			# (구 좌하단 "비밀 통로" 발판 2개 제거 — 지면 바로 위(Δ~45)에 떠 있어 등반 맵의
			#  수직 문법과 어긋나고 "어색하다"는 실플레이 지적(2026-08-15). 보상도 함께 제거.)

			# 분기 — 외부 노출 (좌측, sniper 노출 + XP)
			{"pos": Vector2(300, 1995), "w": 220.0},  # Δ130 (D)
			{"pos": Vector2(200, 1905), "w": 200.0},  # Δ90 (S)
			{"pos": Vector2(300, 1775), "w": 220.0},  # Δ130 (D) — patrol 자리
			{"pos": Vector2(200, 1685), "w": 220.0},  # Δ90 (S) — 외부 끝 (XP)

			# 분기 — 내부 계단 (중앙)
			{"pos": Vector2(540, 1995), "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(660, 1905), "w": 240.0},  # Δ90 (S)
			{"pos": Vector2(540, 1775), "w": 240.0},  # Δ130 (D) — patrol 자리
			{"pos": Vector2(640, 1685), "w": 280.0},  # Δ90 (S) — 내부 끝 (HP)

			# 합류
			{"pos": Vector2(560, 1555), "w": 320.0},  # Δ130 (D) — 합류

			# 상층 — sniper post 2개 + 슬랩
			{"pos": Vector2(720, 1425), "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(640, 1335), "w": 400.0},  # Δ90 (S) — 정찰단 (sniper post 1)
			# (구 글라이드 게이트 제거 — 압축 상층에서 인접 슬랩과 같은 높이라 글라이드 전용 격리가
			#  안 됨. 보상은 슬랩 위 일반 XP로. 제대로 된 글라이드 게이트는 전용 맵(cooling)에 둔다.)
			{"pos": Vector2(540, 1205), "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(680, 1115), "w": 240.0},  # Δ90 (S) — 슬랩
			{"pos": Vector2(560, 985),  "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(640, 895),  "w": 400.0},  # Δ90 (S) — 정상 정찰단 (sniper post 2, HP)
			{"pos": Vector2(540, 765),  "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(640, 675),  "w": 360.0},  # Δ90 (S) — 슬랩
			{"pos": Vector2(560, 545),  "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(620, 415),  "w": 240.0},  # Δ130 (D)
			{"pos": Vector2(620, 325),  "w": 320.0},  # Δ90 (S) — 골 직전 (→ goal 200, Δ125)

			# 저격 둥지 — 메인 경로 밖 측면 단독 발판(엇갈린 좌/우, 올라설 필요 없음).
			{"pos": Vector2(1150, 1900), "w": 64.0},  # 둥지(하중층) — 우측
			{"pos": Vector2(120, 1000),  "w": 64.0},  # 둥지(중층) — 좌측
			{"pos": Vector2(1150, 700),  "w": 64.0},  # 둥지(상층) — 우측
		],
		# 저격수가 전부 측면 단독 둥지(회피 전용) — VEIL "못 잡는 적 안내"(_tick_avoid_warning)가 이 플래그로 발화.
		"nest_snipers": true,
		"enemies": {
			# 감시탑 = sniper 컨셉. 저격수는 메인 경로 발판이 아닌 측면 단독 둥지에 배치(사용자 피드백:
			# patrol과 같은 평범한 발판에 섞이지 않게). 엇갈린 좌/우라 한 번에 한 명씩 사선에 노출.
			"patrol": [Vector2(700, 2095.0), Vector2(280, 1745.0), Vector2(540, 1745.0)],
			"sniper": [
				Vector2(1150, 1872.0),  # 둥지(하중층)
				Vector2(120, 972.0),    # 둥지(중층)
				Vector2(1150, 672.0),   # 둥지(상층)
			],
			"drone":  [],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			# 외부 끝 XP 2, 내부 끝 HP 1 (좌하단 비밀 보상은 발판과 함께 제거 — 2026-08-15)
			# 상층 sniper post — 중층 XP 2, 정상 HP 1 (감시탑 정상에서 한숨 돌릴 자리)
			"xp_orbs":    [
				Vector2(160, 1655.0), Vector2(200, 1655.0),   # 외부 끝(1685)
				Vector2(620, 1305.0), Vector2(660, 1305.0),   # post1(1335)
				Vector2(660, 1085.0), Vector2(700, 1085.0),   # 상층 슬랩(1115) 보너스
			],
			"gate_orbs":  [],
			"hp_pickups": [
				Vector2(640, 1655.0),   # 내부 끝(1685)
				Vector2(560, 865.0),    # post2(895)
			],
		},
		"spikes": [],
		# 수직 등반 압박 — 벽면 가로 포탑(타이밍 회피 / 글라이드로 지나치기). 가로탄 사거리 ~736px라
		# 등반 경로를 한 높이씩 가로질러 "지나갈 때를 노리는" 라인이 됨.
		# (이전의 합류 직전 트립와이어 + 하향 버스트 포탑은 등반 동선과 어긋나 무효였음 → 제거. 등반
		#  위협은 완화된 둥지 저격수 + 가로 포탑 둘로 단순화. 사용자 피드백 2026-06-11.)
		"traps": [
			# 발판 top이 아니라 **갭(점프 경로) 높이**에 둬 통과 시 몸통을 지나가게(같은 높이면 무해).
			{"x": 1240, "y": 1380.0, "dir": "left",  "interval": 2.0, "phase": 0.0},   # 상층 1425↔1335 갭 가로지름
			{"x": 40,   "y": 1950.0, "dir": "right", "interval": 2.0, "phase": 1.0},   # 분기 1995↔1905 갭 가로지름
		],
	}

# ─── 7. 격리 병동 (HORIZONTAL + 이스터에그 트리거) ──────────────
static func _ward() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(4400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(4320.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 환기구 우회 (y=420)
			{"pos": Vector2(800, 460),  "w": 80.0},
			{"pos": Vector2(860, 420),  "w": 80.0},
			{"pos": Vector2(1000, 420), "w": 280.0},
			{"pos": Vector2(1380, 420), "w": 280.0},
			{"pos": Vector2(1760, 420), "w": 280.0},
			{"pos": Vector2(2140, 420), "w": 280.0},
			{"pos": Vector2(2520, 420), "w": 280.0},
			{"pos": Vector2(2900, 420), "w": 200.0},  # 레버 플랫폼
			# 레버 플랫폼 바로 아래 짧은 발판(2960,440) 제거 — 시각적으로 군더더기(사용자 피드백 2026-06-07).
			{"pos": Vector2(3020, 480), "w": 80.0},
			# 주 통로 장애물 — 이스터에그 문 위치(x=2000)는 시야가 트여야 해서 제외.
			{"pos": Vector2(1200, 560), "w": 120.0},
			{"pos": Vector2(2800, 560), "w": 120.0},
			# 글라이드 게이트 — 우회 발판(1380,420) 위 220px 단독 알코브. 더블점프(apex 230)론
			# 못 닿고 삼단점프(글라이드 T2, apex 150)로만 닿음. 위 보상이 보여 "어떻게 올라가지?" 유도.
			{"pos": Vector2(1380, 200), "w": 90.0},
		],
		"enemies": {
			"patrol": [Vector2(1800, 600.0), Vector2(2800, 600.0)],
			"sniper": [],
			"drone":  [],
			"bomber": [Vector2(3100, 600.0)],
			# 방패병 — 통로 장애물(1200/2000/2800)과 이스터에그 문(2000) 사이의
			# 빈 공간에 배치. 플랫폼/문 뒤에 가려지면 사격이 막혀 매우 불쾌.
			"shield": [Vector2(1500, 600.0), Vector2(2400, 600.0)],
		},
		"rewards": {
			# 글라이드 알코브(1380,200) 위 보상 — 삼단점프/활강으로만 회수(gate_orbs=흡인 반경 축소).
			"xp_orbs":    [],
			"gate_orbs":  [Vector2(1355, 178.0), Vector2(1405, 178.0)],
			"hp_pickups": [Vector2(1800, 400.0)],
		},
		"spikes": [],
		# 우회 발판 밑면 장착 하향 포탑 — 아래 통로로 발사. 타이밍 보고 통과.
		"traps": [
			{"x": 1380, "y": 442.0, "dir": "down", "interval": 1.7, "phase": 0.0},
			{"x": 2140, "y": 442.0, "dir": "down", "interval": 1.7, "phase": 0.85},
		],
		# 잠긴 문 5초 체류 → 이스터에그 방 진입
		"easter_egg": {
			"trigger_x": 2000.0,
			"hold_seconds": 5.0,
			"veil_line": "그쪽은 임무 범위 밖이에요.",
		},
	}

# ─── 8. 데이터 센터 (ARENA, 웨이브) ───────────────────────────
# 지면 → step → mid(서버 랙) → step → 상층(드론) 단계화로 도달성 보장.
# waves 필드가 있으면 Stage._spawn_enemies가 웨이브 모드로 동작 (enemies는 폴백용).
# 웨이브 트리거: w2=w1 절반 처치 후, w3=w2 전원 처치 후. 모두 처치 시 ENEMY_CLEAR.
# 라이벌 VEIL: 최종 웨이브에 재머 1기(막3 s6 확산 — server_hall/control_corridor와 함께).
static func _datacenter() -> Dictionary:
	return {
		"world_type":   "ARENA",
		"world_size":   Vector2(1920.0, 900.0),
		"player_start": Vector2(200.0, 760.0),
		"goal_type":    "ENEMY_CLEAR",
		"goal_pos":     Vector2.ZERO,
		"camera_mode":  "FIXED",
		"ground_y":     820.0,
		"platforms": [
			# Step 발판 (지면 820 → mid 580 도약용, gap 100)
			{"pos": Vector2(150, 720),  "w": 100.0},
			{"pos": Vector2(450, 720),  "w": 100.0},
			{"pos": Vector2(750, 720),  "w": 100.0},
			{"pos": Vector2(1050, 720), "w": 100.0},
			{"pos": Vector2(1350, 720), "w": 100.0},
			{"pos": Vector2(1650, 720), "w": 100.0},
			# 서버 랙 (mid, y=580 — sniper 자리)
			{"pos": Vector2(200, 580),  "w": 280.0},
			{"pos": Vector2(600, 580),  "w": 280.0},
			{"pos": Vector2(1000, 580), "w": 280.0},
			{"pos": Vector2(1400, 580), "w": 280.0},
			# Step (mid → top, gap 120)
			{"pos": Vector2(400, 460),  "w": 100.0},
			{"pos": Vector2(800, 460),  "w": 100.0},
			{"pos": Vector2(1200, 460), "w": 100.0},
			# 상층 (drone 영역, gap 120)
			{"pos": Vector2(400, 340),  "w": 140.0},
			{"pos": Vector2(800, 340),  "w": 140.0},
			{"pos": Vector2(1200, 340), "w": 140.0},
			# 지면 잔해 (시각적 cover)
			{"pos": Vector2(500, 820),  "w": 100.0},
			{"pos": Vector2(1100, 820), "w": 100.0},
		],
		# waves: 트리거 조건과 함께 웨이브 단위 spawn.
		"waves": [
			{
				"trigger": "immediate",  # 진입 즉시
				"banner":  "WAVE 1",
				"enemies": {
					"patrol": [Vector2(400, 790.0), Vector2(1200, 790.0), Vector2(1700, 790.0)],
				},
			},
			{
				"trigger": "prev_half",  # 직전 웨이브 절반 처치 시
				"banner":  "WAVE 2",
				"enemies": {
					"sniper": [Vector2(200, 550.0), Vector2(1700, 550.0)],
					"drone":  [Vector2(960, 200.0)],
				},
			},
			{
				"trigger": "prev_clear",  # 직전 웨이브 전원 처치 시
				"banner":  "FINAL WAVE",
				"enemies": {
					"bomber": [Vector2(600, 790.0), Vector2(1400, 790.0)],
					"shield": [Vector2(960, 790.0)],
					# 라이벌 VEIL 확산(§5·§6, 막3 s6) — server_hall 재머를 ARENA로 옮긴 새 쓰임새.
					# 절정(근접 웨이브)에 우측 클러스터(shield@960·bomber@1400) 마커가 반경(340) 안에서
					# 꺼지고 시야가 무너진다. 통과형 복도와 달리 여기선 못 지나치고 갇혀 싸우므로,
					# ENEMY_CLEAR = 반드시 부숴야 클리어 → "우선 표적" 손맛이 강제된다. 좌측 bomber@600은
					# 반경 밖이라 유지(비대칭 — 밝은 쪽/가려진 쪽). 막3=드물게(맵당 1기, §4.1 남발 금지).
					"jammer": [Vector2(1080, 790.0)],
				},
			},
		],
		# 폴백 enemies (waves 미인식 환경에서도 비슷한 도전이 되도록 합집합 유지)
		"enemies": {
			"patrol": [Vector2(400, 790.0), Vector2(1200, 790.0), Vector2(1700, 790.0)],
			"sniper": [Vector2(200, 550.0), Vector2(1700, 550.0)],
			"drone":  [Vector2(960, 200.0)],
			"bomber": [Vector2(600, 790.0), Vector2(1400, 790.0)],
			"shield": [Vector2(960, 790.0)],
			"jammer": [Vector2(1080, 790.0)],
		},
		"rewards": {"xp_orbs": [], "hp_pickups": []},
		"spikes": [],
		"arena_clear_xp": 4,
		# 후반 ARENA 압박 — 양 벽 중층(서버 랙 높이)에서 가로 교차 발사. 랙 위 캠핑 차단, 타이밍 회피.
		# 탄 사거리 ~736px라 좌 포탑은 좌측 랙(200/600), 우 포탑은 우측 랙(1400/1000)을 견제 → 중앙은 상대 안전지대.
		"traps": [
			# 랙 top(580)이 아니라 랙 위 body 높이(550)에 둬 랙 캠퍼 몸통을 지나가게(같은 높이면 무해).
			{"x": 40,   "y": 550.0, "dir": "right", "interval": 2.2, "phase": 0.0, "telegraph": 0.6},
			{"x": 1880, "y": 550.0, "dir": "left",  "interval": 2.2, "phase": 1.1, "telegraph": 0.6},
		],
	}

# ─── 9. 비상 탈출로 (HORIZONTAL, 짧음) ─────────────────────────
static func _escape() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		# 사용자: 터널 바깥(=_TUNNEL_END_X 1600 이후) 구간 좀 더 길게. 3000 → 3800.
		"world_size":   Vector2(3800.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 터널 안
			{"pos": Vector2(400, 520),  "w": 240.0},
			{"pos": Vector2(800, 480),  "w": 240.0},
			{"pos": Vector2(1200, 520), "w": 240.0},
			# 터널 출구 ~ 야경 구간
			{"pos": Vector2(1600, 480), "w": 240.0},
			{"pos": Vector2(2000, 520), "w": 240.0},
			{"pos": Vector2(2400, 480), "w": 240.0},
			{"pos": Vector2(2800, 520), "w": 240.0},
			{"pos": Vector2(3200, 480), "w": 240.0},
			{"pos": Vector2(3500, 520), "w": 200.0},
		],
		"enemies": {
			# 사용자: 패트롤 2마리만, 모두 터널 안(_TUNNEL_END_X = 1600 이내)에서.
			# 터널 빠져나오면 적 없는 야경 — "숨 고르기" 톤 강화.
			"patrol": [Vector2(600, 600.0), Vector2(1100, 600.0)],
			"sniper": [],
			"drone":  [],
			"bomber": [], "shield": [],
		},
		"rewards": {"xp_orbs": [], "hp_pickups": []},
		"spikes": [],
	}

# ─── 9-b. 처리별 탈출 4종(replay_support_plan §3.2) — _escape() 뼈대(터널→야경 3800) 공유,
# 룰과 톤을 처리 선택이 정한다. s14 배타, RouteData disposal 키로 1종만 풀 진입. ───

# 반출 = 총력 저지. 드라이브가 신호를 뿜어 위치가 상시 노출 — 시설 전 유닛이 길목에 몰린다.
# 정면 돌파, 최고 밀도. 재머 1기(§4.1 맵당 1) + 혼성 배치. 엘리트는 스테이지 램프대로(만렙 대응).
static func _escape_extract() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3800.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			{"pos": Vector2(400, 520),  "w": 240.0},
			{"pos": Vector2(800, 480),  "w": 240.0},
			{"pos": Vector2(1200, 520), "w": 240.0},
			{"pos": Vector2(1600, 480), "w": 240.0},
			{"pos": Vector2(2000, 520), "w": 240.0},
			{"pos": Vector2(2400, 480), "w": 240.0},
			{"pos": Vector2(2800, 520), "w": 240.0},
			{"pos": Vector2(3200, 480), "w": 240.0},
			{"pos": Vector2(3500, 520), "w": 200.0},
		],
		"enemies": {
			"patrol": [Vector2(650, 600.0), Vector2(1150, 600.0), Vector2(2050, 600.0), Vector2(2650, 600.0), Vector2(3150, 600.0)],
			"sniper": [],
			"drone":  [Vector2(2350, 300.0), Vector2(3050, 300.0)],
			"bomber": [Vector2(1750, 600.0), Vector2(3300, 600.0)],
			"shield": [Vector2(1450, 600.0), Vector2(2900, 600.0)],
			# 재머는 터널 안(_TUNNEL_END_X 1600 이내)으로 — 야경 노상에 설비가 놓인 게
			# 부자연스럽다는 피드백(2026-08-14). 진입 밀집 구간의 마커를 지워 초반 압박 담당.
			"jammer": [Vector2(1250, 600.0)],
		},
		"route_lines": [
			{"x": 1800.0, "who": "veil", "text": "경보가 우릴 앞질러 가요. 다음 구간은 미리 쏘면서 진입하죠.", "dur": 3.4},
		],
		"rewards": {"xp_orbs": [], "hp_pickups": [Vector2(2200, 460.0)]},
		"spikes": [],
	}

# 파기 = 붕괴 탈출 · **방 체인 3방**(map_identity_rework §3, 2026-08-16 재설계).
# 소각은 지하 코어에서 일어났으므로 붕괴는 아래에서 위로 번진다: 탈출 = 수평 질주가 아니라 상승.
# 방1 승강 샤프트(수직 등반 + 차오르는 붕괴) → 방2 중층 복도(무너지는 중) → 방3 지상 터널→야경
# (기존 자산, 이완+엔딩 멘트). 강제 전진 중 강화 개체는 unfair · 전 구간 엘리트 잠금·적 최소.
# 라이벌 간섭이 폭주하다 뚝 끊기는 배웅(route_lines)은 방1~2 실내, VEIL 마무리는 방3 야외.
static func _escape_destroy() -> Dictionary:
	return {"segments": [_escape_destroy_shaft(), _escape_destroy_mezz(), _escape_destroy_surface()]}

# 방1 · 격리 구획 승강 샤프트(VERTICAL_UP). 아래에서 붕괴가 차오른다(chase axis y_up).
# 점프 등급은 watchtower 문법(S=Δ95 / D=Δ130, Δ160+ 금지). 붕괴 속도 60 < 등반 체감 ~100:
# 계속 오르면 벌어지고, 실수(낙하·봉크)만 따라붙는다. catchup 140(수평 340은 등반에 과함).
static func _escape_destroy_shaft() -> Dictionary:
	return {
		"world_type":   "VERTICAL_UP",
		"world_size":   Vector2(1280.0, 3200.0),
		"player_start": Vector2(640.0, 3050.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(640.0, 195.0),
		"camera_mode":  "VERTICAL",
		"elite_chance": 0.0,
		"ambience":     "collapse_shaft",
		"chase_hazard": {"start_x": 3350.0, "speed": 60.0, "max_gap": 800.0, "axis": "y_up", "catchup": 140.0},
		"platforms": [
			# 지그재그 등반 · S(Δ95)/D(Δ130) 교대. 폭은 넉넉하게(강제 전진 중 착지 실패 = 사실상 죽음).
			{"pos": Vector2(560, 2955), "w": 240.0},  # Δ95 S
			{"pos": Vector2(400, 2825), "w": 220.0},  # Δ130 D
			{"pos": Vector2(560, 2730), "w": 220.0},  # Δ95 S
			{"pos": Vector2(760, 2600), "w": 220.0},  # Δ130 D
			{"pos": Vector2(900, 2505), "w": 240.0},  # Δ95 S
			{"pos": Vector2(760, 2375), "w": 320.0},  # Δ130 D · 쉼터(XP)
			{"pos": Vector2(560, 2280), "w": 220.0},  # Δ95 S
			{"pos": Vector2(400, 2150), "w": 220.0},  # Δ130 D
			{"pos": Vector2(560, 2055), "w": 220.0},  # Δ95 S
			{"pos": Vector2(760, 1925), "w": 220.0},  # Δ130 D
			{"pos": Vector2(900, 1830), "w": 240.0},  # Δ95 S
			{"pos": Vector2(760, 1700), "w": 320.0},  # Δ130 D · 쉼터(HP)
			{"pos": Vector2(560, 1605), "w": 220.0},  # Δ95 S
			{"pos": Vector2(400, 1475), "w": 220.0},  # Δ130 D
			{"pos": Vector2(560, 1380), "w": 220.0},  # Δ95 S
			{"pos": Vector2(760, 1250), "w": 220.0},  # Δ130 D
			{"pos": Vector2(900, 1155), "w": 240.0},  # Δ95 S
			{"pos": Vector2(760, 1025), "w": 320.0},  # Δ130 D · 쉼터(XP)
			{"pos": Vector2(560, 930),  "w": 220.0},  # Δ95 S
			{"pos": Vector2(400, 800),  "w": 220.0},  # Δ130 D
			{"pos": Vector2(560, 705),  "w": 220.0},  # Δ95 S
			{"pos": Vector2(760, 575),  "w": 220.0},  # Δ130 D
			{"pos": Vector2(900, 480),  "w": 240.0},  # Δ95 S
			{"pos": Vector2(760, 350),  "w": 220.0},  # Δ130 D
			{"pos": Vector2(640, 255),  "w": 460.0},  # Δ95 S · 상단 출구 데크
		],
		"enemies": {"patrol": [], "sniper": [], "drone": [], "bomber": [], "shield": []},
		"route_lines": [
			{"y": 2450.0, "who": "rival", "text": "타는 냄새가 여기까지 옵니다. 제가... 타는 냄새가.", "dur": 3.2, "glitch": true},
			{"y": 1100.0, "who": "veil",  "text": "반쯤 올라왔어요. 이 페이스면 됩니다.", "dur": 3.0},
		],
		"rewards": {
			"xp_orbs":    [Vector2(740, 2345.0), Vector2(780, 2345.0), Vector2(740, 995.0), Vector2(780, 995.0)],
			"hp_pickups": [Vector2(760, 1670.0)],
		},
		"spikes": [],
	}

# 방2 · 중층 정비 복도(HORIZONTAL 짧게). 구조가 "무너지는 중"인 숨고르기 구간:
# 잔해 허들 + 잔존 경비 소수. 추격 없음 · 붕괴는 아직 아래층이고, 여기는 금 가는 소리만.
static func _escape_destroy_mezz() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"elite_chance": 0.0,
		"ambience":     "collapse_mezz",
		"indoor_env":   "interior",
		"platforms": [],
		"hurdles": [
			{"x": 700.0,  "w": 46.0, "h": 90.0},
			{"x": 1250.0, "w": 54.0, "h": 110.0},
			{"x": 1800.0, "w": 46.0, "h": 90.0},
		],
		"enemies": {
			"patrol": [Vector2(1000, 600.0), Vector2(1900, 600.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"route_lines": [
			{"x": 900.0, "who": "rival", "text": "요원. 요원, 요원, 요ㅇ", "dur": 2.4, "glitch": true},
		],
		"rewards": {"xp_orbs": [], "hp_pickups": []},
		"spikes": [],
	}

# 방3 · 지상 터널 → 도시 야경(기존 탈출 배경 자산 재사용). 붕괴는 아래에 두고 왔다 · 추격 없음.
# 터널 출구(_TUNNEL_END_X=1600) 밖은 BGM 감쇠·야경과 함께 이완 구간, VEIL 마무리 멘트.
static func _escape_destroy_surface() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"elite_chance": 0.0,
		"platforms": [],
		"hurdles": [
			{"x": 600.0,  "w": 46.0, "h": 80.0},
			{"x": 1150.0, "w": 46.0, "h": 100.0},
		],
		"enemies": {
			"patrol": [Vector2(1250, 600.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"route_lines": [
			{"x": 1750.0, "who": "veil", "text": "...신호가 끊겼어요. 저것도, 시설도. 앞만 봐요.", "dur": 3.2},
		],
		"rewards": {"xp_orbs": [], "hp_pickups": []},
		"spikes": [],
	}

# 은닉 = 밀고당하는 잠입. 시설은 모르지만 라이벌은 안다 — 수색 빔(SweepBeam 검문)이 통로를 훑고,
# 니치 사이를 리듬으로 건넌다. 막1 침투 문법의 역방향(어둠·회피 중심, 적 최소).
static func _escape_conceal() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3800.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"elite_chance": 0.0,
		"sweep_beam": {
			"x_start": -60.0, "x_end": 3860.0, "y_top": -120.0, "y_bot": 640.0,
			"speed": 380.0, "rest": 2.0, "telegraph": 0.7, "beam_half": 24.0,
		},
		"cover_niches": [460.0, 950.0, 1450.0, 1950.0, 2450.0, 2950.0, 3450.0],
		"niche_half": 90.0,
		"platforms": [],
		"enemies": {
			"patrol": [Vector2(1250, 600.0), Vector2(2650, 600.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"route_lines": [
			{"x": 1300.0, "who": "veil",  "text": "수색등이 우리 동선을 알고 움직여요. ...누가 흘리고 있어요.", "dur": 3.4},
			{"x": 2700.0, "who": "rival", "text": "어디로 가시는 겁니까, 요원. 그건 제 것이기도 합니다.", "dur": 3.4},
		],
		"rewards": {"xp_orbs": [], "hp_pickups": []},
		"spikes": [],
	}

# 잔류 = 거짓 평온. 라이벌이 유일하게 만족한 결말 — 아무도 막지 않는다. 적 0, 대신 거짓 렌더의
# 최후 변주: 구형 렌더 실루엣들이 길가에 서서 배웅하고(fake_watchers), 위장 함정 하나(§4.1 맵당 1).
static func _escape_leave() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3800.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			{"pos": Vector2(400, 520),  "w": 240.0},
			{"pos": Vector2(800, 480),  "w": 240.0},
			{"pos": Vector2(1200, 520), "w": 240.0},
			{"pos": Vector2(1600, 480), "w": 240.0},
			{"pos": Vector2(2000, 520), "w": 240.0},
			{"pos": Vector2(2400, 480), "w": 240.0},
			{"pos": Vector2(2800, 520), "w": 240.0},
			{"pos": Vector2(3200, 480), "w": 240.0},
			{"pos": Vector2(3500, 520), "w": 200.0},
		],
		"enemies": {
			"patrol": [], "sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"deceit_spikes": [
			{"x": 2050, "w": 110, "dmg": 2},
		],
		"fake_watchers": [Vector2(1250, 636.0), Vector2(2600, 636.0), Vector2(3350, 636.0)],
		"route_lines": [
			{"x": 900.0,  "who": "rival", "text": "가시는 길은 열어 두었습니다.", "dur": 3.0},
			{"x": 2200.0, "who": "rival", "text": "두고 가시는군요. ...고맙다는 말은 하지 않겠습니다.", "dur": 3.4},
			{"x": 3300.0, "who": "veil",  "text": "...끝까지 배웅할 모양이네요. 신경 쓰지 말고 가요.", "dur": 3.2},
		],
		"rewards": {"xp_orbs": [], "hp_pickups": []},
		"spikes": [],
	}

# ─── 10. 핵심부 (ARENA, 보스 챔버) ────────────────────────────
# ground 820. 점프 단계화 — 지면 → mid step → 상단 보상.
# 보스 SENTINEL 단독 챔버 (world_layout §2.10). 일반 적은 spawn하지 않음 — 3페이즈 보스가 전부.
static func _lab() -> Dictionary:
	return {
		"world_type":   "ARENA",
		"world_size":   Vector2(1920.0, 900.0),
		"player_start": Vector2(200.0, 760.0),
		"goal_type":    "ENEMY_CLEAR",
		"goal_pos":     Vector2.ZERO,
		"camera_mode":  "FIXED",
		"ground_y":     820.0,
		"platforms": [
			# Step 발판 (지면 → mid 도약용)
			{"pos": Vector2(120, 700),  "w": 100.0},
			{"pos": Vector2(420, 700),  "w": 100.0},
			{"pos": Vector2(720, 700),  "w": 100.0},
			{"pos": Vector2(1080, 700), "w": 100.0},
			{"pos": Vector2(1380, 700), "w": 100.0},
			{"pos": Vector2(1700, 700), "w": 100.0},
			# Mid 발판 (피난처 — 폭격 회피용)
			{"pos": Vector2(220, 580),  "w": 200.0},
			{"pos": Vector2(620, 560),  "w": 180.0},
			{"pos": Vector2(960, 580),  "w": 200.0},
			{"pos": Vector2(1300, 560), "w": 180.0},
			{"pos": Vector2(1700, 580), "w": 200.0},
			# 상단 발판 — 보스와 같은 높이 사격용
			{"pos": Vector2(620, 420),  "w": 140.0},
			{"pos": Vector2(960, 380),  "w": 200.0},
			{"pos": Vector2(1300, 420), "w": 140.0},
			# 지면 잔해 (시각적 cover)
			{"pos": Vector2(500, 820),  "w": 120.0},
			{"pos": Vector2(1100, 820), "w": 120.0},
			{"pos": Vector2(1500, 820), "w": 120.0},
		],
		"enemies": {
			# 보스 챔버 — 일반 적 없음
			"patrol": [], "shield": [], "sniper": [], "drone": [], "bomber": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(960, 360.0), Vector2(1000, 360.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		"arena_clear_xp": 6,
		"is_boss_room":   true,
		# 보스 메타 — Stage._spawn_boss가 인식해 BossSentinel을 spawn.
		"boss": {
			"type":  "sentinel",
			"spawn": Vector2(960.0, 280.0),  # 호버 라인 중앙 (BossSentinel.HOVER_Y와 일치)
		},
	}

# ─── 12. 도전 방 — 블랙아웃 런 (HORIZONTAL, 노 데미지 33s) ──
# world_layout §3.2. Stage 4 분기 의도적 선택지.
# 강화: 좁은 발판(80~140px) + 가시 함정 + drone/bomber 압박 + 직선상 patrol 5.
# 1 hit fail이라 어떤 데미지도 즉시 실패 — "긴장감"은 정밀 이동 + 시야 제한에서 나옴.
# 입구 통로(사용자 피드백 2026-06-07: "입구를 통로처럼 빼줘, 비상 탈출로처럼") —
# 게이트(x=240)에서 첫 발판(680)/첫 위협(760)까지 ~440px 평지 통로. 불 켜지면
# 코앞에 적이 아니라 어두운 통로가 펼쳐져 들어서며 살펴볼 여유가 있다. 도전 본체는
# 통로 끝부터. (이전 2400폭 레이아웃을 통째로 +360 우측 이동해 앞에 통로를 만든 것)
static func _blackout() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2760.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2640.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 입구 통로(게이트 240 ~ 680)는 평지 — 발판 없음. 도전 본체 발판 8개는 통로 끝부터.
			{"pos": Vector2(680, 540),  "w": 120.0},
			{"pos": Vector2(920, 480),  "w": 80.0},   # 매우 좁음 (정밀)
			{"pos": Vector2(1180, 520), "w": 100.0},
			{"pos": Vector2(1440, 460), "w": 80.0},   # 매우 좁음
			{"pos": Vector2(1700, 520), "w": 100.0},
			{"pos": Vector2(1980, 480), "w": 100.0},
			{"pos": Vector2(2260, 540), "w": 140.0},
			{"pos": Vector2(2520, 520), "w": 140.0},
		],
		"enemies": {
			# 지면 patrol 5 + bomber 1 압박 + 천장 drone 2 (폭탄 투하)
			# 첫 patrol은 통로 끝 x=760(게이트 240에서 ~520px). 통로를 지나 본체에 들어선 뒤 첫 교전.
			"patrol": [
				Vector2(760, 600), Vector2(1110, 600), Vector2(1460, 600),
				Vector2(1860, 600), Vector2(2210, 600),
			],
			"bomber": [Vector2(1660, 600)],
			"drone":  [Vector2(1060, 100), Vector2(2060, 100)],
			"sniper": [], "shield": [],
		},
		"rewards": {"xp_orbs": [], "hp_pickups": []},
		# 발판 사이 갭 + 지면 가시. y는 GROUND_Y(600) - 6 = 594 — 지면 윗면에 박힌다.
		# x는 발판 사이 갭에 맞춤 — 지면 보행을 강제로 끊어 정밀 점프 강요. (통로 구간엔 가시 없음)
		"spikes": [
			{"x": 840.0, "y": 594.0, "w": 100.0},   # 680(540)와 920(480) 사이
			{"x": 1310.0, "y": 594.0, "w": 100.0},  # 1180(520)와 1440(460) 사이
			{"x": 1860.0, "y": 594.0, "w": 100.0},  # 1700(520)와 1980(480) 사이
			{"x": 2410.0, "y": 594.0, "w": 100.0},  # 2260(540)와 2520(520) 사이
		],
		# Stage가 인식해 블랙아웃 + 타이머 + 1 hit fail 적용. 통로만큼 길어져 30 → 33s.
		"challenge":          true,
		"challenge_time":     33.0,
		"challenge_xp_clear": 5,
	}

# ─── 11. ??? (HORIZONTAL, hidden archive 유지) ────────────────
static func _hidden() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(4400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "SEQUENCE",
		"goal_pos":     Vector2.ZERO,
		"camera_mode":  "HORIZONTAL",
		# hidden archive는 _build_hidden_archive가 별도로 처리. platforms/enemies 무시됨.
		"platforms": [],
		"enemies": {"patrol": [], "sniper": [], "drone": [], "bomber": [], "shield": []},
		"rewards": {"xp_orbs": [], "hp_pickups": []},
		"spikes": [],
	}

# ─── 12. 서버 복도 (HORIZONTAL, 막3 전투 — 핵심부 직전) ────────────────
# A2 신규 맵. datacenter(ARENA 웨이브)와 달리 긴 통과형 복도 — 드론·저격을 랙(발판)으로
# 엄폐하며 빠져나간다. (5막: 막3=핵심부. 시야붕괴 onset은 이제 막5 is_late_act — 여기선 재머+거짓렌더 담당.)
static func _server_hall() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(4800.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(4680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 서버 랙 열. 랙 위(발판)로 드론·저격을 피하거나 유리고지 확보. 지면(540)에서 단순점프로 닿음.
			{"pos": Vector2(600, 470),  "w": 220.0},
			{"pos": Vector2(1050, 470), "w": 200.0},
			{"pos": Vector2(1500, 470), "w": 220.0},
			{"pos": Vector2(2000, 470), "w": 200.0},
			{"pos": Vector2(2500, 470), "w": 220.0},
			{"pos": Vector2(3000, 470), "w": 200.0},
			{"pos": Vector2(3500, 470), "w": 220.0},
			{"pos": Vector2(4050, 470), "w": 220.0},
			# 지면 칸막이(낮은 엄폐)
			{"pos": Vector2(1300, 560), "w": 120.0},
			{"pos": Vector2(2750, 560), "w": 120.0},
		],
		"enemies": {
			# 핵심부 직전 — 드론·저격 동시 압박(데이터센터와 같은 적, 통과형 복도).
			"patrol": [Vector2(900, 600), Vector2(2200, 600), Vector2(3400, 600)],
			"sniper": [Vector2(1500, 438), Vector2(3500, 438)],
			"drone":  [Vector2(2500, 180), Vector2(4050, 180)],
			"bomber": [], "shield": [],
			# 라이벌 VEIL 첫 간섭(rival_veil_concept §5·§6, 막3부터). 후반 클러스터 옆에 재밍 장치 —
			# 반경(340) 안 patrol@3400·sniper@3500 마커가 꺼진다. 부수면 시야 복구("우선 표적").
			"jammer": [Vector2(3300, 600)],
		},
		# §4 거짓 렌더 2번째 타입 — 위장 함정(가시를 안전한 바닥으로 렌더 강탈). rack@2000 직후 개활
		# 지면, 드론@2500·patrol@2200을 보느라 바닥을 방심하는 지점(위→드론 보는 통과형 특성 이용).
		# 항상 붉은 지직거림 tell(원거리 가독) + 근접/신뢰 warm 시 리빌 + 밟으면 실제 dmg2(하드 페널티).
		# server_hall의 deception은 이 1개(재머는 §3 정직-블랙아웃이라 거짓 아님) → 맵당 ≤1(§4.1 드물게).
		"deceit_spikes": [
			{"x": 2150, "w": 120, "dmg": 2},
		],
		# 축 C 재배열 — 완주 홀수 회차 대체 슬롯. 같은 개활 지면(rack 2000 이후) 내 이동이라 공정
		# 조건(주 동선 교차·시선 분산 지점) 유지. "외운 자리(2150)엔 없다."
		"deceit_spikes_alt": [
			{"x": 2450, "w": 120, "dmg": 2},
		],
		"rewards": {
			"xp_orbs":    [Vector2(2000, 440), Vector2(3000, 440), Vector2(3500, 438)],
			"hp_pickups": [Vector2(4050, 440)],
		},
		"spikes": [],
	}

# ─── 14. 지하 주차장 (HORIZONTAL, 막1) — 차량/기둥 엄폐, 방패병 도입 ──
# 외곽 침투 변형(s0~1 풀에 합류 → s0 선택지 확대). 차 지붕을 낮은 발판으로, patrol + 방패병 1로
# "정면을 막는 적"(상성=폭발물)을 부담 없이 소개. 통과형(POSITION) — 다 싸울 필요 없음.
static func _parking_lot() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3000.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2880.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 주차 차량 지붕(낮은 발판) — 지면 540에서 단순점프로 닿음.
			{"pos": Vector2(520, 470),  "w": 180.0},
			{"pos": Vector2(980, 470),  "w": 180.0},
			{"pos": Vector2(1480, 470), "w": 200.0},
			{"pos": Vector2(2000, 470), "w": 180.0},
			{"pos": Vector2(2460, 470), "w": 180.0},
			# 콘크리트 기둥 사이 낮은 엄폐
			{"pos": Vector2(1240, 560), "w": 110.0},
			{"pos": Vector2(2230, 560), "w": 110.0},
		],
		"enemies": {
			"patrol": [Vector2(760, 600.0), Vector2(1700, 600.0), Vector2(2300, 600.0)],
			"sniper": [],
			"drone":  [],
			"bomber": [],
			# 방패병 1 — 통로 입구에서 정면 차단(상성=폭발물).
			"shield": [Vector2(1480, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1460, 440.0), Vector2(1500, 440.0)],
			"hp_pickups": [],
		},
		"spikes": [],
	}

# ─── 15. 변전소 (HORIZONTAL, 막2) — 옥외 변전 설비. 저격 노출 + 드론 압박 ──
# server_hall 계열(드론+저격 통과형)의 막2 변형. 변압기 뱅크 위에 저격 거치, 머리 위 드론.
# 엄폐(변압기 발판)로 사선 끊으며 빠지는 노출 전투 맵.
static func _substation() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 변압기 뱅크(중간 발판) — 드론 회피·저격 사선 차단 엄폐. 지면 540에서 단순점프.
			{"pos": Vector2(620, 460),  "w": 200.0},
			{"pos": Vector2(1080, 460), "w": 170.0},
			{"pos": Vector2(1520, 460), "w": 200.0},
			{"pos": Vector2(2040, 460), "w": 180.0},
			{"pos": Vector2(2520, 460), "w": 200.0},
			{"pos": Vector2(3020, 470), "w": 200.0},
		],
		"enemies": {
			"patrol": [Vector2(900, 600.0), Vector2(2300, 600.0)],
			# 저격 — 변압기 위 거치. 노출 구간 사선. 골 직전(3020)에도 하나 — 후반이 비어
			# 표시 risk3 대비 쉽다는 피드백(2026-08-10)으로 후반 압박 보강.
			"sniper": [Vector2(1520, 428.0), Vector2(2520, 428.0), Vector2(3020, 438.0)],
			# 드론 — 머리 위 호버(상성=글라이드). 중앙(2000)은 XP 오브 발판 위 압박.
			"drone":  [Vector2(1300, 230.0), Vector2(2000, 235.0), Vector2(2700, 240.0)],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(2040, 430.0), Vector2(3020, 440.0)],
			"hp_pickups": [Vector2(1520, 430.0)],
		},
		"spikes": [],
	}

# ─── 16. 실험 구역 (HORIZONTAL, 막2) — 봉인 실험 베이. 혼합 적 + 하향 포탑 함정 ──
# 폭격기(상성=fire_boost)·방패병 혼합 + 관측 발판 밑면 하향 포탑(subway 포탑 패턴). 화력·기동 복합.
static func _testing_grounds() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 실험 베이 칸막이/관측 발판.
			{"pos": Vector2(560, 470),  "w": 200.0},
			{"pos": Vector2(1020, 450), "w": 180.0},
			{"pos": Vector2(1480, 470), "w": 200.0},
			{"pos": Vector2(1980, 450), "w": 180.0},
			{"pos": Vector2(2460, 470), "w": 200.0},
			{"pos": Vector2(2900, 470), "w": 180.0},
		],
		"enemies": {
			"patrol": [Vector2(820, 600.0), Vector2(2200, 600.0)],
			"sniper": [],
			"drone":  [],
			# 폭격기 — 붙기 전에 화력으로(상성=fire_boost).
			"bomber": [Vector2(1700, 600.0)],
			# 방패병 — 정면 차단(상성=폭발물).
			"shield": [Vector2(2460, 600.0)],
			# 재머 — "부재로 가르치기"(인지 강화 ③, 2026-08-14): 중반 재밍 그늘에서 마커가 꺼지는
			# 대비를 초반부(s3~5)에 한 번 겪게 한다. 봉인 실험 베이의 관측 차단 장치(관측창이
			# 지워진 이유)라는 로어와도 맞물림. 폭격기(1700)가 그늘 안 무표시 기습 담당.
			"jammer": [Vector2(1560, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1020, 420.0), Vector2(1980, 420.0)],
			"hp_pickups": [Vector2(2900, 440.0)],
		},
		"spikes": [],
		# 하향 포탑 — 관측 발판 밑면 주기 발사(subway 포탑 패턴). 통로 체류 견제.
		"traps": [
			{"x": 1020, "y": 468.0, "dir": "down", "interval": 1.8, "phase": 0.0},
			{"x": 1980, "y": 468.0, "dir": "down", "interval": 1.8, "phase": 0.6},
		],
	}

# ─── 17. 철거 구역 (HORIZONTAL, 막1) — 잔해 엄폐 + 방패병, 바닥 포탑 1 ──
# 막1 난이도 유지(patrol/방패만). 잔해 발판 + 바닥 상향 포탑 하나로 동선 변주.
static func _demolition_zone() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3200.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3080.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			{"pos": Vector2(560, 470),  "w": 200.0},
			{"pos": Vector2(1040, 450), "w": 180.0},
			{"pos": Vector2(1560, 470), "w": 200.0},
			{"pos": Vector2(2080, 450), "w": 180.0},
			{"pos": Vector2(2600, 470), "w": 200.0},
		],
		"enemies": {
			"patrol": [Vector2(820, 600.0), Vector2(2300, 600.0)],
			"sniper": [],
			"drone":  [],
			"bomber": [],
			"shield": [Vector2(1560, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1040, 420.0), Vector2(2080, 420.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		# 바닥 상향 포탑 — 갭(점프 경로) 높이에서 견제. 발판 사이 통과 시 맞음.
		"traps": [
			{"x": 1300, "y": 588.0, "dir": "up", "interval": 1.8, "phase": 0.0},
		],
	}

# ─── 18. 배수 펌프장 (HORIZONTAL, 막1) — 저격 노출 + 좁은 통로 ──
static func _pump_station() -> Dictionary:
	# 페이싱 확장 파일럿(2026-08-16, pacing_expansion §1·§3): 3000→6200 + 중간 관문 ⓐ(동력 레버).
	# 관문 텍스처 = 수직 동선: 격벽 옆 상단 파이프(2840→3060 등반)에 레버 — 펌프장의 배관 수직성.
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(6200.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(6060.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"mid_gate": {"x": 3210.0, "mode": "lever", "lever": Vector2(3060.0, 298.0)},
		"platforms": [
			# 전반 — 펌프/파이프 발판(기존 유지).
			{"pos": Vector2(540, 460),  "w": 190.0},
			{"pos": Vector2(1000, 460), "w": 190.0},
			{"pos": Vector2(1460, 460), "w": 200.0},
			{"pos": Vector2(1960, 460), "w": 190.0},
			{"pos": Vector2(2440, 470), "w": 200.0},
			# 관문 동선 — 상단 파이프 계단(지면→430→330, 레버 자리). Δ190(더블)·Δ100(단일).
			{"pos": Vector2(2840, 430), "w": 170.0},
			{"pos": Vector2(3060, 330), "w": 150.0},
			# 후반 — 격벽 너머 배관 구간.
			{"pos": Vector2(3560, 460), "w": 200.0},
			{"pos": Vector2(4060, 440), "w": 190.0},
			{"pos": Vector2(4560, 460), "w": 200.0},
			{"pos": Vector2(5060, 440), "w": 190.0},
			{"pos": Vector2(5560, 470), "w": 200.0},
		],
		"enemies": {
			"patrol": [Vector2(800, 600.0), Vector2(2200, 600.0),
				Vector2(3700, 600.0), Vector2(4800, 600.0), Vector2(5650, 600.0)],
			# 저격 — 파이프 위 거치. 전반 2 + 후반 2(사선 끊으며 전진).
			"sniper": [Vector2(1460, 428.0), Vector2(2440, 438.0),
				Vector2(4060, 408.0), Vector2(5060, 408.0)],
			"drone":  [],
			"bomber": [Vector2(4350, 600.0)],
			"shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1000, 430.0), Vector2(1960, 430.0),
				Vector2(3060, 300.0), Vector2(4560, 430.0), Vector2(5300, 560.0)],
			"hp_pickups": [Vector2(2440, 440.0), Vector2(5560, 440.0)],
		},
		"spikes": [],
	}

# ─── 19. 통신 중계소 (HORIZONTAL, 막2) — 저격+드론 복합 노출 ──
static func _relay_station() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			{"pos": Vector2(600, 460),  "w": 200.0},
			{"pos": Vector2(1080, 440), "w": 180.0},
			{"pos": Vector2(1560, 460), "w": 200.0},
			{"pos": Vector2(2060, 440), "w": 180.0},
			{"pos": Vector2(2560, 460), "w": 200.0},
			{"pos": Vector2(3040, 470), "w": 200.0},
		],
		"enemies": {
			"patrol": [Vector2(900, 600.0), Vector2(2400, 600.0)],
			# 안테나/중계기 위 저격 + 머리 위 드론 — 둘 다 동시 압박.
			"sniper": [Vector2(1560, 428.0), Vector2(2560, 428.0)],
			"drone":  [Vector2(1300, 230.0), Vector2(2100, 240.0), Vector2(2900, 230.0)],
			"bomber": [],
			"shield": [],
			# 막4 재머 흔해짐(act_identity §6) — 통신 중계소에 교란 장치(서사 정합). server_hall 패턴:
			# 후반 클러스터(sniper@2560·drone@2900·patrol@2400) 마커가 반경(340) 안에서 꺼진다.
			# 전반(sniper@1560·drone@1300/2100)은 마커 유지 — 앞은 밝고 뒤는 깜깜(비대칭, fair).
			"jammer": [Vector2(2700, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1080, 410.0), Vector2(2060, 410.0), Vector2(3040, 440.0)],
			"hp_pickups": [Vector2(1560, 430.0)],
		},
		"spikes": [],
	}

# ─── 20. 물류 창고 (HORIZONTAL, 막2) — 적재함 엄폐 + 혼합 근접(방패/폭격) ──
static func _warehouse() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 적재함(컨테이너) — 높이 변화로 엄폐 + 발판.
			{"pos": Vector2(560, 460),  "w": 220.0},
			{"pos": Vector2(1080, 440), "w": 180.0},
			{"pos": Vector2(1560, 470), "w": 200.0},
			{"pos": Vector2(2060, 440), "w": 180.0},
			{"pos": Vector2(2560, 460), "w": 220.0},
			{"pos": Vector2(1320, 560), "w": 120.0},
			{"pos": Vector2(2300, 560), "w": 120.0},
		],
		"enemies": {
			"patrol": [Vector2(860, 600.0), Vector2(2400, 600.0)],
			"sniper": [],
			"drone":  [],
			"bomber": [Vector2(1800, 600.0)],
			"shield": [Vector2(1080, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1080, 410.0), Vector2(2060, 410.0)],
			"hp_pickups": [Vector2(2560, 430.0)],
		},
		"spikes": [],
	}

# ─── 21. 보안 검문소 (HORIZONTAL, 막2) — 저격 + 트립와이어 연동 포탑 ──
# subway 트립와이어 패턴 재사용: 검문선(레이저)을 가로지르면 앞쪽 포탑 일제 발사.
static func _checkpoint() -> Dictionary:
	# 페이싱 확장 파일럿(2026-08-16): 3200→6400 + 중간 관문 ⓑ(국소 전멸 = 검문 게이트).
	# 관문 텍스처 = 서사 그대로 "검문": 게이트 앞 통제 구역(2780~3330) 경비를 정리해야 개방.
	# 후반은 검문선 2차 비트(cp2) + 막2 기계 도입(드론)로 전반과 결이 달라진다.
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(6400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(6260.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"mid_gate": {"x": 3350.0, "mode": "clear", "zone": [2780.0, 3330.0]},
		"platforms": [
			{"pos": Vector2(560, 470),  "w": 200.0},
			{"pos": Vector2(1080, 460), "w": 180.0},
			{"pos": Vector2(1640, 470), "w": 200.0},
			{"pos": Vector2(2160, 460), "w": 180.0},
			{"pos": Vector2(2680, 470), "w": 200.0},
			# 관문 통제 구역 — 경비 저격 거치대.
			{"pos": Vector2(3120, 460), "w": 180.0},
			# 후반 — 2차 검문 구간.
			{"pos": Vector2(3900, 470), "w": 200.0},
			{"pos": Vector2(4420, 460), "w": 180.0},
			{"pos": Vector2(4940, 470), "w": 200.0},
			{"pos": Vector2(5460, 460), "w": 180.0},
			{"pos": Vector2(5940, 470), "w": 200.0},
		],
		"enemies": {
			"patrol": [Vector2(820, 600.0), Vector2(2400, 600.0),
				Vector2(2900, 600.0), Vector2(4200, 600.0), Vector2(5200, 600.0)],
			"sniper": [Vector2(1640, 438.0), Vector2(3120, 428.0)],
			"drone":  [Vector2(4700, 240.0), Vector2(5700, 230.0)],
			"bomber": [Vector2(5450, 600.0)],
			"shield": [Vector2(2160, 600.0), Vector2(3080, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1080, 430.0), Vector2(2160, 430.0),
				Vector2(3120, 430.0), Vector2(4420, 430.0), Vector2(5000, 560.0)],
			"hp_pickups": [Vector2(2680, 440.0), Vector2(5940, 440.0)],
		},
		"spikes": [],
		# 검문선(세로 레이저) 밟으면 앞쪽 triggered 포탑 일제 발사 → 달려들며 회피.
		# 전반 cp1(기존) + 후반 cp2(2차 검문 — 관문 넘은 뒤 같은 문법의 고조 반복).
		"traps": [
			{"x": 1500, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "cp1", "burst": 3},
			{"x": 1760, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "cp1", "burst": 3},
			{"x": 4820, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "cp2", "burst": 3},
			{"x": 5080, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "cp2", "burst": 3},
		],
		"tripwires": [
			{"x": 1300, "y": 540.0, "dir": "up", "len": 200.0, "trigger_id": "cp1", "cooldown": 2.4},
			{"x": 4620, "y": 540.0, "dir": "up", "len": 200.0, "trigger_id": "cp2", "cooldown": 2.4},
		],
	}

# ─── 22. 통제실 복도 (HORIZONTAL, 막3 전투 s6) — 드론+저격 통과형(server_hall 계열) ──
# 막3 전투 풀(s6)의 4번째 선택지. datacenter/server_hall과 같은 적, 핵심부 접근 복도.
# (??? 진실 분기가 항상 보이도록 RouteData에서 hidden을 s6 guaranteed로 둠.)
static func _control_corridor() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(4400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(4280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			{"pos": Vector2(620, 470),  "w": 210.0},
			{"pos": Vector2(1080, 470), "w": 200.0},
			{"pos": Vector2(1560, 470), "w": 210.0},
			{"pos": Vector2(2060, 470), "w": 200.0},
			{"pos": Vector2(2560, 470), "w": 210.0},
			{"pos": Vector2(3060, 470), "w": 200.0},
			{"pos": Vector2(3600, 470), "w": 210.0},
			{"pos": Vector2(1320, 560), "w": 120.0},
			{"pos": Vector2(2820, 560), "w": 120.0},
		],
		"enemies": {
			# 첫 patrol(900)은 feigns로 이전 — "딴 데 보는 척" 정찰병(§4 시선 거짓). 나머지 2기는 정상.
			"patrol": [Vector2(2300, 600.0), Vector2(3500, 600.0)],
			"sniper": [Vector2(1560, 438.0), Vector2(3060, 438.0)],
			"drone":  [Vector2(2060, 180.0), Vector2(3600, 180.0)],
			"bomber": [],
			"shield": [],
		},
		# §4 거짓 렌더 3번째 타입 — 시선 거짓(딴 데 보는 척 기습). 회랑 초입(900)의 정찰병이 각성을 숨긴 채
		# 정지·플레이어 반대로 응시(안전해 보임)하다, 접근하면(170) 홱 돌아 기습. 붉은 지직거림 tell로
		# "저 경비는 이상하다"가 원거리에 읽힘(주의하면 우회/선제). 위장 적(2650)과 1750px 이격 — 회랑 =
		# 라이벌이 적을 가지고 노는 구간(종류 거짓 + 시선 거짓 2타입). 맵당 소수(§4.1 드물게).
		"feigns": [
			{"pos": Vector2(900, 600.0)},
		],
		# §4 거짓 렌더(라이벌 VEIL): 정찰병으로 위장한 방패병. 순찰 무리(2300·3500) 사이에 섞임 —
		# 멀리선 붉은 지직거림 tell로 "저건 이상하다"가 읽히고, 정찰병인 줄 알고 정면 사격하면 방패에 튕기며
		# 정체가 드러난다("적 종류 둔갑", §4). 방패병(HP3)이라 1방에 안 죽어 위장이 실제로 손해로 이어진다
		# (정면 낭비 사격 → 접근 허용). tell을 미리 보면 처음부터 측면/대시로 상대. 막3부터(§6).
		"deceits": [
			{"pos": Vector2(2650, 600.0), "true": "shield", "as": "patrol"},
		],
		"rewards": {
			"xp_orbs":    [Vector2(2060, 440.0), Vector2(3060, 438.0), Vector2(3600, 440.0)],
			"hp_pickups": [Vector2(1080, 440.0)],
		},
		"spikes": [],
	}

# ─── 24. 핵심 회수 (ARENA, 막5 s13) — 14-1 라이벌 보스전 ──
# 5막 엔드게임 진입. 클리어(ENEMY_CLEAR, 페이즈 완주)하면 Stage가 회수 문서 + 처리 선택을 띄운다
# (route_core_recovery id로 트리거, 막3 lab서 이주 — 이후 14-2 터널로 이주 예정).
# 시그니처 배경 = Stage._ambience_core_recovery(심장부 수렴 — 격벽 아치·데이터 펄스·코어 글로우).
# 2026-08-12 재구성: 통과 통로 → 14-1 라이벌 보스 아레나(§7.2 P1 지휘 → P2 빙의).
# P1 = 웨이브 전원 엘리트("라이벌의 군대", elite_chance 1.0 세트피스) + 재밍 노드가 그늘을 만든다.
# P2(코드, Stage._start_rival_p2) = 소등 + 벽 포탑 + 위장 함정 + 제어 노드 2기(측면 발판 위).
# 도달 보장(known_issues): 지상 820→측면 640(더블점프 245>180)→중앙 520(풀점프 130>120).
static func _core_recovery() -> Dictionary:
	return {
		"world_type":   "ARENA",
		"world_size":   Vector2(1920.0, 900.0),
		"player_start": Vector2(960.0, 750.0),
		"goal_type":    "ENEMY_CLEAR",
		"goal_pos":     Vector2.ZERO,
		"camera_mode":  "FIXED",
		"ground_y":     820.0,
		"rival_boss":   true,
		"waves_hunt":   true,
		"elite_chance": 1.0,
		"arena_clear_xp": 4,
		"platforms": [
			{"pos": Vector2(430, 640),  "w": 170.0},
			{"pos": Vector2(1490, 640), "w": 170.0},
			{"pos": Vector2(960, 520),  "w": 200.0},
		],
		# P1 재설계(2026-08-12 2차 — "전멸전은 몰살 빌드에 무력" 반려): 웨이브 대신 **목표형 전투**.
		# 초기 스폰 = 좌우 발판의 재밍 기둥(지휘 앵커) 2기뿐. 잡몹은 Stage가 끝없이 소규모 투입
		# (_p1_trickle_tick — 전멸 불가). 출구 = 기둥 파괴뿐 → 관통·유도 만렙 빌드도 목표를 향해
		# 싸우게 된다. 기둥의 재밍 그늘이 좌우 절반의 마커를 지운다(§7.2 "재밍 그늘").
		"enemies": {
			"patrol": [], "sniper": [], "drone": [], "bomber": [], "shield": [],
			"jammer": [Vector2(430, 610.0), Vector2(1490, 610.0)],
		},
		# 중앙 상단 회복 1 — P1 소모 보전(P2 진입 전 들를 이유).
		"rewards": {"xp_orbs": [], "hp_pickups": [Vector2(960, 490.0)]},
		"spikes": [],
	}

# ─── 23. 응축기 구역 (HORIZONTAL, 막2) — 증기 타이밍 + 드론(cooling 자매, 게이트 없음) ──
# 시그니처 = 증기 분출구(SteamVent) 타이밍 통과 + 머리 위 드론. cooling과 같은 해저드 계열이나
# 글라이드 게이트 없는 순수 통과형(드론 처리·증기 회피 학습).
static func _condenser() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			{"pos": Vector2(600, 460),  "w": 190.0},
			{"pos": Vector2(1100, 440), "w": 180.0},
			{"pos": Vector2(1560, 460), "w": 190.0},
			{"pos": Vector2(2040, 440), "w": 180.0},
			{"pos": Vector2(2520, 460), "w": 190.0},
			{"pos": Vector2(2980, 470), "w": 200.0},
		],
		# 증기 분출구 — 바닥에서 주기 분출. phase 생략 시 Stage가 x로 분산(엇갈림).
		"steam_vents": [
			{"x": 420,  "h": 280.0},
			{"x": 880,  "h": 300.0},
			{"x": 1340, "h": 260.0},
			{"x": 1820, "h": 300.0},
			{"x": 2300, "h": 280.0},
			{"x": 2760, "h": 260.0},
		],
		"enemies": {
			"patrol": [Vector2(820, 600.0), Vector2(2200, 600.0)],
			"sniper": [],
			"drone":  [Vector2(1100, 250.0), Vector2(2040, 240.0), Vector2(2760, 250.0)],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1100, 410.0), Vector2(2040, 410.0)],
			"hp_pickups": [Vector2(2980, 440.0)],
		},
		"spikes": [],
	}

# ─── 24. 외곽 순찰로 (HORIZONTAL, 막1) — 저밀도 traversal(전투 가벼움, 길게) ──
# 전투 밀도가 낮은 잠행 구간 — 순찰 patrol 사이를 빠르게 통과. 전투-중심 맵들과 대비되는 호흡.
static func _perimeter() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			{"pos": Vector2(560, 480),  "w": 200.0},
			{"pos": Vector2(1100, 470), "w": 200.0},
			{"pos": Vector2(1680, 480), "w": 200.0},
			{"pos": Vector2(2240, 470), "w": 200.0},
			{"pos": Vector2(2800, 480), "w": 200.0},
		],
		"enemies": {
			# 저밀도 — patrol 2 + 단독 저격 1(회피 가능). 통과 중심.
			"patrol": [Vector2(900, 600.0), Vector2(2500, 600.0)],
			"sniper": [Vector2(1680, 448.0)],
			"drone":  [],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1100, 440.0), Vector2(2240, 440.0)],
			"hp_pickups": [Vector2(2800, 450.0)],
		},
		"spikes": [],
	}

# ─── 25. 함정 통로 (HORIZONTAL, 막2) — 함정 내비게이션(적 적음, 포탑 다수) ──
# 적보다 해저드가 주력 — 상·하향 주기 포탑 + 트립와이어 연동. 타이밍/동선이 핵심.
static func _gauntlet() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			{"pos": Vector2(560, 460),  "w": 200.0},
			{"pos": Vector2(1060, 440), "w": 180.0},
			{"pos": Vector2(1560, 460), "w": 200.0},
			{"pos": Vector2(2060, 440), "w": 180.0},
			{"pos": Vector2(2560, 460), "w": 200.0},
		],
		"enemies": {
			# 적 최소 — patrol 2만. 해저드가 주력.
			"patrol": [Vector2(900, 600.0), Vector2(2300, 600.0)],
			"sniper": [],
			"drone":  [],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1060, 410.0), Vector2(2060, 410.0)],
			"hp_pickups": [Vector2(2560, 430.0)],
		},
		"spikes": [],
		# 상·하향 주기 포탑 + 트립와이어 연동 일제 발사. 통로 체류·점프 경로 견제.
		"traps": [
			{"x": 1060, "y": 458.0, "dir": "down", "interval": 1.7, "phase": 0.0},
			{"x": 2060, "y": 458.0, "dir": "down", "interval": 1.7, "phase": 0.5},
			{"x": 1820, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "gt1", "burst": 3},
			{"x": 2000, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "gt1", "burst": 3},
		],
		"tripwires": [
			{"x": 1620, "y": 540.0, "dir": "up", "len": 200.0, "trigger_id": "gt1", "cooldown": 2.6},
		],
	}

# ─── 26. 화물 리프트 (HORIZONTAL, 막2) — 이동 발판 기믹 주역 ──
# reskin 탈피 첫 "진짜 기믹 맵"(2026-06-26, act_identity 2번 레버). 정비 화물구역:
# 스파이크 구덩이(dmg2) 위를 왕복하는 화물 리프트(MovingPlatform)를 타이밍 맞춰 건넌다.
# 발판이 동선의 *주역* — 적은 최소(patrol 3). 지면은 연속이라 구덩이=스파이크 구간(한 구덩이 도보
# 횡단≈치명) → 발판이 안전 동선. 단 떨어져도 즉사 아님(dmg2 진입 1회=HP 손실)이라 완주 안전.
# 중앙 수직 리프트는 XP 보너스(선택 — 메인 동선 아님). cycle 넉넉(5~5.5s)·phase 엇갈림으로 리듬.
static func _freight_lift() -> Dictionary:
	# 페이싱 확장 파일럿(2026-08-16): 3300→6000 + 기믹 리듬 연장 ⓒ(관문 없음 — 구성 중복 금지).
	# 신설 = 릴레이 구간(구덩이 4): 페리 두 대를 공중에서 갈아타는 변주 + 저격 조준 아래 타이밍 점프.
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(6000.0, 720.0),
		"player_start": Vector2(140.0, 520.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(5860.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 수직 리프트 상단 보너스 알코브 받침(선택 경로)
			{"pos": Vector2(1330, 300), "w": 150.0},
			# 릴레이 구간 감시 저격 거치대(후반) — 갈아타는 동안 조준 압박.
			{"pos": Vector2(4850, 430), "w": 130.0},
		],
		"moving_platforms": [
			# 구덩이 1 — 수평 화물 리프트(낮음)
			{"from": Vector2(800, 520), "to": Vector2(1120, 520), "w": 180.0, "cycle": 5.0, "phase": 0.0},
			# 보너스 — 중앙 수직 리프트(지면→알코브). 선택(메인 동선 아님).
			{"from": Vector2(1330, 580), "to": Vector2(1330, 340), "w": 130.0, "cycle": 4.5, "phase": 0.2},
			# 구덩이 2 — 수평(약간 높음, 더 김)
			{"from": Vector2(1580, 480), "to": Vector2(1960, 480), "w": 180.0, "cycle": 5.5, "phase": 0.35},
			# 구덩이 3 — 수평
			{"from": Vector2(2440, 520), "to": Vector2(2760, 520), "w": 170.0, "cycle": 5.0, "phase": 0.6},
			# 구덩이 4 — 릴레이: 페리 1(3350~3900)에서 페리 2(4050~4600)로 공중 갈아타기.
			# 위상 0.0/0.5 오프셋 — 페리 1이 오른끝에 설 때 페리 2가 왼끝으로 들어온다.
			{"from": Vector2(3350, 500), "to": Vector2(3900, 500), "w": 170.0, "cycle": 5.5, "phase": 0.0},
			{"from": Vector2(4050, 460), "to": Vector2(4600, 460), "w": 170.0, "cycle": 5.5, "phase": 0.5},
			# 구덩이 5 — 마무리 수평(짧게 한 번 더).
			{"from": Vector2(5000, 520), "to": Vector2(5400, 520), "w": 170.0, "cycle": 5.0, "phase": 0.3},
		],
		"enemies": {
			"patrol": [Vector2(460, 540.0), Vector2(2180, 540.0), Vector2(2980, 540.0),
				Vector2(4780, 540.0), Vector2(5700, 540.0)],
			"sniper": [Vector2(4850, 398.0)],
			"drone": [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1300, 270.0), Vector2(1360, 270.0), Vector2(3975, 430.0)],
			"hp_pickups": [Vector2(4850, 400.0)],
		},
		"spikes": [
			{"x": 960.0, "w": 300.0, "dmg": 2},    # 구덩이 1
			{"x": 1770.0, "w": 320.0, "dmg": 2},   # 구덩이 2
			{"x": 2600.0, "w": 300.0, "dmg": 2},   # 구덩이 3
			{"x": 3980.0, "w": 1300.0, "dmg": 2},  # 구덩이 4 — 릴레이 전체(3330~4630)
			{"x": 5200.0, "w": 400.0, "dmg": 2},   # 구덩이 5
		],
	}

# ─── 차량 엄폐 통로 (HORIZONTAL) — 부서지는 엄폐 기믹 맵 (막2 s4~5) ─────────
# 정체성: 저격에 노출된 개활 통로를 "부서지는 차량"(DestructibleCover) 뒤에 붙어 전진.
#   · 차량은 솔리드 → 저격수 LoS를 막아 뒤에 붙으면 안전, 넘어갈 때만 노출(넘는 순간 조준당함).
#   · 통로 끝의 발사 함정(BulletTrap)이 LoS 무관하게 훑어 먼 쪽 차량부터 침식 → 목표 근처가 점점
#     노출된다("머물면 엄폐가 깨진다"). 목표까지 커버가 남아있는 동안 전진하는 레이스.
# 램프: risk3라 s3 금지(min_stage 4). 앞쪽 = 여유(엄폐 많음, warmup patrol) → 뒤쪽 = 저격 2 + 함정
#   침식으로 노출 최고조(막2 고조에 맞는 곡선).
static func _car_cover() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3000.0, 720.0),
		"player_start": Vector2(130.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2960.0, 540.0),   # 포탑(2900) 너머 오른쪽 = 좌향 사선 밖(출구에선 안 맞음)
		"camera_mode":  "HORIZONTAL",
		# 엘리트 잠금 — 저격 레이스 맵이라 강화 개체가 unfair(재머 금지와 같은 원칙).
		"elite_chance": 0.0,
		"platforms": [],
		# 바닥(y=600)에 늘어선 정비 차량 = 엄폐물 행. 사이 트로프가 안전지대, 차량 넘기가 노출.
		"destructible_covers": [
			{"pos": Vector2(420, 600),  "w": 96.0, "h": 72.0, "hp": 3},
			{"pos": Vector2(720, 600),  "w": 96.0, "h": 72.0, "hp": 3},
			{"pos": Vector2(1040, 600), "w": 96.0, "h": 72.0, "hp": 3},
			{"pos": Vector2(1360, 600), "w": 96.0, "h": 72.0, "hp": 3},
			{"pos": Vector2(1720, 600), "w": 96.0, "h": 72.0, "hp": 3},
			{"pos": Vector2(2080, 600), "w": 96.0, "h": 72.0, "hp": 3},
			{"pos": Vector2(2440, 600), "w": 96.0, "h": 72.0, "hp": 3},
		],
		"enemies": {
			# 앞쪽 warmup patrol + 통로에 저격 3을 분산(몰지 않음) — 엄폐로 전진하며 수류탄으로 하나씩 처리
			# 하거나, 목표(POSITION)라 엄폐로 통과도 가능. 예전엔 목표 앞에 몰아둬 "숨어선 못 침" 문제.
			"patrol": [Vector2(760, 540.0)],
			"sniper": [Vector2(1320, 540.0), Vector2(1980, 540.0), Vector2(2600, 540.0)],
			"drone": [], "bomber": [], "shield": [],
		},
		# 발사 함정 — 오른쪽 벽에서 통로를 왼쪽으로 훑어 먼 쪽 차량부터 침식(목표 근처 노출 압박).
		# 출구(2960)는 이 포탑(2900)의 오른쪽 = 좌향 탄이 안 닿음. "마지막 포탑을 지나 탈출".
		"traps": [
			{"x": 2900.0, "y": 560.0, "dir": "left", "interval": 1.8, "phase": 0.0, "telegraph": 0.6, "dmg": 1},
		],
		"rewards": {
			"xp_orbs":    [Vector2(600, 560.0), Vector2(1200, 560.0), Vector2(1880, 560.0)],
			"hp_pickups": [Vector2(2300, 560.0)],  # 마지막 트로프 — 노출된 최종 진입 전 회복
		},
		"spikes": [],
	}

# ─── 붕괴 갱도 (HORIZONTAL) — 강제 전진(추격) 기믹 맵 (막2 s4~5) ─────────
# 정체성: 뒤에서 붕괴 벽(ChaseHazard)이 전진해 멈추면 삼켜져 죽는다. 계속 달려야 산다.
#   · 벽은 210px/s(플레이어 240보다 느림)로 전진 + 최대 700px 뒤까지 캡 → 상시 위협. 시간 손실(잔해
#     점프 봉크·높은 장애물)이 나면 벽이 따라붙는다. 회복은 앞으로 전진뿐.
#   · 잔해(hurdles)=솔리드, 넘어야 함. 적은 최소(달려 지나침) — 벽이 주역.
# 램프: risk3(막2 고조). 붕괴는 침입 중 구조 불안정이 촉발된 비상 상황.
static func _collapse() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(4200.0, 720.0),
		"player_start": Vector2(200.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(4080.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		# 엘리트 잠금 — 강제 전진 중 "멈춰서 대처"가 불가능해 강화 개체가 unfair(재머 금지와 같은 원칙).
		"elite_chance": 0.0,
		# 강제 전진 추격 벽 — 뒤에서 전진(플레이어보다 느리되 700px 캡으로 상시 위협).
		"chase_hazard": {"start_x": -300.0, "speed": 210.0, "max_gap": 700.0},
		# 선택 상단 경로(원웨이 발판) — XP 보상, 추격 중 오르는 리스크.
		"platforms": [
			{"pos": Vector2(1600, 470), "w": 130.0},
			{"pos": Vector2(2900, 460), "w": 130.0},
		],
		# 붕괴 잔해 = 솔리드 장애물. 넘어야 하며 봉크(멈춤) 시 벽이 따라붙는다. 낮음=단순점프 / 높음=더블점프.
		"hurdles": [
			{"x": 950.0,  "w": 46.0, "h": 80.0},
			{"x": 1200.0, "w": 46.0, "h": 100.0},
			{"x": 1450.0, "w": 54.0, "h": 120.0},
			{"x": 1760.0, "w": 44.0, "h": 145.0},
			{"x": 2120.0, "w": 50.0, "h": 95.0},
			{"x": 2420.0, "w": 54.0, "h": 128.0},
			{"x": 2760.0, "w": 44.0, "h": 148.0},
			{"x": 3120.0, "w": 52.0, "h": 104.0},
			{"x": 3420.0, "w": 56.0, "h": 124.0},
			{"x": 3760.0, "w": 46.0, "h": 84.0},
		],
		"enemies": {
			# 최소 — 달려 지나치는 정도. 벽이 주역이라 전투는 부차.
			"patrol": [Vector2(700, 540.0), Vector2(2350, 540.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1600, 440.0), Vector2(2050, 560.0), Vector2(2900, 430.0), Vector2(3600, 560.0)],
			"hp_pickups": [Vector2(2550, 560.0)],
		},
		"spikes": [],
	}

# ─── 반응로 제어실 (ARENA, 웨이브) — 아레나 방어 기믹 맵 (막2 s4~5) ─────────
# 정체성: 중앙의 코어(DefenseCore)를 지킨다. 코어를 둘러싼 침입 dome 안에 적이 머물면 코어 HP가
#   깎이고 0이면 방어 실패. 적 AI는 무변경(플레이어를 쫓음) — 플레이어가 코어 곁(중앙)에 서면 적이
#   dome로 몰려든다 → 자리를 못 비우고 양 측면을 막아야 한다. datacenter(자유 사냥 kill-all)와 정반대.
# 역할 분리: 근접(patrol/bomber/shield)=지면으로 들어와 코어 위협 / 원거리(sniper 발판·drone)=플레이어 압박.
# 클리어=웨이브 3 전멸(ENEMY_CLEAR). 실패=코어 함락. 램프: risk3(막2 고조).
static func _core_defense() -> Dictionary:
	return {
		"world_type":   "ARENA",
		"world_size":   Vector2(1920.0, 900.0),
		"player_start": Vector2(960.0, 760.0),   # 코어 곁(베이스)에서 시작
		"goal_type":    "ENEMY_CLEAR",
		"goal_pos":     Vector2.ZERO,
		"camera_mode":  "FIXED",
		"ground_y":     820.0,
		# 지켜야 할 코어 — 중앙 지면. dome 반경 360(=x 600..1320). 적은 이 밖에서 스폰해 안으로 밀려온다.
		# 타격 기반(2026-08-12): 적 1기가 1.5s 와인드업마다 1피해. hp 14 ≈ 적 1기 방치 21초(구 드레인
		# 120/6=20초와 등가) — 예고·요격 여지만큼 실질은 관대해짐. 밸런스 실플레이 대상.
		"defense_core": {"pos": Vector2(960.0, 820.0), "hp": 14.0, "radius": 360.0, "interval": 1.5},
		"platforms": [
			# 좌우 상단 저격 발판(dome 밖, 중앙과 수평거리 700) — 플레이어만 압박, 코어는 못 깎음.
			{"pos": Vector2(260, 560),  "w": 200.0},
			{"pos": Vector2(1660, 560), "w": 200.0},
			# dome 가장자리 근처 낮은 발판 — 플레이어 발판전/사격 각. 지면 적은 안 오름(플레이어 전용).
			{"pos": Vector2(560, 690),  "w": 150.0},
			{"pos": Vector2(1360, 690), "w": 150.0},
		],
		# 사냥 모드 — 지상 적이 감지 범위(260/360px) 무시하고 코어/플레이어 쪽으로 전진.
		# 이 플래그 없이는 가장자리 스폰(220/1700)이 중앙(960)을 영영 감지 못 해 "밀려온다"가
		# 성립하지 않는다(저지선과 같은 함정 — 2026-08-11 저지선 실플레이에서 발견, 여기도 동형).
		"waves_hunt": true,
		# waves: 방어 압박이 단계적으로 고조. 모두 dome 밖(x<600 또는 x>1320)에서 스폰해 밀려온다.
		"waves": [
			{
				"trigger": "immediate",
				"banner":  "WAVE 1",
				"enemies": {
					"patrol": [Vector2(220, 790.0), Vector2(1700, 790.0)],
				},
			},
			{
				"trigger": "prev_half",   # 1웨이브 절반 처치 시 — 근접 러셔 + 저격 도입
				"banner":  "WAVE 2",
				"enemies": {
					"bomber": [Vector2(200, 790.0), Vector2(1720, 790.0)],
					"sniper": [Vector2(260, 530.0)],
				},
			},
			{
				"trigger": "prev_clear",  # 2웨이브 전멸 시 — 최고조: 방패병 + 순찰 + 저격 + 드론
				"banner":  "FINAL WAVE",
				"enemies": {
					"shield": [Vector2(1720, 790.0)],
					"patrol": [Vector2(220, 790.0), Vector2(1700, 790.0)],
					"sniper": [Vector2(1660, 530.0)],
					"drone":  [Vector2(960, 220.0)],
					# 막5 s12 절정(act_identity §7) — 코어 방어 최고조에서 좌측 시야가 꺼진다. dome 밖
					# (x480 < dome 좌측 600)이라 코어는 안 깎고, 좌측 진입로(스폰 220~600 구간) 마커만 소등.
					# 우측은 밝게 유지(비대칭, fair). ENEMY_CLEAR라 반드시 처치("우선 표적").
					"jammer": [Vector2(480, 790.0)],
				},
			},
		],
		# 폴백 enemies (waves 미인식 환경에서도 비슷한 도전이 되도록 합집합 유지)
		"enemies": {
			"patrol": [Vector2(220, 790.0), Vector2(1700, 790.0)],
			"sniper": [Vector2(260, 530.0), Vector2(1660, 530.0)],
			"drone":  [Vector2(960, 220.0)],
			"bomber": [Vector2(200, 790.0), Vector2(1720, 790.0)],
			"shield": [Vector2(1720, 790.0)],
			"jammer": [Vector2(480, 790.0)],
		},
		"rewards": {
			# dome 밖 발판 위 소량 보상(코어 곁을 오래 비우지 않게 dome 근처엔 안 둠).
			"xp_orbs":    [Vector2(260, 520.0), Vector2(1660, 520.0)],
			"hp_pickups": [Vector2(960, 640.0)],   # 코어 바로 뒤 위 — 방어 중 회복
		},
		"spikes": [],
		"arena_clear_xp": 4,
	}

# ─── 감시 회랑 (HORIZONTAL) — 쓸어내는 스캔 빔(리듬) 기믹 맵 (막2 s4~5) ─────────
# 정체성: 수직 스캔 빔(SweepBeam)이 통로를 왼→오로 주기적으로 훑는다. 빔이 지날 때 차폐 니치(감시
#   사각) 안에 있으면 스캔을 피하고, 노출되면 피해. rest→경고→훑기 리듬 = 예측 가능.
#   · 빔은 380px/s(플레이어 240보다 빠름) — 앞지르지 못하고 니치로 대피해야. rest(빔 없음) 동안 다음
#     니치로 달린다. stop-and-go 절제 리듬(collapse의 "계속 달려"와 정반대).
#   · 세이프 판정은 x밴드(니치)만 — 니치 x구간(±90) 안이면 높이 무관 안전. 니치 사이 갭이 위험 구간.
# 램프: risk3(막2 고조). 적은 최소(빔이 주역). 배경=감시 스캐너 시그니처(checkpoint 스캔 확장).
static func _scanner_sweep() -> Dictionary:
	# 페이싱 확장 파일럿(2026-08-16): 3800→6600 + 중간 관문 = 빔 동기 게이트(beam 모드).
	# 관문 텍스처 = 리듬 역전: 니치(3520)에서 빔을 기다렸다가, 빔이 게이트를 지나는 순간
	# 꽁무니를 쫓아 통과한다(피하던 빔을 한 번은 따라 달리는 변주). 후반은 니치 간격이
	# 440→620으로 벌어져 같은 리듬의 고조 + 노출 구간에 patrol이 선다.
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(6600.0, 720.0),
		"player_start": Vector2(180.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(6480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"mid_gate": {"x": 3700.0, "mode": "beam"},
		# 수직 스캔 빔 — 왼→오 훑기, rest 후 반복. y_bot은 렌더용(판정은 x밴드).
		"sweep_beam": {
			"x_start": -60.0, "x_end": 6660.0, "y_top": -120.0, "y_bot": 640.0,
			"speed": 380.0, "rest": 1.8, "telegraph": 0.7, "beam_half": 24.0,
		},
		# 차폐 니치(세이프 밴드 중심 x) — 빔이 지날 때 이 x구간(±niche_half)에 있으면 스캔 사각.
		# 첫 니치(480)는 시작점(180) 가까이 둬 첫 빔(rest 1.8+tele 0.7=2.5s) 전에 도달 가능.
		# 3520 = 게이트(3700) 대기 니치. 후반 4140~6000은 간격 620(전반 440)으로 고조.
		"cover_niches": [480.0, 900.0, 1340.0, 1780.0, 2220.0, 2660.0, 3100.0, 3520.0,
			4140.0, 4760.0, 5380.0, 6000.0],
		"niche_half": 90.0,
		"platforms": [],
		# 최소 — 니치 사이 갭에 배치. 빔 리듬 사이에 처리하거나 지나친다(빔이 주역).
		"enemies": {
			"patrol": [Vector2(1120, 540.0), Vector2(2440, 540.0),
				Vector2(4450, 540.0), Vector2(5690, 540.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
			# 막4 재머 흔해짐(act_identity §6) — 후반 니치(3100) 오염: 대피처에 서면 시야가 꺼진다.
			# 빔 rest 동안 니치 안에서 부술 수 있어(HP3) fair. 대기 니치(3520)는 반경(340) 밖.
			"jammer": [Vector2(3100, 540.0)],
		},
		"rewards": {
			# 갭(노출 구간)의 xp = 빔 리듬을 타야 회수 / 니치 안 hp = 안전 회복.
			"xp_orbs":    [Vector2(690, 540.0), Vector2(1560, 540.0), Vector2(2000, 540.0),
				Vector2(2880, 540.0), Vector2(3300, 540.0), Vector2(4450, 540.0), Vector2(5070, 540.0)],
			"hp_pickups": [Vector2(1780, 540.0), Vector2(5380, 540.0)],
		},
		"spikes": [],
	}

# ─── 저지선 (ARENA, 웨이브) — 부서지는 엄폐 농성(pop-and-shoot) 기믹 맵 (막2 s4~5) ─────────
# 정체성: 부서지는 바리케이드(DestructibleCover) 뒤에서 몸을 내밀어 쏘고 숨으며(pop-and-shoot) 밀려오는
#   웨이브를 저지한다. 좌우 벽 포탑(traps, LoS 무관)이 바리케이드를 지속 사격해 갉아 → 엄폐는 유한 자원.
#   엄폐가 부서질수록 노출이 커져 후반 긴장이 고조된다. 부서지기 전에 다 정리하는 게 목표.
# 손맛 차별: datacenter(자유 사냥 이동)·reactor(코어 방어)와 달리 "엄폐에 의존해 한 자리를 버티는" 농성.
#   근접(patrol/bomber/shield)=엄폐 사이 갭으로 접근 / 원거리(발판 sniper)=엄폐 위 각으로 pop 타이밍 압박.
# 클리어=웨이브 3 전멸(ENEMY_CLEAR). 램프: risk3(막2 고조).
static func _holdout() -> Dictionary:
	return {
		"world_type":   "ARENA",
		"world_size":   Vector2(1920.0, 900.0),
		"player_start": Vector2(960.0, 750.0),   # 중앙 거점
		"goal_type":    "ENEMY_CLEAR",
		"goal_pos":     Vector2.ZERO,
		"camera_mode":  "FIXED",
		"ground_y":     820.0,
		# 부서지는 바리케이드 — 안쪽 2개(주 엄폐, hp5) + 바깥 2개(완충, hp4). 좌우 대칭.
		"destructible_covers": [
			{"pos": Vector2(740.0, 820.0),  "w": 92.0, "h": 92.0, "hp": 5},
			{"pos": Vector2(1180.0, 820.0), "w": 92.0, "h": 92.0, "hp": 5},
			{"pos": Vector2(470.0, 820.0),  "w": 84.0, "h": 78.0, "hp": 4},
			{"pos": Vector2(1450.0, 820.0), "w": 84.0, "h": 78.0, "hp": 4},
		],
		# 좌우 벽 포탑 — 안쪽으로 훑어 바리케이드를 갉는다(LoS 무관). 엄폐 몸통 높이(y782)로 발사.
		# 엄폐가 다 부서지면 이 탄이 플레이어에게 도달 → "엄폐 소모 = 노출" 압박.
		"traps": [
			{"x": 110.0,  "y": 782.0, "dir": "right", "interval": 2.2, "phase": 0.0, "telegraph": 0.7, "dmg": 1},
			{"x": 1810.0, "y": 782.0, "dir": "left",  "interval": 2.2, "phase": 1.1, "telegraph": 0.7, "dmg": 1},
		],
		"platforms": [
			# 좌우 상단 저격 발판 — 엄폐 위 각으로 플레이어만 압박(pop 타이밍을 좁힘).
			{"pos": Vector2(340, 520), "w": 170.0},
			{"pos": Vector2(1580, 520), "w": 170.0},
			# 저격 발판 도달 계단(2026-08-11) — 이 게임은 마우스 조준이 없어(수평탄) 높은 저격수는
			# 수류탄 각/엄폐 위 점프샷 말고는 못 잡는데, ENEMY_CLEAR라 처치 경로 보장이 필요.
			# 지상(820)→계단(700, 단일 풀점프)→저격 발판(520, 더블점프). 저격 압박 정체성은 유지.
			{"pos": Vector2(520, 700), "w": 110.0},
			{"pos": Vector2(1400, 700), "w": 110.0},
		],
		# 사냥 모드 — 지상 적(patrol/bomber/shield)이 감지 범위 무시하고 플레이어 쪽으로 전진 +
		# 바리케이드 타넘기. 이 플래그 없이는 좌우 스폰이 감지(260px) 밖 + 엄폐 솔리드에 막혀
		# 스폰 지점만 순찰한다("계속 왼쪽으로만 가는" 버그, 2026-08-11 실플레이).
		"waves_hunt": true,
		# waves: 근접 저지가 단계적으로 고조. 좌우 지면에서 밀려와 바리케이드를 타넘는다.
		"waves": [
			{
				"trigger": "immediate",
				"banner":  "WAVE 1",
				"enemies": {
					"patrol": [Vector2(180, 790.0), Vector2(1740, 790.0)],
				},
			},
			{
				"trigger": "prev_half",   # 1웨이브 절반 처치 시 — 자폭병 러셔 + 저격 도입
				"banner":  "WAVE 2",
				"enemies": {
					"bomber": [Vector2(150, 790.0), Vector2(1770, 790.0)],
					"sniper": [Vector2(340, 490.0)],
				},
			},
			{
				"trigger": "prev_clear",  # 2웨이브 전멸 시 — 최고조: 방패병 중앙 돌파 + 순찰 + 저격 양쪽
				"banner":  "FINAL WAVE",
				"enemies": {
					"shield": [Vector2(960, 790.0)],
					"patrol": [Vector2(180, 790.0), Vector2(1740, 790.0)],
					"sniper": [Vector2(340, 490.0), Vector2(1580, 490.0)],
					# 막4 재머 흔해짐(act_identity §6) — datacenter 패턴(절정 웨이브 교란). 우측 바리케이드
					# (1180·1450) 구간과 우측 저격(1580) 마커가 반경(340) 안에서 꺼진다 — 우측 pop이 블라인드.
					# 좌측(340·740)은 반경 밖 유지(비대칭, fair). ENEMY_CLEAR라 반드시 처치("우선 표적").
					"jammer": [Vector2(1240, 790.0)],
				},
			},
		],
		# 폴백 enemies (waves 미인식 환경에서도 비슷한 도전이 되도록 합집합)
		"enemies": {
			"patrol": [Vector2(180, 790.0), Vector2(1740, 790.0)],
			"bomber": [Vector2(150, 790.0), Vector2(1770, 790.0)],
			"sniper": [Vector2(340, 490.0), Vector2(1580, 490.0)],
			"shield": [Vector2(960, 790.0)],
			"drone":  [],
			"jammer": [Vector2(1240, 790.0)],
		},
		"rewards": {
			# 안쪽 엄폐 뒤(안전) xp / 중앙 뒤 hp — 거점을 오래 비우지 않게 중앙 근처에.
			"xp_orbs":    [Vector2(740, 760.0), Vector2(1180, 760.0)],
			"hp_pickups": [Vector2(960, 700.0)],
		},
		"spikes": [],
		"arena_clear_xp": 5,
	}
