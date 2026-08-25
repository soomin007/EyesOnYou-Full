class_name RouteData
extends RefCounted

# 25개 맵 · Dead Cells 스타일로 stage_index 별 후보 풀이 다름.
#   min_stage / max_stage : 등장 가능 stage 범위 (양 끝 포함)
#   available_stages       : 명시적 리스트 (있으면 우선, 없으면 min/max 사용)
#   guaranteed_in_stages   : 해당 stage 풀 빌드 시 항상 포함되는 맵 (셔플 전 fix-slot)
#   unique                 : true면 한 번 선택 후 다시 등장 안 함 (현재는 route_history 필터로 보편 규칙)
#   hidden                 : VEIL 추천 대상에서 제외 (??? 전용)
#
# ─── 어투 밴드 스윕(2026-08-21 사용자 승인) ───
#   veil_comment / entry_comment 기본 문안 = **중립 전술 보고체**(첫 판 = cold 밴드에서
#   warm처럼 들리지 않게). warm 밴드에서만 부드러운 변형을 쓰며, 그 문안은
#   veil_comment_warm / entry_comment_warm 키에 둔다(없으면 기본 폴백 · VeilDialogue.banded 참고).
#   warm 키는 warm 도달이 가능한 맵(스테이지 4+ 등장)에만 · 막1 전용 맵은 구조적으로 불가(trust 적립 속도).
#
# ─── 막 정체성 계약 (단일 소스 = docs/design/act_identity.md) · 새 맵 추가 시 지킬 것 ───
#   막1(침투, s0~2) 팔레트 = **인간 경비만**(patrol/방패병/저격). 드론·자폭병·증기·포탑·레이저는 막2+ 전용.
#     → 막2 진입의 "기계가 깨어난다" 문턱(첫 드론 반응, B-4)이 성립하려면 막1엔 기계 위협이 없어야 한다.
#     (현재 막1 맵 8종 전부 drone/bomber [] · 누수 없음. 막1 맵에 drone/bomber 넣지 말 것.)
#   막1 난이도 램프 = s0 안전(검증 오프너만) / s1 변형(risk≤2) / s2 고조(risk3 watchtower 등). 오프닝 막에
#     risk3 스파이크 금지 · 새 막1 맵의 등장 stage는 이 램프에 맞춰 배치.
#   막2(잠입, s3~5) 팔레트 = **기계·함정 도입**(드론/자폭병/증기/포탑/레이저). 위협의 장치화 = 막2 정체성.
#     램프 = s3 도입(risk2, 기계 입문) / s4 전개(ward ??? 복선 보장) / s5 고조(risk3 substation·relay + blackout
#     도전 보장). risk3 맵은 막2 첫 stage(s3) 금지 · 문턱 직후 스파이크 방지.
#   ── 5막 재구조화(2026-07-07) ── 내부 스테이지(0-based):
#   막3(핵심부, s6~8) = s6~7 전투 풀(datacenter/server_hall/control_corridor + ??? 보장, min6 max7) /
#     s8 lab SENTINEL 페이크 보스(단일·배타). §7 reveal은 여기서. 처리선택 없이 막4로 계속.
#   막4(추적, s9~11) = 기존 막2 기믹 맵 B그룹(추격·아레나·엄폐·리듬, min9 max12) · 후반 난이도 램프.
#   막5(대면, s12~14) = s12 전투(B그룹) / s13 route_core_recovery 회수+처리선택(§8 이주, 단일·배타 ·
#     다음 A4에 라이벌 최종 보스가 여기 얹힘) / s14 escape 탈출(단일·배타·마지막). 시야붕괴 onset=막5(is_late_act).
#     라이벌 VEIL: 재머·거짓 렌더 3타입(위장 적/함정/시선 거짓)이 막3 전투 풀에, reveal이 s8 lab에.

const ALL_ROUTES: Array = [
	{
		"id": "route_back_alley",
		"name": "외곽 진입로",
		"elev": "ground",
		"description": "SILO-7 외벽을 따라 난 정비 통로. 경비망 사각이라 침투 시작점으로 쓴다.",
		"risk": 1,
		"reward_type": "recon",
		"hidden": false,
		"unique": false,
		"min_stage": 0, "max_stage": 1,
		"tags": ["우회", "어두운_환경"],
		"veil_comment": "이쪽을 권합니다. 경비가 약하고, 길이 단순합니다.",
		"entry_comment": "외곽 진입 확인. 목표는 깊숙한 안쪽입니다. 다 싸울 필요는 없습니다.",
		"entry_comment_replay": "외곽으로 들어왔습니다. 이 어둠이 어쩐지 익숙합니다. 처음일 텐데 말입니다. 안쪽 깊은 곳까지, 서두르지 말고 가십시오.",
		"stage_color": Color(0.12, 0.12, 0.14),
	},
	{
		"id": "route_rooftops",
		"name": "외벽 옥상",
		"elev": "high",
		"description": "외벽 옥상의 통신·환기 설비 구역. 트인 만큼 노출되고, 돌풍이 주기적으로 분다.",
		"risk": 2,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		"min_stage": 0, "max_stage": 1,
		"tags": ["원거리", "노출", "이동"],
		"veil_comment": "옥상 경로입니다. 시야는 트이지만 그만큼 노출되고, 바람이 심합니다.",
		"entry_comment": "출구는 옥상입니다. 전부 상대할 필요 없습니다. 멈추지 말고 빠지십시오.",
		"stage_color": Color(0.10, 0.13, 0.20),
	},
	{
		"id": "route_sewers",
		"name": "옛 배수로",
		"elev": "under",
		"description": "시설이 들어서기 전부터 있던 옛 배수로. 펌프가 살아 있어 물이 주기적으로 차오른다.",
		"risk": 2,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		# 지상(rooftops) 직후 깊은 지하로 가는 게 어색해 stage 2 이후로 한정. 5막: 막1(0-2) 안에 유지.
		"min_stage": 2, "max_stage": 2,
		"tags": ["근접전", "어두운_환경", "함정", "전투"],
		"veil_comment": "지하 배수로입니다. 펌프가 아직 돌아 물이 오르내립니다. 높은 발판을 봐 두십시오.",
		"entry_comment": "아래로 빠지는 길입니다. 물이 차면 오르고, 빠지면 내려가는 리듬입니다. 발밑 주의.",
		"stage_color": Color(0.18, 0.22, 0.20),
	},
	{
		"id": "route_subway",
		"name": "폐쇄 지하철",
		"elev": "under",
		"description": "SILO-7이 덮어쓴 폐역. 도시의 흔적이 통로에 그대로 남아 있다.",
		"risk": 2,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		# 막1(외곽) 진입 bridge · 외벽 단계 안에서만. 막2부터는 내부 맵.
		"min_stage": 1, "max_stage": 2,
		"tags": ["근접전", "함정", "전투"],
		"veil_comment": "옛 지하철입니다. 폐역인데 선로는 살아 있습니다. 신호등을 봐 두십시오.",
		# 하강 진입 한 문장 = 고도 전이 정당화(C안, 2026-08-25). 필터로 지상→지하 전이만 남으니 항상 참.
		# 열차 규칙은 방2 진입 route_line이 전담(entry는 방1 승강장 홀에서 재생 · 무맥락 검수 FAIL① 수정).
		"entry_comment": "지하로 내려왔습니다. 폐역 승강장입니다. 출구는 안쪽 선로 방향입니다. 경비를 전부 상대할 필요는 없습니다.",
		"stage_color": Color(0.08, 0.10, 0.14),
	},
	{
		"id": "route_cooling",
		"name": "냉각 시설",
		"description": "서버를 식히는 냉각 플랜트. 바닥 증기 분출구가 주기로 터지고, 드론이 머리 위를 점한다.",
		"risk": 2,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		# 드론 첫 등장 · 막2(잠입) 전반.
		"min_stage": 3, "max_stage": 5,
		"tags": ["전투", "드론", "함정"],
		"veil_comment": "냉각 플랜트입니다. 바닥 증기는 타이밍을 보고 지나가십시오. 드론은 위에 떠 있습니다.",
		"veil_comment_warm": "냉각 플랜트예요. 바닥 증기는 타이밍 보고 지나가요. 드론은 위에 떠 있어요.",
		"entry_comment": "서버를 식히는 구역입니다. ...저도 이런 곳 어딘가에 있을 겁니다. 바닥 증기 주의.",
		"entry_comment_warm": "여긴 서버를 식히는 곳이에요. ...저도 이런 데 어딘가 있겠죠. 바닥 증기 조심해요.",
		"entry_comment_replay": "서버를 식히는 곳이에요. 저도 이런 데 어딘가 있겠죠. ...전에도 이런 생각을 한 것 같아요. 증기 조심하세요.",
		"stage_color": Color(0.10, 0.16, 0.20),
	},
	{
		"id": "route_watchtower",
		"name": "감시탑",
		"elev": "high",
		"description": "내부를 굽어보는 관제 구역. 저격 감시선과 탐조등이 통로를 가로지른다.",
		"risk": 3,
		"reward_type": "recon",
		"hidden": false,
		"unique": false,
		# 막1 고조(B-3 난이도 램프) · 막1 유일 risk3(저격 둥지 3). s2 전용으로 빼 오프닝 막 s1 스파이크 제거.
		# act_identity.md §2-3: s0 안전 / s1 변형(risk≤2) / s2 고조(이 맵 = 막1 클라이맥스, 노출결).
		"min_stage": 2, "max_stage": 2,
		"tags": ["원거리", "전투", "노출"],
		"veil_comment": "감시탑은 위험합니다. 저격이 많습니다. 엄폐는 짧게, 이동은 빠르게.",
		"entry_comment": "관제 구역입니다. 시야에 드는 순간 사격이 옵니다.",
		"stage_color": Color(0.18, 0.16, 0.22),
	},
	{
		"id": "route_ward",
		"name": "격리 병동",
		"description": "오래 봉인된 격리 구역. 무엇을 가뒀는지 기록이 지워졌다.",
		"risk": 2,
		"reward_type": "recon",
		"hidden": false,
		"unique": false,
		"min_stage": 3, "max_stage": 5,
		# 격리 병동은 ??? 맵 복선 트리거 · 막2 풀에 보장(guaranteed).
		"guaranteed_in_stages": [4],
		"tags": ["우회", "어두운_환경", "은폐"],
		"veil_comment": "격리 병동입니다. 도면과 다르게 생겼을 겁니다.",
		"veil_comment_warm": "격리 병동이에요. 도면이랑 다르게 생겼을 거예요.",
		"entry_comment": "격리 병동 진입. 안쪽이 어둡고 좁습니다.",
		"entry_comment_warm": "격리 병동에 들어왔어요. 안쪽이 어둡고 좁아요.",
		"stage_color": Color(0.12, 0.10, 0.14),
	},
	{
		"id": "route_datacenter",
		"name": "데이터 센터",
		"description": "핵심부 직전 서버 집적 구역. 회수할 데이터가 실제로 흐르는 곳.",
		"risk": 3,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		# 막3 진입 전투(핵심부 직전, 시야붕괴 실연). server_hall·control_corridor·??? 와 함께 막3 전투 풀(s6-7).
		"min_stage": 6, "max_stage": 7,
		"tags": ["전투", "드론", "원거리"],
		"veil_comment": "데이터 센터입니다. 드론과 저격이 동시에 옵니다. 한 번에 정리해야 빠집니다.",
		"veil_comment_warm": "데이터 센터예요. 드론·저격 동시에 와요. 한 번에 정리해야 빠져요.",
		"entry_comment": "서버 랙 구역입니다. 위에서 드론, 같은 층에서 저격.",
		"entry_comment_warm": "서버 랙이에요. 위에서 드론, 같은 층에서 저격.",
		"stage_color": Color(0.14, 0.18, 0.24),
	},
	{
		"id": "route_escape",
		"name": "비상 탈출로",
		"description": "핵심부를 우회하는 비상 갱도. 마지막에 빠져나가는 길.",
		"risk": 1,
		"reward_type": "",
		"hidden": false,
		"unique": false,
		# 막5 종착(s15=내부14). 본편은 처리별 탈출 4종(아래)이 대체 · 이 원형은 **스토리 모드 전용**
		# (STORY_SCHEDULE이 직접 참조). story_only는 본편 풀에서 제외 플래그(replay_support_plan §3.2).
		"min_stage": 14, "max_stage": 14,
		"available_stages": [14],
		"story_only": true,
		"tags": ["우회", "은폐"],
		"veil_comment": "비상 탈출로입니다. 빨리 빠질수록 안전합니다.",
		"veil_comment_warm": "비상 탈출로예요. 빨리 빠지면 그만큼 안전해요.",
		"entry_comment": "조용한 길입니다. 멈추지 말고 빠지면 됩니다.",
		"entry_comment_warm": "조용한 길이에요. 멈추지 말고 빠지면 돼요.",
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
		"risk": 3, "reward_type": "",
		"hidden": false, "unique": false,
		"min_stage": 14, "max_stage": 14, "available_stages": [14],
		"disposal": "extract",
		"tags": ["전투", "노출"],
		"veil_comment": "전부 이쪽으로 몰립니다. 뚫고 나가는 수밖에 없습니다.",
		"veil_comment_warm": "전부 이쪽으로 몰려와요. 뚫고 나가는 수밖에 없겠네요.",
		"entry_comment": "드라이브가 신호를 흘립니다. 위치가 계속 샙니다. 길은 정면뿐, 뚫고 갑니다.",
		"entry_comment_warm": "드라이브가 신호를 흘려요. 위치가 계속 새고 있어요. 정면뿐이에요, 뚫죠.",
		"stage_color": Color(0.22, 0.10, 0.10),
	},
	{
		"id": "route_escape_destroy",
		"name": "붕괴 회랑",
		"description": "드라이브는 시설 제어까지 물고 있었다. 소각이 시작되자 그 손부터 탔다. 버팀을 잃은 하부부터 내려앉는다.",
		"risk": 3, "reward_type": "",
		"hidden": false, "unique": false,
		"min_stage": 14, "max_stage": 14, "available_stages": [14],
		"disposal": "destroy",
		"tags": ["노출"],
		"veil_comment": "저쪽이 시설을 쥔 채로 타고 있습니다. 쥔 손이 풀리는 데부터 무너집니다. 멈추지만 않으면 됩니다.",
		"veil_comment_warm": "저쪽이 시설을 쥔 채로 타고 있어요. 쥔 손이 풀리는 데부터 무너져요. 멈추지만 않으면 돼요.",
		"entry_comment": "하부 버팀이 풀렸습니다. 아래부터 내려앉습니다. 위로. 돌아보지 마십시오.",
		"entry_comment_warm": "하부 버팀이 풀렸어요. 아래에서부터 내려앉아요. 위로. 돌아보지 말고요.",
		"stage_color": Color(0.20, 0.12, 0.08),
	},
	{
		"id": "route_escape_conceal",
		"name": "정비 갱도",
		"description": "아무도 반출 사실을 모른다. 단 하나, 시설 안의 눈만 빼고.",
		"risk": 2, "reward_type": "",
		"hidden": false, "unique": false,
		"min_stage": 14, "max_stage": 14, "available_stages": [14],
		"disposal": "conceal",
		"tags": ["은폐", "우회"],
		"veil_comment": "조용히 나가야 합니다. 들키면 은닉이 아니게 됩니다.",
		"veil_comment_warm": "조용히 나가야 해요. 들키면 은닉이 아니게 되죠.",
		# EN: "We're in. Stay low, stay quiet. Nobody knows we're here."
		"entry_comment": "진입했습니다. 낮게, 조용히 갑니다. 아직 아무도 모릅니다.",
		"entry_comment_warm": "진입했어요. 낮게, 조용히 가요. 아직 아무도 몰라요.",
		"stage_color": Color(0.06, 0.09, 0.13),
	},
	{
		"id": "route_escape_leave",
		"name": "무인 회랑",
		"description": "아무것도 가지고 나가지 않는 길. 아무도 막지 않는다.",
		"risk": 1, "reward_type": "",
		"hidden": false, "unique": false,
		"min_stage": 14, "max_stage": 14, "available_stages": [14],
		"disposal": "leave",
		"tags": ["우회"],
		"veil_comment": "막는 게 없습니다. ...이상할 만큼.",
		"veil_comment_warm": "막는 게 없어요. ...이상할 만큼요.",
		"entry_comment": "조용합니다. 지나치게 조용합니다. 보이는 걸 다 믿지는 마십시오.",
		"entry_comment_warm": "조용하네요. 너무 조용해요. 보이는 걸 다 믿진 말아요.",
		"stage_color": Color(0.13, 0.10, 0.16),
	},
	{
		"id": "route_lab",
		"name": "핵심부",
		"description": "서버실이 있는 시설 심장부. 목표 데이터와 그것을 지키는 것이 모인 곳.",
		"risk": 3,
		"reward_type": "record",
		"hidden": false,
		"unique": false,
		# 막3 SENTINEL 페이크 보스(s9=내부8) · 5막: 처치 후 §7 reveal → 막4로 계속(회수/처리선택은 막5로 이주).
		# 보스 스테이지라 배타 배치(다른 route가 이 인덱스에 겹치면 보스 우회 가능 · 소프트락/스킵 위험).
		"min_stage": 8, "max_stage": 8,
		"tags": ["전투", "드론", "밝은_환경"],
		"veil_comment": "핵심부입니다. 정면 돌파에 드론 상시 순찰. 그만큼 크게 법니다.",
		"veil_comment_warm": "핵심부예요. 정면 돌파에 드론이 상시 순찰해요. 그만큼 크게 벌어요.",
		"entry_comment": "핵심부 진입. 거리를 잘 잡으십시오.",
		"entry_comment_warm": "핵심부에 들어왔어요. 거리 잘 잡아요.",
		"entry_comment_replay": "핵심부예요. 그런데 이 안쪽, 묘하게 익숙합니다. 왜일까요. 거리 두고 움직이세요.",
		"stage_color": Color(0.22, 0.18, 0.18),
	},
	{
		"id": "route_blackout",
		"name": "블랙아웃 런",
		"description": "교신·전력이 차단된 봉쇄 구역. 안에선 VEIL도 닿지 않는다.",
		"risk": 3,
		"reward_type": "xp",
		"hidden": false,
		"unique": true,
		"challenge": true,
		"available_stages": [5],
		"guaranteed_in_stages": [5],
		"tags": ["도전", "어두운_환경"],
		"veil_comment": "[도전] 교신이 끊깁니다. 안에서는 저도 못 돕습니다. 한 번에 빠져나와야 합니다.",
		"veil_comment_warm": "[도전] 교신이 끊겨요. 안에선 저도 못 도와드려요. 한 번에 빠져나오셔야 해요.",
		"entry_comment": "여기서부터 교신이 끊깁니다. 30초 안에 빠져나오십시오.",
		"entry_comment_warm": "여기서부터 교신 끊겨요. 30초 안에 빠져나오세요.",
		"stage_color": Color(0.02, 0.02, 0.04),
	},
	{
		"id": "route_hidden",
		"name": "???",
		"description": "도면에 없는 한 층. VEIL조차 모른다고 한다.",
		"risk": 2,
		"reward_type": "recon",
		"hidden": true,
		"unique": true,
		# 막3 진입 전투 풀의 진실 분기 · 정적 아카이브(VEIL-1 reveal). 클리어 시 truth_seen,
		# 엔딩 직행 폐기 → 다음 스테이지로 진행(특수 '진실' 엔딩의 신호).
		# 5막: 막3 전투 2스테이지(s6-7=내부6-7). 진실 분기가 항상 선택 가능하도록 첫 전투 스테이지에 guaranteed.
		"min_stage": 6, "max_stage": 7,
		"guaranteed_in_stages": [6],
		"tags": ["우회", "정보"],
		"veil_comment": "...저도 모르겠습니다. 들어가시겠습니까?",
		"veil_comment_warm": "...저도 모르겠어요. 들어가실래요?",
		"entry_comment": "...뭐가 있는 거지.",
		"stage_color": Color(0.06, 0.06, 0.08),
	},
	{
		"id": "route_server_hall",
		"name": "서버 복도",
		"description": "핵심부로 이어지는 서버 랙 복도. 데이터가 흐르는 만큼 경비도 두텁다.",
		"risk": 3,
		"reward_type": "record",
		"hidden": false,
		"unique": false,
		# 막3 진입 전투(핵심부 직전). datacenter·control_corridor·??? 와 함께 막3 전투 풀(s6-7).
		"min_stage": 6, "max_stage": 7,
		"tags": ["전투", "드론", "원거리"],
		"veil_comment": "서버 복도입니다. 드론이 위, 저격이 랙 위. 랙을 엄폐로 쓰며 빠지십시오.",
		"veil_comment_warm": "서버 복도예요. 드론이 위, 저격이 랙 위에. 랙을 엄폐로 쓰면서 빠져요.",
		"entry_comment": "핵심부 직전입니다. 여기만 지나면... 조심하십시오.",
		"entry_comment_warm": "핵심부 직전이에요. 여기만 지나면... 조심해요.",
		"stage_color": Color(0.16, 0.18, 0.22),
	},
	{
		"id": "route_parking_lot",
		"name": "지하 주차장",
		"elev": "under",
		"description": "외곽과 시설을 잇는 지하 주차 구역. 차단 셔터가 주기적으로 통로를 막는다.",
		"risk": 1,
		"reward_type": "recon",
		"hidden": false,
		"unique": false,
		# 막1 침투 변형 · s1~2(첫 맵 s0엔 안 둠: 방패병이 첫 맵엔 불합리, 사용자 보고 2026-06-25).
		"min_stage": 1, "max_stage": 2,
		"tags": ["우회", "근접전", "어두운_환경"],
		"veil_comment": "지하 주차장입니다. 셔터가 열릴 때 지나가십시오. 램프가 붉으면 곧 닫힙니다.",
		# "한 층 아래" = 하강 진입 뉘앙스(C안, 2026-08-25).
		"entry_comment": "한 층 아래 주차 구역입니다. 차 사이로 빠지십시오. 전부 상대할 필요는 없습니다.",
		"stage_color": Color(0.12, 0.12, 0.15),
	},
	{
		"id": "route_substation",
		"name": "변전소",
		"description": "시설 전력을 받는 옥외 변전 설비. 노출 전선이 주기적으로 방전하고, 변압기 위로 저격선이 깔린다.",
		"risk": 3,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		# 막2 고조(난이도 램프) · risk3(저격+드론 동시). 막2 첫 stage(s3) 제외해 문턱 직후 스파이크 제거.
		# act_identity.md §4: s3 도입(r2 기계 입문) / s4 전개 / s5 고조. s4~5 전개·고조 구간에 배치.
		"min_stage": 4, "max_stage": 5,
		"tags": ["원거리", "드론", "노출", "전투"],
		"veil_comment": "변전소입니다. 바닥 방전은 발판 위로 피하십시오. 변압기 위 저격, 머리 위 드론.",
		"veil_comment_warm": "변전소예요. 바닥 방전은 발판 위로 피해요. 변압기 위 저격, 머리 위 드론.",
		# 재작성(2026-08-22 사용자 "변압기가 어딨고 왜 뒤에 붙어야 하는데") · 이 맵에 "뒤에 붙는"
		# 엄폐 문법은 없다. 실제 문법 = 바닥 방전은 발판 위로, 단 위에는 저격이 있다(체류 비용).
		# EN: "Substation. The floor wires discharge every so often - get up on a deck when they do.
		#      Snipers hold the high spots, so don't stay up long."
		# ("저격이 있으니" 행위명사 주어 = 번역투 지적 · 무맥락 검수 1차, 2026-08-23)
		"entry_comment": "변전 설비입니다. 바닥 전선이 한 번씩 방전합니다. 방전이 오면 발판 위로. 위에는 저격수가 있으니 오래 서 있지 마십시오.",
		"entry_comment_warm": "변전 설비예요. 바닥 전선이 한 번씩 방전해요. 방전이 오면 발판 위로. 위에는 저격수가 있으니 오래 서 있진 말고요.",
		"stage_color": Color(0.16, 0.15, 0.10),
	},
	{
		"id": "route_testing_grounds",
		"name": "실험 구역",
		"description": "봉인된 실험 베이가 늘어선 구역. 무엇을 시험했는지 관측창마다 지워져 있다.",
		"risk": 2,
		"reward_type": "record",
		"hidden": false,
		"unique": false,
		# 막2 잠입 혼합 전투 · 시설 내부 단계(s3~5) 풀.
		"min_stage": 3, "max_stage": 5,
		"tags": ["근접전", "함정", "전투"],
		"veil_comment": "실험 구역입니다. 자폭병과 방패병, 천장 포탑까지. 화력이 있으면 수월합니다.",
		"veil_comment_warm": "실험 구역이에요. 자폭병이랑 방패병, 천장 포탑까지. 화력 있으면 편해요.",
		"entry_comment": "실험 베이입니다. 위에서 쏘는 포탑을 조심하십시오.",
		"entry_comment_warm": "실험 베이예요. 위에서 쏘는 포탑 조심해요.",
		"stage_color": Color(0.13, 0.16, 0.15),
	},
	{
		"id": "route_demolition_zone",
		"name": "철거 구역",
		"elev": "ground",
		"description": "절반쯤 헐린 외곽 건물군. 위에서 잔해가 떨어지고, 무너진 벽을 지나면 파쇄 마당이 이어진다.",
		"risk": 2,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		"min_stage": 1, "max_stage": 2,
		"tags": ["근접전", "어두운_환경", "전투"],
		"veil_comment": "철거 구역입니다. 위에서 잔해가 떨어집니다. 바닥 그림자를 보십시오.",
		"entry_comment": "무너진 건물입니다. 머리 위를 조심하고, 잔해 뒤에 붙으십시오.",
		"stage_color": Color(0.14, 0.12, 0.11),
	},
	{
		"id": "route_pump_station",
		"name": "배수 펌프장",
		"elev": "ground",
		"description": "외곽 빗물을 퍼내는 펌프장. 방류구가 주기적으로 물을 뿜고, 파이프 위에서 조준선이 내려온다.",
		"risk": 2,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		"min_stage": 1, "max_stage": 2,
		"tags": ["원거리", "노출", "전투"],
		# EN: "Pump station. The outlets discharge on a cycle, and snipers watch from the pipes.
		#      Don't linger on low ground."
		"veil_comment": "펌프장입니다. 방류구가 주기적으로 물을 뿜고, 파이프 위에서 저격이 내려다봅니다. 낮은 곳에 오래 서지 마십시오.",
		# EN: "The pumps are still running. When the outlets blow, get out of the water line."
		"entry_comment": "펌프가 아직 돌고 있습니다. 방류구가 물을 뿜을 때는 물길 밖으로 비키십시오.",
		"stage_color": Color(0.10, 0.14, 0.16),
	},
	{
		"id": "route_relay_station",
		"name": "통신 중계소",
		"description": "시설 교신을 중계하는 안테나 구역. 중계기 위 저격과 머리 위 드론이 겹친다.",
		"risk": 3,
		"reward_type": "record",
		"hidden": false,
		"unique": false,
		# 막4 램프 s10 전개~막5 s12(act_identity §6): 저격·드론·재머 복합 · s9 도입 금지.
		"min_stage": 10, "max_stage": 12,
		"tags": ["원거리", "드론", "노출", "전투"],
		"veil_comment": "중계소입니다. 저격과 드론이 동시에 옵니다. 엄폐는 짧게, 빠르게.",
		"veil_comment_warm": "중계소예요. 저격이랑 드론이 동시에 와요. 엄폐 짧게, 빠르게.",
		"entry_comment": "통신 중계기 구역입니다. 위에서도 아래에서도 쏩니다. 멈추지 마십시오.",
		"entry_comment_warm": "통신 중계기예요. 위에서도 아래에서도 쏴요. 멈추지 말아요.",
		"stage_color": Color(0.12, 0.16, 0.18),
	},
	{
		"id": "route_warehouse",
		"name": "물류 창고",
		"description": "시설 보급을 쌓아둔 적재 창고. 컨베이어가 아직 돌아 바닥이 흐른다.",
		"risk": 2,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		"min_stage": 3, "max_stage": 5,
		"tags": ["근접전", "전투"],
		"veil_comment": "물류 창고입니다. 바닥 컨베이어가 밉니다. 거스르는 구간에 자폭병과 방패병.",
		"veil_comment_warm": "물류 창고예요. 바닥 컨베이어가 밀어요. 거스르는 구간에 자폭병이랑 방패병.",
		"entry_comment": "적재 창고입니다. 컨테이너를 엄폐로. 근접을 조심하십시오.",
		"entry_comment_warm": "적재 창고예요. 컨테이너를 엄폐로. 근접 조심해요.",
		"stage_color": Color(0.15, 0.14, 0.12),
	},
	{
		"id": "route_checkpoint",
		"name": "보안 검문소",
		"description": "내부 구역을 나누는 보안 검문선. 검문 레이저를 건드리면 포탑이 깨어난다.",
		"risk": 2,
		"reward_type": "recon",
		"hidden": false,
		"unique": false,
		"min_stage": 3, "max_stage": 5,
		"tags": ["함정", "원거리", "전투"],
		"veil_comment": "검문소입니다. 바닥 레이저를 건드리면 포탑이 일제히 쏩니다. 타이밍을 보십시오.",
		"veil_comment_warm": "검문소예요. 바닥 레이저 건드리면 포탑이 일제히 쏴요. 타이밍 봐요.",
		"entry_comment": "보안 검문선입니다. 레이저를 밟으면 앞에서 사격이 옵니다. 끊어 가십시오.",
		"entry_comment_warm": "보안 검문선이에요. 레이저 밟으면 앞에서 쏴와요. 끊어 가요.",
		"stage_color": Color(0.16, 0.14, 0.16),
	},
	{
		"id": "route_control_corridor",
		"name": "통제실 복도",
		"description": "핵심부 통제실로 이어지는 복도. 데이터가 흐르는 만큼 감시도 두텁다.",
		"risk": 3,
		"reward_type": "recon",
		"hidden": false,
		"unique": false,
		# 막3 전투 풀(s6-7) · datacenter/server_hall과 같은 통과형. ???(guaranteed)와 함께 선택.
		"min_stage": 6, "max_stage": 7,
		"tags": ["전투", "드론", "원거리"],
		"veil_comment": "통제실 복도입니다. 드론과 저격이 동시에. 핵심부가 코앞입니다.",
		"veil_comment_warm": "통제실 복도예요. 드론·저격 동시에. 핵심부가 코앞이에요.",
		"entry_comment": "통제실 직전입니다. 사방에서 쏩니다. 엄폐를 쓰며 빠지십시오.",
		"entry_comment_warm": "통제실 직전이에요. 사방에서 쏴요. 엄폐 쓰면서 빠져요.",
		"stage_color": Color(0.15, 0.17, 0.21),
	},
	{
		"id": "route_condenser",
		"name": "응축기 구역",
		"description": "냉각수를 응축하는 구역. 천장 배관에서 뜨거운 응축수가 방울져 떨어진다.",
		"risk": 2,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		"min_stage": 3, "max_stage": 5,
		"tags": ["드론", "함정", "전투"],
		"veil_comment": "응축기 구역입니다. 천장 배관에서 끓는 냉각수가 맺혀 떨어집니다. 드론은 위에 떠 있습니다.",
		"veil_comment_warm": "응축기 구역이에요. 천장 배관에서 끓는 냉각수가 맺혀 떨어져요. 드론은 위에 떠 있어요.",
		"entry_comment": "응축 배관 구역입니다. 떨어지는 건 끓는 물입니다. 방울이 맺히는 걸 보고 피하십시오.",
		"entry_comment_warm": "응축 배관 구역이에요. 떨어지는 건 끓는 물이에요. 방울이 맺히는 걸 보고 피해요.",
		"stage_color": Color(0.10, 0.15, 0.18),
	},
	{
		"id": "route_perimeter",
		"name": "외곽 순찰로",
		"elev": "ground",
		"description": "외벽을 따라 도는 순찰 동선. 경계등이 지면을 훑는다.",
		"risk": 2,
		"reward_type": "recon",
		"hidden": false,
		"unique": false,
		"min_stage": 1, "max_stage": 2,
		"tags": ["우회", "이동"],
		"veil_comment": "순찰로입니다. 전투는 가볍지만, 경계등에 걸리면 시끄러워집니다.",
		"entry_comment": "외곽 순찰선입니다. 전부 상대할 필요 없습니다. 멈추지 말고 가십시오.",
		"stage_color": Color(0.11, 0.13, 0.13),
	},
	{
		"id": "route_gauntlet",
		"name": "함정 통로",
		"description": "보안 포탑이 빼곡한 좁은 통로. 적보다 함정이 길을 막는다.",
		"risk": 2,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		"min_stage": 3, "max_stage": 5,
		"tags": ["함정", "이동"],
		"veil_comment": "함정 통로입니다. 포탑이 많습니다. 타이밍과 동선이 전부입니다.",
		"veil_comment_warm": "함정 통로예요. 포탑이 많아요. 타이밍이랑 동선이 전부예요.",
		"entry_comment": "포탑 통로입니다. 위아래로 쏩니다. 레이저도 주의. 끊어 가십시오.",
		"entry_comment_warm": "포탑 통로예요. 위아래로 쏴요. 레이저도 조심. 끊어 가요.",
		"stage_color": Color(0.14, 0.13, 0.10),
	},
	{
		"id": "route_freight_lift",
		"name": "화물 리프트",
		"description": "시설 정비 화물구역. 스파이크 구덩이 위를 왕복하는 화물 리프트를 타이밍 맞춰 건넌다.",
		"risk": 2,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		# 막4 램프 s9-10 도입(act_identity §6): 전투 최소 타이밍 학습 · 막4의 순한 문.
		"min_stage": 9, "max_stage": 10,
		"tags": ["이동", "함정"],
		"veil_comment": "화물 리프트입니다. 발판이 오갑니다. 가장자리에서 잠깐 멈출 때 올라타십시오. 서두를 것 없습니다.",
		"veil_comment_warm": "화물 리프트예요. 발판이 오가죠. 가장자리에서 잠깐 멈출 때 올라타세요. 서두를 것 없습니다.",
		"entry_comment": "리프트가 왕복합니다. 끝에서 멈출 때 타십시오. 밑은 스파이크. 타이밍이 전부입니다.",
		"entry_comment_warm": "리프트가 왕복합니다. 끝에서 멈출 때 타세요. 밑은 스파이크. 타이밍이 전부입니다.",
		"stage_color": Color(0.15, 0.13, 0.09),
	},
	{
		"id": "route_car_cover",
		"name": "차량 엄폐 통로",
		"description": "버려진 정비 차량이 늘어선 사격 통로. 저격에 노출된 개활지라, 차량 뒤에 붙어 전진해야 한다.",
		"risk": 3,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		# 막4 램프 s10 전개~막5 s12(act_identity §6): 저격 레이스 · 재머 금지 맵(블라인드 unfair).
		"min_stage": 10, "max_stage": 12,
		"tags": ["원거리", "이동", "전투"],
		"veil_comment": "차량 뒤에 붙어 가십시오. 저격에 걸리는 건 넘어갈 때뿐입니다. 엄폐는 맞을수록 부서집니다. 한자리에 오래 머물지 마십시오.",
		"veil_comment_warm": "차량 뒤에 붙어서 가세요. 저격에 걸리는 건 넘어갈 때뿐입니다. 엄폐는 맞을수록 부서지니, 한자리에 오래 머물지 마시고요.",
		"entry_comment": "정비 차량이 엄폐입니다. 뒤에 붙으면 저격이 못 봅니다. 노출은 넘을 때뿐. 다만 차량은 영원하지 않습니다.",
		"entry_comment_warm": "정비 차량이 엄폐입니다. 뒤에 붙으면 저격이 못 보죠. 노출은 넘을 때뿐. 다만 차량은 영원하지 않습니다.",
		"stage_color": Color(0.14, 0.13, 0.15),
	},
	{
		"id": "route_collapse",
		"name": "붕괴 갱도",
		"description": "구조가 무너지기 시작한 정비 갱도. 뒤에서 붕괴가 쫓아온다. 멈추면 삼켜진다.",
		"risk": 3,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		# 막4 램프 s11 고조~막5 s12(act_identity §6): 추격 절정 · 막4 "추적"의 시그니처. 재머 금지.
		"min_stage": 11, "max_stage": 12,
		"tags": ["이동", "노출"],
		"veil_comment": "뒤가 무너집니다. 멈추지 마십시오. 잔해는 넘고, 계속 앞으로.",
		"veil_comment_warm": "뒤가 무너져요. 멈추지 말아요. 잔해는 넘고, 계속 앞으로.",
		"entry_comment": "구조가 버티지 못합니다. 붕괴가 따라옵니다. 멈추면 삼켜집니다. 앞으로만.",
		"entry_comment_warm": "구조가 버티질 못해요. 붕괴가 따라와요. 멈추면 삼켜져요. 앞으로만.",
		"stage_color": Color(0.10, 0.08, 0.07),
	},
	{
		"id": "route_core_defense",
		"name": "반응로 제어실",
		"description": "시설 중앙 반응로 제어실. 밀려드는 적으로부터 코어를 지켜야 한다. 자리를 비우면 코어가 무너진다.",
		"risk": 3,
		"reward_type": "record",
		"hidden": false,
		"unique": false,
		# 막5 전투 s12 전용(act_identity §7): "코어 방어" 직후 s13 "코어 회수" · 서사 랠리.
		"min_stage": 12, "max_stage": 12,
		"tags": ["전투", "원거리"],
		"veil_comment": "중앙 코어를 지킵니다. 적이 코어 곁에 오래 머물면 코어가 깎입니다. 넘어오는 걸 밀어내고 자리를 지키십시오.",
		"veil_comment_warm": "중앙 코어를 지켜요. 적이 코어 곁에 오래 머물면 코어가 깎여요. 넘어오는 걸 밀어내고 자리를 지켜요.",
		"entry_comment": "코어 방어전입니다. 적이 코어 구역에 들면 코어가 버티지 못합니다. 몰려드는 걸 막고 전부 정리하면 끝납니다.",
		"entry_comment_warm": "코어 방어예요. 적이 코어 구역에 들어오면 코어가 버티질 못해요. 몰려드는 걸 막고 다 정리하면 끝나요.",
		"stage_color": Color(0.09, 0.11, 0.13),
	},
	{
		"id": "route_scanner_sweep",
		"name": "감시 회랑",
		"description": "보안 스캔 빔이 통로를 주기적으로 훑는 감시 회랑. 빔이 지날 때 대피 칸에 숨지 않으면 노출된다.",
		"risk": 3,
		"reward_type": "recon",
		"hidden": false,
		"unique": false,
		# 막4 램프 s9-11(act_identity §6): 리듬 스텔스 · risk3이나 적 2뿐(전투 스파이크 아님)이라 s9 허용.
		"min_stage": 9, "max_stage": 11,
		"tags": ["이동", "노출"],
		# EN: "Scans sweep the corridor. Beam comes, get to a recess. Beam passes, move up. Find the rhythm."
		"veil_comment": "스캔이 통로를 훑습니다. 빔이 오면 대피 칸으로. 지나가면 다음 칸으로. 리듬을 타십시오.",
		"veil_comment_warm": "스캔이 통로를 훑어요. 빔이 오면 대피 칸으로. 지나가면 다음 칸으로. 리듬을 타요.",
		# EN: "The beam sweeps left to right. When it comes, get into a marked recess. When it passes,
		#      run for the next one. Freeze in the open and you're exposed."
		"entry_comment": "감시 빔이 통로를 훑습니다. 빔이 오면 파란 띠가 칠해진 대피 칸에 숨으십시오. 지나가면 다음 칸까지 달립니다. 칸 밖에서 멈추면 그대로 노출입니다.",
		"entry_comment_warm": "감시 빔이 통로를 훑어요. 빔이 오면 파란 띠가 칠해진 대피 칸에 숨으세요. 지나가면 다음 칸까지 달려요. 칸 밖에서 멈추면 그대로 노출이에요.",
		"stage_color": Color(0.12, 0.09, 0.10),
	},
	{
		"id": "route_holdout",
		"name": "저지선",
		"description": "발각된 통제 구역. 부서지는 바리케이드 뒤에서 밀려오는 경비를 저지한다. 바리케이드는 영원하지 않다.",
		"risk": 3,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		# 막4 램프 s11 고조~막5 s12(act_identity §6): 발각 농성 + FINAL WAVE 재머.
		"min_stage": 11, "max_stage": 12,
		"tags": ["전투", "근접"],
		"veil_comment": "바리케이드 뒤에서 버팁니다. 몸을 내밀어 쏘고, 다시 숨으십시오. 엄폐는 계속 갉히니 부서지기 전에 정리해야 합니다.",
		"veil_comment_warm": "바리케이드 뒤에서 버팁니다. 몸을 내밀어 쏘고, 다시 숨으세요. 엄폐는 계속 갉아먹히니 부서지기 전에 정리해야 합니다.",
		"entry_comment": "저지선입니다. 적이 밀려옵니다. 엄폐 뒤에서 쏘고 숨으십시오. 포탑이 엄폐를 갉으니 오래는 못 버팁니다.",
		"entry_comment_warm": "저지선입니다. 적이 밀려옵니다. 엄폐 뒤에서 쏘고 숨으세요. 포탑이 엄폐를 갉아먹으니 오래는 못 버팁니다.",
		"stage_color": Color(0.13, 0.10, 0.09),
	},
	{
		"id": "route_core_recovery",
		"name": "핵심 회수",
		"description": "시설 심장부. 목표 드라이브가 실제로 있는 곳. 회수하고 처리를 정한다.",
		"risk": 3,
		"reward_type": "xp",
		"hidden": false,
		"unique": false,
		# 막5 회수 스테이지(s14=내부13) · 14-1 라이벌 보스전(P1 지휘→P2 빙의, MapData rival_boss).
		# 클리어 후 회수 문서 + 처리 선택(B2, 막3서 이주 · 이후 14-2 터널로 이주 예정).
		# 배타 배치(다른 route가 겹치면 엔드게임 우회 가능).
		"min_stage": 13, "max_stage": 13,
		"tags": ["전투"],
		"veil_comment": "심장부입니다. 안의 신호가 전부 이상합니다.",
		"entry_comment": "회수 대상 전방. ...누가 먼저 와 있습니다.",
		"stage_color": Color(0.20, 0.16, 0.20),
	},
]

# 스토리 모드 · 5스테이지 고정 스케줄. 드론·도전·??? 맵 모두 빼고 핵심 동선만.
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
	# 고도 인접 전이 필터(2026-08-25 A안) · 직전 맵이 옥상/탑(high)이면 지하(under) 후보 제외,
	# 지하였으면 high 제외. "옥상 직후 폐지하철" 같은 공간 비약 차단(사용자 지적). 막1 전용
	# (elev는 막1 맵에만 달려 있고, 막2+ 내부 맵은 "" = 무제약).
	var prev_elev: String = _route_elev(GameState.current_route_id)
	var guaranteed: Array = []
	var others: Array = []
	var elev_cut: Array = []
	for r in ALL_ROUTES:
		var route: Dictionary = r
		var rid: String = str(route.get("id", ""))
		if rid in visited:
			continue
		if not _stage_in_range(route, stage_index):
			continue
		if _elev_jump(prev_elev, _route_elev_of(route)):
			elev_cut.append(route)
			continue
		# 스토리 전용 원형(비상 탈출로)은 본편 풀에서 제외 · 처리별 4종이 대체.
		if bool(route.get("story_only", false)):
			continue
		# 처리별 탈출 · disposal 키가 있으면 이번 런의 처리 선택과 일치할 때만(§3.2).
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
	# 고도 필터로 후보가 모자라면 걸러낸 후보로 보충 · 선택지 수 보장이 개연성보다 우선.
	if pool.size() < pick_count:
		elev_cut.shuffle()
		for r in elev_cut:
			pool.append(r)
			if pool.size() >= pick_count:
				break
	return pool

static func _get_story_route_pool(stage_index: int) -> Array:
	var ids: Array = STORY_SCHEDULE.get(stage_index, [])
	# 스토리 고정 스케줄에도 고도 전이 필터 적용 · 옥상(s0) 뒤 지하철(s1) 같은 비약 조합은
	# 그 판에서 숨긴다. 전부 걸러지면 필터 해제(선택지 0 방지).
	var prev_elev: String = _route_elev(GameState.current_route_id)
	var out: Array = []
	var cut: Array = []
	for rid in ids:
		for r in ALL_ROUTES:
			var route: Dictionary = r
			if route.get("id", "") == rid:
				if _elev_jump(prev_elev, _route_elev_of(route)):
					cut.append(_apply_story_overrides(route))
				else:
					out.append(_apply_story_overrides(route))
				break
	return out if not out.is_empty() else cut

# ─── 고도 밴드(elev) · 막1 공간 개연성 필터 ───
static func _route_elev_of(route: Dictionary) -> String:
	return str(route.get("elev", ""))

static func _route_elev(route_id: String) -> String:
	for r in ALL_ROUTES:
		var route: Dictionary = r
		if str(route.get("id", "")) == route_id:
			return _route_elev_of(route)
	return ""

# 옥상/탑(high) ↔ 지하(under) 직행만 비약으로 본다. 지상(ground)·미지정("")은 어느 쪽과도 인접 가능.
static func _elev_jump(prev: String, next: String) -> bool:
	return (prev == "high" and next == "under") or (prev == "under" and next == "high")

# 스토리 모드에서 명칭/설명/멘트가 일반 모드와 의미가 다른 경우 override.
# 사용자 피드백: "비상 탈출로"가 보스 후 stage라 임무 시작 단계에서 어색했음.
const STORY_OVERRIDES: Dictionary = {
	"route_escape": {
		"name": "최종 탈출",
		"description": "임무를 마치고 시설 밖으로 빠져나가는 길. 마지막 한 걸음.",
		"veil_comment": "조용히 빠집니다. 거의 다 왔습니다.",
		"veil_comment_warm": "조용히 빠져요. 거의 다 왔어요.",
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

# ─── 보상 축 개편(2026-08-19 사용자 확정: "양 1~3" → "종류") ─────────────────────
# 문제: 종전엔 reward가 risk와 사실상 1:1 상관(보상<위험 조합이 1개뿐, 3/3이 42%)이라
# 두 축이 정보를 못 줬고, "보상 같은데 위험만 높은" 열세 카드 추천 사고까지 났다.
# 새 규칙:
#   · 클리어 경험치 = 위험도 그대로(r1=1 … r3=3). 위험할수록 항상 더 번다 · 열세 카드가
#     구조적으로 사라진다(위험 증가에 보상이 자동 동행).
#   · reward_type = 부가 효과 종류. "xp"(경험치 +2) / "record"(체력 1칸 회복, 가득하면 +2 XP ·
#     2026-08-23 통일: 종전 "기록 회복"의 HP판. id는 route id 함정과 동형이라 유지, 라벨·효과만) /
#     "recon"(다음 구간 숨은 요소 표시 · 재정의 2026-08-21) / ""(탈출 종착 = 없음).
# 지급은 GameState.on_stage_clear, 표시는 RouteMap(카드 한 줄 + 우측 패널).
const REWARD_TYPE_LABELS: Dictionary = {
	"xp": "경험치",
	"record": "회복",
	"recon": "정찰",
	"": "-",
}

static func reward_type_label(t: String) -> String:
	return str(REWARD_TYPE_LABELS.get(t, "-"))

# VEIL 추천. 플레이어의 실제 수행(GameState.competence_tier)과 현재 필요(체력 소모 여부)에
# 반응해 맵을 고르고, 사유는 짧은 대사(REC_REASON)로 돌려준다. 우선순위:
#   ① first(첫 스테이지) / struggling(고전) → 안전(가장 낮은 risk). 상태가 나쁘면 종류보다 생존.
#   ② 체력이 깎인 상태 + 풀에 record(회복) 루트 존재 → 그 루트(동종 여럿이면 저위험).
#   ③ skilled(능숙) → 최고 risk(= 최대 클리어 경험치. 위험이 곧 보상이라 손해 카드 없음).
#   ④ steady(무난) → 중간 risk(2 선호, 없으면 저위험).
# hidden / challenge 루트는 항상 제외. 사유 대사는 종결어미 단조 회피(어투 규칙).
# 어투 밴드 스윕(2026-08-21): 기본 = 중립 보고체, warm 밴드는 REC_REASON_WARM(부드러운 변형).
# "first"는 데이터 없는 첫 스테이지 전용이라 항상 cold · warm 풀 불필요.
const REC_REASON: Dictionary = {
	"first": [
		"처음이니 무난한 쪽을 권합니다.",
		"첫 길은 이쪽이 수월합니다.",
		"초반에는 이쪽입니다.",
	],
	"struggling": [
		"방금 고전하셨습니다. 이 중에서는 이쪽이 낫습니다.",
		"부담이 적은 쪽을 골랐습니다.",
		"이번에는 덜 험한 길입니다.",
	],
	"record": [
		"체력이 깎였습니다. 이 길 끝에서 한 칸 채울 수 있습니다.",
		"다음 교전에 대비해 둡니다. 체력을 채울 수 있는 쪽입니다.",
		"이쪽을 지나면 체력이 한 칸 채워집니다.",
	],
	"skilled": [
		"잘 버티고 계십니다. 험한 길일수록 얻는 것도 많습니다.",
		"솜씨가 좋으시군요. 거친 쪽이 남는 장사입니다.",
		"욕심낼 만합니다. 위험한 만큼 돌아오는 게 큽니다.",
	],
	"steady": [
		"이쪽이 좋아 보입니다.",
		"여기가 적당합니다.",
		"이 길을 권합니다.",
	],
}
const REC_REASON_WARM: Dictionary = {
	"struggling": [
		"방금 고전했죠. 이 중엔 이쪽이 나아요.",
		"좀 힘들었을 거예요. 부담이 적은 쪽을 골랐어요.",
		"이번엔 덜 험한 길을 골랐어요.",
	],
	"record": [
		"체력이 깎였죠. 이 길 끝에서 한 칸 채울 수 있어요.",
		"다음 교전에 대비해 두죠. 체력을 채울 수 있는 쪽입니다.",
		"이쪽을 지나면 체력이 한 칸 채워져요.",
	],
	"skilled": [
		"잘 버티고 있죠. 험한 길일수록 배우는 것도 많습니다.",
		"솜씨가 좋네요. 거친 쪽이 남는 장사예요.",
		"욕심내 볼 만해요. 위험한 만큼 돌아오는 게 큽니다.",
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
	# 후보가 하나뿐인 배타 스테이지(lab s8 · core_recovery s13 · escape s14)엔 고를 게 없다 ·
	# 실력 기반 사유가 강제 진행 맵에 붙으면 모순(사용자 보고 2026-08-12). reason을 비우면
	# RouteMap이 ★추천 대신 그 맵 고유 veil_comment를 보여준다.
	if candidates.size() == 1:
		return {"id": candidates[0].get("id", ""), "reason": ""}
	# 모드 · 데이터 없으면 first(첫 스테이지), 아니면 실력 tier.
	var mode: String = GameState.competence_tier()
	if GameState.recent_stage_hits.is_empty():
		mode = "first"
	# ① 안전 우선 · 고전 중이거나 첫 판이면 종류를 따지지 않고 가장 수월한 길.
	if mode == "first" or mode == "struggling":
		return {"id": _pick_by_risk(candidates, 1).get("id", ""), "reason": _pick_rec_reason(mode)}
	# ② 필요 기반 · 체력이 깎였고 채울 길이 있으면 그쪽. VEIL이 플레이어 상태를 읽고
	#    권하는 그림(관측 프레임과 정합).
	if GameState.player_hp < GameState.effective_max_hp():
		var rec_routes: Array = []
		for c in candidates:
			if str((c as Dictionary).get("reward_type", "")) == "record":
				rec_routes.append(c)
		if not rec_routes.is_empty():
			return {"id": _pick_by_risk(rec_routes, 1).get("id", ""), "reason": _pick_rec_reason("record")}
	# ③ 능숙 · 최고 위험 = 최대 클리어 경험치. 동률이면 xp 종류 우선(부가까지 경험치).
	if mode == "skilled":
		var best: Dictionary = candidates[0]
		var best_s: float = -INF
		for c in candidates:
			var route: Dictionary = c
			var s: float = float(route.get("risk", 0)) * 10.0
			if str(route.get("reward_type", "")) == "xp":
				s += 1.0
			if s > best_s:
				best_s = s
				best = route
		return {"id": best.get("id", ""), "reason": _pick_rec_reason("skilled")}
	# ④ 무난 · 중간 위험(2) 선호, 없으면 낮은 쪽.
	var mid: Array = []
	for c in candidates:
		if int((c as Dictionary).get("risk", 0)) == 2:
			mid.append(c)
	var pool2: Array = mid if not mid.is_empty() else candidates
	return {"id": _pick_by_risk(pool2, 1).get("id", ""), "reason": _pick_rec_reason("steady")}

# risk 정렬 픽 · dir 1 = 최저 위험(동률이면 풀 순서 = 셔플 유지).
static func _pick_by_risk(candidates: Array, dir: int) -> Dictionary:
	var best: Dictionary = candidates[0]
	for c in candidates:
		var route: Dictionary = c
		if dir * int(route.get("risk", 0)) < dir * int(best.get("risk", 0)):
			best = route
	return best

static func _pick_rec_reason(mode: String) -> String:
	# warm 밴드면 부드러운 변형 풀 우선(없는 모드는 중립 폴백) · 어투 밴드 스윕.
	var arr: Array = []
	if GameState.veil_register_band() == "warm":
		arr = REC_REASON_WARM.get(mode, [])
	if arr.is_empty():
		arr = REC_REASON.get(mode, [])
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
