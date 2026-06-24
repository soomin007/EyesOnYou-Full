class_name MapData
extends RefCounted

# 11개 맵의 세계 형태 + platform/적 spawn/보상/함정 통합 명세.
# 명세: docs/design/world_layout.md
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
		"world_size":   Vector2(1280.0, 3200.0),
		"player_start": Vector2(640.0, 3050.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(640.0, 200.0),
		"camera_mode":  "VERTICAL",
		"platforms": [
			# 지상(3080) → 저층 옥상(2680) — 비상사다리 2 step + 옥상 1
			{"pos": Vector2(560, 2960), "w": 220.0},  # 120 (1 빠듯) 비상사다리
			{"pos": Vector2(740, 2840), "w": 220.0},  # 120 (1 빠듯) 비상사다리
			{"pos": Vector2(640, 2680), "w": 480.0},  # 160 (2) — ROOF 1 (저층 옥상, patrol)

			# 저층 → 중층 옥상(2360) — HVAC 2 step + 옥상 1
			{"pos": Vector2(420, 2540), "w": 180.0},  # 140 (2) HVAC 박스
			{"pos": Vector2(700, 2440), "w": 180.0},  # 100 (1) AC 유니트
			{"pos": Vector2(560, 2360), "w": 440.0},  # 80 (1) — ROOF 2 (중층 옥상)

			# 중층 → 분기 옥상(2040) — 스카이라이트 2 step + 옥상 1
			{"pos": Vector2(820, 2240), "w": 180.0},  # 120 (1 빠듯) 스카이라이트
			{"pos": Vector2(540, 2120), "w": 180.0},  # 120 (1 빠듯)
			{"pos": Vector2(640, 2040), "w": 520.0},  # 80 (1) — ROOF 3 (분기점, patrol)

			# 비밀 통로 — ROOF 3에서 우측 멀리 더블점프 → 안테나 발판 → 비밀 옥상.
			# 시야 밖(우측 외곽)이라 호기심 있는 사람만 발견. XP 2 + HP 1 보너스.
			{"pos": Vector2(1130, 2160), "w": 100.0}, # 안테나 발판
			{"pos": Vector2(1180, 2280), "w": 140.0}, # 비밀 옥상 끝 — XP 2 + HP 1
			# (이전의 글라이드 게이트 알코브(1180,2060) 제거 — 바로 아래 안테나 발판(2160)이 100px
			#  거리라 더블점프로 닿아 글라이드 게이트가 무의미했고, stage 0엔 글라이드 자체가 없음.
			#  비밀 보상은 비밀 옥상 끝 XP 2 + HP 1로 충분. 사용자 피드백 2026-06-12.)

			# 분기 우측(XP) — 노출된 옥상 가장자리. 짧음(2 발판).
			{"pos": Vector2(960, 1900), "w": 200.0},  # 140 (2)
			{"pos": Vector2(1080, 1820), "w": 180.0}, # 80 (1) — XP 끝

			# 분기 좌측(HP) — 안전한 안쪽. 짧음(2 발판).
			{"pos": Vector2(320, 1900), "w": 200.0},  # 140 (2)
			{"pos": Vector2(200, 1820), "w": 180.0},  # 80 (1) — HP 끝

			# 합류 — 양쪽 끝(1820)에서 1700 (120) → ROOF 4
			{"pos": Vector2(560, 1700), "w": 440.0},  # ROOF 4 합류

			# 상층 — sniper post 2개 + 옥상 슬랩으로 콘텐츠 채움. 이전 9단 모놀로직 step → 8단 + 보상.
			{"pos": Vector2(720, 1540), "w": 240.0},  # 160 (2)
			{"pos": Vector2(540, 1380), "w": 240.0},  # 160 (2)
			{"pos": Vector2(660, 1220), "w": 400.0},  # 160 (2) — ROOF 5 (sniper post 1)
			{"pos": Vector2(540, 1060), "w": 240.0},  # 160 (2)
			{"pos": Vector2(680, 900),  "w": 240.0},  # 160 (2)
			{"pos": Vector2(560, 740),  "w": 400.0},  # 160 (2) — ROOF 6 (sniper post 2, HP 보상)
			{"pos": Vector2(680, 580),  "w": 240.0},  # 160 (2)
			{"pos": Vector2(540, 420),  "w": 240.0},  # 160 (2)
			{"pos": Vector2(620, 280),  "w": 320.0},  # 140 (2) — 골 직전

			# 저격 둥지 — 메인 경로 밖 측면 단독 발판. 경로를 가로질러 내려다봄(올라설 필요 없음).
			{"pos": Vector2(1150, 1240), "w": 64.0},  # 둥지(중상층) — 우측
			{"pos": Vector2(130, 760),   "w": 64.0},  # 둥지(상층) — 좌측
		],
		# 저격수가 전부 측면 단독 둥지(회피 전용) — VEIL "못 잡는 적 안내"(_tick_avoid_warning)가 이 플래그로 발화.
		"nest_snipers": true,
		"enemies": {
			# stage 0~1 등장 — 드론 제거. 저격수는 메인 옥상 발판이 아닌 측면 단독 둥지에서 사선 확보
			# (사용자 피드백: patrol과 같은 평범한 발판에 섞이지 않게). 엇갈린 좌/우.
			"patrol": [Vector2(640, 2650.0), Vector2(640, 2010.0), Vector2(560, 1670.0)],
			"sniper": [
				Vector2(1150, 1212.0),  # 둥지(중상층)
				Vector2(130, 732.0),    # 둥지(상층)
			],
			"drone":  [],
			"bomber": [], "shield": [],
		},
		"rewards": {
			# 일반 분기 — 우측 XP 2, 좌측 HP 1
			# 비밀 옥상 — XP 2 + HP 1 보너스
			# 상층 sniper post — ROOF 5에 XP 2(보너스), ROOF 6에 HP 1(보스 보충)
			"xp_orbs":    [
				Vector2(1060, 1790.0), Vector2(1100, 1790.0),
				Vector2(1160, 2250.0), Vector2(1200, 2250.0),
				Vector2(640, 1190.0), Vector2(680, 1190.0),
			],
			# 글라이드 게이트 없음 — stage 0 맵이라 글라이드 미보유. 비밀 보상은 비밀 옥상 끝 XP/HP로 충분.
			"hp_pickups": [
				Vector2(200, 1790.0),
				Vector2(1180, 2250.0),
				Vector2(560, 710.0),
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
		"world_size":   Vector2(1280.0, 3200.0),
		"player_start": Vector2(640.0, 3050.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(640.0, 200.0),
		"camera_mode":  "VERTICAL",
		"platforms": [
			# 지상(3080) → 분기점(2440) — gap 100/120/140 섞기 (6 → 5 발판)
			{"pos": Vector2(560, 2960), "w": 280.0},  # 120 (1 빠듯)
			{"pos": Vector2(700, 2840), "w": 240.0},  # 120 (1 빠듯) — patrol 자리
			{"pos": Vector2(540, 2700), "w": 240.0},  # 140 (2)
			{"pos": Vector2(660, 2580), "w": 240.0},  # 120 (1 빠듯)
			{"pos": Vector2(640, 2440), "w": 360.0},  # 140 (2) — 분기점, patrol 자리

			# 비밀 통로 — 분기점에서 좌측 멀리 더블점프. 시야 외곽 발판.
			# 보안 통로 측면 사다리 컨셉. XP 2 + HP 1 보너스.
			{"pos": Vector2(120, 2540), "w": 100.0},  # 사다리 진입
			{"pos": Vector2(80, 2660), "w": 140.0},   # 비밀 끝 — XP 2 + HP 1

			# 분기 — 외부 노출 (좌측, sniper 노출 + XP). 6 → 4 발판.
			{"pos": Vector2(280, 2280), "w": 220.0},  # 160 (2 진입)
			{"pos": Vector2(160, 2140), "w": 200.0},  # 140 (2)
			{"pos": Vector2(280, 1980), "w": 220.0},  # 160 (2) — patrol 자리
			{"pos": Vector2(180, 1820), "w": 220.0},  # 160 (2) — 외부 끝 (XP)

			# 분기 — 내부 계단 (중앙). 6 → 4 발판.
			{"pos": Vector2(540, 2280), "w": 240.0},  # 160 (2 진입)
			{"pos": Vector2(660, 2140), "w": 240.0},  # 140 (2)
			{"pos": Vector2(540, 1980), "w": 240.0},  # 160 (2) — patrol 자리
			{"pos": Vector2(640, 1820), "w": 280.0},  # 160 (2) — 내부 끝 (HP)

			# 합류 — 두 끝(1820)에서 1680 (140) → 단일 경로
			{"pos": Vector2(560, 1680), "w": 320.0},

			# 상층 — 감시탑 정상 컨셉 살려 sniper post 2개 + 광폭 발판 추가.
			{"pos": Vector2(720, 1520), "w": 240.0},  # 160 (2)
			{"pos": Vector2(540, 1360), "w": 240.0},  # 160 (2)
			{"pos": Vector2(660, 1180), "w": 400.0},  # 180 (2 빠듯) — 중층 정찰단 (sniper post 1)
			# 글라이드 게이트 — 정찰단(1180) 우측 끝(x820) 위 220px 단독 알코브. 위가 비어(1020 발판은
			# x420~660, 860 발판은 x560~800) 순수 수직 220 hop. 더블(190) 못 닿고 삼단(381)으로만.
			{"pos": Vector2(820, 960), "w": 90.0},
			{"pos": Vector2(540, 1020), "w": 240.0},  # 160 (2)
			{"pos": Vector2(680, 860),  "w": 240.0},  # 160 (2)
			{"pos": Vector2(560, 700),  "w": 400.0},  # 160 (2) — 정상 정찰단 (sniper post 2)
			{"pos": Vector2(680, 540),  "w": 240.0},  # 160 (2)
			{"pos": Vector2(540, 380),  "w": 240.0},  # 160 (2)
			{"pos": Vector2(620, 280),  "w": 320.0},  # 100 (1) — 골 직전

			# 저격 둥지 — 메인 경로에서 떨어진 측면 단독 발판(엇갈린 좌/우). 경로를 가로질러 내려다봄.
			# 플레이어는 둥지에 올라설 필요 없이 사선만 통과(엄폐·사거리로 회피). 글라이드로 가서 처치는 선택.
			{"pos": Vector2(1150, 2000), "w": 64.0},  # 둥지(하중층) — 우측
			{"pos": Vector2(120, 1200),  "w": 64.0},  # 둥지(중층) — 좌측
			{"pos": Vector2(1150, 720),  "w": 64.0},  # 둥지(상층) — 우측
		],
		# 저격수가 전부 측면 단독 둥지(회피 전용) — VEIL "못 잡는 적 안내"(_tick_avoid_warning)가 이 플래그로 발화.
		"nest_snipers": true,
		"enemies": {
			# 감시탑 = sniper 컨셉. 저격수는 메인 경로 발판이 아닌 측면 단독 둥지에 배치(사용자 피드백:
			# patrol과 같은 평범한 발판에 섞이지 않게). 엇갈린 좌/우라 한 번에 한 명씩 사선에 노출.
			"patrol": [Vector2(700, 2810.0), Vector2(280, 1950.0), Vector2(540, 1950.0)],
			"sniper": [
				Vector2(1150, 1972.0),  # 둥지(하중층)
				Vector2(120, 1172.0),   # 둥지(중층)
				Vector2(1150, 692.0),   # 둥지(상층)
			],
			"drone":  [],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			# 외부 끝 XP 2, 내부 끝 HP 1, 비밀 사다리 끝 XP 2 + HP 1
			# 상층 sniper post — 중층 XP 2, 정상 HP 1 (감시탑 정상에서 한숨 돌릴 자리)
			"xp_orbs":    [
				Vector2(160, 1790.0), Vector2(200, 1790.0),
				Vector2(60, 2630.0), Vector2(100, 2630.0),
				Vector2(640, 1150.0), Vector2(680, 1150.0),
				# (구 글라이드 게이트) 알코브(820,960)가 윗 발판(680,860)에서 그냥 닿아 게이트로
				# 기능 못 함 → 일반 XP로 강등(2026-06-13). 제대로 된 글라이드 게이트는 냉각 리뉴얼에.
				Vector2(800, 938.0), Vector2(840, 938.0),
			],
			"gate_orbs":  [],
			"hp_pickups": [
				Vector2(640, 1790.0),
				Vector2(80, 2630.0),
				Vector2(560, 670.0),
			],
		},
		"spikes": [],
		# 수직 등반 압박 — 벽면 가로 포탑(타이밍 회피 / 글라이드로 지나치기). 가로탄 사거리 ~736px라
		# 등반 경로를 한 높이씩 가로질러 "지나갈 때를 노리는" 라인이 됨.
		# (이전의 합류 직전 트립와이어 + 하향 버스트 포탑은 등반 동선과 어긋나 무효였음 → 제거. 등반
		#  위협은 완화된 둥지 저격수 + 가로 포탑 둘로 단순화. 사용자 피드백 2026-06-11.)
		"traps": [
			# 발판 top이 아니라 **갭(점프 경로) 높이**에 둬 통과 시 몸통을 지나가게(같은 높이면 무해).
			{"x": 1240, "y": 1440.0, "dir": "left",  "interval": 2.0, "phase": 0.0},   # 1520↔1360 갭 가로지름
			{"x": 40,   "y": 2060.0, "dir": "right", "interval": 2.0, "phase": 1.0},   # 분기 2140↔1980 갭 가로지름
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
