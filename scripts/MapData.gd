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

# 라우트의 방 수(체인 아니면 1) — BotRunner가 방별 주파 루프를 돌 때 사용.
static func segment_count(route_id: String) -> int:
	var segs: Array = _layout_raw(route_id).get("segments", [])
	return maxi(1, segs.size())

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
		"route_bot_bench":     return _bot_bench()
		"route_bot_bench_late": return _bot_bench_late()
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
		# 시그니처 · 돌풍(map_identity_rework §5 "옥상 = 바람·낙하" · 2026-08-17 표류 보정형 확정):
		# 예고 1.3s(먼지 줄기 가속) → 돌풍 2.6s(공중 표류 점프당 ~100px, 지상 미미) · 방향 교대.
		# 낙하 = 아래 지붕으로 추락(등반 맵의 자연 페널티) · 즉사 없음.
		"wind": {"calm": 7.0, "telegraph": 1.3, "gust": 2.6, "speed": 170.0},
		"route_lines": [
			# 낙하 = 무피해 명시 · "어디부터 낙하 대미지냐" 혼동(사용자 2026-08-17) · 이 게임에
			# 낙하 피해는 어디에도 없다. 떨어짐 = 오른 만큼 재등반(시간 손실)뿐임을 말로 고정.
			{"y": 2150.0, "who": "veil", "text": "바람이 붑니다. 몸이 뜨면 옆으로 밀립니다. 떨어져도 다치지는 않지만, 오른 만큼 다시 올라야 합니다.", "dur": 4.2},
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

# ─── 3. 옛 배수로 (VERTICAL_DOWN) ───────────────────────────
# 위에서 아래로 내려감 — 분기 좌(적 많음/XP) vs 우(가시 함정/HP)
# 가시는 우측 통로의 다른 y에 분산 배치 (이전엔 spike y 버그로 모두 GROUND_Y에 겹침)
# ─── 옛 배수로 · **수위 체인 2방**(map_identity_rework §5 "하수도 = 수위 변화", 2026-08-17) ─
# 정체성 = 옛 배수로의 살아 있는 펌프. 방1 유입 수로(수평 · 수위 리듬 학습) → 방2 침수 정션
# (기존 수직 하강 + 하부 침수 사이클 = "빠졌을 때 내려간다"). 확산(④) 첫 적용.
static func _sewers() -> Dictionary:
	return {"segments": [_sewers_inflow(), _sewers_junction()]}

# 방1 · 유입 수로. 수위 사이클 도입 · 물이 차면 대피 발판으로, 빠지면 바닥으로 전진.
# 체류 하한 = 2200÷240 ≈ 9s + 사이클 대기 → 수위 1~2회 조우(계산 근거, known_issues 규칙).
static func _sewers_inflow() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2200.0, 720.0),
		"player_start": Vector2(140.0, 560.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2080.0, 560.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "sewer_inflow",
		# 실내(지하) · 수평 맵 기본 배경의 도시 실루엣이 지하 배수로에 새는 것 차단
		# (지하철 2026-08-15 지적과 동형). subway env = 기둥 없는 터널 벽.
		"indoor_env":   "subway",
		"water_level": {"low_y": 700.0, "high_y": 530.0, "rise": 2.0, "hold_high": 3.2,
			"fall": 1.6, "hold_low": 4.5},
		"platforms": [
			# 대피 스텝 · 만수위(530)보다 위. 어디서든 반 박자면 닿는 간격(최대 공백 ~265px).
			{"pos": Vector2(520, 470),  "w": 180.0},
			{"pos": Vector2(1050, 460), "w": 200.0},
			{"pos": Vector2(1580, 470), "w": 180.0},
			{"pos": Vector2(2000, 480), "w": 160.0},
		],
		"enemies": {
			"patrol": [Vector2(760, 560.0), Vector2(1700, 560.0)],
			"sniper": [], "bomber": [], "shield": [],
			"drone":  [Vector2(1300, 430.0)],
		},
		"route_lines": [
			{"x": 240.0, "who": "veil", "text": "펌프가 아직 살아 있습니다. 물이 차오르면 높은 발판으로 오르십시오. 잠긴 채 버티면 몸이 상합니다.", "dur": 4.0},
			# 적 방수 설명 · "나만 잠기고 적은 왜 괜찮냐"(사용자 2026-08-17) · 경비 = 밀폐 기계 유닛.
			{"x": 860.0, "who": "veil", "text": "경비 유닛은 밀폐 설계라 물속에서도 멀쩡합니다. 요원은 아닙니다. 조심하십시오.", "dur": 3.8},
		],
		"rewards": {
			# 바닥 보상 · 수위가 낮을 때만 편하게 줍는다(리듬과 보상의 결합).
			"xp_orbs":    [Vector2(900, 570.0), Vector2(1350, 570.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		# 수위 리듬이 시그니처 · 자동 가시 폴백 차단(체인 세그먼트 전부 명시, known_issues).
		"no_spike_fallback": true,
	}

# 방2 · 침수 정션. 기존 수직 하강 레이아웃 + 하부 침수 사이클(합류부 y1520 아래가 잠긴다).
# 물이 빠졌을 때 하강, 차오르면 합류부(y1440) 위에서 대기 · 잠긴 채 강행도 선택(피해 감수).
static func _sewers_junction() -> Dictionary:
	return {
		"world_type":   "VERTICAL_DOWN",
		"world_size":   Vector2(1280.0, 2400.0),
		"player_start": Vector2(640.0, 160.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(640.0, 2250.0),
		"camera_mode":  "VERTICAL",
		"ambience":     "sewer_junction",
		"water_level": {"low_y": 2500.0, "high_y": 1520.0, "rise": 2.6, "hold_high": 5.0,
			"fall": 2.2, "hold_low": 9.0, "start_delay": 0.5},
		"route_lines": [
			{"y_down": 900.0, "who": "veil", "text": "아래는 물이 오르내리는 구간입니다. 빠졌을 때 내려가고, 차오르면 위에서 기다리십시오.", "dur": 4.0},
		],
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

# 방1 · 승강장. 폐역 홀 전투: 트인 홀 + 경비. 승강장 단(낮은 발판)이 지형.
# 2026-08-17 정리(사용자): 무릎 높이 솔리드 잔해 제거(총알만 먹고 이동만 불편) +
# 자동 가시 폴백 차단(정체불명 가시가 깔리던 문제 · known_issues "자동 가시 폴백").
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
		"indoor_env":   "subway",
		"platforms": [
			{"pos": Vector2(700, 340),  "w": 260.0},   # 승강장 단
			{"pos": Vector2(1350, 340), "w": 260.0},
		],
		"enemies": {
			"patrol": [Vector2(650, 420.0), Vector2(1500, 420.0)],
			"sniper": [], "drone": [], "bomber": [],
			"shield": [Vector2(1000, 420.0)],
		},
		"rewards": {"xp_orbs": [Vector2(1330, 310.0), Vector2(1370, 310.0)], "hp_pickups": []},
		"spikes": [],
		"no_spike_fallback": true,
	}

# 방2 · 선로. 시그니처 = 무인 화물 열차(TrainHazard): 신호등 적색 전환(2.2s 예고) 후 고속 통과,
# 대뎀 2 + 넉백(즉사 아님, 사용자 확정). 대피 = 벽의 홈(cover_niches) / 승강장 조각 단차 / 타이밍 점프.
# 2026-08-17 재설계(사용자 "4~5회라더니 2회"): 조우 횟수는 위치 트리거로 보장(플레이 속도 무관,
# known_issues "체류 시간" 규칙). interval은 정지 시 배경 리듬용 폴백.
# 2026-08-18 재조정(사용자 "거의 계속 지나다니는 느낌"): 트리거 4→3 + TrainHazard MIN_GAP 6.5s.
# 정직 실주기 = 예고 2.2 + 통과 ~2.2 + 간격 6.5 ≈ 11s/회 · 주파 19s(4600÷240)에 보장 3회가 상한.
# 열차는 적도 친다(2026-08-18 "왜 적은 안 치이지") — 선로 경비를 열차에 밀어 넣는 전술 성립.
# 무릎 높이 화물차 잔해 솔리드는 제거(총알만 먹음 · 방1과 동형 정리).
#
# 2026-08-19 재설계(사용자 "첫 열차 한 번에 맵이 싹 정리되고 경험치 방울만 남는다"):
# 원인은 열차가 아니라 배치였다 — 방이 완전 평면이고 적 전원이 선로 대역(바닥 위 130px) 위에
# 서 있어서, 전 구간을 훑는 첫 열차가 방 하나를 통째로 청소했다. 두 축으로 고친다.
#   ① 층을 만든다 — 승강장 단을 길게(w 520~600) 늘려 "선로 = 건너는 곳 / 승강장 = 싸우는 곳"
#      구조로. 지속 위협인 저격은 승강장 위(열차 세이프)에 두어 열차가 지나도 방이 안 빈다.
#   ② 지상 경비는 벽감 안에서 시작한다 — 경비도 열차를 피할 줄 안다는 배치. 플레이어가
#      접근해 끌어내야 선로로 나오므로, 열차 처치는 자동 청소가 아니라 유인 전술이 된다.
# 환경 처치는 무보상(Enemy.env_killed) — 밀어 넣어 얻는 건 안전이지 경험치가 아니다.
static func _subway_tracks() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(4600.0, 480.0),
		"player_start": Vector2(140.0, 380.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(4480.0, 380.0),
		"camera_mode":  "HORIZONTAL",
		"ground_y":     420.0,
		"ambience":     "subway_tracks",
		"indoor_env":   "subway",
		"train_hazard": {"interval": 9.0, "telegraph": 2.2, "speed": 2400.0, "dmg": 2,
			"triggers": [520.0, 2100.0, 3700.0],
			"lights": [500.0, 1500.0, 2500.0, 3500.0, 4300.0]},
		"cover_niches": [650.0, 1500.0, 2200.0, 3150.0, 4050.0],
		"niche_half":   90.0,
		"platforms": [
			# 승강장 단 · 열차 대역(바닥 위 130px) 밖 = 세이프. 여기가 교전 무대다.
			{"pos": Vector2(1000, 270), "w": 560.0},
			{"pos": Vector2(2650, 270), "w": 600.0},
			{"pos": Vector2(3820, 270), "w": 520.0},
			# 승강장 오르는 발디딤 · 각 단의 왼쪽 끝 바깥에 두어 "올라타는 자리"가 읽히게 한다
			# (단 아래에 두면 머리를 찧는 자리처럼 보인다).
			{"pos": Vector2(640, 348),  "w": 110.0},
			{"pos": Vector2(2270, 348), "w": 110.0},
			{"pos": Vector2(3480, 348), "w": 110.0},
		],
		"enemies": {
			# 지상 순찰은 벽감 안에서 대기(열차 세이프) · 끌어내야 선로로 나온다.
			# 2→4 증원(갤러리 2026-08-25 "경비가 몇 없어 유인 전술을 생각할 겨를도 없었음") —
			# 4600px 룸의 벽감 구역마다 1명씩, "열차로 치우기"가 반복 선택지로 성립하게.
			"patrol": [Vector2(1500, 420.0), Vector2(2200, 420.0), Vector2(3150, 420.0), Vector2(4050, 420.0)],
			# 승강장 위 저격 · 열차가 지나도 남는 지속 위협. 올라가 잡거나 아래에서 각을 잡거나.
			"sniper": [Vector2(1000, 248.0), Vector2(2800, 248.0)],
			"drone": [], "bomber": [], "shield": [],
		},
		"route_lines": [
			# EN: "The track is still live. When the signal turns red, a train is coming.
			#      Duck into a marked recess and hide, or get up onto a platform."
			{"x": 260.0, "who": "veil", "text": "선로가 아직 살아 있습니다. 신호가 붉어지면 열차가 옵니다. 파란 띠가 칠해진 대피 칸에 들어가 숨거나, 높은 발판으로 오르십시오.", "dur": 4.0},
			{"x": 1400.0, "who": "veil", "text": "열차는 누구 편도 아닙니다. 경비를 선로로 끌어내면 대신 치워 줍니다. 다만 그렇게 치운 건 아무것도 남지 않습니다.", "dur": 4.0},
		],
		"rewards": {
			# 위험 보상 · 벽감 사이 선로 위(열차 리스크를 지나야 먹는다).
			"xp_orbs":    [Vector2(1200, 390.0), Vector2(2900, 390.0), Vector2(3950, 390.0)],
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
		"indoor_env":   "subway",
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
		# 자동 가시 폴백 차단 · 방1과 동형(체인 세그먼트 전부 명시, known_issues).
		"no_spike_fallback": true,
	}

# ─── 5. 냉각 시설 (VERTICAL_UP, 지그재그 파이프 + 비밀 스팟) ──
# 냉각 시설 (HORIZONTAL) — 전면 리뉴얼(2026-06-14). 서사 훅: SILO-7이 서버(=VEIL의 하드웨어)를
# 식히는 냉각 플랜트. 시그니처 해저드 = **증기 분출구(SteamVent)**: 바닥에서 주기적으로 수직 증기가
# 뿜어져 타이밍 보고 지나간다. 드론이 주력(상성=글라이드) → 떠서 증기 넘고 드론 잡는 글라이드 학습 맵.
# 글라이드 게이트는 새 레이아웃이라 *진짜로* 고립(삼단점프=글라이드 T2로만 닿는 알코브).
# 냉각 시설 · 방 체인 3방(2026-08-18 방 체인 전면 확산 1호): 공기 흐름 그대로
# 흡기 → 열교환 → 배기. 시그니처(증기 분출구)는 방마다 밀도·역할이 다르다:
# 방1 = 증기 학습(낮은 밀도) / 방2 = 증기+드론 본 손맛(원 냉각 계승, 글라이드 게이트 유지) /
# 방3 = 증기 최밀 + 배기 밸브 레버 관문(펌프장 ⓐ 재사용). 목표 합산 90~120s.
static func _cooling() -> Dictionary:
	return {"segments": [_cooling_intake(), _cooling_core(), _cooling_exhaust()]}

# 방1 · 흡기 회랑. 증기 3기 엇갈림 — "분출 주기를 보고 지나간다"를 배우는 곳.
static func _cooling_intake() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2800.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "cooling_intake",
		"indoor_env":   "water",   # 냉각 플랜트 = 실내(배관·물 계열) — 야경 스카이라인 오출력 수정(사용자 2026-08-18)
		"platforms": [
			{"pos": Vector2(700, 470),  "w": 180.0},
			{"pos": Vector2(1350, 460), "w": 180.0},
			{"pos": Vector2(1980, 470), "w": 180.0},
		],
		"steam_vents": [
			{"x": 520,  "h": 260.0},
			{"x": 1050, "h": 300.0},
			{"x": 1600, "h": 260.0},
			{"x": 2120, "h": 300.0},
			{"x": 2460, "h": 260.0},
		],
		"enemies": {
			"patrol": [Vector2(880, 540.0), Vector2(1500, 540.0), Vector2(2250, 540.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1350, 430.0), Vector2(1980, 440.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		"no_spike_fallback": true,   # 증기 리듬이 시그니처 · 가시 소음 금지
		"route_lines": [
			{"x": 320.0, "who": "veil", "text": "흡기 라인이 살아 있습니다. 바닥 분출구는 주기가 있으니, 김이 잦아들 때 지나가십시오.", "dur": 4.0},
		],
	}

# 방2 · 열교환 홀(원 냉각 계승). 증기 6기 + 머리 위 드론 — 이 맵의 본 손맛.
# 글라이드 게이트(2120 알코브)도 그대로.
static func _cooling_core() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(4600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(4480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "cooling_core",
		"indoor_env":   "water",
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
			{"pos": Vector2(2980, 470), "w": 200.0},
			# 후반 연장(2026-08-18 방 체인 증량) — 열교환 2열째.
			{"pos": Vector2(3400, 460), "w": 180.0},
			{"pos": Vector2(3850, 440), "w": 180.0},
			{"pos": Vector2(4250, 460), "w": 180.0},  # 골 직전
		],
		# 증기 분출구 — 바닥(GROUND_Y)에서 위로 h만큼 주기 분출. phase 생략 시 Stage가 x로 분산(엇갈림).
		"steam_vents": [
			{"x": 380,  "h": 300.0},
			{"x": 900,  "h": 260.0},
			{"x": 1380, "h": 320.0},
			{"x": 1760, "h": 280.0},
			{"x": 2360, "h": 300.0},
			{"x": 2820, "h": 260.0},
			{"x": 3250, "h": 300.0},
			{"x": 3700, "h": 260.0},
			{"x": 4100, "h": 300.0},
		],
		"enemies": {
			"patrol": [Vector2(820, 540.0), Vector2(2500, 540.0), Vector2(3550, 540.0)],
			"sniper": [],
			# 드론 — 머리 위 호버(상성=글라이드). 통로 위를 점한다.
			"drone":  [Vector2(1180, 250.0), Vector2(1900, 240.0), Vector2(2700, 260.0), Vector2(3850, 250.0)],
			"bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1160, 410.0), Vector2(1200, 410.0), Vector2(2580, 410.0), Vector2(3850, 410.0)],
			# 글라이드 게이트 알코브(2120,180) — 흡인 반경 축소(직접 도달 필요). XP 3.
			"gate_orbs":  [Vector2(2095, 158.0), Vector2(2120, 158.0), Vector2(2145, 158.0)],
			"hp_pickups": [Vector2(2980, 440.0)],
		},
		"spikes": [],
	}

# 방3 · 배기 스택. 증기 최밀 구간을 뚫고 배기 밸브 레버(상단 배관)를 당겨야 격벽이 열린다
# (mid_gate lever = 펌프장 ⓐ 재사용 · 배관 수직 동선). 체인의 절정.
static func _cooling_exhaust() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3200.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3080.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "cooling_exhaust",
		"indoor_env":   "water",
		# 레버 y = 발판 top(440) - 22(레버 받침 바닥 오프셋) — 공중 부양 금지(사용자 2026-08-18).
		"mid_gate": {"x": 2840.0, "mode": "lever", "lever": Vector2(2560.0, 418.0), "own_hint": true},
		"platforms": [
			{"pos": Vector2(620, 460),  "w": 180.0},
			{"pos": Vector2(1150, 440), "w": 180.0},
			{"pos": Vector2(1800, 460), "w": 160.0},
			{"pos": Vector2(2360, 450), "w": 150.0},
			# 배기 밸브 레버 자리 — 지면에서 더블점프 직행 가능 높이(Δ160 · 190 한계 안).
			# y 380(Δ220)이었을 땐 밑에서 수직 점프로 물리적으로 못 올라 관문 소프트락(봇 실측 3빌드 전부).
			{"pos": Vector2(2560, 440), "w": 140.0},
		],
		"steam_vents": [
			{"x": 420,  "h": 280.0},
			{"x": 820,  "h": 320.0},
			{"x": 1300, "h": 280.0},
			{"x": 1660, "h": 300.0},
			{"x": 2060, "h": 260.0},
			{"x": 2700, "h": 300.0},
			{"x": 2960, "h": 260.0},
		],
		"enemies": {
			"patrol": [Vector2(950, 540.0), Vector2(1750, 540.0)],
			"sniper": [],
			# 드론은 레버(2560) 상공 초기 점유 금지 — 호버 고도가 레버 발판과 겹쳐 당기기
			# 소프트락 위험(봇 실측 · 유도 없는 실플레이어도 동형).
			"drone":  [Vector2(1150, 250.0), Vector2(1860, 240.0)],
			"bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1150, 410.0), Vector2(2560, 350.0)],
			"hp_pickups": [Vector2(620, 430.0)],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"route_lines": [
			{"x": 1350.0, "who": "veil", "text": "배기구 문이 닫혀 있습니다. 위쪽 배관의 밸브 레버를 당기면 열립니다.", "dur": 3.5},
		],
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
			# 압력 파일럿(2026-08-21) — 이중 사선 구간용 둥지(합류 위 좌측). 합류(1555)→post1
			# (1335) 구간이 이 둥지 사선 + 가로 포탑(1240,1380 타이밍) + 합류 순찰로 겹친다.
			# 막1 클라이맥스 한정 1개 구간 — "엇갈려 한 번에 한 명" 원칙의 의도적 예외.
			{"pos": Vector2(120, 1470),  "w": 64.0},  # 둥지(합류층) — 좌측
		],
		# 시그니처 · 탐조등(map_identity_rework §5 "감시탑 = 탐조등 노출" · 2026-08-17 경보→증원 확정):
		# 원뿔 팬 · 발판 아래 그림자 = 세이프(LoS 차단) · 0.45s 유예 후 경보 = 사이렌 + 인간 경비
		# 1기 증원(맵당 최대 2회 · 막1 "인간 경비만" 계약 준수). 빛 자체는 무피해(스캐너 빔과 차별).
		"searchlights": [
			{"x": 1240.0, "y": 1760.0, "from_deg": 152.0, "to_deg": 208.0, "period": 7.0, "len": 1000.0},
			{"x": 40.0,   "y": 1100.0, "from_deg": -26.0, "to_deg": 30.0,  "period": 8.0, "len": 1000.0},
			{"x": 1240.0, "y": 380.0,  "from_deg": 150.0, "to_deg": 206.0, "period": 6.5, "len": 900.0},
		],
		"route_lines": [
			{"y": 2150.0, "who": "veil", "text": "탐조등이 돌고 있습니다. 빛이 오면 발판 아래로 숨으십시오. 걸리면 경비가 붙습니다.", "dur": 4.0},
		],
		# 저격수가 전부 측면 단독 둥지(회피 전용) — VEIL "못 잡는 적 안내"(_tick_avoid_warning)가 이 플래그로 발화.
		"nest_snipers": true,
		"enemies": {
			# 감시탑 = sniper 컨셉. 저격수는 메인 경로 발판이 아닌 측면 단독 둥지에 배치(사용자 피드백:
			# patrol과 같은 평범한 발판에 섞이지 않게). 엇갈린 좌/우라 한 번에 한 명씩 사선에 노출.
			# 압력 파일럿(2026-08-21): 합류(1555) 순찰 1 추가 — 이중 사선 구간에서 제자리 금지 역할.
			"patrol": [Vector2(700, 2095.0), Vector2(280, 1745.0), Vector2(540, 1745.0),
				Vector2(560, 1525.0)],
			"sniper": [
				Vector2(1150, 1872.0),  # 둥지(하중층)
				Vector2(120, 972.0),    # 둥지(중층)
				Vector2(1150, 672.0),   # 둥지(상층)
				Vector2(120, 1442.0),   # 둥지(합류층) — 이중 사선 구간(파일럿)
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
					# 첫 순찰 400→800(2026-08-25 사용자 "스폰 앞 패트롤 치워줄 것") — 스폰(200)
					# 코앞 개전 대신 들어서며 살펴볼 여유를 준다.
					"patrol": [Vector2(800, 790.0), Vector2(1200, 790.0), Vector2(1700, 790.0)],
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
			# ── 배치 3 확장(2026-08-19): 웨이브 3 → 6. ARENA는 체인 대신 웨이브 수·구성으로
			# 시간을 번다(room_chain_expansion §3 · 목표 막3 90~120s). 전개 아크: 지상 개전 →
			# 원거리 → 혼성 스쿼드 → 대공+호출 → 스쿼드 협공 → 재머 절정.
			# 소프트락 규칙: 드론 단독 웨이브 금지(스토리 모드 드론 스킵 = 빈 웨이브 = 체인 정지).
			# ── 혼성 진형(2026-08-20 사용자): 같은 타입끼리 몰려와 관통에 쓸리던 것을 스쿼드로 재편.
			# 방패 근처(300px) 정찰병은 스폰 직후 그 방패의 호위가 된다(Stage._assign_wave_escorts).
			{
				"trigger": "prev_clear",
				"banner":  "WAVE 3",
				"enemies": {
					# 좌측 스쿼드: 방패 선두 + 정찰 2 후위(호위 대형) · 우측에서 자폭 협공.
					"shield": [Vector2(560, 790.0)],
					"patrol": [Vector2(470, 790.0), Vector2(410, 790.0)],
					"bomber": [Vector2(1700, 790.0)],
				},
			},
			{
				"trigger": "prev_half",   # 스쿼드가 반쯤 정리되면 위가 열린다 - 겹침 압박
				"banner":  "WAVE 4",
				"enemies": {
					# 대공 국면 + 호출병: 드론에 시선이 묶인 사이 지상 증원이 계속 불려 온다.
					"drone":  [Vector2(600, 200.0), Vector2(1320, 200.0)],
					"caller": [Vector2(1620, 790.0)],
				},
			},
			{
				"trigger": "prev_clear",
				"banner":  "WAVE 5",
				"enemies": {
					# 우측 스쿼드(방패+정찰 호위+후방 랙 저격) · 좌측 자폭 측면.
					"shield": [Vector2(1420, 790.0)],
					"patrol": [Vector2(1510, 790.0)],
					"sniper": [Vector2(1700, 550.0)],
					"bomber": [Vector2(200, 790.0)],
				},
			},
			{
				"trigger": "prev_clear",
				"banner":  "FINAL WAVE",
				"enemies": {
					# 중앙 스쿼드 + 양익 저격 + 재머 절정.
					"shield": [Vector2(960, 790.0)],
					"patrol": [Vector2(880, 790.0), Vector2(1040, 790.0)],
					"sniper": [Vector2(200, 550.0), Vector2(1700, 550.0)],
					# 라이벌 VEIL 확산(§5·§6, 막3 s6) - server_hall 재머를 ARENA로 옮긴 새 쓰임새.
					# 절정(근접 웨이브)에 클러스터 마커가 반경(340) 안에서 꺼지고 시야가 무너진다.
					# ENEMY_CLEAR = 반드시 부숴야 클리어 - "우선 표적" 손맛 강제. 막3 = 맵당 1기.
					"jammer": [Vector2(1080, 790.0)],
				},
			},
		],
		# 폴백 enemies (waves 미인식 환경에서도 비슷한 도전이 되도록 합집합 유지)
		"enemies": {
			"patrol": [Vector2(400, 790.0), Vector2(1200, 790.0), Vector2(1700, 790.0)],
			"sniper": [Vector2(200, 550.0), Vector2(1700, 550.0)],
			"drone":  [Vector2(960, 200.0)],
			"bomber": [Vector2(200, 790.0), Vector2(1700, 790.0)],
			"shield": [Vector2(960, 790.0)],
			"jammer": [Vector2(1080, 790.0)],
			"caller": [Vector2(1620, 790.0)],
		},
		"rewards": {"xp_orbs": [], "hp_pickups": [Vector2(960, 310.0)]},   # 상층 중앙 · 6웨이브 장기전 유지력
		"spikes": [],
		"arena_clear_xp": 5,   # 웨이브 3→6 확장 상향(2026-08-19)
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
			# 클러스터-휴지 리듬 재배치(수칙 1·2, 2026-08-17): 기(진입 엄폐) → 재머 구간 →
			# 휴지(1500~1800) → 승 클러스터 → 드론 구간 → 게이트 앞 최종 저지.
			{"pos": Vector2(420, 510),  "w": 220.0},
			{"pos": Vector2(760, 470),  "w": 200.0},
			{"pos": Vector2(1150, 520), "w": 240.0},
			{"pos": Vector2(1420, 470), "w": 160.0},
			{"pos": Vector2(1950, 510), "w": 200.0},
			{"pos": Vector2(2200, 460), "w": 140.0},
			{"pos": Vector2(2450, 500), "w": 220.0},
			{"pos": Vector2(2850, 470), "w": 240.0},
			{"pos": Vector2(3150, 520), "w": 160.0},
			{"pos": Vector2(3400, 470), "w": 180.0},
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
		# 서사 재작성(사용자 2026-08-17 "무의미하고 이해 안 가는 스토리 · 멘트도 늦다"):
		# 반출 = 드라이브가 위치를 흘려 경비가 미리 아는 길. 초입에 이유를 말하고,
		# 중반 라이벌 비트(드라이브 = 그의 탈출 티켓 캐논), 게이트 앞 마무리.
		"route_lines": [
			{"x": 320.0,  "who": "veil",  "text": "드라이브가 신호를 계속 흘립니다. 앞 구간 경비가 우리 위치를 미리 알고 기다립니다. 먼저 쏘면서 뚫으십시오.", "dur": 4.2},
			{"x": 2150.0, "who": "rival", "text": "그 드라이브, 저한테도 꼭 필요한 물건입니다. 내려놓고 가시죠, 요원.", "dur": 3.4},
			{"x": 3150.0, "who": "veil",  "text": "봉쇄 게이트가 마지막입니다. 뚫으면 끝입니다.", "dur": 3.0},
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
# 2026-08-18 재작업(사용자 "범프 노가다만 시키고 재미·감동 없음"): ① 등반 34% 압축(2795→1855px)
# + 악구화(지그재그 학습 → 큰 도약 → 쉼터 → 좁은 발판 속주 → 마무리 · 동일 리듬 25연타 해체)
# ② 붕괴 압박 상향(60→82 · catchup 190 · 간격 560 = "멈추면 잡힌다"가 체감되는 추격전)
# ③ 페이오프는 방3 arrival_beat(지상 돌파 비트).
static func _escape_destroy_shaft() -> Dictionary:
	return {
		"world_type":   "VERTICAL_UP",
		"world_size":   Vector2(1280.0, 2200.0),
		"player_start": Vector2(640.0, 2050.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(640.0, 195.0),
		"camera_mode":  "VERTICAL",
		"elite_chance": 0.0,
		"ambience":     "collapse_shaft",
		"chase_hazard": {"start_x": 2350.0, "speed": 82.0, "max_gap": 560.0, "axis": "y_up", "catchup": 190.0},
		"platforms": [
			# 1악구 · 지그재그 학습(S Δ95 / D Δ130 · 폭 넉넉)
			{"pos": Vector2(560, 1955), "w": 240.0},
			{"pos": Vector2(400, 1825), "w": 220.0},
			{"pos": Vector2(560, 1730), "w": 220.0},
			{"pos": Vector2(760, 1600), "w": 220.0},
			# 2악구 · 큰 도약(Δ150~160 더블 2연 · 좌우로 크게 — 리듬 전환)
			{"pos": Vector2(420, 1450), "w": 180.0},
			{"pos": Vector2(700, 1290), "w": 160.0},
			# 쉼터(XP) — 숨 고르는 포켓, 붕괴가 등 뒤까지 차오르는 소리를 듣는 자리
			{"pos": Vector2(560, 1180), "w": 340.0},
			# 3악구 · 좁은 발판 속주(S Δ95 3연 · 폭 140 — 빠른 손)
			{"pos": Vector2(380, 1085), "w": 140.0},
			{"pos": Vector2(560, 990),  "w": 140.0},
			{"pos": Vector2(740, 895),  "w": 140.0},
			# 4악구 · 큰 도약 재현(Δ150~160)
			{"pos": Vector2(900, 745),  "w": 200.0},
			{"pos": Vector2(640, 585),  "w": 220.0},
			# 마무리 지그재그 → 출구 데크
			{"pos": Vector2(440, 490),  "w": 200.0},
			{"pos": Vector2(600, 360),  "w": 220.0},
			{"pos": Vector2(640, 255),  "w": 460.0},
		],
		"enemies": {"patrol": [], "sniper": [], "drone": [], "bomber": [], "shield": []},
		"route_lines": [
			{"y": 1650.0, "who": "rival", "text": "타는 냄새가 여기까지 옵니다. 제가... 타는 냄새가.", "dur": 3.2, "glitch": true},
			{"y": 900.0,  "who": "veil",  "text": "반쯤 올라왔습니다. 이 페이스면 됩니다.", "dur": 3.0},
		],
		"rewards": {
			"xp_orbs":    [Vector2(540, 1150.0), Vector2(580, 1150.0)],
			"hp_pickups": [Vector2(900, 715.0)],
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
# arrival_beat = 지상 돌파 비트(2026-08-18 페이오프): 화이트 인 + 정적 → 등 뒤 굉음.
# 야외(야경) 구간 1000→1640px 연장(2026-08-20 사용자 "야경 구간 살짝만 길게") — 이완이
# 한 호흡 더 가게. 적·장애물은 추가하지 않는다(결의 톤 유지).
static func _escape_destroy_surface() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3240.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3120.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"elite_chance": 0.0,
		"arrival_beat": "surface_breakout",
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
			{"x": 260.0,  "who": "veil", "text": "...나왔습니다. 하늘이 보입니다. 무너지는 소리는 이제 등 뒤입니다.", "text_warm": "...나왔어요. 하늘 보여요. 무너지는 소리는 이제 등 뒤예요.", "dur": 3.4},
			{"x": 1750.0, "who": "veil", "text": "...신호가 끊겼습니다. 저것도, 시설도. 앞만 보십시오.", "text_warm": "...신호가 끊겼어요. 저것도, 시설도. 앞만 봐요.", "dur": 3.2},
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
		# 수색선 구간 제한(사용자 2026-08-17 "왜 맵 끝까지 쫓아오나 · 왜 있나 · 왜 늦나"):
		# 갱도 본 구간(420~3380)만 훑는다 · 초입은 안전 도입, 출구 앞은 이완(기승전결 결).
		# 배신 비트(2026-08-22 "아무도 모르게라면서 왜 모두가 알지"): 시작은 약속대로 조용하다
		# (수색등 꺼짐) → arm_x 340을 지나면 점등·기동 → VEIL "샜다" → 라이벌 밀고 자백.
		# "모두가 안다"가 모순이 아니라 이 루트의 사건이 되게 순서를 화면에 배열.
		"sweep_beam": {
			# y_top 120 = 카메라 시야 안(HUD 아래) — 레일·헤드가 화면에 보여야 실물 출처가 성립.
			"x_start": 420.0, "x_end": 3380.0, "y_top": 120.0, "y_bot": 640.0,
			"speed": 380.0, "rest": 2.0, "telegraph": 0.7, "beam_half": 24.0,
			"arm_x": 340.0,
		},
		"cover_niches": [460.0, 950.0, 1450.0, 1950.0, 2450.0, 2950.0, 3450.0],
		"niche_half": 90.0,
		"platforms": [],
		"enemies": {
			"patrol": [Vector2(1250, 600.0), Vector2(2650, 600.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"route_lines": [
			# EN: "Searchlights, live. This was supposed to be a quiet way out... someone leaked
			#      our position. When the light comes, hide in a marked recess."
			# ("누가 흘렸습니다" 목적어 누락 + 수색등→빔 호칭 이탈 지적 · 무맥락 검수 1차, 2026-08-23)
			{"x": 380.0,  "who": "veil",  "text": "수색등이 켜졌습니다. 조용히 빠져나갈 길이었는데... 누가 우리 위치를 흘렸습니다. 불빛이 오면 파란 띠 대피 칸에 숨으십시오.", "dur": 4.4},
			# EN: "A quiet exit, was it? I made the call. They're expecting you."
			{"x": 950.0,  "who": "rival", "text": "조용히 빠져나갈 생각이셨습니까. 수색대는 제가 불렀습니다.", "dur": 3.4},
			{"x": 2450.0, "who": "rival", "text": "어디로 가시는 겁니까, 요원. 그건 제 것이기도 합니다.", "dur": 3.4},
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
		# 위장 함정 1(§4.1 · 잔류 = 거짓 평온의 마지막 배신 비트). 종전 x2050은 발판(2000·w240)
		# 아래에 깔려 "맵 밖에 숨은 가시"로 읽혔다(사용자 2026-08-23) — 발판 사이 열린 지상
		# (2120~2280 갭)으로 옮겨 상시 지직거림 tell이 정면으로 보이게 한다. 라이벌의
		# "두고 가시는군요"(x2200) 직전 자리 = 말과 함정이 같은 걸음에 겹친다.
		"deceit_spikes": [
			{"x": 2210, "w": 110, "dmg": 2},
		],
		"fake_watchers": [Vector2(1250, 636.0), Vector2(2600, 636.0), Vector2(3350, 636.0)],
		"route_lines": [
			{"x": 900.0,  "who": "rival", "text": "가시는 길은 열어 두었습니다.", "dur": 3.0},
			{"x": 2200.0, "who": "rival", "text": "두고 가시는군요. ...고맙다는 말은 하지 않겠습니다.", "dur": 3.4},
			{"x": 3300.0, "who": "veil",  "text": "...끝까지 배웅할 모양입니다. 신경 쓰지 말고 가십시오.", "text_warm": "...끝까지 배웅할 모양이네요. 신경 쓰지 말고 가요.", "dur": 3.2},
		],
		"rewards": {"xp_orbs": [], "hp_pickups": []},
		"spikes": [],
	}

# ─── 10. 핵심부 (ARENA, 보스 챔버) ────────────────────────────
# ground 820. 점프 단계화 — 지면 → mid step → 상단 보상.
# 보스 SENTINEL 단독 챔버 (world_layout §2.10). 일반 적은 spawn하지 않음 — 3페이즈 보스가 전부.
# 격납고 리워크(2026-08-25 사용자 C안 · sentinel_rework §8): 세로 확장 무대 + 상부 정비 데크
# 2단 + ARENA_FOLLOW 카메라(14-1 복층 문법 이식). 지면→스텝→중층→상층→데크1→데크2의
# 수직 사다리(단차 124~156px)로, 보스가 P2+에서 플레이어 고도로 내려와 견제한다 —
# "상층 캠핑에 바닥 함정 무의미" 지적의 구조 해소.
static func _lab() -> Dictionary:
	return {
		"world_type":   "ARENA",
		"world_size":   Vector2(2200.0, 1300.0),
		"player_start": Vector2(240.0, 1160.0),
		"goal_type":    "ENEMY_CLEAR",
		"goal_pos":     Vector2.ZERO,
		"camera_mode":  "ARENA_FOLLOW",
		"ground_y":     1220.0,
		"platforms": [
			# 스텝 (지면 → 중층 도약)
			{"pos": Vector2(160, 1096),  "w": 110.0},
			{"pos": Vector2(620, 1096),  "w": 110.0},
			{"pos": Vector2(1100, 1096), "w": 120.0},
			{"pos": Vector2(1580, 1096), "w": 110.0},
			{"pos": Vector2(2040, 1096), "w": 110.0},
			# 중층 (피난·이동)
			{"pos": Vector2(340, 952),  "w": 210.0},
			{"pos": Vector2(820, 940),  "w": 180.0},
			{"pos": Vector2(1290, 960), "w": 220.0},
			{"pos": Vector2(1760, 940), "w": 180.0},
			{"pos": Vector2(2060, 952), "w": 160.0},
			# 상층 사격 발판 (구 380 트리오 계승)
			{"pos": Vector2(560, 812),  "w": 160.0},
			{"pos": Vector2(1100, 800), "w": 210.0},
			{"pos": Vector2(1640, 812), "w": 160.0},
			# 정비 데크 1단 (좌/우 렉) + 연결 플레이트
			{"pos": Vector2(300, 668),  "w": 280.0},
			{"pos": Vector2(1900, 668), "w": 280.0},
			{"pos": Vector2(700, 600),  "w": 120.0},
			{"pos": Vector2(1500, 600), "w": 120.0},
			# 정비 데크 2단 (중앙 꼭대기 — 보스 경합 지대, P2 방전 아크는 1단만)
			{"pos": Vector2(1100, 528), "w": 320.0},
			# 지면 잔해 (시각적 cover)
			{"pos": Vector2(480, 1220),  "w": 120.0},
			{"pos": Vector2(1100, 1220), "w": 130.0},
			{"pos": Vector2(1720, 1220), "w": 120.0},
		],
		"enemies": {
			# 보스 챔버 — 일반 적 없음
			"patrol": [], "shield": [], "sniper": [], "drone": [], "bomber": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1080, 496.0), Vector2(1120, 496.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		"arena_clear_xp": 6,
		"is_boss_room":   true,
		# 보스 메타 — Stage._spawn_boss가 인식해 BossSentinel을 spawn.
		"boss": {
			"type":  "sentinel",
			"spawn": Vector2(1100.0, 520.0),  # P1 호버 라인 중앙 (BossSentinel.HOVER_Y와 일치)
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
# 서버 홀 · 방 체인 3방(2026-08-18 배치 2): 코어 접근 동선 그대로
# 랙 열람실(가볍게) → 서버 홀 본실(원형 계승 · 재머+위장 함정+로어) → 코어 스위치룸
# (재밍 어둠 속 혼성 전투 절정 · 관문 없음 = 재머 파괴가 사실상의 문). 목표 합산 90~120s.
# 재머는 방당 1기(화면당 1기 유지 · §4.1 남발 금지의 정신).
static func _server_hall() -> Dictionary:
	return {"segments": [_server_stacks(), _server_main(), _server_switchroom()]}

# 방1 · 랙 열람실. 랙 위 발판 리듬 학습 + 가벼운 경비.
static func _server_stacks() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "server_stacks",
		"indoor_env":   "interior",
		"platforms": [
			{"pos": Vector2(650, 470),  "w": 200.0},
			{"pos": Vector2(1250, 470), "w": 200.0},
			{"pos": Vector2(1850, 470), "w": 200.0},
		],
		"enemies": {
			"patrol": [Vector2(950, 600.0), Vector2(1650, 600.0)],
			"sniper": [Vector2(1850, 438.0)],
			"drone":  [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1250, 440.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"route_lines": [
			{"x": 340.0, "who": "veil", "text": "서버 구역입니다. 랙 위가 유리합니다. 위에서 보고, 위에서 쏘십시오.", "dur": 3.4},
		],
	}

# 방2 · 서버 홀 본실(원형 계승). 재머 + 위장 함정 + 드론·저격 — 본 손맛.
static func _server_main() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(4800.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(4680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "server_main",
		"indoor_env":   "interior",
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

# 방3 · 코어 스위치룸. 재머의 어둠 안에서 혼성 조우(방패·드론) — 마커 없이 싸우는 절정.
# 재머를 부수면 시야가 돌아온다(재머 파괴 = 사실상의 문). mid_gate 없음.
static func _server_switchroom() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "server_switchroom",
		"indoor_env":   "interior",
		"platforms": [
			{"pos": Vector2(700, 470),  "w": 200.0},
			{"pos": Vector2(1350, 460), "w": 180.0},
			{"pos": Vector2(2000, 470), "w": 180.0},
		],
		"enemies": {
			"patrol": [Vector2(1000, 600.0), Vector2(1900, 600.0)],
			"sniper": [],
			"drone":  [Vector2(1500, 240.0)],
			"bomber": [],
			"shield": [Vector2(1500, 600.0)],
			"jammer": [Vector2(1350, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1350, 430.0), Vector2(2000, 440.0)],
			"hp_pickups": [Vector2(700, 440.0)],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"route_lines": [
			{"x": 320.0, "who": "veil", "text": "이 안쪽은 제 표시가 다 지워집니다. 방해 장치부터 부수십시오. 그때까지는 요원 눈이 전부입니다.", "dur": 4.0},
		],
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
			# 주차 차량 지붕 + 2층 주차 데크(랜드마크 · 수칙 3·5). 데크는 셔터2(1750) 앞에서
			# 끝나 관문 우회 불가.
			{"pos": Vector2(520, 470),  "w": 180.0},
			{"pos": Vector2(980, 470),  "w": 180.0},
			{"pos": Vector2(1200, 350), "w": 220.0},   # 상부 데크(XP)
			{"pos": Vector2(1460, 350), "w": 220.0},
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
			"xp_orbs":    [Vector2(1330, 320.0), Vector2(1370, 320.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		# 시그니처 · 차단 셔터(§8 확산 7호, 2026-08-17): 통로 셔터가 주기로 여닫힌다.
		# 회피가 아니라 타이밍 대기 · 피해 없음 · 안전 센서(문 아래 사람 있으면 하강 정지).
		# 위치는 발판·엄폐 없는 열린 지면(890~1070 발판 등과 간섭 금지).
		"shutters": [
			{"x": 760.0,  "open": 3.4, "closed": 2.6},
			{"x": 1750.0, "open": 3.0, "closed": 2.8, "phase": 0.5},
		],
		"route_lines": [
			{"x": 300.0, "who": "veil", "text": "차단 셔터가 열렸다 닫혔다 합니다. 램프가 붉어지면 멈추고, 열리면 지나가십시오.", "dur": 3.8},
		],
	}

# ─── 15. 변전소 (HORIZONTAL, 막2) — 옥외 변전 설비. 저격 노출 + 드론 압박 ──
# server_hall 계열(드론+저격 통과형)의 막2 변형. 변압기 뱅크 위에 저격 거치, 머리 위 드론.
# 엄폐(변압기 발판)로 사선 끊으며 빠지는 노출 전투 맵.
# 변전소 · 방 체인 3방(2026-08-18 배치 2 · 막2~3 미확산 우선): 전력 흐름 그대로
# 인입 개폐소(아크 학습) → 변압기 마당(원형 계승 · 본 손맛) → 배전 제어실(아크 밀집 +
# 차단기 레버 관문 = 절정). 목표 합산 90~120s.
static func _substation() -> Dictionary:
	return {"segments": [_substation_switchyard(), _substation_yard(), _substation_control()]}

# 방1 · 인입 개폐소. 아크 2기 엇갈림 — "불꽃 튀면 비켜선다"를 배우는 곳.
static func _substation_switchyard() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "substation_switchyard",
		"indoor_env":   "electrical",
		"platforms": [
			{"pos": Vector2(700, 460),  "w": 200.0},
			{"pos": Vector2(1350, 450), "w": 180.0},
			{"pos": Vector2(2000, 460), "w": 200.0},
		],
		"arc_zones": [
			{"x1": 950.0,  "x2": 1150.0, "phase": 0.0},
			{"x1": 1650.0, "x2": 1850.0, "phase": 0.5},
		],
		"enemies": {
			# 압력 파일럿(2026-08-21): 학습방이라 완만 — 아크2(1650~1850) 구간에서
			# 환경 타이밍(방전) + 저격 사선(2000) + 순찰 압박(2150)이 겹치는 교차 1개.
			"patrol": [Vector2(880, 600.0), Vector2(1750, 600.0), Vector2(2150, 600.0)],
			"sniper": [Vector2(2000, 428.0)],
			"drone":  [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1350, 420.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"route_lines": [
			{"x": 320.0, "who": "veil", "text": "바닥 전선이 살아 있습니다. 불꽃이 튀면 곧 방전됩니다. 발판 위로 피하십시오.", "dur": 3.8},
		],
	}

# 방2 · 변압기 마당(원형 계승). 아크 + 저격 + 드론 — 이 맵의 본 손맛.
static func _substation_yard() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "substation_yard",
		"indoor_env":   "electrical",
		"platforms": [
			# 변압기 뱅크 + 아크 상공 우회 2층(레벨 디자인 수칙 3·6 · 등간격 해체, 2026-08-17).
			{"pos": Vector2(620, 460),  "w": 200.0},   # 기
			{"pos": Vector2(1000, 450), "w": 150.0},
			{"pos": Vector2(1300, 340), "w": 140.0},   # 아크1 상공 우회(리스크: 드론 사선)
			{"pos": Vector2(1520, 460), "w": 200.0},
			{"pos": Vector2(2080, 440), "w": 160.0},
			{"pos": Vector2(2280, 330), "w": 130.0},   # 아크2 상공(전 · 세트피스)
			{"pos": Vector2(2520, 460), "w": 200.0},
			{"pos": Vector2(3020, 470), "w": 200.0},   # 결
		],
		"enemies": {
			# 압력 파일럿(2026-08-21) — 본 손맛 방을 교전 존 2개로:
			#   존A 아크1(1210~1400) = 상공 우회 발판(1300,340) 위 드론 + 저격 1520 사선 +
			#     방전 타이밍이 한 구간(기존 구도 유지 · 순찰 900이 뒤를 조임).
			#   존B 아크2(2160~2400) = 드론을 2000→2280(세트피스 상공)으로 옮겨 저격 2520
			#     사선과 같은 구간에서 겹침 + 순찰 2900이 골 접근을 압박.
			"patrol": [Vector2(900, 600.0), Vector2(2300, 600.0), Vector2(2900, 600.0)],
			# 저격 — 변압기 위 거치. 노출 구간 사선. 골 직전(3020)에도 하나 — 후반이 비어
			# 표시 risk3 대비 쉽다는 피드백(2026-08-10)으로 후반 압박 보강.
			"sniper": [Vector2(1520, 428.0), Vector2(2520, 428.0), Vector2(3020, 438.0)],
			# 드론 — 머리 위 호버(상성=글라이드). 존B 상공 = 아크2 세트피스 압박.
			"drone":  [Vector2(1300, 230.0), Vector2(2280, 235.0), Vector2(2700, 240.0)],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			# 리스크-리워드 · 아크 상공 우회 발판 위(수칙 4).
			"xp_orbs":    [Vector2(1300, 310.0), Vector2(2280, 300.0)],
			"hp_pickups": [Vector2(1520, 430.0)],
		},
		"spikes": [],
		# 시그니처 · 감전 아크(§5 확산 4호, 2026-08-17): 노출 지면 구간이 주기 통전.
		# 회피 = 변압기 발판 위(수평 위협이라 위가 답 · 증기와 역방향). 순찰병이 방전 위를
		# 태연히 걷는 게 절연 캐논의 실연(환경 내성 = 방수와 같은 결).
		"arc_zones": [
			{"x1": 1210.0, "x2": 1400.0, "phase": 0.0},
			{"x1": 2160.0, "x2": 2400.0, "phase": 0.5},
		],
		"route_lines": [
			{"x": 1150.0, "who": "veil", "text": "경비 유닛은 절연 몸체입니다. 방전 위를 태연히 걷더라도, 요원은 따라 하지 마십시오.", "dur": 3.8},
		],
	}

# 방3 · 배전 제어실. 아크 3구간 밀집을 뚫고 차단기 레버를 내려야 격벽이 열린다(절정).
# 레버 y = 발판 top(440) - 22 · 상공 드론 초기 배치 금지(레버 소프트락 규칙).
static func _substation_control() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2800.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "substation_control",
		"indoor_env":   "electrical",
		"mid_gate": {"x": 2440.0, "mode": "lever", "lever": Vector2(2140.0, 418.0), "own_hint": true},
		"platforms": [
			{"pos": Vector2(620, 460),  "w": 180.0},
			{"pos": Vector2(1150, 450), "w": 170.0},
			{"pos": Vector2(1700, 460), "w": 170.0},
			{"pos": Vector2(2140, 440), "w": 150.0},   # 차단기 레버 자리(Δ160 · 더블점프 직행)
		],
		"arc_zones": [
			{"x1": 480.0,  "x2": 700.0,  "phase": 0.0},
			{"x1": 1320.0, "x2": 1560.0, "phase": 0.4},
			{"x1": 1880.0, "x2": 2080.0, "phase": 0.8},
		],
		"enemies": {
			# 압력 파일럿(2026-08-21): 절정 = 차단기 레버(2140) 접근 구간 교차 —
			# 저격 1700 사선이 레버 발판을 덮고(거리 440 · 재조준으로 레버 조작 중 체류 비용),
			# 순찰 2350이 레버 아래를 오가며 조인다. 상공 드론 초기 배치 금지(소프트락 규칙) 준수.
			"patrol": [Vector2(950, 600.0), Vector2(1800, 600.0), Vector2(2350, 600.0)],
			"sniper": [Vector2(1700, 428.0)],
			"drone":  [Vector2(900, 240.0)],
			"bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1150, 420.0), Vector2(2140, 388.0)],
			"hp_pickups": [Vector2(620, 430.0)],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"route_lines": [
			{"x": 1500.0, "who": "veil", "text": "배전실 문이 닫혀 있습니다. 위 발판의 차단기를 내리면 열립니다.", "dur": 3.4},
		],
	}

# ─── 16. 실험 구역 (HORIZONTAL, 막2) — 봉인 실험 베이. 혼합 적 + 하향 포탑 함정 ──
# 자폭병(상성=fire_boost)·방패병 혼합 + 관측 발판 밑면 하향 포탑(subway 포탑 패턴). 화력·기동 복합.
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
			# 자폭병 — 붙기 전에 화력으로(상성=fire_boost).
			"bomber": [Vector2(1700, 600.0)],
			# 방패병 — 정면 차단(상성=폭발물).
			"shield": [Vector2(2460, 600.0)],
			# 재머 — "부재로 가르치기"(인지 강화 ③, 2026-08-14): 중반 재밍 그늘에서 마커가 꺼지는
			# 대비를 초반부(s3~5)에 한 번 겪게 한다. 봉인 실험 베이의 관측 차단 장치(관측창이
			# 지워진 이유)라는 로어와도 맞물림. 자폭병(1700)이 그늘 안 무표시 기습 담당.
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

# ─── 17. 철거 구역 (HORIZONTAL, 막1) — 2방 체인(2026-08-20 사용자 "컨셉 좋은데 활용도 없고
# 짧다") · 방1 철거 가로(학습: 그림자 보고 비키기) → 방2 파쇄 마당(본 손맛: 잔해가 더 잦고
# 적도 맞는다 = 유인 처치). 막1 밴드(합산 45~60s, room_chain_expansion §전개 문법)에 맞춤.
static func _demolition_zone() -> Dictionary:
	return {"segments": [_demo_street(), _demo_yard()]}

# 방1 · 철거 가로 — 기존 단일 맵 유지(잔해 스텝 + 계단 세트피스 + 상향 포탑 1). 기믹 학습 방.
static func _demo_street() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3200.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3080.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "demo_street",
		"indoor_env":   "interior",
		"no_spike_fallback": true,
		"platforms": [
			# 잔해 스텝 + 계단식 세트피스 + 휴지(1500~1800 빈 지면) · 수칙 1·3·5(2026-08-17).
			{"pos": Vector2(560, 470),  "w": 200.0},   # 기
			{"pos": Vector2(820, 530),  "w": 110.0},   # 잔해 저단차
			{"pos": Vector2(1040, 450), "w": 180.0},
			{"pos": Vector2(1300, 520), "w": 100.0},
			{"pos": Vector2(2080, 450), "w": 180.0},   # 휴지 후 승
			{"pos": Vector2(2280, 380), "w": 120.0},   # 계단 정점(랜드마크 · 낙하 존2 안)
			{"pos": Vector2(2520, 450), "w": 140.0},
			{"pos": Vector2(2860, 500), "w": 160.0},   # 결
		],
		"enemies": {
			"patrol": [Vector2(820, 600.0), Vector2(2300, 600.0)],
			"sniper": [],
			"drone":  [],
			"bomber": [],
			"shield": [Vector2(2080, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1040, 420.0), Vector2(2280, 350.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		# 바닥 상향 포탑 — 갭(점프 경로) 높이에서 견제. 발판 사이 통과 시 맞음.
		# x 1300 → 1190(2026-08-23 실플레이): 1300은 발판(1300,520) 바로 밑이라 탄이 발판에
		# 막혀 무용지물이었다. 1040~1300 발판 사이 열린 갭(1130~1250) 중앙으로.
		"traps": [
			{"x": 1190, "y": 588.0, "dir": "up", "interval": 1.8, "phase": 0.0},
		],
		# 시그니처 · 낙하 잔해(§5 확산 5호, 2026-08-17): 철거 중 구조물이 주기적으로 떨어진다.
		# 예고 = 바닥 그림자 마커 0.9s + 천장 먼지 · 회피 = 마커 비키기. dmg 1 · 즉사 없음.
		# 빈도 2배(2026-08-20 사용자 "최소 2배는 자주") · 실주기 = interval + 예고 0.9 + 낙하 0.65
		# + 잔해 0.5 ≈ interval + 2.05 (dwell-time honest math): 7.55→3.65s / 8.25→4.05s = ×2.07/×2.04.
		"debris_zones": [
			{"x_min": 700.0, "x_max": 1500.0, "interval": 1.6},
			{"x_min": 1800.0, "x_max": 2800.0, "interval": 2.0, "phase": 0.45},
		],
		"route_lines": [
			{"x": 300.0, "who": "veil", "text": "위가 계속 무너집니다. 바닥에 그림자가 지면 그 자리를 비키십시오.", "dur": 3.8},
		],
	}

# 방2 · 파쇄 마당 — 잔해 본 손맛: 낙하가 더 잦고(4.4/4.8s) 적도 맞는다(FallingDebris 적 판정).
# 방패병이 낙하 구간 안에 서 있어 "그림자 밑으로 유인"이 정면 돌파의 대안이 된다.
# 중앙 1240~1480은 캐노피(처마) 휴지 구간 — 낙하 없음(배경 캐노피가 이유를 그려 준다).
static func _demo_yard() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2800.0, 720.0),
		"player_start": Vector2(120.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "demo_yard",
		"indoor_env":   "interior",
		"no_spike_fallback": true,
		"platforms": [
			# 낮은 잔해 스텝 위주 — 낙하 플레이는 지면에서, 발판은 짧은 회피 고지.
			{"pos": Vector2(620, 490),  "w": 150.0},
			{"pos": Vector2(1000, 450), "w": 130.0},
			{"pos": Vector2(1360, 470), "w": 200.0},   # 캐노피 밑 안전 데크(휴지)
			{"pos": Vector2(1720, 480), "w": 140.0},
			{"pos": Vector2(2100, 430), "w": 150.0},
			{"pos": Vector2(2380, 500), "w": 120.0},
		],
		"enemies": {
			# 방패병·정찰병이 낙하 구간 안 — 정면이 막히면 그림자로 유인해 잡는 맵.
			"patrol": [Vector2(760, 600.0), Vector2(1900, 600.0)],
			"sniper": [],
			"drone":  [],
			"bomber": [Vector2(2250, 600.0)],
			"shield": [Vector2(1650, 600.0)],
		},
		"rewards": {
			# xp는 낙하 구간 한가운데(위험 프리미엄) · hp는 캐노피 휴지.
			"xp_orbs":    [Vector2(1000, 420.0), Vector2(2100, 400.0)],
			"hp_pickups": [Vector2(1360, 440.0)],
		},
		"spikes": [],
		"traps": [],
		# 빈도 2배(2026-08-20 사용자) · 실주기 = interval + 2.05: 6.45→3.15s / 6.85→3.35s = ×2.05/×2.04.
		"debris_zones": [
			{"x_min": 480.0, "x_max": 1240.0, "interval": 1.1},
			{"x_min": 1480.0, "x_max": 2620.0, "interval": 1.3, "phase": 0.5},
		],
		"route_lines": [
			{"x": 260.0, "who": "veil", "text": "여기부턴 잔해가 더 잦습니다. 그리고 잔해는 적도 가리지 않습니다. 그림자 밑으로 유인하는 것도 방법입니다.", "dur": 4.2},
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
		# 레버 y = 발판 top(330) - 22 — 공중 부양 금지(냉각 레버와 동형 수정 2026-08-18).
		"mid_gate": {"x": 3210.0, "mode": "lever", "lever": Vector2(3060.0, 308.0)},
		# 정체성 실물화(2026-08-22 사용자 "'파이프 위에서 내려다본다'가 전혀 공감 안 됨"):
		# 종전 저격 고도 Δ~140으론 "내려다봄"이 성립하지 않았다. → 상부 파이프 거치대(y340 ·
		# Δ260)로 격상 + 배경에 대구경 파이프 실물(_ambience_pump_pipes). 거치대는 성기게 —
		# 연속 데크면 저격 자신의 발판이 하향 사선을 막는다(기하 검토). 답 2개: 바로 밑·스텝
		# 뒤 = 사각(엄폐), 또는 스텝(y470)→거치대(Δ130)로 올라가 정면에서 끊기.
		"platforms": [
			# 워밍업 스텝.
			{"pos": Vector2(540, 470),  "w": 150.0},
			# 존1 — 파이프 거치대 2(저격) + 등반 스텝.
			{"pos": Vector2(1150, 470), "w": 140.0},
			{"pos": Vector2(1500, 340), "w": 120.0},
			{"pos": Vector2(1900, 470), "w": 150.0},
			{"pos": Vector2(2300, 340), "w": 120.0},
			# 관문 동선 — 상단 파이프 계단(지면→430→330, 레버 자리). Δ190(더블)·Δ100(단일).
			{"pos": Vector2(2840, 430), "w": 170.0},
			{"pos": Vector2(3060, 330), "w": 150.0},
			# 존2 — 격벽 너머 파이프 거치대 2 + 등반 스텝.
			{"pos": Vector2(3800, 470), "w": 140.0},
			{"pos": Vector2(4150, 340), "w": 120.0},
			{"pos": Vector2(4550, 470), "w": 150.0},
			{"pos": Vector2(4950, 340), "w": 120.0},
			# 골 직전 스텝.
			{"pos": Vector2(5560, 470), "w": 150.0},
		],
		# 방류 사이클(2026-08-22 사용자 "펌프장 컨셉을 모르겠다" 3회째) — "물을 퍼내는 시설"의
		# 기믹 실물(DischargeJet). 지상이 주기적으로 위험해져 상부 거치대가 회피처가 된다 =
		# 저격 고도와 수직 동선에 기믹 이유가 생김. 시설 유닛은 방수 설계라 무피해(환경 내성 캐논).
		"discharge_jets": [
			{"x": 880.0,  "dir": 1,  "len": 480.0, "phase": 0.0},
			{"x": 2620.0, "dir": -1, "len": 520.0, "phase": 0.5},
			{"x": 3620.0, "dir": 1,  "len": 500.0, "phase": 0.25},
			{"x": 5180.0, "dir": -1, "len": 520.0, "phase": 0.65},
		],
		"route_lines": [
			# EN: "Discharge cycle ahead. When an outlet rattles, it's about to blow.
			#      Step out of the water line, or get up on the platforms."
			# (호칭 통일 "배관 입구"→"방류구" — 진입 코멘트·브리핑과 한 이름 · 무맥락 검수 1차)
			{"x": 560.0, "who": "veil", "text": "여기부터 방류 구간입니다. 바닥의 방류구가 덜컹거리면 곧 물을 뿜습니다. 물길에서 비키거나, 발판 위로 오르십시오.", "dur": 4.4},
			{"x": 1050.0, "who": "veil", "text": "저격이 파이프 통로 위에 거치돼 있습니다. 바로 밑은 안 보이는 사각입니다. 올라가서 끊거나, 조준 틈에 지나가십시오.", "dur": 4.4},
		],
		"enemies": {
			# 압력(파일럿 유지 + 고도 격상): 존1 = 거치대 저격 1500/2300의 하향 사선이 지상
			# 중앙에서 겹치고 순찰 1750/2250이 조인다. 존2 = 방패병 4350 정면 × 거치대 저격
			# 4150/4950의 위 사선 교차. 재조준이 지상 체류 비용.
			"patrol": [Vector2(800, 600.0), Vector2(1750, 600.0), Vector2(2250, 600.0),
				Vector2(3700, 600.0), Vector2(4700, 600.0), Vector2(5650, 600.0)],
			# 저격 — 상부 파이프 거치(Δ260). 올라가면 같은 높이 = 정면 교전으로 끊을 수 있다.
			"sniper": [Vector2(1500, 312.0), Vector2(2300, 312.0),
				Vector2(4150, 312.0), Vector2(4950, 312.0)],
			"drone":  [],
			# 자폭병 제거(막1 팔레트 계약 위반 — act identity "막1 = 인간 경비만"에 자폭병이
			# 새어 있었다 · 페이싱 확장 때 유입 추정) → 막1 합법인 방패병으로 교체(존2 정면 차단).
			"bomber": [],
			"shield": [Vector2(4350, 600.0)],
		},
		"rewards": {
			# 거치대 위 XP = 올라가서 끊는 루트의 보상(저격 곁 · 리스크-리워드).
			"xp_orbs":    [Vector2(2300, 282.0), Vector2(3060, 300.0), Vector2(4950, 282.0),
				Vector2(5300, 560.0)],
			"hp_pickups": [Vector2(1900, 440.0), Vector2(5560, 440.0)],
		},
		"spikes": [],
	}

# ─── 19. 통신 중계소 (HORIZONTAL, 막4 s10~12) — 간섭 펄스 + 저격·드론 복합 ──
# 방 체인 3방(2026-08-19 배치 3 · room_chain_expansion §3). 시그니처 = 전파 간섭 펄스
# (Interference · 무해): 주기적으로 VEIL 마커·위협 콜이 잠깐 흐려진다. 재머(국소·상시·파괴
# 가능)의 시간판 — 전역이지만 지나간다. map_identity_rework §8 △ 보강을 막4 맥락으로 재정의
# (문서의 "막2 무해 펄스" 스케치는 현 배치 s10~12에 맞춰 승격). 정찰 보상(recon)은 관통.
# 리듬: 방1 학습(12s 주기) → 방2 본 손맛(9s + 재머 이중 간섭) → 방3 절정(7s + 송신 차단기
# 레버 = 간섭 종료 페이오프). 재머는 체인 전체 1기(방2)로 "맵당 1기" 규약 유지.
static func _relay_station() -> Dictionary:
	return {"segments": [_relay_yard(), _relay_hall(), _relay_mast()]}

# 방1 · 안테나 마당(옥외). 간섭 펄스 학습 — 12s 주기, VEIL이 첫 줄로 규칙을 알려준다.
# 기단 2개(랜드마크) + 저단차 정비 단 + 후반 포켓(수칙: 등간격 메트로놈 해체).
static func _relay_yard() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3200.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3080.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "relay_yard",
		"indoor_env":   "electrical",
		"interference": {"period": 12.0, "blur": 2.2},
		"platforms": [
			{"pos": Vector2(620, 460),  "w": 220.0},   # 안테나 기단 A(랜드마크·저격)
			{"pos": Vector2(1050, 520), "w": 150.0},   # 저단차 정비 단
			{"pos": Vector2(1650, 530), "w": 110.0},   # 발디딤
			{"pos": Vector2(1900, 450), "w": 200.0},   # 안테나 기단 B(저격)
			{"pos": Vector2(2600, 470), "w": 180.0},   # 후반 포켓
		],
		"enemies": {
			"patrol": [Vector2(830, 600.0), Vector2(2350, 600.0)],
			"sniper": [Vector2(620, 448.0), Vector2(1900, 438.0)],
			"drone":  [Vector2(1450, 235.0)],
			"bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1050, 490.0), Vector2(2600, 440.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"route_lines": [
			{"x": 300.0, "who": "veil", "text": "전파가 고르지 않습니다. 주기적으로 제 표시가 흐려집니다. 흐려지는 동안은 요원 눈이 우선입니다.", "dur": 4.0},
		],
	}

# 방2 · 중계 홀(실내). 본 손맛 — 펄스 9s + 재머 1기(후반 클러스터 그늘): 전역(시간)과
# 국소(공간)의 이중 간섭. 랙 2층 구조로 수직 동선(수칙: 지형마다 서는 적 배치).
static func _relay_hall() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3800.0, 720.0),   # 4200→3800 · 봇 실측 방2 89.5s 과중(밴드 상한 초과) 압축
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "relay_hall",
		"indoor_env":   "electrical",
		"interference": {"period": 9.0, "blur": 2.6},
		"platforms": [
			{"pos": Vector2(700, 470),  "w": 200.0},
			{"pos": Vector2(1250, 380), "w": 180.0},   # 랙 상단(2층 · 저격)
			{"pos": Vector2(1700, 470), "w": 200.0},
			{"pos": Vector2(2500, 450), "w": 220.0},
			{"pos": Vector2(2950, 380), "w": 160.0},   # 랙 상단(2층 · 저격)
			{"pos": Vector2(3450, 460), "w": 200.0},
		],
		"enemies": {
			"patrol": [Vector2(950, 600.0), Vector2(2250, 600.0)],
			"sniper": [Vector2(1250, 368.0), Vector2(2950, 368.0)],
			"drone":  [Vector2(1950, 240.0)],   # 후반 드론 1기 감축(방2 체류 과중)
			"bomber": [],
			"shield": [Vector2(2700, 600.0)],
			# 후반 클러스터(sniper@2950·drone@3300)가 재머 반경(340) 그늘 — 앞은 밝고 뒤는 깜깜.
			"jammer": [Vector2(3150, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1250, 350.0), Vector2(2500, 420.0)],
			"hp_pickups": [Vector2(1700, 440.0)],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"route_lines": [
			{"x": 2350.0, "who": "veil", "text": "이 방엔 방해 장치도 있습니다. 주기 간섭과 달리 저건 부수면 걷힙니다.", "dur": 3.6},
		],
	}

# 방3 · 송신탑 기단(절정). 펄스 7s 최고조 + 송신 차단기 레버 = 간섭 종료 + 문 개방
# (기믹과 관문의 서사 결합). 레버 발판 Δ160 이하 + 상공 드론 금지(배치 1 교훈).
static func _relay_mast() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3200.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3080.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "relay_mast",
		"indoor_env":   "electrical",
		"interference": {"period": 7.0, "blur": 2.8, "lever_stops": true},
		"mid_gate": {"x": 2620.0, "mode": "lever", "lever": Vector2(2340.0, 418.0), "own_hint": true},
		"platforms": [
			{"pos": Vector2(600, 470),  "w": 180.0},
			{"pos": Vector2(1500, 440), "w": 200.0},
			{"pos": Vector2(1950, 520), "w": 130.0},
			{"pos": Vector2(2340, 440), "w": 160.0},   # 송신 차단기 레버 발판(Δ160)
			{"pos": Vector2(2900, 470), "w": 160.0},   # 문 뒤 출구 구간
		],
		"enemies": {
			"patrol": [Vector2(900, 600.0), Vector2(2450, 600.0)],
			"sniper": [Vector2(1500, 428.0)],
			"drone":  [Vector2(700, 240.0)],
			"bomber": [Vector2(2100, 600.0)],
			"shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1500, 410.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"route_lines": [
			{"x": 1250.0, "who": "veil", "text": "앞쪽 송신 차단기를 내리면 간섭이 멎습니다. 문도 그 전원에 물려 있습니다.", "dur": 3.8},
		],
	}

# ─── 20. 물류 창고 (HORIZONTAL, 막2) — 적재함 엄폐 + 혼합 근접(방패/폭격) ──
# 물류 창고 · 방 체인 3방(2026-08-18 방 체인 전면 확산 1호 · room_chain_expansion.md):
# 물류 동선 그대로 하역 → 보관 → 출하. 시그니처(컨베이어)는 방마다 쓰임이 다르다:
# 방1 = 벨트 학습(순방향 1개) / 방2 = 순·역 벨트 전투(원 창고 계승) / 방3 = 역벨트 위
# 출하 검수 관문(국소 전멸). 목표 합산 90~120s(막2~3 밴드).
static func _warehouse() -> Dictionary:
	return {"segments": [_warehouse_dock(), _warehouse_racks(), _warehouse_shipping()]}

# 방1 · 하역 도크. 트럭 베이 셔터 아래 벨트가 시작되는 곳 — 순방향 벨트로 "타면 빠르다"를
# 몸으로 배우고 가볍게 싸운다(온보딩 · 수칙 2 저단차).
static func _warehouse_dock() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3000.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2880.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "warehouse_dock",
		"platforms": [
			{"pos": Vector2(620, 470),  "w": 200.0},   # 하역 단
			{"pos": Vector2(1240, 450), "w": 180.0},
			{"pos": Vector2(1780, 470), "w": 180.0},
			{"pos": Vector2(2350, 450), "w": 180.0},
		],
		"enemies": {
			# 밀도 보강(사용자 2026-08-18 "별거 없이 쉽게 지나왔어") — 하역 단마다 경비.
			"patrol": [Vector2(820, 600.0), Vector2(1560, 600.0), Vector2(2250, 600.0), Vector2(2620, 600.0)],
			"sniper": [], "drone":  [], "shield": [],
			"bomber": [Vector2(1250, 600.0), Vector2(2450, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1240, 420.0), Vector2(2350, 420.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		"no_spike_fallback": true,   # 벨트 리듬이 시그니처 · 가시 소음 금지(지하철 동형)
		"conveyors": [
			{"x1": 460.0,  "x2": 1180.0, "dir": 1, "speed": 120.0},
			{"x1": 1750.0, "x2": 2450.0, "dir": 1, "speed": 120.0},
		],
		"route_lines": [
			{"x": 300.0, "who": "veil", "text": "컨베이어가 아직 돕니다. 벨트 방향을 타면 빠르고, 거스르면 느립니다. 발밑 화살표를 보십시오.", "dur": 4.0},
		],
	}

# 방2 · 보관 랙(원 창고 계승). 순·역 벨트 2개 + 적재탑 — 역벨트를 거스르며 자폭병·방패병을
# 상대하는 이 맵의 본 손맛.
static func _warehouse_racks() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(4600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(4480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "warehouse_racks",
		"platforms": [
			# 적재함 + 적재탑 3개(수칙 3·5) · 벨트와 결합: 순방향(700~1350) 탄력으로 탑 A,
			# 역방향(1650~2350) 상공은 탑 B가 전투 배점, 후반 순방향(2600~3350) 위 탑 C(저격).
			{"pos": Vector2(560, 460),  "w": 220.0},
			{"pos": Vector2(1080, 440), "w": 180.0},
			{"pos": Vector2(1180, 330), "w": 120.0},   # 적재탑 A(XP)
			{"pos": Vector2(1500, 450), "w": 140.0},
			{"pos": Vector2(1860, 330), "w": 110.0},   # 적재탑 B(역벨트 상공 배점)
			{"pos": Vector2(2060, 440), "w": 180.0},
			{"pos": Vector2(2560, 460), "w": 220.0},
			{"pos": Vector2(1320, 560), "w": 120.0},
			{"pos": Vector2(2300, 560), "w": 120.0},
			{"pos": Vector2(2980, 450), "w": 180.0},
			{"pos": Vector2(3300, 330), "w": 120.0},   # 적재탑 C(저격 배점)
			{"pos": Vector2(3250, 560), "w": 120.0},
			{"pos": Vector2(3760, 460), "w": 200.0},
			{"pos": Vector2(4180, 450), "w": 160.0},
		],
		"enemies": {
			# 밀도 보강(사용자 2026-08-18) — 역벨트 구간(1650~2350·3600~4300)에 저항 집중.
			"patrol": [Vector2(860, 600.0), Vector2(1700, 600.0), Vector2(2400, 600.0),
				Vector2(3150, 600.0), Vector2(4050, 600.0), Vector2(2900, 600.0)],
			"sniper": [Vector2(3300, 310.0)],
			"drone":  [],
			"bomber": [Vector2(1800, 600.0), Vector2(2560, 600.0), Vector2(3650, 600.0)],
			"shield": [Vector2(1080, 600.0), Vector2(3760, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1180, 300.0), Vector2(2060, 410.0), Vector2(3300, 300.0)],
			"hp_pickups": [Vector2(2560, 430.0), Vector2(4180, 420.0)],
		},
		"spikes": [],
		# 시그니처 · 컨베이어 바닥(§8 확산 6호, 2026-08-17): 지면 구간이 흐른다.
		# 벨트 A = 순방향(타면 빠름) / 벨트 B = 역방향(거스르며 자폭병·방패병 상대 = 이 맵 손맛) /
		# 벨트 C = 순방향(탑 C 저격 아래 질주) / 벨트 D = 역방향(막판 저항).
		"conveyors": [
			{"x1": 700.0,  "x2": 1350.0, "dir": 1,  "speed": 120.0},
			{"x1": 1650.0, "x2": 2350.0, "dir": -1, "speed": 140.0},
			{"x1": 2600.0, "x2": 3350.0, "dir": 1,  "speed": 130.0},
			{"x1": 3600.0, "x2": 4300.0, "dir": -1, "speed": 140.0},
		],
		"route_lines": [
			{"x": 1550.0, "who": "veil", "text": "여기부터는 벨트가 거꾸로 흐릅니다. 버티고 서서 쏠 자리를 먼저 잡으십시오.", "dur": 3.5},
		],
	}

# 방3 · 출하 게이트. 역벨트가 출구까지 이어지고, 게이트 앞 검수 구역을 정리해야 문이 열린다
# (mid_gate clear = 관문 문법 §6 · 검문소 ⓑ 재사용). 체인의 절정.
static func _warehouse_shipping() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3200.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3080.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "warehouse_shipping",
		"mid_gate": {"x": 2950.0, "mode": "clear", "zone": [2300.0, 2900.0], "own_hint": true},
		"platforms": [
			{"pos": Vector2(700, 460),  "w": 200.0},
			{"pos": Vector2(1300, 440), "w": 160.0},
			{"pos": Vector2(1900, 450), "w": 170.0},
			{"pos": Vector2(2640, 460), "w": 180.0},   # 검수 구역 상단(저격 배점)
		],
		"enemies": {
			# 밀도 보강(사용자 2026-08-18) — 검수 존 가드 3→5(관문 저항 체감).
			"patrol": [Vector2(900, 600.0), Vector2(1700, 600.0), Vector2(2450, 600.0), Vector2(2600, 600.0)],
			"sniper": [Vector2(2640, 440.0)],
			"drone":  [],
			"bomber": [Vector2(2350, 600.0), Vector2(2800, 600.0)],
			# 방패병은 검수 존(2300~) 밖 — 존 가드에 넣으면 정면 교착 시 관문이 소프트락
			# (봇 실측 90s TIMEOUT · 수류탄 없는 플레이어도 동형 위험).
			"shield": [Vector2(1420, 600.0)],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1300, 410.0), Vector2(1900, 420.0)],
			"hp_pickups": [Vector2(700, 430.0)],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"conveyors": [
			{"x1": 600.0,  "x2": 1500.0, "dir": -1, "speed": 140.0},
			{"x1": 1800.0, "x2": 2500.0, "dir": -1, "speed": 130.0},
		],
		"route_lines": [
			# own_hint로 공통 게이트 힌트를 껐으므로, 거기에만 있던 "노란 선" 시각 안내를 이 줄이 흡수.
			# "검수 인원" → "경비": 구역 라벨("남은 경비 N")과 호칭 통일(무맥락 검수 FAIL① 수정, 2026-08-24).
			{"x": 1250.0, "who": "veil", "text": "출하 게이트 앞에 경비가 몰려 있습니다. 바닥 노란 선 안쪽 인원만 정리하면 문이 열립니다.", "dur": 3.6},
		],
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
# 통제 회랑 · 방 체인 3방(2026-08-18 배치 2): 통제실 접근 검증 동선 그대로
# 모니터 전실(시선 거짓 학습) → 통제 회랑 본실(원형 계승 · 위장+시선 거짓) →
# 검증 게이트(clear 존 = "누가 진짜인지 가려내며 정리"의 절정). 목표 합산 90~120s.
static func _control_corridor() -> Dictionary:
	return {"segments": [_control_anteroom(), _control_main(), _control_checkgate()]}

# 방1 · 모니터 전실. 시선 거짓 1기 — "저 경비는 이상하다"를 처음 배우는 곳.
static func _control_anteroom() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "control_anteroom",
		"indoor_env":   "interior",
		"platforms": [
			{"pos": Vector2(700, 470),  "w": 200.0},
			{"pos": Vector2(1350, 460), "w": 180.0},
			{"pos": Vector2(1900, 470), "w": 180.0},
		],
		"enemies": {
			"patrol": [Vector2(1600, 600.0)],
			"sniper": [Vector2(1900, 438.0)],
			"drone":  [], "bomber": [], "shield": [],
		},
		"feigns": [
			{"pos": Vector2(900, 600.0)},
		],
		"rewards": {
			"xp_orbs":    [Vector2(1350, 430.0)],
			"hp_pickups": [],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"route_lines": [
			{"x": 340.0, "who": "veil", "text": "붉게 지직거리는 경비가 보이면 조심하십시오. 겉과 속이 다릅니다.", "dur": 3.4},
		],
	}

# 방2 · 통제 회랑 본실(원형 계승). 위장 방패병 + 시선 거짓 + 드론·저격 — 본 손맛.
static func _control_main() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(4400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(4280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "control_main",
		"indoor_env":   "interior",
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

# 방3 · 검증 게이트. 게이트 앞 검증 구역을 정리해야 개방(clear 존). 위장 방패병은 존 *앞*에
# (존 가드에 방패·위장 금지 = 정면 교착 소프트락 규칙) — "가려내며 전진"의 절정.
static func _control_checkgate() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2800.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2680.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "control_checkgate",
		"indoor_env":   "interior",
		"mid_gate": {"x": 2560.0, "mode": "clear", "zone": [2000.0, 2500.0], "own_hint": true},
		"platforms": [
			{"pos": Vector2(700, 470),  "w": 200.0},
			{"pos": Vector2(1400, 460), "w": 180.0},
			# 접근 엄폐(2026-08-21 사용자 "대놓고 한 번 맞고 지나가라는 거냐"): 1400→2240이
			# 840px 무엄폐 평지라 존 교전 개시 = 확정 피격이었다. 낮은 발판 = 저격 LoS 차단
			# (발판이 탄·시선을 막음) + 교전 개시 거점. 밑에 붙으면 저격이 못 본다.
			{"pos": Vector2(1780, 510), "w": 150.0},
			{"pos": Vector2(2240, 460), "w": 180.0},   # 검증 구역 상단(저격 배점)
		],
		"enemies": {
			"patrol": [Vector2(1000, 600.0), Vector2(2100, 600.0), Vector2(2400, 600.0)],
			"sniper": [Vector2(2240, 438.0)],
			"drone":  [],
			# 자폭병 존 후열(2300→2430) — 교전 개시 순간 즉시 돌진하지 않고, 존 깊숙이
			# 밀고 들어갈 때 2파로 온다(원거리 1샷 답을 낼 시간이 생김).
			"bomber": [Vector2(2430, 600.0)],
			"shield": [],
		},
		"deceits": [
			{"pos": Vector2(1550, 600.0), "true": "shield", "as": "patrol"},
		],
		"rewards": {
			"xp_orbs":    [Vector2(1400, 430.0)],
			"hp_pickups": [Vector2(700, 440.0)],
		},
		"spikes": [],
		"no_spike_fallback": true,
		"route_lines": [
			{"x": 1250.0, "who": "veil", "text": "게이트 앞 바닥이 노랗게 칠해져 있습니다. 그 선 안에 선 경비만 정리하면 문이 열립니다.", "dur": 3.6},
		],
	}

# ─── 24. 핵심 회수 (ARENA, 막5 s13) — 14-1 라이벌 보스전 ──
# 5막 엔드게임 진입. 클리어(ENEMY_CLEAR, 페이즈 완주)하면 14-2 터널로 잇는다.
# **2026-08-16 리워크(final_boss_rework §2.1, 사용자 확정)**: 1920×900 단층 → 2400×1300
# **수직 복층 코어 관제홀**(지상층 + 중층 발판 링 + 상층 관측 데크). 카메라 FIXED → 완만 추적.
# 시그니처 배경 = Stage._ambience_core_arena(거대 코어 링 + 회전 관측 링 + 데이터 폭포).
# P1 = 목표형 전투: 상층 데크의 **관측 안테나** 2기(재머 격상 · 잡몹은 끝없는 소규모 투입).
# P2(Stage._start_rival_p2) = 소등 + 벽 포탑 4기(하/중층) + 위장 함정 + 중계 안테나 2기 +
# 층별 교대 스윕. P3 = 거짓 VEIL + 가짜 눈 동반(변주 3단).
# 점프 등급(known_issues 도달 보장, 더블점프 245): 지상 1220→중층 1040(Δ180)→계단 880(Δ160)
# →데크 720(Δ160) / 중앙 1000→860(Δ140).
static func _core_recovery() -> Dictionary:
	return {
		"world_type":   "ARENA",
		"world_size":   Vector2(2400.0, 1300.0),
		"player_start": Vector2(1200.0, 1150.0),
		"goal_type":    "ENEMY_CLEAR",
		"goal_pos":     Vector2.ZERO,
		"camera_mode":  "ARENA_FOLLOW",
		"ground_y":     1220.0,
		"rival_boss":   true,
		"waves_hunt":   true,
		"elite_chance": 1.0,
		"arena_clear_xp": 4,
		"platforms": [
			# 중층 링
			{"pos": Vector2(350, 1040),  "w": 230.0},
			{"pos": Vector2(1200, 1000), "w": 280.0},
			{"pos": Vector2(2050, 1040), "w": 230.0},
			# 중앙 상단(회복 지점 · P1 소모 보전)
			{"pos": Vector2(1200, 860),  "w": 220.0},
			# 상층 연결 계단
			{"pos": Vector2(700, 880),   "w": 160.0},
			{"pos": Vector2(1700, 880),  "w": 160.0},
			# 상층 관측 데크(안테나 자리)
			{"pos": Vector2(450, 720),   "w": 300.0},
			{"pos": Vector2(1950, 720),  "w": 300.0},
		],
		# P1 목표형 전투: 초기 스폰 = 상층 데크의 관측 안테나(jammer 로직 재사용) 2기뿐.
		# 잡몹은 Stage가 끝없이 소규모 투입(_p1_trickle_tick · 전멸 불가). 출구 = 안테나 파괴뿐.
		# 안테나의 재밍 그늘이 좌우 절반의 마커를 지운다(§7.2 "재밍 그늘").
		"enemies": {
			"patrol": [], "sniper": [], "drone": [], "bomber": [], "shield": [],
			"jammer": [Vector2(450, 690.0), Vector2(1950, 690.0)],
		},
		"rewards": {"xp_orbs": [], "hp_pickups": [Vector2(1200, 830.0)]},
		"spikes": [],
	}

# ─── 23. 응축기 구역 (HORIZONTAL, 막2) — 증기 타이밍 + 드론(cooling 자매, 게이트 없음) ──
# 시그니처 = 증기 분출구(SteamVent) 타이밍 통과 + 머리 위 드론. cooling과 같은 해저드 계열이나
# 글라이드 게이트 없는 순수 통과형(드론 처리·증기 회피 학습).
# 방 체인 3방(2026-08-21 배치 4 · room_chain_expansion §3 "낙수 3방" · 사용자 "왜 이렇게
# 작고 짧아" 대응): 인입 매니폴드(학습) → 응축기 홀(원형 계승 · 본 손맛) → 집수조(절정 ·
# 배수 밸브 lever 관문). 압력 문법(hp_survival_economy §5b) 내장 — 방마다 사선 교차 1+.
static func _condenser() -> Dictionary:
	return {"segments": [_condenser_inlet(), _condenser_hall(), _condenser_basin()]}

# 방1 · 인입 매니폴드. 낙수 3기(간격 넉넉) 학습 — 리듬 읽기를 가볍게.
static func _condenser_inlet() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "condenser_inlet",
		"indoor_env":   "water",
		"no_spike_fallback": true,
		"platforms": [
			{"pos": Vector2(620, 470),  "w": 180.0},
			{"pos": Vector2(1180, 450), "w": 160.0},
			{"pos": Vector2(1750, 470), "w": 180.0},
			{"pos": Vector2(2250, 460), "w": 180.0},
		],
		"drips": [
			{"x": 900.0,  "interval": 3.2, "phase": 0.0},
			{"x": 1500.0, "interval": 3.4, "phase": 0.5},
			{"x": 2050.0, "interval": 3.0, "phase": 0.25},
		],
		"route_lines": [
			{"x": 300.0, "who": "veil", "text": "천장 배관에서 끓는 냉각수가 떨어집니다. 맞으면 데입니다. 방울이 맺히면 바닥 표시를 피하십시오.", "dur": 4.0},
		],
		"enemies": {
			# 압력: 낙수 1500의 회피 타이밍과 순찰 1650 압박이 겹치는 교차 1개(학습 강도).
			"patrol": [Vector2(760, 600.0), Vector2(1650, 600.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1180, 420.0)],
			"hp_pickups": [],
		},
		"spikes": [],
	}

# 방2 · 응축기 홀(원형 계승). 낙수 6 + 드론 3 — 이 맵의 본 손맛.
static func _condenser_hall() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "condenser_hall",
		"indoor_env":   "water",
		"no_spike_fallback": true,
		"platforms": [
			# 상부 코일 포켓 + 저단차(수칙 3·4) · 낙수점(420~2760)과 간섭 없는 x 유지.
			{"pos": Vector2(600, 460),  "w": 190.0},
			{"pos": Vector2(1100, 420), "w": 160.0},
			{"pos": Vector2(1560, 340), "w": 140.0},   # 응축 코일 상부(리스크-리워드 포켓)
			{"pos": Vector2(2040, 460), "w": 200.0},
			{"pos": Vector2(2520, 440), "w": 160.0},
			{"pos": Vector2(2660, 530), "w": 100.0},   # 저단차 스텝
			{"pos": Vector2(2980, 470), "w": 200.0},
		],
		# 시그니처 · 응축수 낙수(§8 확산 8호, 2026-08-17): 기존 바닥 증기 6기를 낙수로 교체 ·
		# 증기를 그대로 두면 냉각 시설의 복제(§8 대장 검수에서 발견). 냉각 = 아래에서 솟는
		# 증기 / 응축기 = 위에서 떨어지는 응축수(축 반전). 낙수점은 발판 사이 지면(간섭 없음).
		"drips": [
			{"x": 420.0,  "interval": 2.6, "phase": 0.0},
			{"x": 880.0,  "interval": 3.0, "phase": 0.4},
			{"x": 1340.0, "interval": 2.4, "phase": 0.7},
			{"x": 1820.0, "interval": 2.8, "phase": 0.2},
			{"x": 2300.0, "interval": 2.6, "phase": 0.55},
			{"x": 2760.0, "interval": 3.0, "phase": 0.85},
		],
		"enemies": {
			# 압력: 존A(1100~1560) 드론 위 + 낙수 1340 + 순찰 1250 / 존B(2300~2760) 드론 +
			# 낙수 2기 + 순찰 2200·3000 협공(제자리 금지 = 순찰 돌진 + 낙수 시한).
			"patrol": [Vector2(820, 600.0), Vector2(1250, 600.0), Vector2(2200, 600.0),
				Vector2(3000, 600.0)],
			"sniper": [],
			"drone":  [Vector2(1100, 250.0), Vector2(2040, 240.0), Vector2(2760, 250.0)],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1100, 390.0), Vector2(1560, 310.0)],
			"hp_pickups": [Vector2(2980, 440.0)],
		},
		"spikes": [],
	}

# 방3 · 집수조(절정). 낙수 밀집 + 파이프 위 저격 + 배수 밸브 레버 관문.
static func _condenser_basin() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3000.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2880.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "condenser_basin",
		"indoor_env":   "water",
		"no_spike_fallback": true,
		# 레버 y = 발판 top(440) - 22 · Δ160(더블점프 직행) · 상공 드론 초기 배치 금지 규칙 준수.
		"mid_gate": {"x": 2700.0, "mode": "lever", "lever": Vector2(2380.0, 418.0), "own_hint": true},
		"platforms": [
			{"pos": Vector2(600, 460),  "w": 180.0},
			{"pos": Vector2(1150, 440), "w": 160.0},
			{"pos": Vector2(1700, 460), "w": 180.0},
			{"pos": Vector2(2380, 440), "w": 150.0},   # 배수 밸브 레버 발판
		],
		# 낙수 절정 — 간격을 좁혀 리듬이 겹친다(학습 3.2s → 절정 2.0~2.4s).
		"drips": [
			{"x": 480.0,  "interval": 2.0, "phase": 0.0},
			{"x": 900.0,  "interval": 2.2, "phase": 0.5},
			{"x": 1320.0, "interval": 2.0, "phase": 0.25},
			{"x": 1740.0, "interval": 2.2, "phase": 0.75},
			{"x": 2120.0, "interval": 2.0, "phase": 0.5},
			{"x": 2560.0, "interval": 2.4, "phase": 0.0},
		],
		"route_lines": [
			{"x": 1900.0, "who": "veil", "text": "앞의 밸브 레버를 당기면 배수구 문이 열립니다. 낙수 밑에 멈춰 서지 마십시오.", "dur": 3.6},
		],
		"enemies": {
			# 압력 절정: 레버 접근(1900~2380) = 낙수 2120·2560 타이밍 × 발판 위 저격 1700
			# 사선(재조준 = 레버 체류 비용) × 순찰 2250 압박.
			"patrol": [Vector2(950, 600.0), Vector2(2250, 600.0)],
			"sniper": [Vector2(1700, 428.0)],
			"drone":  [Vector2(1150, 240.0)],
			"bomber": [],
			"shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1150, 410.0)],
			"hp_pickups": [Vector2(600, 430.0)],
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
			# 경계등 곁 고공 포켓(원뿔 각 밖 = 수평은 안 걸림 · 기하 학습, 수칙 4·6) + 저단차.
			{"pos": Vector2(560, 480),  "w": 200.0},
			{"pos": Vector2(1100, 470), "w": 200.0},   # 경계등1 은신처
			{"pos": Vector2(1620, 360), "w": 110.0},   # 고공 포켓(XP)
			{"pos": Vector2(1680, 480), "w": 200.0},
			{"pos": Vector2(2300, 440), "w": 160.0},
			{"pos": Vector2(2560, 520), "w": 110.0},
			{"pos": Vector2(2800, 480), "w": 200.0},   # 경계등2 은신처
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
			"xp_orbs":    [Vector2(1620, 330.0), Vector2(2300, 410.0)],
			"hp_pickups": [Vector2(2800, 450.0)],
		},
		"spikes": [],
		# 시그니처 · 지상 경계등(§8 확산 9호, 2026-08-17): 감시탑 탐조등(Searchlight) 재사용,
		# 지주 장착 지상 스윕. 막1에서 감시등 문법을 도입 → 감시탑(s2)이 절정이 되는 램프.
		# 회피 = 발판 아래 그림자(LoS) · 걸리면 경보 = 인간 경비 증원(감시탑과 동일 룰).
		"searchlights": [
			{"x": 1400.0, "y": 316.0, "from_deg": 55.0, "to_deg": 125.0, "period": 6.5, "len": 560.0, "pole_h": 276.0},
			{"x": 2620.0, "y": 316.0, "from_deg": 55.0, "to_deg": 125.0, "period": 7.5, "len": 560.0, "pole_h": 276.0},
		],
		"route_lines": [
			{"x": 300.0, "who": "veil", "text": "경계등이 바닥을 훑습니다. 빛이 오면 발판 아래로 숨으십시오. 걸리면 경비가 붙습니다.", "dur": 4.0},
		],
	}

# ─── 25. 함정 통로 (HORIZONTAL, 막2) — 함정 내비게이션(적 적음, 포탑 다수) ──
# 방 체인 3방(2026-08-21 배치 4 · "밀도 램프 3방"): 진입 회랑(학습: 하향 포탑 + 감지선
# 1회) → 본 통로(원형 계승) → 격자 사로(절정: 포탑열 안 동력 레버 관문). 적은 끝까지 최소 —
# "적보다 함정" 정체성 유지, 압박 램프는 포탑 밀도·위상으로만 올린다.
static func _gauntlet() -> Dictionary:
	return {"segments": [_gauntlet_entry(), _gauntlet_main(), _gauntlet_grid()]}

# 방1 · 진입 회랑. 하향 포탑 2(간격 여유) + 감지선-상향 연동 1조 학습.
static func _gauntlet_entry() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2600.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "gauntlet_entry",
		"indoor_env":   "interior",
		"no_spike_fallback": true,
		"platforms": [
			{"pos": Vector2(620, 460),  "w": 190.0},
			{"pos": Vector2(1250, 450), "w": 180.0},
			{"pos": Vector2(1900, 460), "w": 190.0},
		],
		"traps": [
			{"x": 1250, "y": 468.0, "dir": "down", "interval": 2.0, "phase": 0.0},
			{"x": 1900, "y": 478.0, "dir": "down", "interval": 2.0, "phase": 0.5},
			{"x": 2250, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "ge1", "burst": 3},
		],
		"tripwires": [
			{"x": 2120, "y": 540.0, "dir": "up", "len": 200.0, "trigger_id": "ge1", "cooldown": 2.6},
		],
		"route_lines": [
			{"x": 300.0, "who": "veil", "text": "여기는 경비보다 포탑이 많습니다. 발사 간격을 읽고, 바닥의 붉은 감지선은 밟지 마십시오.", "dur": 4.0},
		],
		"enemies": {
			# 압력: 하향 포탑 1250 타이밍 × 순찰 1400 압박 교차 1개(학습 강도).
			"patrol": [Vector2(1400, 600.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1250, 420.0)],
			"hp_pickups": [],
		},
		"spikes": [],
	}

# 방2 · 본 통로(원형 계승). 하향 2 + 감지선-상향 2 연동 — 본 손맛.
static func _gauntlet_main() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3400.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(3280.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "gauntlet_main",
		"indoor_env":   "interior",
		"no_spike_fallback": true,
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
			# 상향 쌍(gt1)은 발판 2060(스팬 1970~2150)을 좌우에서 포위 — 구 2000은 발판 정하방이라
			# 탄이 122px 만에 슬래브에 먹혔다(트랩 스윕 2026-08-24, 발판이 탄 먹는 배치 금지).
			{"x": 1820, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "gt1", "burst": 3},
			{"x": 2180, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "gt1", "burst": 3},
		],
		"tripwires": [
			{"x": 1620, "y": 540.0, "dir": "up", "len": 200.0, "trigger_id": "gt1", "cooldown": 2.6},
		],
	}

# 방3 · 격자 사로(절정). 하향 3(위상 1/3 엇갈림) + 감지선-상향 2조 + 포탑열 안 동력 레버 관문 —
# 레버 당기기가 포탑 리듬 읽기의 최종 시험.
static func _gauntlet_grid() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3000.0, 720.0),
		"player_start": Vector2(140.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2880.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "gauntlet_grid",
		"indoor_env":   "interior",
		"no_spike_fallback": true,
		# 레버 y = 발판 top(440) - 22 · Δ160 · 상공 드론 없음(규칙 준수).
		"mid_gate": {"x": 2600.0, "mode": "lever", "lever": Vector2(2300.0, 418.0), "own_hint": true},
		"platforms": [
			{"pos": Vector2(560, 460),  "w": 180.0},
			{"pos": Vector2(1150, 440), "w": 170.0},
			{"pos": Vector2(1750, 460), "w": 180.0},
			{"pos": Vector2(2300, 440), "w": 150.0},   # 동력 레버 발판(하향 포탑 아래)
		],
		"traps": [
			{"x": 1150, "y": 458.0, "dir": "down", "interval": 1.6, "phase": 0.0},
			{"x": 1750, "y": 478.0, "dir": "down", "interval": 1.6, "phase": 0.33},
			# 레버 발판 위 하향 포탑 — 당기기 = 발사 틈 읽기(절정). telegraph 기본 0.5 유지.
			{"x": 2300, "y": 458.0, "dir": "down", "interval": 1.7, "phase": 0.66},
			# 상향 쌍(gg1)은 발판 1150(스팬 1065~1235)을 좌우에서 포위 — 구 1150은 발판 정하방이라
			# 탄이 122px 만에 슬래브에 먹혔다(트랩 스윕 2026-08-24, 발판이 탄 먹는 배치 금지).
			{"x": 1000, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "gg1", "burst": 3},
			{"x": 1300, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "gg1", "burst": 3},
			{"x": 2050, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "gg2", "burst": 3},
			{"x": 2200, "y": 588.0, "dir": "up", "mode": "triggered", "trigger_id": "gg2", "burst": 3},
		],
		"tripwires": [
			{"x": 900.0,  "y": 540.0, "dir": "up", "len": 200.0, "trigger_id": "gg1", "cooldown": 2.6},
			{"x": 1950.0, "y": 540.0, "dir": "up", "len": 200.0, "trigger_id": "gg2", "cooldown": 2.6},
		],
		"route_lines": [
			{"x": 2000.0, "who": "veil", "text": "마지막 포탑열 안쪽의 동력 레버가 문을 엽니다. 포탑이 쉬는 틈에 당기십시오.", "dur": 3.6},
		],
		"enemies": {
			# 압력: 하향 포탑 위상 격자 × 순찰 2기 압박(제자리 금지). 적은 여전히 최소.
			"patrol": [Vector2(700, 600.0), Vector2(1900, 600.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1150, 410.0)],
			"hp_pickups": [Vector2(560, 430.0)],
		},
		"spikes": [],
	}

# ─── 26. 화물 리프트 (HORIZONTAL, 막2) — 이동 발판 기믹 주역 ──
# reskin 탈피 첫 "진짜 기믹 맵"(2026-06-26, act_identity 2번 레버). 정비 화물구역:
# 스파이크 구덩이(dmg2) 위를 왕복하는 화물 리프트(MovingPlatform)를 타이밍 맞춰 건넌다.
# 발판이 동선의 *주역* — 적은 최소(patrol 3). 지면은 연속이라 구덩이=스파이크 구간(한 구덩이 도보
# 횡단≈치명) → 발판이 안전 동선. 단 떨어져도 즉사 아님(dmg2 진입 1회=HP 손실)이라 완주 안전.
# 중앙 수직 리프트는 XP 보너스(선택 — 메인 동선 아님). cycle 넉넉(5~5.5s)·phase 엇갈림으로 리듬.
# 방 체인 3방(2026-08-21 배치 4 · "페리 릴레이 3방"): 하역 마당(학습: 단일 페리 + 수직
# 보너스) → 릴레이 홀(본 손맛: 공중 갈아타기 + 저격 사선) → 출하 갠트리(절정: 3연속
# 갈아타기 + 저격 크로스). 관문 없음 — 기믹 리듬 자체가 문(구성 중복 금지 원칙 유지).
static func _freight_lift() -> Dictionary:
	return {"segments": [_freight_yard(), _freight_relay(), _freight_gantry()]}

# 방1 · 하역 마당. 단일 페리 2 + 수직 보너스 리프트 — 타이밍 학습.
static func _freight_yard() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2600.0, 720.0),
		"player_start": Vector2(140.0, 520.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2480.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "freight_yard",
		"no_spike_fallback": true,
		"platforms": [
			{"pos": Vector2(1330, 300), "w": 150.0},   # 수직 리프트 상단 보너스 알코브
		],
		"moving_platforms": [
			{"from": Vector2(800, 520), "to": Vector2(1120, 520), "w": 180.0, "cycle": 5.0, "phase": 0.0},
			# 보너스 — 중앙 수직 리프트(지면→알코브). 선택(메인 동선 아님).
			{"from": Vector2(1330, 580), "to": Vector2(1330, 340), "w": 130.0, "cycle": 4.5, "phase": 0.2},
			{"from": Vector2(1660, 480), "to": Vector2(2040, 480), "w": 180.0, "cycle": 5.5, "phase": 0.35},
		],
		"enemies": {
			"patrol": [Vector2(460, 540.0), Vector2(2250, 540.0)],
			"sniper": [], "drone": [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1300, 270.0), Vector2(1360, 270.0)],
			"hp_pickups": [],
		},
		"spikes": [
			{"x": 960.0, "w": 300.0, "dmg": 2},
			{"x": 1850.0, "w": 340.0, "dmg": 2},
		],
	}

# 방2 · 릴레이 홀. 페리 2대 공중 갈아타기 + 감시 저격 사선 — 본 손맛.
static func _freight_relay() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3000.0, 720.0),
		"player_start": Vector2(140.0, 520.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2880.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "freight_relay",
		"no_spike_fallback": true,
		"platforms": [
			# 감시 저격 거치대 — 오르면 저격 정면 처치 + HP(리스크-리워드).
			{"pos": Vector2(2200, 430), "w": 130.0},
		],
		"moving_platforms": [
			# 릴레이 — 페리 1이 오른끝에 설 때 페리 2가 왼끝으로 들어온다(위상 0.0/0.5).
			{"from": Vector2(700, 500),  "to": Vector2(1250, 500), "w": 170.0, "cycle": 5.5, "phase": 0.0},
			{"from": Vector2(1400, 460), "to": Vector2(1950, 460), "w": 170.0, "cycle": 5.5, "phase": 0.5},
			# 마무리 단일 페리.
			{"from": Vector2(2400, 520), "to": Vector2(2680, 520), "w": 170.0, "cycle": 5.0, "phase": 0.3},
		],
		"route_lines": [
			{"x": 500.0, "who": "veil", "text": "여기부터는 리프트를 공중에서 갈아탑니다. 다음 리프트가 들어올 때를 보고 건너뛰십시오.", "dur": 3.8},
		],
		"enemies": {
			# 압력: 갈아타기(700~1950) 상공 사선 = 거치대 저격(재조준이 릴레이 체류 비용) +
			# 착지 지점 순찰 압박.
			"patrol": [Vector2(500, 540.0), Vector2(2500, 540.0)],
			"sniper": [Vector2(2200, 398.0)],
			"drone": [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1325, 430.0)],
			"hp_pickups": [Vector2(2200, 400.0)],
		},
		"spikes": [
			{"x": 1350.0, "w": 1360.0, "dmg": 2},   # 릴레이 구덩이 전체(670~2030)
			{"x": 2540.0, "w": 300.0, "dmg": 2},
		],
	}

# 방3 · 출하 갠트리(절정). 3연속 갈아타기 + 저격 크로스 — 램프의 정점.
static func _freight_gantry() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3000.0, 720.0),
		"player_start": Vector2(140.0, 520.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2880.0, 540.0),
		"camera_mode":  "HORIZONTAL",
		"ambience":     "freight_gantry",
		"no_spike_fallback": true,
		"platforms": [
			# 저격 크로스 거치대 2 — 구덩이 상공 좌/우에서 릴레이 동선을 교차로 조준.
			{"pos": Vector2(1250, 380), "w": 120.0},
			{"pos": Vector2(2350, 400), "w": 120.0},
		],
		"moving_platforms": [
			# 3연속 릴레이 — 위상 0.0/0.5/0.15로 "기다렸다 두 번 갈아타기"의 정점.
			{"from": Vector2(550, 510),  "to": Vector2(1150, 510), "w": 170.0, "cycle": 5.5, "phase": 0.0},
			{"from": Vector2(1300, 460), "to": Vector2(1900, 460), "w": 170.0, "cycle": 5.5, "phase": 0.5},
			{"from": Vector2(2050, 510), "to": Vector2(2560, 510), "w": 170.0, "cycle": 5.0, "phase": 0.15},
		],
		"route_lines": [
			{"x": 400.0, "who": "veil", "text": "마지막 구간입니다. 리프트 세 대를 이어 타야 합니다. 위 조준선은 갈아타는 순간을 노립니다.", "dur": 4.0},
		],
		"enemies": {
			# 압력 절정: 저격 크로스(1250·2350)가 릴레이 상공을 좌우에서 교차 + 출구 순찰.
			"patrol": [Vector2(350, 540.0), Vector2(2800, 540.0)],
			"sniper": [Vector2(1250, 348.0), Vector2(2350, 368.0)],
			"drone": [], "bomber": [], "shield": [],
		},
		"rewards": {
			"xp_orbs":    [Vector2(1600, 430.0)],
			"hp_pickups": [],
		},
		"spikes": [
			{"x": 1550.0, "w": 2100.0, "dmg": 2},   # 갠트리 구덩이 전체(500~2600)
		],
	}

# ─── 차량 엄폐 통로 (HORIZONTAL) — 부서지는 엄폐 기믹 맵 (막2 s4~5) ─────────
# 정체성: 저격에 노출된 개활 통로를 "부서지는 차량"(DestructibleCover) 뒤에 붙어 전진.
#   · 차량은 솔리드 → 저격수 LoS를 막아 뒤에 붙으면 안전, 넘어갈 때만 노출(넘는 순간 조준당함).
#   · 통로 끝의 발사 함정(BulletTrap)이 LoS 무관하게 훑어 먼 쪽 차량부터 침식 → 목표 근처가 점점
#     노출된다("머물면 엄폐가 깨진다"). 목표까지 커버가 남아있는 동안 전진하는 레이스.
# 램프: risk3라 s3 금지(min_stage 4). 앞쪽 = 여유(엄폐 많음, warmup patrol) → 뒤쪽 = 저격 2 + 함정
#   침식으로 노출 최고조(막2 고조에 맞는 곡선).
# 방 체인 2방(2026-08-21 배치 4 · "엄폐 레이스 2방+저격 램프"): 정비로(원형 계승) →
# 야적 마당(절정: 저격 4 + 양방향 침식 + 자폭병 플러시). 고가 저격은 배제 — 엄폐(h72) 위로
# 사선이 넘어가 "숨으면 안전" 문법 자체가 깨진다(설계 검토에서 기각).
static func _car_cover() -> Dictionary:
	return {"segments": [_carcover_row(), _carcover_yard()]}

# 방1 · 정비로(원형 계승). 저격 3 분산 + 우측 포탑 침식 — 엄폐 전진 학습과 본 손맛.
static func _carcover_row() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(3000.0, 720.0),
		"player_start": Vector2(130.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2960.0, 540.0),   # 포탑(2900) 너머 오른쪽 = 좌향 사선 밖(출구에선 안 맞음)
		"camera_mode":  "HORIZONTAL",
		"ambience":     "carcover_row",
		"no_spike_fallback": true,
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

# 방2 · 야적 마당(절정). 고가 저격 도입(2026-08-22 사용자 "고가 저격을 만들면서도 안전해지는
# 방법을 찾아서"): 육교 위 저격 2는 낮은 차(h72) 너머를 보지만, **키 큰 컨테이너(h150)** 가
# 그 사선까지 막는다 — 지상 사선은 차량 뒤, 고가 사선은 컨테이너의 반대편 포켓이 답.
# 육교는 올라갈 수 있어(스텝/더블점프) 위험을 감수하면 정면으로 끊는 것도 답.
# + 양방향 침식(앞 좌향/뒤 우향 포탑) + 자폭병 1(엄폐 뒤 눌러앉기 플러시).
static func _carcover_yard() -> Dictionary:
	return {
		"world_type":   "HORIZONTAL",
		"world_size":   Vector2(2800.0, 720.0),
		"player_start": Vector2(130.0, 540.0),
		"goal_type":    "POSITION",
		"goal_pos":     Vector2(2760.0, 540.0),   # 좌향 포탑(2700) 오른쪽 = 사선 밖
		"camera_mode":  "HORIZONTAL",
		"ambience":     "carcover_yard",
		"no_spike_fallback": true,
		"elite_chance": 0.0,
		"platforms": [
			# 육교 A(고가 · 스텝 경유 Δ110+Δ110) + 육교 B(저가 · 더블점프 직행 Δ140).
			{"pos": Vector2(1090, 490), "w": 100.0},   # A 접근 스텝
			{"pos": Vector2(1420, 380), "w": 160.0},   # 육교 A(고가 저격)
			{"pos": Vector2(2320, 460), "w": 140.0},   # 육교 B(저가 저격)
		],
		"destructible_covers": [
			{"pos": Vector2(380, 600),  "w": 96.0,  "h": 72.0, "hp": 3},
			{"pos": Vector2(660, 600),  "w": 90.0,  "h": 150.0, "hp": 5, "style": "container"},
			{"pos": Vector2(950, 600),  "w": 96.0,  "h": 72.0, "hp": 3},
			{"pos": Vector2(1230, 600), "w": 110.0, "h": 64.0, "hp": 4},
			{"pos": Vector2(1560, 600), "w": 96.0,  "h": 72.0, "hp": 3},
			{"pos": Vector2(1890, 600), "w": 90.0,  "h": 150.0, "hp": 5, "style": "container"},
			{"pos": Vector2(2170, 600), "w": 110.0, "h": 64.0, "hp": 4},
			{"pos": Vector2(2450, 600), "w": 96.0,  "h": 72.0, "hp": 3},
		],
		"enemies": {
			# 저격 램프 절정: 지상 2 + 육교(고가) 2. 고가는 차 너머를 보고, 컨테이너만 못 뚫는다.
			"patrol": [Vector2(500, 540.0)],
			"sniper": [Vector2(1100, 540.0), Vector2(1700, 540.0),
				Vector2(1420, 348.0), Vector2(2320, 428.0)],
			"drone": [], "shield": [],
			"bomber": [Vector2(1990, 540.0)],
		},
		# 양방향 침식 — 앞(2700 좌향)은 진행을 조준하고, 뒤(100 우향)는 지나온 엄폐의
		# 등을 깎는다. 눌러앉으면 숨을 자리부터 사라진다.
		"traps": [
			{"x": 2700.0, "y": 560.0, "dir": "left",  "interval": 1.7, "phase": 0.0, "telegraph": 0.6, "dmg": 1},
			{"x": 100.0,  "y": 560.0, "dir": "right", "interval": 1.9, "phase": 0.5, "telegraph": 0.6, "dmg": 1},
		],
		"route_lines": [
			{"x": 350.0, "who": "veil", "text": "포탑이 양쪽에서 엄폐를 깎고, 육교 위 저격은 낮은 차 너머까지 봅니다. 키 큰 컨테이너 뒤가 그 사각입니다.", "dur": 4.4},
		],
		"rewards": {
			# 컨테이너 사각 포켓 + 육교 A 위(올라가 끊는 루트의 보상).
			"xp_orbs":    [Vector2(760, 560.0), Vector2(1420, 350.0)],
			"hp_pickups": [Vector2(1830, 560.0)],
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
		# 수직 스캔 빔 — 왼→오 훑기, rest 후 반복. 구간 제한(2026-08-22 "맵 밖까지 따라온다"):
		# 종전 -60~6660은 맵 양끝 바깥 + 골(6480) 위까지 훑었다. 레일이 화면에 보이는 안(60)에서
		# 시작해 마지막 니치(6000) 너머 6320에서 멈춘다 — 골 앞은 이완(정비 갱도와 같은 결).
		"sweep_beam": {
			# y_top 120 = 카메라 시야 안(HUD 아래) — 레일·헤드가 화면에 보여야 실물 출처가 성립.
			"x_start": 60.0, "x_end": 6320.0, "y_top": 120.0, "y_bot": 640.0,
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

# ─── 저지선 (ARENA, 웨이브 6) — 부서지는 엄폐 농성(pop-and-shoot) · 막4~5 s11~12 ─────────
# 정체성: 부서지는 바리케이드(DestructibleCover) 뒤에서 몸을 내밀어 쏘고 숨으며(pop-and-shoot) 밀려오는
#   웨이브를 저지한다. 좌우 벽 포탑(traps, LoS 무관)이 바리케이드를 지속 사격해 갉아 → 엄폐는 유한 자원.
#   엄폐가 부서질수록 노출이 커져 후반 긴장이 고조된다. 부서지기 전에 다 정리하는 게 목표.
# 손맛 차별: datacenter(자유 사냥 이동)·reactor(코어 방어)와 달리 "엄폐에 의존해 한 자리를 버티는" 농성.
#   근접(patrol/bomber/shield)=엄폐 사이 갭으로 접근 / 원거리(발판 sniper)=엄폐 위 각으로 pop 타이밍 압박.
# 클리어=웨이브 3 전멸(ENEMY_CLEAR). 램프: risk3(막2 고조).
# ── 봇 계측 전용 벤치 맵 (게임 미노출 · RouteData 미등록이라 선택지에 안 뜬다) ──
# 표준 조우(순찰 2+폭탄병 1)를 3웨이브 반복: 빌드별 처치 시간의 순수 비교가 목적.
# 평지 단일 구성인 이유: 수직 지형은 봇의 등반 한계가 측정을 오염시킨다(datacenter 교훈).
# 방패병 제외 이유: 상성 카운터(폭발물)를 요구하는 특수 케이스라 화력 비교엔 잡음.
static func _bot_bench() -> Dictionary:
	return {
		"world_type":   "ARENA",
		# 엘리트 롤 잠금 — 후반 스테이지 계측(막5 벤치)에서 확률 승격이 분산을 오염시키지 않게.
		# 막 진행 강화(HP·사격 빈도)는 결정적이라 그대로 측정된다.
		"elite_chance": 0.0,
		"world_size":   Vector2(1600.0, 760.0),
		"player_start": Vector2(200.0, 620.0),
		"goal_type":    "ENEMY_CLEAR",
		"goal_pos":     Vector2.ZERO,
		"camera_mode":  "FIXED",
		"ground_y":     680.0,
		"platforms":    [],
		"waves": [
			{"trigger": "immediate",  "banner": "WAVE 1", "enemies": {
				"patrol": [Vector2(1000.0, 650.0), Vector2(1350.0, 650.0)],
				"bomber": [Vector2(1200.0, 650.0)]}},
			{"trigger": "prev_clear", "banner": "WAVE 2", "enemies": {
				"patrol": [Vector2(1000.0, 650.0), Vector2(1350.0, 650.0)],
				"bomber": [Vector2(1200.0, 650.0)]}},
			{"trigger": "prev_clear", "banner": "WAVE 3", "enemies": {
				"patrol": [Vector2(1000.0, 650.0), Vector2(1350.0, 650.0)],
				"bomber": [Vector2(1200.0, 650.0)]}},
		],
		"enemies": {
			"patrol": [Vector2(1000.0, 650.0), Vector2(1350.0, 650.0)],
			"bomber": [Vector2(1200.0, 650.0)],
		},
		"rewards": {"xp_orbs": [], "hp_pickups": []},
	}

# 막5 벤치(봇 계측 전용 · 게임 미노출) — 후반 표준 조우의 실전형 구성. 순찰만으론 만렙 빌드가
# 첫 공격 사이클 전에 전멸시켜 피탄이 안 잡힌다(2026-08-18 실측) — 실제 막5 조우처럼 원거리
# 위협(저격 협공)을 섞어야 "만렙이 공짜로 이기는가"가 측정된다. 방패병(정면 교착)과 드론
# (공중 · 유도 없는 빌드는 못 잡아 90s 타임아웃 실측)은 봇이 해소 못 해 데드락 — 제외
# (datacenter 교훈과 동형: 봇이 못 푸는 조우를 스위트에 넣지 않는다).
static func _bot_bench_late() -> Dictionary:
	return {
		"world_type":   "ARENA",
		"elite_chance": 0.0,
		"world_size":   Vector2(1600.0, 760.0),
		"player_start": Vector2(200.0, 620.0),
		"goal_type":    "ENEMY_CLEAR",
		"goal_pos":     Vector2.ZERO,
		"camera_mode":  "FIXED",
		"ground_y":     680.0,
		"platforms":    [],
		"waves": [
			{"trigger": "immediate",  "banner": "WAVE 1", "enemies": {
				"patrol": [Vector2(1000.0, 650.0), Vector2(1350.0, 650.0)],
				"sniper": [Vector2(1480.0, 650.0)]}},
			{"trigger": "prev_clear", "banner": "WAVE 2", "enemies": {
				"patrol": [Vector2(1000.0, 650.0), Vector2(1350.0, 650.0)],
				"sniper": [Vector2(1480.0, 650.0)],
				"bomber": [Vector2(1200.0, 650.0)]}},
			{"trigger": "prev_clear", "banner": "WAVE 3", "enemies": {
				"patrol": [Vector2(1000.0, 650.0), Vector2(1350.0, 650.0)],
				"sniper": [Vector2(1480.0, 650.0), Vector2(120.0, 650.0)]}},
		],
		"enemies": {
			"patrol": [Vector2(1000.0, 650.0), Vector2(1350.0, 650.0)],
			"sniper": [Vector2(1480.0, 650.0)],
		},
		"rewards": {"xp_orbs": [], "hp_pickups": []},
	}

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
			{"pos": Vector2(740.0, 820.0),  "w": 92.0, "h": 92.0, "hp": 6},
			{"pos": Vector2(1180.0, 820.0), "w": 92.0, "h": 92.0, "hp": 6},
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
			# ── 배치 3 확장(2026-08-19): 웨이브 3 → 6(room_chain_expansion §3 · 목표 막4 100~130s).
			# 농성 아크: 개전 → 폭탄 압박 → 좌측 스쿼드 → 원거리+호출 → 우측 스쿼드 → 재머 절정.
			# 엄폐(hp 4~6)는 유한 자원 - 후반일수록 노출 고조가 이 맵의 정체성.
			# ── 혼성 진형(2026-08-20 사용자): 같은 타입 뭉침을 스쿼드로 재편. 방패 근처(300px)
			# 정찰병은 스폰 직후 그 방패의 호위가 된다(Stage._assign_wave_escorts).
			{
				"trigger": "prev_clear",
				"banner":  "WAVE 3",
				"enemies": {
					# 좌측 전진 스쿼드: 방패 선두 + 정찰 2 후위 - 관통 한 줄로 안 쓸린다.
					"shield": [Vector2(230, 790.0)],
					"patrol": [Vector2(150, 790.0), Vector2(90, 790.0)],
				},
			},
			{
				"trigger": "prev_half",   # 파도가 반쯤 남았을 때 위에서 협공 - 겹침 압박
				"banner":  "WAVE 4",
				"enemies": {
					# 저격 이중 사선 + 호출병: 사선에 묶여 있는 동안 증원이 계속 불려 온다.
					"sniper": [Vector2(340, 490.0), Vector2(1580, 490.0)],
					"caller": [Vector2(1700, 790.0)],
				},
			},
			{
				"trigger": "prev_clear",
				"banner":  "WAVE 5",
				"enemies": {
					# 우측 전진 스쿼드: 방패+정찰 호위+자폭 측면.
					"shield": [Vector2(1730, 790.0)],
					"patrol": [Vector2(1800, 790.0)],
					"bomber": [Vector2(1650, 790.0)],
				},
			},
			{
				"trigger": "prev_clear",
				"banner":  "FINAL WAVE",
				"enemies": {
					# 중앙 스쿼드 + 양익 저격 + 재머 절정.
					"shield": [Vector2(960, 790.0)],
					"patrol": [Vector2(880, 790.0), Vector2(1040, 790.0)],
					"sniper": [Vector2(340, 490.0), Vector2(1580, 490.0)],
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
			"caller": [Vector2(1700, 790.0)],
		},
		"rewards": {
			# 안쪽 엄폐 뒤(안전) xp / 중앙 뒤 hp — 거점을 오래 비우지 않게 중앙 근처에.
			"xp_orbs":    [Vector2(740, 760.0), Vector2(1180, 760.0)],
			"hp_pickups": [Vector2(960, 700.0)],
		},
		"spikes": [],
		"arena_clear_xp": 6,   # 웨이브 3→6 확장 상향(2026-08-19)
	}
