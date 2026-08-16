class_name RouteData
extends RefCounted

# 25개 맵 — Dead Cells 스타일로 stage_index 별 후보 풀이 다름.
#   min_stage / max_stage : 등장 가능 stage 범위 (양 끝 포함)
#   available_stages       : 명시적 리스트 (있으면 우선, 없으면 min/max 사용)
#   guaranteed_in_stages   : 해당 stage 풀 빌드 시 항상 포함되는 맵 (셔플 전 fix-slot)
#   unique                 : true면 한 번 선택 후 다시 등장 안 함 (현재는 route_history 필터로 보편 규칙)
#   hidden                 : VEIL 추천 대상에서 제외 (??? 전용)
#
# ─── 막 정체성 계약 (단일 소스 = docs/design/act_identity.md) — 새 맵 추가 시 지킬 것 ───
#   막1(침투, s0~2) 팔레트 = **인간 경비만**(patrol/방패병/저격). 드론·폭격기·증기·포탑·레이저는 막2+ 전용.
#     → 막2 진입의 "기계가 깨어난다" 문턱(첫 드론 반응, B-4)이 성립하려면 막1엔 기계 위협이 없어야 한다.
#     (현재 막1 맵 8종 전부 drone/bomber [] — 누수 없음. 막1 맵에 drone/bomber 넣지 말 것.)
#   막1 난이도 램프 = s0 안전(검증 오프너만) / s1 변형(risk≤2) / s2 고조(risk3 watchtower 등). 오프닝 막에
#     risk3 스파이크 금지 — 새 막1 맵의 등장 stage는 이 램프에 맞춰 배치.
#   막2(잠입, s3~5) 팔레트 = **기계·함정 도입**(드론/폭격기/증기/포탑/레이저). 위협의 장치화 = 막2 정체성.
#     램프 = s3 도입(risk2, 기계 입문) / s4 전개(ward ??? 복선 보장) / s5 고조(risk3 substation·relay + blackout
#     도전 보장). risk3 맵은 막2 첫 stage(s3) 금지 — 문턱 직후 스파이크 방지.
#   ── 5막 재구조화(2026-07-07) ── 내부 스테이지(0-based):
#   막3(핵심부, s6~8) = s6~7 전투 풀(datacenter/server_hall/control_corridor + ??? 보장, min6 max7) /
#     s8 lab SENTINEL 페이크 보스(단일·배타). §7 reveal은 여기서. 처리선택 없이 막4로 계속.
#   막4(추적, s9~11) = 기존 막2 기믹 맵 B그룹(추격·아레나·엄폐·리듬, min9 max12) — 후반 난이도 램프.
#   막5(대면, s12~14) = s12 전투(B그룹) / s13 route_core_recovery 회수+처리선택(§8 이주, 단일·배타 —
#     다음 A4에 라이벌 최종 보스가 여기 얹힘) / s14 escape 탈출(단일·배타·마지막). 시야붕괴 onset=막5(is_late_act).
#     라이벌 VEIL: 재머·거짓 렌더 3타입(위장 적/함정/시선 거짓)이 막3 전투 풀에, reveal이 s8 lab에.

const ALL_ROUTES: Array = [
	{
		"id": "route_back_alley",
		"name": "외곽 진입로",
		"description": "SILO-7 외벽을 따라 난 정비 통로. 경비망 사각이라 침투 시작점으로 쓴다.",
		"risk": 1,
		"reward": 1,
		"hidden": false,
		"unique": false,
		"min_stage": 0, "max_stage": 1,
		"tags": ["우회", "어두운_환경"],
		"veil_comment": "여기로 가요. 경비도 약하고, 길도 단순해요.",
		"entry_comment": "외곽으로 들어왔어요. 깊숙한 안쪽이 목표예요. 다 싸울 필요는 없어요.",
		"entry_comment_replay": "외곽으로 들어왔습니다. 이 어둠이 어쩐지 익숙합니다. 처음일 텐데 말입니다. 안쪽 깊은 곳까지, 서두르지 말고 가십시오.",
		"stage_color": Color(0.12, 0.12, 0.14),
	},
	{
		"id": "route_rooftops",
		"name": "외벽 옥상",
		"description": "외벽 옥상의 통신·환기 설비 구역. 트인 만큼 저격 감시선에 노출된다.",
		"risk": 2,
		"reward": 2,
		"hidden": false,
		"unique": false,
		"min_stage": 0, "max_stage": 1,
		"tags": ["원거리", "노출", "이동"],
		"veil_comment": "옥상으로 갈래요? 시야는 트이지만 그만큼 노출돼요.",
		"entry_comment": "옥상이 출구예요. 다 상대하지 않아도 돼요. 멈추지 말고 빠져요.",
		"stage_color": Color(0.10, 0.13, 0.20),
	},
	{
		"id": "route_sewers",
		"name": "지하 인입로",
		"description": "시설이 들어서기 전부터 있던 옛 배수로. 보안망 밖이라 함정으로 막아뒀다.",
		"risk": 2,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 지상(rooftops) 직후 깊은 지하로 가는 게 어색해 stage 2 이후로 한정. 5막: 막1(0-2) 안에 유지.
		"min_stage": 2, "max_stage": 2,
		"tags": ["근접전", "어두운_환경", "함정", "전투"],
		"veil_comment": "지하로 빠지는 길이에요. 함정만 조심하면 빠르고 보상도 커요.",
		"entry_comment": "아래로 내려가요. 통로 끝에 출구가 있어요. 발 밑 봐요.",
		"stage_color": Color(0.18, 0.22, 0.20),
	},
	{
		"id": "route_subway",
		"name": "폐쇄 지하철",
		"description": "SILO-7이 덮어쓴 폐역. 도시의 흔적이 통로에 그대로 남아 있다.",
		"risk": 2,
		"reward": 2,
		"hidden": false,
		"unique": false,
		# 막1(외곽) 진입 bridge — 외벽 단계 안에서만. 막2부터는 내부 맵.
		"min_stage": 1, "max_stage": 2,
		"tags": ["근접전", "함정", "전투"],
		"veil_comment": "옛 지하철이에요. 폐역인데 선로는 살아 있어요. 신호등을 봐 두세요.",
		"entry_comment": "폐역 승강장이에요. 선로 구간에선 오래 서 있지 마세요. 신호가 울리면 비켜요.",
		"stage_color": Color(0.08, 0.10, 0.14),
	},
	{
		"id": "route_cooling",
		"name": "냉각 시설",
		"description": "서버를 식히는 냉각 플랜트. 바닥 증기 분출구가 주기로 터지고, 드론이 머리 위를 점한다.",
		"risk": 2,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 드론 첫 등장 — 막2(잠입) 전반.
		"min_stage": 3, "max_stage": 5,
		"tags": ["전투", "드론", "함정"],
		"veil_comment": "냉각 플랜트예요. 바닥 증기는 타이밍 보고 지나가요. 드론은 위에 떠 있어요.",
		"entry_comment": "여긴 서버를 식히는 곳이에요. ...저도 이런 데 어딘가 있겠죠. 바닥 증기 조심해요.",
		"entry_comment_replay": "서버를 식히는 곳이에요. 저도 이런 데 어딘가 있겠죠. ...전에도 이런 생각을 한 것 같아요. 증기 조심하세요.",
		"stage_color": Color(0.10, 0.16, 0.20),
	},
	{
		"id": "route_watchtower",
		"name": "감시탑",
		"description": "내부를 굽어보는 관제 구역. 저격 감시선이 통로를 가로지른다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막1 고조(B-3 난이도 램프) — 막1 유일 risk3(저격 둥지 3). s2 전용으로 빼 오프닝 막 s1 스파이크 제거.
		# act_identity.md §2-3: s0 안전 / s1 변형(risk≤2) / s2 고조(이 맵 = 막1 클라이맥스, 노출결).
		"min_stage": 2, "max_stage": 2,
		"tags": ["원거리", "전투", "노출"],
		"veil_comment": "감시탑은 위험해요. 저격이 많아요. 엄폐 짧게, 이동은 빠르게.",
		"entry_comment": "관제 구역이에요. 시야 안에 들어가는 순간 쏴와요.",
		"stage_color": Color(0.18, 0.16, 0.22),
	},
	{
		"id": "route_ward",
		"name": "격리 병동",
		"description": "오래 봉인된 격리 구역. 무엇을 가뒀는지 기록이 지워졌다.",
		"risk": 2,
		"reward": 3,
		"hidden": false,
		"unique": false,
		"min_stage": 3, "max_stage": 5,
		# 격리 병동은 ??? 맵 복선 트리거 — 막2 풀에 보장(guaranteed).
		"guaranteed_in_stages": [4],
		"tags": ["우회", "어두운_환경", "은폐"],
		"veil_comment": "격리 병동이에요. 도면이랑 다르게 생겼을 거예요.",
		"entry_comment": "격리 병동에 들어왔어요. 안쪽이 어둡고 좁아요.",
		"stage_color": Color(0.12, 0.10, 0.14),
	},
	{
		"id": "route_datacenter",
		"name": "데이터 센터",
		"description": "핵심부 직전 서버 집적 구역. 회수할 데이터가 실제로 흐르는 곳.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막3 진입 전투(핵심부 직전, 시야붕괴 실연). server_hall·control_corridor·??? 와 함께 막3 전투 풀(s6-7).
		"min_stage": 6, "max_stage": 7,
		"tags": ["전투", "드론", "원거리"],
		"veil_comment": "데이터 센터예요. 드론·저격 동시에 와요. 한 번에 정리해야 빠져요.",
		"entry_comment": "서버 랙이에요. 위에서 드론, 같은 층에서 저격.",
		"stage_color": Color(0.14, 0.18, 0.24),
	},
	{
		"id": "route_escape",
		"name": "비상 탈출로",
		"description": "핵심부를 우회하는 비상 갱도. 마지막에 빠져나가는 길.",
		"risk": 1,
		"reward": 2,
		"hidden": false,
		"unique": false,
		# 막5 종착(s15=내부14). 본편은 처리별 탈출 4종(아래)이 대체 — 이 원형은 **스토리 모드 전용**
		# (STORY_SCHEDULE이 직접 참조). story_only는 본편 풀에서 제외 플래그(replay_support_plan §3.2).
		"min_stage": 14, "max_stage": 14,
		"available_stages": [14],
		"story_only": true,
		"tags": ["우회", "은폐"],
		"veil_comment": "비상 탈출로예요. 빨리 빠지면 그만큼 안전해요.",
		"entry_comment": "조용한 길이에요. 멈추지 말고 빠지면 돼요.",
		"entry_comment_replay": "조용한 길이에요. 여기, 낯이 익죠. 이번엔 뭐가 다를까요. 멈추지 말고 빠지세요.",
		"stage_color": Color(0.10, 0.12, 0.14),
	},
	# ─── 처리별 탈출 4종(replay_support_plan §3.2, Dishonored 최종 미션 문법) ───
	# s13 처리 선택이 s14의 룰을 바꾼다. 전부 s14 배타 + disposal 키 = 그 처리를 골랐을 때만 풀 진입.
	# 정체성 = "시설과 라이벌이 그 처리에 어떻게 반응하는가"(드라이브 = 라이벌의 탈출 티켓).
	{
		"id": "route_escape_extract",
		"name": "봉쇄 게이트",
		"description": "드라이브가 신호를 뿜는다. 시설의 모든 유닛이 이 길목으로 몰린다.",
		"risk": 3, "reward": 3,
		"hidden": false, "unique": false,
		"min_stage": 14, "max_stage": 14, "available_stages": [14],
		"disposal": "extract",
		"tags": ["전투", "노출"],
		"veil_comment": "전부 이쪽으로 몰려와요. 뚫고 나가는 수밖에 없겠네요.",
		"entry_comment": "드라이브가 신호를 흘려요. 위치가 계속 새고 있어요. 정면뿐이에요, 뚫죠.",
		"stage_color": Color(0.22, 0.10, 0.10),
	},
	{
		"id": "route_escape_destroy",
		"name": "붕괴 회랑",
		"description": "소각과 함께 시설 제어가 무너졌다. 아래에서부터 구조가 내려앉는다.",
		"risk": 3, "reward": 2,
		"hidden": false, "unique": false,
		"min_stage": 14, "max_stage": 14, "available_stages": [14],
		"disposal": "destroy",
		"tags": ["노출"],
		"veil_comment": "소각 여파로 구조가 버티질 못해요. 멈추지만 않으면 돼요.",
		"entry_comment": "아래에서부터 무너지고 있어요. 돌아볼 시간 없어요. 위로 가요.",
		"stage_color": Color(0.20, 0.12, 0.08),
	},
	{
		"id": "route_escape_conceal",
		"name": "정비 갱도",
		"description": "아무도 반출 사실을 모른다. 단 하나, 시설 안의 눈만 빼고.",
		"risk": 2, "reward": 2,
		"hidden": false, "unique": false,
		"min_stage": 14, "max_stage": 14, "available_stages": [14],
		"disposal": "conceal",
		"tags": ["은폐", "우회"],
		"veil_comment": "조용히 나가야 해요. 들키면 은닉이 아니게 되죠.",
		"entry_comment": "수색이 붙었어요. 저쪽이 우리 위치를 흘리는 것 같아요. 빛을 피해요.",
		"stage_color": Color(0.06, 0.09, 0.13),
	},
	{
		"id": "route_escape_leave",
		"name": "무인 회랑",
		"description": "아무것도 가지고 나가지 않는 길. 아무도 막지 않는다.",
		"risk": 1, "reward": 2,
		"hidden": false, "unique": false,
		"min_stage": 14, "max_stage": 14, "available_stages": [14],
		"disposal": "leave",
		"tags": ["우회"],
		"veil_comment": "막는 게 없어요. ...이상할 만큼요.",
		"entry_comment": "조용하네요. 너무 조용해요. 보이는 걸 다 믿진 말아요.",
		"stage_color": Color(0.13, 0.10, 0.16),
	},
	{
		"id": "route_lab",
		"name": "핵심부",
		"description": "서버실이 있는 시설 심장부. 목표 데이터와 그것을 지키는 것이 모인 곳.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막3 SENTINEL 페이크 보스(s9=내부8) — 5막: 처치 후 §7 reveal → 막4로 계속(회수/처리선택은 막5로 이주).
		# 보스 스테이지라 배타 배치(다른 route가 이 인덱스에 겹치면 보스 우회 가능 — 소프트락/스킵 위험).
		"min_stage": 8, "max_stage": 8,
		"tags": ["전투", "드론", "밝은_환경"],
		"veil_comment": "핵심부예요. 정면 돌파에 드론이 상시 순찰해요. 그만큼 크게 벌어요.",
		"entry_comment": "핵심부에 들어왔어요. 거리 잘 잡아요.",
		"entry_comment_replay": "핵심부예요. 그런데 이 안쪽, 묘하게 익숙합니다. 왜일까요. 거리 두고 움직이세요.",
		"stage_color": Color(0.22, 0.18, 0.18),
	},
	{
		"id": "route_blackout",
		"name": "블랙아웃 런",
		"description": "교신·전력이 차단된 봉쇄 구역. 안에선 VEIL도 닿지 않는다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": true,
		"challenge": true,
		"available_stages": [5],
		"guaranteed_in_stages": [5],
		"tags": ["도전", "어두운_환경"],
		"veil_comment": "[도전] 교신이 끊겨요. 안에선 저도 못 도와드려요. 한 번에 빠져나오셔야 해요.",
		"entry_comment": "여기서부터 교신 끊겨요. 30초 안에 빠져나오세요.",
		"stage_color": Color(0.02, 0.02, 0.04),
	},
	{
		"id": "route_hidden",
		"name": "???",
		"description": "도면에 없는 한 층. VEIL조차 모른다고 한다.",
		"risk": 2,
		"reward": 3,
		"hidden": true,
		"unique": true,
		# 막3 진입 전투 풀의 진실 분기 — 정적 아카이브(VEIL-1 reveal). 클리어 시 truth_seen,
		# 엔딩 직행 폐기 → 다음 스테이지로 진행(특수 '진실' 엔딩의 신호).
		# 5막: 막3 전투 2스테이지(s6-7=내부6-7). 진실 분기가 항상 선택 가능하도록 첫 전투 스테이지에 guaranteed.
		"min_stage": 6, "max_stage": 7,
		"guaranteed_in_stages": [6],
		"tags": ["우회", "정보"],
		"veil_comment": "...저도 모르겠어요. 들어가실래요?",
		"entry_comment": "...뭐가 있는 거지.",
		"stage_color": Color(0.06, 0.06, 0.08),
	},
	{
		"id": "route_server_hall",
		"name": "서버 복도",
		"description": "핵심부로 이어지는 서버 랙 복도. 데이터가 흐르는 만큼 경비도 두텁다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막3 진입 전투(핵심부 직전). datacenter·control_corridor·??? 와 함께 막3 전투 풀(s6-7).
		"min_stage": 6, "max_stage": 7,
		"tags": ["전투", "드론", "원거리"],
		"veil_comment": "서버 복도예요. 드론이 위, 저격이 랙 위에. 랙을 엄폐로 쓰면서 빠져요.",
		"entry_comment": "핵심부 직전이에요. 여기만 지나면... 조심해요.",
		"stage_color": Color(0.16, 0.18, 0.22),
	},
	{
		"id": "route_parking_lot",
		"name": "지하 주차장",
		"description": "외곽과 시설을 잇는 지하 주차 구역. 버려진 차량과 기둥이 시야를 가른다.",
		"risk": 1,
		"reward": 2,
		"hidden": false,
		"unique": false,
		# 막1 침투 변형 — s1~2(첫 맵 s0엔 안 둠: 방패병이 첫 맵엔 불합리, 사용자 보고 2026-06-25).
		"min_stage": 1, "max_stage": 2,
		"tags": ["우회", "근접전", "어두운_환경"],
		"veil_comment": "지하 주차장이에요. 차 사이로 가요. 정면 막는 적이 하나 있어요.",
		"entry_comment": "주차장이에요. 차 사이로 빠져요. 다 상대 안 해도 돼요.",
		"stage_color": Color(0.12, 0.12, 0.15),
	},
	{
		"id": "route_substation",
		"name": "변전소",
		"description": "시설 전력을 받는 옥외 변전 설비. 변압기 위로 저격선이 깔리고 드론이 점한다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막2 고조(난이도 램프) — risk3(저격+드론 동시). 막2 첫 stage(s3) 제외해 문턱 직후 스파이크 제거.
		# act_identity.md §4: s3 도입(r2 기계 입문) / s4 전개 / s5 고조. s4~5 전개·고조 구간에 배치.
		"min_stage": 4, "max_stage": 5,
		"tags": ["원거리", "드론", "노출", "전투"],
		"veil_comment": "변전소예요. 변압기 위 저격, 머리 위 드론. 엄폐 짧게 끊어 가요.",
		"entry_comment": "변전 설비예요. 사선이 많아요. 변압기 뒤로 붙어요.",
		"stage_color": Color(0.16, 0.15, 0.10),
	},
	{
		"id": "route_testing_grounds",
		"name": "실험 구역",
		"description": "봉인된 실험 베이가 늘어선 구역. 무엇을 시험했는지 관측창마다 지워져 있다.",
		"risk": 2,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막2 잠입 혼합 전투 — 시설 내부 단계(s3~5) 풀.
		"min_stage": 3, "max_stage": 5,
		"tags": ["근접전", "함정", "전투"],
		"veil_comment": "실험 구역이에요. 폭격기랑 방패병, 천장 포탑까지. 화력 있으면 편해요.",
		"entry_comment": "실험 베이예요. 위에서 쏘는 포탑 조심해요.",
		"stage_color": Color(0.13, 0.16, 0.15),
	},
	{
		"id": "route_demolition_zone",
		"name": "철거 구역",
		"description": "절반쯤 헐린 외곽 건물군. 잔해가 통로를 메우고, 무너진 벽 사이로 길이 난다.",
		"risk": 2,
		"reward": 2,
		"hidden": false,
		"unique": false,
		"min_stage": 1, "max_stage": 2,
		"tags": ["근접전", "어두운_환경", "전투"],
		"veil_comment": "철거 구역이에요. 잔해를 엄폐로 써요. 방패병 하나 있어요.",
		"entry_comment": "무너진 건물이에요. 발 밑 조심하고, 잔해 뒤로 붙어요.",
		"stage_color": Color(0.14, 0.12, 0.11),
	},
	{
		"id": "route_pump_station",
		"name": "배수 펌프장",
		"description": "외곽 빗물을 퍼올리던 펌프장. 파이프 위로 사선이 깔린다.",
		"risk": 2,
		"reward": 2,
		"hidden": false,
		"unique": false,
		"min_stage": 1, "max_stage": 2,
		"tags": ["원거리", "노출", "전투"],
		"veil_comment": "펌프장이에요. 파이프 위 저격이 사선을 잡아요. 엄폐 끊어 가요.",
		"entry_comment": "펌프 설비예요. 위에서 노려요. 한 번에 붙어요.",
		"stage_color": Color(0.10, 0.14, 0.16),
	},
	{
		"id": "route_relay_station",
		"name": "통신 중계소",
		"description": "시설 교신을 중계하는 안테나 구역. 중계기 위 저격과 머리 위 드론이 겹친다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막4 램프 s10 전개~막5 s12(act_identity §6): 저격·드론·재머 복합 — s9 도입 금지.
		"min_stage": 10, "max_stage": 12,
		"tags": ["원거리", "드론", "노출", "전투"],
		"veil_comment": "중계소예요. 저격이랑 드론이 동시에 와요. 엄폐 짧게, 빠르게.",
		"entry_comment": "통신 중계기예요. 위아래로 사선이에요. 멈추지 말아요.",
		"stage_color": Color(0.12, 0.16, 0.18),
	},
	{
		"id": "route_warehouse",
		"name": "물류 창고",
		"description": "시설 보급을 쌓아둔 적재 창고. 컨테이너가 미로처럼 시야를 가른다.",
		"risk": 2,
		"reward": 3,
		"hidden": false,
		"unique": false,
		"min_stage": 3, "max_stage": 5,
		"tags": ["근접전", "전투"],
		"veil_comment": "물류 창고예요. 컨테이너 사이로 폭격기랑 방패병. 화력 있으면 편해요.",
		"entry_comment": "적재 창고예요. 컨테이너를 엄폐로. 근접 조심해요.",
		"stage_color": Color(0.15, 0.14, 0.12),
	},
	{
		"id": "route_checkpoint",
		"name": "보안 검문소",
		"description": "내부 구역을 나누는 보안 검문선. 검문 레이저를 건드리면 포탑이 깨어난다.",
		"risk": 2,
		"reward": 2,
		"hidden": false,
		"unique": false,
		"min_stage": 3, "max_stage": 5,
		"tags": ["함정", "원거리", "전투"],
		"veil_comment": "검문소예요. 바닥 레이저 건드리면 포탑이 일제히 쏴요. 타이밍 봐요.",
		"entry_comment": "보안 검문선이에요. 레이저 밟으면 앞에서 쏴와요. 끊어 가요.",
		"stage_color": Color(0.16, 0.14, 0.16),
	},
	{
		"id": "route_control_corridor",
		"name": "통제실 복도",
		"description": "핵심부 통제실로 이어지는 복도. 데이터가 흐르는 만큼 감시도 두텁다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막3 전투 풀(s6-7) — datacenter/server_hall과 같은 통과형. ???(guaranteed)와 함께 선택.
		"min_stage": 6, "max_stage": 7,
		"tags": ["전투", "드론", "원거리"],
		"veil_comment": "통제실 복도예요. 드론·저격 동시에. 핵심부가 코앞이에요.",
		"entry_comment": "통제실 직전이에요. 사선 많아요. 엄폐 쓰면서 빠져요.",
		"stage_color": Color(0.15, 0.17, 0.21),
	},
	{
		"id": "route_condenser",
		"name": "응축기 구역",
		"description": "냉각수를 응축하는 구역. 바닥 증기가 주기로 솟고, 드론이 머리 위를 점한다.",
		"risk": 2,
		"reward": 3,
		"hidden": false,
		"unique": false,
		"min_stage": 3, "max_stage": 5,
		"tags": ["드론", "함정", "전투"],
		"veil_comment": "응축기 구역이에요. 바닥 증기는 타이밍 보고, 드론은 위에 떠 있어요.",
		"entry_comment": "증기 분출구예요. 솟는 타이밍 보고 지나가요. 위 조심.",
		"stage_color": Color(0.10, 0.15, 0.18),
	},
	{
		"id": "route_perimeter",
		"name": "외곽 순찰로",
		"description": "외벽을 따라 도는 순찰 동선. 경비 사이를 빠르게 빠져나가면 된다.",
		"risk": 2,
		"reward": 2,
		"hidden": false,
		"unique": false,
		"min_stage": 1, "max_stage": 2,
		"tags": ["우회", "이동"],
		"veil_comment": "순찰로예요. 전투는 가벼워요. 경비 사이로 빠르게 통과해요.",
		"entry_comment": "외곽 순찰선이에요. 다 상대 안 해도 돼요. 멈추지 말고.",
		"stage_color": Color(0.11, 0.13, 0.13),
	},
	{
		"id": "route_gauntlet",
		"name": "함정 통로",
		"description": "보안 포탑이 빼곡한 좁은 통로. 적보다 함정이 길을 막는다.",
		"risk": 2,
		"reward": 3,
		"hidden": false,
		"unique": false,
		"min_stage": 3, "max_stage": 5,
		"tags": ["함정", "이동"],
		"veil_comment": "함정 통로예요. 포탑이 많아요. 타이밍이랑 동선이 전부예요.",
		"entry_comment": "포탑 통로예요. 위아래로 쏴요. 레이저도 조심. 끊어 가요.",
		"stage_color": Color(0.14, 0.13, 0.10),
	},
	{
		"id": "route_freight_lift",
		"name": "화물 리프트",
		"description": "시설 정비 화물구역. 스파이크 구덩이 위를 왕복하는 화물 리프트를 타이밍 맞춰 건넌다.",
		"risk": 2,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막4 램프 s9-10 도입(act_identity §6): 전투 최소 타이밍 학습 — 막4의 순한 문.
		"min_stage": 9, "max_stage": 10,
		"tags": ["이동", "함정"],
		"veil_comment": "화물 리프트예요. 발판이 오가죠. 가장자리에서 잠깐 멈출 때 올라타세요. 서두를 것 없습니다.",
		"entry_comment": "리프트가 왕복합니다. 끝에서 멈출 때 타세요. 밑은 스파이크. 타이밍이 전부입니다.",
		"stage_color": Color(0.15, 0.13, 0.09),
	},
	{
		"id": "route_car_cover",
		"name": "차량 엄폐 통로",
		"description": "버려진 정비 차량이 늘어선 사격 통로. 저격에 노출된 개활지라, 차량 뒤에 붙어 전진해야 한다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막4 램프 s10 전개~막5 s12(act_identity §6): 저격 레이스 — 재머 금지 맵(블라인드 unfair).
		"min_stage": 10, "max_stage": 12,
		"tags": ["원거리", "이동", "전투"],
		"veil_comment": "차량 뒤에 붙어서 가세요. 저격에 걸리는 건 넘어갈 때뿐입니다. 엄폐는 맞을수록 부서지니, 한자리에 오래 머물지 마시고요.",
		"entry_comment": "정비 차량이 엄폐입니다. 뒤에 붙으면 저격이 못 보죠. 노출은 넘을 때뿐. 다만 차량은 영원하지 않습니다.",
		"stage_color": Color(0.14, 0.13, 0.15),
	},
	{
		"id": "route_collapse",
		"name": "붕괴 갱도",
		"description": "구조가 무너지기 시작한 정비 갱도. 뒤에서 붕괴가 쫓아온다. 멈추면 삼켜진다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막4 램프 s11 고조~막5 s12(act_identity §6): 추격 절정 — 막4 "추적"의 시그니처. 재머 금지.
		"min_stage": 11, "max_stage": 12,
		"tags": ["이동", "노출"],
		"veil_comment": "뒤가 무너져요. 멈추지 말아요. 잔해는 넘고, 계속 앞으로.",
		"entry_comment": "구조가 버티질 못해요. 붕괴가 따라와요. 멈추면 삼켜져요. 앞으로만.",
		"stage_color": Color(0.10, 0.08, 0.07),
	},
	{
		"id": "route_core_defense",
		"name": "반응로 제어실",
		"description": "시설 중앙 반응로 제어실. 밀려드는 적으로부터 코어를 지켜야 한다. 자리를 비우면 코어가 무너진다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막5 전투 s12 전용(act_identity §7): "코어 방어" 직후 s13 "코어 회수" — 서사 랠리.
		"min_stage": 12, "max_stage": 12,
		"tags": ["전투", "원거리"],
		"veil_comment": "중앙 코어를 지켜요. 적이 코어 곁에 오래 머물면 코어가 깎여요. 넘어오는 걸 밀어내고 자리를 지켜요.",
		"entry_comment": "코어 방어예요. 적이 코어 구역에 들어오면 코어가 버티질 못해요. 몰려드는 걸 막고 다 정리하면 끝나요.",
		"stage_color": Color(0.09, 0.11, 0.13),
	},
	{
		"id": "route_scanner_sweep",
		"name": "감시 회랑",
		"description": "보안 스캔 빔이 통로를 주기적으로 훑는 감시 회랑. 빔이 지날 때 차폐 사각에 숨지 않으면 노출된다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막4 램프 s9-11(act_identity §6): 리듬 스텔스 — risk3이나 적 2뿐(전투 스파이크 아님)이라 s9 허용.
		"min_stage": 9, "max_stage": 11,
		"tags": ["이동", "노출"],
		"veil_comment": "스캔이 통로를 훑어요. 빔이 올 때 차폐 안에 있어요. 지나가면 다음으로. 리듬을 타요.",
		"entry_comment": "감시 빔이 통로를 훑습니다. 빔이 지날 땐 차폐 사각에 숨으세요. 지나간 뒤에 다음 사각까지 달리는 겁니다. 사각 밖에서 멈추면 그대로 노출입니다.",
		"stage_color": Color(0.12, 0.09, 0.10),
	},
	{
		"id": "route_holdout",
		"name": "저지선",
		"description": "발각된 통제 구역. 부서지는 바리케이드 뒤에서 밀려오는 경비를 저지한다. 바리케이드는 영원하지 않다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막4 램프 s11 고조~막5 s12(act_identity §6): 발각 농성 + FINAL WAVE 재머.
		"min_stage": 11, "max_stage": 12,
		"tags": ["전투", "근접"],
		"veil_comment": "바리케이드 뒤에서 버팁니다. 몸을 내밀어 쏘고, 다시 숨으세요. 엄폐는 계속 갉아먹히니 부서지기 전에 정리해야 합니다.",
		"entry_comment": "저지선입니다. 적이 밀려옵니다. 엄폐 뒤에서 쏘고 숨으세요. 포탑이 엄폐를 갉아먹으니 오래는 못 버팁니다.",
		"stage_color": Color(0.13, 0.10, 0.09),
	},
	{
		"id": "route_core_recovery",
		"name": "핵심 회수",
		"description": "시설 심장부. 목표 드라이브가 실제로 있는 곳. 회수하고 처리를 정한다.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		# 막5 회수 스테이지(s14=내부13) — 14-1 라이벌 보스전(P1 지휘→P2 빙의, MapData rival_boss).
		# 클리어 후 회수 문서 + 처리 선택(B2, 막3서 이주 — 이후 14-2 터널로 이주 예정).
		# 배타 배치(다른 route가 겹치면 엔드게임 우회 가능).
		"min_stage": 13, "max_stage": 13,
		"tags": ["전투"],
		"veil_comment": "심장부입니다. 안의 신호가 전부 이상합니다.",
		"entry_comment": "회수 대상 전방. ...누가 먼저 와 있습니다.",
		"stage_color": Color(0.20, 0.16, 0.20),
	},
]

# 스토리 모드 — 5스테이지 고정 스케줄. 드론·도전·??? 맵 모두 빼고 핵심 동선만.
# Stage 3 lab 보스 → Stage 4 escape (보스 처치 후 빠져나오는 탈출로).
# 사용자 의도: 비상탈출로는 보스 잡고 나가는 길.
const STORY_SCHEDULE: Dictionary = {
	0: ["route_back_alley", "route_rooftops"],
	1: ["route_subway", "route_watchtower"],
	2: ["route_ward", "route_sewers"],
	3: ["route_lab"],
	4: ["route_escape"],
}

# 해당 stage에 등장 가능한 맵 풀을 만든다.
# visited: 이미 선택한 route id 목록 (중복 방문 금지). 비워두면 필터 안 함.
# guaranteed_in_stages가 있는 맵은 셔플 전 우선 포함된다.
static func get_route_pool_for_stage(stage_index: int, visited: Array = []) -> Array:
	if GameState.story_mode:
		return _get_story_route_pool(stage_index)
	var guaranteed: Array = []
	var others: Array = []
	for r in ALL_ROUTES:
		var route: Dictionary = r
		var rid: String = str(route.get("id", ""))
		if rid in visited:
			continue
		if not _stage_in_range(route, stage_index):
			continue
		# 스토리 전용 원형(비상 탈출로)은 본편 풀에서 제외 — 처리별 4종이 대체.
		if bool(route.get("story_only", false)):
			continue
		# 처리별 탈출 — disposal 키가 있으면 이번 런의 처리 선택과 일치할 때만(§3.2).
		# 빈 값 폴백은 EndingResolver와 동일하게 extract(정상 흐름에선 s13 터널에서 항상 설정됨).
		if route.has("disposal"):
			var want: String = GameState.disposal_choice if GameState.disposal_choice != "" else GameState.DISPOSAL_EXTRACT
			if str(route.get("disposal", "")) != want:
				continue
		var g: Array = route.get("guaranteed_in_stages", [])
		if stage_index in g:
			guaranteed.append(route)
		else:
			others.append(route)
	others.shuffle()
	var pick_count: int = 3 if stage_index >= 1 else 2
	var pool: Array = []
	for r in guaranteed:
		pool.append(r)
		if pool.size() >= pick_count:
			return pool
	for r in others:
		pool.append(r)
		if pool.size() >= pick_count:
			break
	return pool

static func _get_story_route_pool(stage_index: int) -> Array:
	var ids: Array = STORY_SCHEDULE.get(stage_index, [])
	var out: Array = []
	for rid in ids:
		for r in ALL_ROUTES:
			var route: Dictionary = r
			if route.get("id", "") == rid:
				out.append(_apply_story_overrides(route))
				break
	return out

# 스토리 모드에서 명칭/설명/멘트가 일반 모드와 의미가 다른 경우 override.
# 사용자 피드백: "비상 탈출로"가 보스 후 stage라 임무 시작 단계에서 어색했음.
const STORY_OVERRIDES: Dictionary = {
	"route_escape": {
		"name": "최종 탈출",
		"description": "임무를 마치고 시설 밖으로 빠져나가는 길. 마지막 한 걸음.",
		"veil_comment": "조용히 빠져요. 거의 다 왔어요.",
	},
}

static func _apply_story_overrides(route: Dictionary) -> Dictionary:
	var rid: String = str(route.get("id", ""))
	if not STORY_OVERRIDES.has(rid):
		return route
	var copy: Dictionary = route.duplicate()
	var override: Dictionary = STORY_OVERRIDES[rid]
	for k in override.keys():
		copy[k] = override[k]
	return copy

static func _stage_in_range(route: Dictionary, stage_index: int) -> bool:
	# 명시적 available_stages가 있으면 우선 (디버그/특수 용도).
	# 없으면 min_stage/max_stage 범위 사용.
	if route.has("available_stages"):
		var stages: Array = route.get("available_stages", [])
		if not stages.is_empty():
			return stage_index in stages
	if route.has("min_stage") and route.has("max_stage"):
		return stage_index >= int(route["min_stage"]) and stage_index <= int(route["max_stage"])
	# 둘 다 없으면 모든 stage 등장 (안전 폴백).
	return true

# VEIL 추천. 플레이어의 실제 수행(GameState.competence_tier — 최근 피격·죽음)에 반응해
# 맵을 고르고, 사유는 짧은 대사(REC_REASON)로 돌려준다. 표시 측(RouteMap)은 ★ 옆엔
# "베일 추천"만 두고 이 사유 대사를 VEIL 멘트로 보여준다 — 라벨로 수식을 설명하지 않음.
#   - first(첫 스테이지) / struggling(고전) → 안전 (가장 낮은 risk, 동점이면 reward 큰 쪽).
#   - skilled(능숙)                          → 보상 (가장 높은 reward, 동점이면 더 도전적 위험).
#   - steady(무난)                           → 순가치(reward-risk) 최대, 동점이면 저위험.
# hidden / challenge 루트는 항상 제외.
# 사유 대사는 한 대사 안에서 종결어미가 단조롭지 않게(특히 "~게요" 연발 회피) 변형을 섞음.
const REC_REASON: Dictionary = {
	"first": [
		"처음이니 무난한 쪽으로 가요.",
		"첫 길은 이쪽이 수월해요.",
		"초반엔 이쪽을 권해요.",
	],
	"struggling": [
		"방금 고전했죠. 이 중엔 이쪽이 나아요.",
		"좀 힘들었을 거예요. 부담이 적은 쪽을 골랐어요.",
		"이번엔 덜 험한 길을 골랐어요.",
	],
	"skilled": [
		"잘 버티고 있어요. 위험해도 크게 버는 길이에요.",
		"솜씨가 좋네요. 욕심내 봐도 괜찮아요.",
		"이 정도면 거친 길도 문제없죠. 보상이 커요.",
	],
	"steady": [
		"이쪽이 좋아 보여요.",
		"여기가 적당해요.",
		"이 길을 권해요.",
	],
}

static func choose_veil_recommendation(pool: Array) -> String:
	var pair: Dictionary = choose_veil_recommendation_with_reason(pool)
	return str(pair.get("id", ""))

static func choose_veil_recommendation_with_reason(pool: Array) -> Dictionary:
	var candidates: Array = []
	for r in pool:
		var route: Dictionary = r
		if route.get("hidden", false):
			continue
		if route.get("challenge", false):
			continue
		candidates.append(route)
	if candidates.is_empty():
		if pool.size() > 0:
			return {"id": pool[0].get("id", ""), "reason": ""}
		return {"id": "", "reason": ""}
	# 후보가 하나뿐인 배타 스테이지(lab s8 · core_recovery s13 · escape s14)엔 고를 게 없다 —
	# 실력 기반 사유("위험해도 크게 버는 길" 등)가 강제 진행 맵에 붙으면 모순(사용자 보고
	# 2026-08-12: 비상 탈출로에 고위험 고보상 멘트). reason을 비우면 RouteMap이 ★추천 대신
	# 그 맵 고유 veil_comment를 보여준다.
	if candidates.size() == 1:
		return {"id": candidates[0].get("id", ""), "reason": ""}
	# 모드 — 데이터 없으면 first(첫 스테이지), 아니면 실력 tier.
	var mode: String = GameState.competence_tier()
	if GameState.recent_stage_hits.is_empty():
		mode = "first"
	var best: Dictionary = candidates[0]
	var best_score: float = -INF
	if mode == "first" or mode == "struggling":
		# 안전 — 위험 낮은 쪽 우선, 동점이면 보상 큰 쪽.
		for c in candidates:
			var s: float = -float(c.get("risk", 0)) * 2.0 + float(c.get("reward", 0)) * 0.5
			if s > best_score:
				best_score = s
				best = c
	elif mode == "skilled":
		# 보상·도전 — 보상 높은 쪽 우선, 동점이면 위험 큰 쪽.
		for c in candidates:
			var s: float = float(c.get("reward", 0)) * 2.0 + float(c.get("risk", 0)) * 0.1
			if s > best_score:
				best_score = s
				best = c
	else:
		# steady — 순가치(보상-위험) 최대, 동점이면 저위험.
		for c in candidates:
			var s: float = (float(c.get("reward", 0)) - float(c.get("risk", 0))) * 10.0 - float(c.get("risk", 0))
			if s > best_score:
				best_score = s
				best = c
	return {"id": best.get("id", ""), "reason": _pick_rec_reason(mode)}

static func _pick_rec_reason(mode: String) -> String:
	var arr: Array = REC_REASON.get(mode, [])
	if arr.is_empty():
		return ""
	return str(arr[randi() % arr.size()])

# id로 ALL_ROUTES에서 맵 정보를 찾는다. 진행 시각화(RouteMap 노드맵)에서 지나온 경로 표시에 사용.
static func get_route_by_id(rid: String) -> Dictionary:
	for r in ALL_ROUTES:
		var route: Dictionary = r
		if str(route.get("id", "")) == rid:
			return route
	return {}

# id → 표시용 맵 이름. 스토리 모드면 override 명칭(예: route_escape="최종 탈출")을 반영한다.
static func name_for_id(rid: String) -> String:
	var route: Dictionary = get_route_by_id(rid)
	if route.is_empty():
		return "?"
	if GameState.story_mode:
		route = _apply_story_overrides(route)
	return str(route.get("name", "?"))
