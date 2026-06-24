class_name RouteData
extends RefCounted

# 11개 맵 — Dead Cells 스타일로 stage_index 별 후보 풀이 다름.
#   min_stage / max_stage : 등장 가능 stage 범위 (양 끝 포함)
#   available_stages       : 명시적 리스트 (있으면 우선, 없으면 min/max 사용)
#   guaranteed_in_stages   : 해당 stage 풀 빌드 시 항상 포함되는 맵 (셔플 전 fix-slot)
#   unique                 : true면 한 번 선택 후 다시 등장 안 함 (현재는 route_history 필터로 보편 규칙)
#   hidden                 : VEIL 추천 대상에서 제외 (??? 전용)

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
		# 지상(rooftops) 직후 깊은 지하로 가는 게 어색해 stage 2 이후로 한정.
		"min_stage": 2, "max_stage": 3,
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
		# 외부→시설 진입 brigde — stage 1~3에 등장해 외벽 단계와 내부 단계를 잇는다.
		"min_stage": 1, "max_stage": 3,
		"tags": ["근접전", "함정", "전투"],
		"veil_comment": "옛 지하철이에요. 좁고 어두워요. 대시 써서 함정 넘어가세요.",
		"entry_comment": "지하철 통로예요. 좁아요. 한 번에 멀리 가요.",
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
		# 드론 첫 등장 맵 — 사용자 피드백상 후반에 등장하는 게 더 자연스러워 stage 3~4로 이동.
		"min_stage": 3, "max_stage": 4,
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
		# stage 1부터 등장 가능 — 외벽 옥상 직후 감시탑(둘 다 노출+높이)이 자연스럽게 이어짐.
		"min_stage": 1, "max_stage": 4,
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
		"min_stage": 3, "max_stage": 4,
		# 격리 병동은 ??? 맵 복선 트리거가 있어 Stage 3~4 풀에 항상 포함되어야 함.
		"guaranteed_in_stages": [3, 4],
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
		"min_stage": 4, "max_stage": 5,
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
		# "마지막에 빠져나가는 길" — 일반 모드에선 최종 스테이지(6)에만 등장(중간에 미리 "탈출"하는
		# 게 서사상 어색해 사용자 피드백으로 제한). 선택 시 클리어=엔딩(보스 없이 빠져나간 결말).
		"min_stage": 6, "max_stage": 6,
		"available_stages": [6],
		"tags": ["우회", "은폐"],
		"veil_comment": "비상 탈출로예요. 빨리 빠지면 그만큼 안전해요.",
		"entry_comment": "조용한 길이에요. 멈추지 말고 빠지면 돼요.",
		"entry_comment_replay": "조용한 길이에요. 여기, 낯이 익죠. 이번엔 뭐가 다를까요. 멈추지 말고 빠지세요.",
		"stage_color": Color(0.10, 0.12, 0.14),
	},
	{
		"id": "route_lab",
		"name": "핵심부",
		"description": "서버실이 있는 시설 심장부. 목표 데이터와 그것을 지키는 것이 모인 곳.",
		"risk": 3,
		"reward": 3,
		"hidden": false,
		"unique": false,
		"min_stage": 5, "max_stage": 6,
		"tags": ["전투", "드론", "밝은_환경"],
		"veil_comment": "핵심부예요. 정면 돌파에 드론이 상시 순찰해요. 그만큼 크게 벌어요.",
		"entry_comment": "핵심부에 들어왔어요. 거리 잘 잡아요.",
		"entry_comment_replay": "핵심부예요. 이 안쪽이 묘하게 익숙해요. 왜일까요. 거리 두고 움직이세요.",
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
		"available_stages": [4],
		"guaranteed_in_stages": [4],
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
		"min_stage": 5, "max_stage": 6,
		"tags": ["우회", "정보"],
		"veil_comment": "...저도 모르겠어요. 들어가실래요?",
		"entry_comment": "...뭐가 있는 거지.",
		"stage_color": Color(0.06, 0.06, 0.08),
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
