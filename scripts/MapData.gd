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

static func get_layout(route_id: String) -> Dictionary:
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
		"route_lab":        return _lab()
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
			{"pos": Vector2(1150, 1085), "w": 64.0},  # 둥지(중상층) — 우측 (ROOF 5 근처)
			{"pos": Vector2(130, 645),   "w": 64.0},  # 둥지(상층) — 좌측 (ROOF 6 근처)
		],
		# 저격수가 전부 측면 단독 둥지(회피 전용) — VEIL "못 잡는 적 안내"(_tick_avoid_warning)가 이 플래그로 발화.
		"nest_snipers": true,
		"enemies": {
			# stage 0~1 등장 — 드론 제거. 저격수는 메인 옥상 발판이 아닌 측면 단독 둥지에서 사선 확보
			# (사용자 피드백: patrol과 같은 평범한 발판에 섞이지 않게). 엇갈린 좌/우.
			"patrol": [Vector2(640, 2095.0), Vector2(640, 1655.0), Vector2(560, 1305.0)],
			"sniper": [
				Vector2(1150, 1057.0),  # 둥지(중상층, ROOF 5 근처)
				Vector2(130, 617.0),    # 둥지(상층, ROOF 6 근처)
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

# ─── 4. 폐쇄 지하철 (HORIZONTAL, 매우 긴 가로 + 낮은 천장) ─────
static func _subway() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(5600.0, 480.0),
		"player_start": Vector2(140.0, 380.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(5480.0, 380.0),
		"camera_mode":  "HORIZONTAL",
		"ground_y":     420.0,  # 지면 높이 커스텀 (천장 낮음 강조)
		"platforms": [
			# 열차 지붕
			{"pos": Vector2(600, 220),  "w": 700.0},
			{"pos": Vector2(1600, 220), "w": 700.0},
			{"pos": Vector2(2700, 220), "w": 700.0},
			{"pos": Vector2(3800, 220), "w": 700.0},
			{"pos": Vector2(4900, 220), "w": 500.0},
			# 지붕 진입 발판 (객차 측면)
			{"pos": Vector2(560, 320),  "w": 60.0},
			{"pos": Vector2(1560, 320), "w": 60.0},
			{"pos": Vector2(2660, 320), "w": 60.0},
			{"pos": Vector2(3760, 320), "w": 60.0},
			# 지면 잔해
			{"pos": Vector2(1380, 380), "w": 100.0},
			{"pos": Vector2(2480, 380), "w": 100.0},
			{"pos": Vector2(3580, 380), "w": 100.0},
			{"pos": Vector2(4680, 380), "w": 100.0},
		],
		"enemies": {
			"patrol": [Vector2(800, 420.0), Vector2(2000, 420.0), Vector2(3200, 420.0), Vector2(4400, 420.0)],
			"sniper": [Vector2(900, 200.0), Vector2(2900, 200.0)],
			"drone":  [],
			"bomber": [],
			"shield": [Vector2(1500, 420.0), Vector2(3500, 420.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(2000, 200.0), Vector2(2050, 200.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		# 발사 함정 — 지붕 밑면 장착 하향 포탑 + 바닥 포탑. 탐지선(tripwire)은 포탑과 분리 배치:
		# x1350 레이저를 가로지르면 앞쪽(1550/1780) 포탑이 일제 발사 → 달려들며 회피.
		"traps": [
			{"x": 700,  "y": 238.0, "dir": "down", "interval": 1.6, "phase": 0.0},   # 지붕1 밑 (주기)
			{"x": 1550, "y": 238.0, "dir": "down", "mode": "triggered", "trigger_id": "tw1", "burst": 3},
			{"x": 1780, "y": 238.0, "dir": "down", "mode": "triggered", "trigger_id": "tw1", "burst": 3},
			{"x": 2800, "y": 238.0, "dir": "down", "interval": 1.6, "phase": 0.6},    # 지붕3 밑 (주기)
			{"x": 3760, "y": 414.0, "dir": "up",   "interval": 1.8, "phase": 0.3},    # 바닥 포탑 (지붕 진입 발판 견제)
		],
		"tripwires": [
			# 통로 가로지르는 세로 레이저 — 밟으면 앞쪽 triggered 포탑(tw1) 발동.
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

			# 비밀 통로 — 분기점에서 좌측 더블점프. XP 2 + HP 1 보너스.
			{"pos": Vector2(120, 2205), "w": 100.0},  # 사다리 진입
			{"pos": Vector2(80, 2305), "w": 140.0},   # 비밀 끝 — XP 2 + HP 1

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
			# 외부 끝 XP 2, 내부 끝 HP 1, 비밀 사다리 끝 XP 2 + HP 1
			# 상층 sniper post — 중층 XP 2, 정상 HP 1 (감시탑 정상에서 한숨 돌릴 자리)
			"xp_orbs":    [
				Vector2(160, 1655.0), Vector2(200, 1655.0),   # 외부 끝(1685)
				Vector2(60, 2275.0), Vector2(100, 2275.0),    # 비밀(2305)
				Vector2(620, 1305.0), Vector2(660, 1305.0),   # post1(1335)
				Vector2(660, 1085.0), Vector2(700, 1085.0),   # 상층 슬랩(1115) 보너스
			],
			"gate_orbs":  [],
			"hp_pickups": [
				Vector2(640, 1655.0),   # 내부 끝(1685)
				Vector2(80, 2275.0),    # 비밀
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

# ─── 12. 서버 회랑 (HORIZONTAL, 막3 전투 — 핵심부 직전) ────────────────
# A2 신규 맵. datacenter(ARENA 웨이브)와 달리 긴 통과형 회랑 — 드론·저격을 랙(발판)으로
# 엄폐하며 빠져나간다. 막3 onset(시야붕괴)이 여기서 켜질 수 있다(is_late_act).
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
			# 핵심부 직전 — 드론·저격 동시 압박(데이터센터와 같은 적, 통과형 회랑).
			"patrol": [Vector2(900, 600), Vector2(2200, 600), Vector2(3400, 600)],
			"sniper": [Vector2(1500, 438), Vector2(3500, 438)],
			"drone":  [Vector2(2500, 180), Vector2(4050, 180)],
			"bomber": [], "shield": [],
		},
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
			# 저격 — 변압기 위 거치. 노출 구간 사선.
			"sniper": [Vector2(1520, 428.0), Vector2(2520, 428.0)],
			# 드론 — 머리 위 호버(상성=글라이드).
			"drone":  [Vector2(1300, 230.0), Vector2(2700, 240.0)],
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
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3000.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2880.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 펌프/파이프 발판.
			{"pos": Vector2(540, 460),  "w": 190.0},
			{"pos": Vector2(1000, 460), "w": 190.0},
			{"pos": Vector2(1460, 460), "w": 200.0},
			{"pos": Vector2(1960, 460), "w": 190.0},
			{"pos": Vector2(2440, 470), "w": 200.0},
		],
		"enemies": {
			"patrol": [Vector2(800, 600.0), Vector2(2200, 600.0)],
			# 저격 — 파이프 위 거치. 사선 끊으며 전진.
			"sniper": [Vector2(1460, 428.0), Vector2(2440, 438.0)],
			"drone":  [],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1000, 430.0), Vector2(1960, 430.0)],
			"hp_pickups": [Vector2(2440, 440.0)],
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
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3200.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3080.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			{"pos": Vector2(560, 470),  "w": 200.0},
			{"pos": Vector2(1080, 460), "w": 180.0},
			{"pos": Vector2(1640, 470), "w": 200.0},
			{"pos": Vector2(2160, 460), "w": 180.0},
			{"pos": Vector2(2680, 470), "w": 200.0},
		],
		"enemies": {
			"patrol": [Vector2(820, 600.0), Vector2(2400, 600.0)],
			"sniper": [Vector2(1640, 438.0)],
			"drone":  [],
			"bomber": [],
			"shield": [Vector2(2160, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1080, 430.0), Vector2(2160, 430.0)],
			"hp_pickups": [Vector2(2680, 440.0)],
		},
		"spikes": [],
		# 검문선(세로 레이저) 밟으면 앞쪽 triggered 포탑(cp1) 일제 발사 → 달려들며 회피.
		"traps": [
			{"x": 1500, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "cp1", "burst": 3},
			{"x": 1760, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "cp1", "burst": 3},
		],
		"tripwires": [
			{"x": 1300, "y": 540.0, "dir": "up", "len": 200.0, "trigger_id": "cp1", "cooldown": 2.4},
		],
	}

# ─── 22. 통제실 회랑 (HORIZONTAL, 막3 전투 s6) — 드론+저격 통과형(server_hall 계열) ──
# 막3 전투 풀(s6)의 4번째 선택지. datacenter/server_hall과 같은 적, 핵심부 접근 회랑.
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
			"patrol": [Vector2(900, 600.0), Vector2(2300, 600.0), Vector2(3500, 600.0)],
			"sniper": [Vector2(1560, 438.0), Vector2(3060, 438.0)],
			"drone":  [Vector2(2060, 180.0), Vector2(3600, 180.0)],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(2060, 440.0), Vector2(3060, 438.0), Vector2(3600, 440.0)],
			"hp_pickups": [Vector2(1080, 440.0)],
		},
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
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3300.0, 720.0),
		"player_start": Vector2(140.0, 520.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3160.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"platforms": [
			# 수직 리프트 상단 보너스 알코브 받침(선택 경로)
			{"pos": Vector2(1330, 300), "w": 150.0},
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
		],
		"enemies": {
			"patrol": [Vector2(460, 540.0), Vector2(2180, 540.0), Vector2(2980, 540.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1300, 270.0), Vector2(1360, 270.0)],
			"hp_pickups": [],
		},
		"spikes": [
			{"x": 960.0, "w": 300.0, "dmg": 2},    # 구덩이 1
			{"x": 1770.0, "w": 320.0, "dmg": 2},   # 구덩이 2
			{"x": 2600.0, "w": 300.0, "dmg": 2},   # 구덩이 3
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
		"goal_pos":     Vector2(2860.0, 540.0),
		"camera_mode":  "HORIZONTAL",
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
			# 앞쪽 warmup patrol(엄폐로 접근해 잡는 법 학습) + 뒤쪽 저격 2(목표 접근 처벌).
			"patrol": [Vector2(880, 540.0)],
			"sniper": [Vector2(2560, 540.0), Vector2(2740, 540.0)],
			"drone": [], "bomber": [], "shield": [],
		},
		# 발사 함정 — 오른쪽 벽에서 통로를 왼쪽으로 훑어 먼 쪽 차량부터 침식(목표 근처 노출 압박).
		"traps": [
			{"x": 2900.0, "y": 560.0, "dir": "left", "interval": 1.8, "phase": 0.0, "telegraph": 0.6, "dmg": 1},
		],
		"rewards": {
			"xp_orbs":    [Vector2(600, 560.0), Vector2(1200, 560.0), Vector2(1880, 560.0)],
			"hp_pickups": [Vector2(2300, 560.0)],  # 마지막 트로프 — 노출된 최종 진입 전 회복
		},
		"spikes": [],
	}
