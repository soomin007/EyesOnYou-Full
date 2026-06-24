class_name SkillTreeData
extends RefCounted

# 스킬 트리 — 3계열 × 여러 라인 × 3티어.
# 플레이어가 한 라인에 보유한 티어는 GameState.skills[line_id]에 정수로 저장 (0=미보유, 1/2/3=보유 티어).
# 같은 라인의 다음 티어는 이전 티어 보유 시에만 후보 등장.

const FAMILY_COMBAT: String = "전투"
const FAMILY_MOBILITY: String = "이동"
const FAMILY_SURVIVAL: String = "생존"

# 계열 색 — 단일 소스. 스킬 트리 텍스트·아이콘·카드가 모두 이 값을 참조해 한 계열은 한 색으로 보인다.
const FAMILY_COLORS: Dictionary = {
	FAMILY_COMBAT: Color(0.97, 0.58, 0.48),
	FAMILY_MOBILITY: Color(0.55, 0.82, 0.97),
	FAMILY_SURVIVAL: Color(0.58, 0.92, 0.68),
}

const TIER_MAX: int = 3

# 각 라인은 id + family + tiers(1~3 효과 정의).
# tiers[0] = T1, tiers[1] = T2, tiers[2] = T3.
const LINES: Array = [
	# 전투 ────────────────────────────────────────────
	{
		"id": "fire_boost", "family": FAMILY_COMBAT,
		"tiers": [
			{"name": "사격 강화",   "desc": "사격 데미지 +1",                  "active": false},
			{"name": "속사",       "desc": "연사 속도 +40%, 사격 후 잠깐 이동 가속", "active": false},
			{"name": "관통",       "desc": "총알 1체 추가 관통",               "active": false},
		],
	},
	{
		"id": "multishot", "family": FAMILY_COMBAT,
		"tiers": [
			{"name": "삼연사",       "desc": "한 번에 부채꼴 3발",            "active": false},
			{"name": "오연사",       "desc": "한 번에 부채꼴 5발",            "active": false},
			{"name": "오연사+추적",  "desc": "5발 + 약한 추적",              "active": false},
		],
	},
	{
		"id": "explosive", "family": FAMILY_COMBAT,
		"tiers": [
			{"name": "폭발물",       "desc": "주위 적 광역 처치 (3s 쿨다운)",  "active": true,  "key": "skill"},
			{"name": "폭발물+",      "desc": "반경 +30%, 쿨다운 2.5s",        "active": true,  "key": "skill"},
			{"name": "이중 충전",    "desc": "폭발물 2회 충전",               "active": true,  "key": "skill"},
		],
	},
	# 이동 ────────────────────────────────────────────
	{
		"id": "glide", "family": FAMILY_MOBILITY,
		"tiers": [
			{"name": "공중 활강",   "desc": "낙하 시 자동으로 천천히 떨어진다", "active": false},
			{"name": "삼단 점프",   "desc": "공중 점프 1회 추가 (최대 3단)",     "active": false},
			{"name": "유도 사격",   "desc": "활강 중 사격이 적을 강하게 유도 (데미지 +1)", "active": false},
		],
	},
	{
		"id": "dash_boost", "family": FAMILY_MOBILITY,
		"tiers": [
			{"name": "대시 강화",    "desc": "대시 쿨다운 -20%",              "active": false},
			{"name": "대시 거리+",   "desc": "대시 거리 +30%",                "active": false},
			{"name": "대시 무적",    "desc": "대시 후 0.3s 무적",             "active": false},
		],
	},
	# 생존 ────────────────────────────────────────────
	{
		"id": "hp", "family": FAMILY_SURVIVAL,
		"tiers": [
			{"name": "최대 체력 +1", "desc": "최대 HP +1 (즉시 1 회복)",      "active": false},
			{"name": "최대 체력 +2", "desc": "최대 HP +2, 피격 후 1s 무적",   "active": false},
			{"name": "피격 슬로모",  "desc": "피격 시 짧은 슬로모션",         "active": false},
		],
	},
	{
		"id": "shield", "family": FAMILY_SURVIVAL,
		"tiers": [
			{"name": "비상 부활",    "desc": "쓰러질 때 1회 부활 (HP 1)",     "active": false},
			{"name": "부활 회복+",   "desc": "부활 시 HP 2 회복",             "active": false},
			{"name": "부활 재충전",  "desc": "30s 후 부활 재무장",            "active": false},
		],
	},
	{
		"id": "barrier", "family": FAMILY_SURVIVAL,
		"tiers": [
			{"name": "에너지 방어막",  "desc": "10초 충전 후 1회 피격 무효",      "active": false},
			{"name": "방어막 가속",   "desc": "충전 시간 6초로 단축",           "active": false},
			{"name": "방어막 잔향",   "desc": "무효 직후 0.6초 무적",           "active": false},
		],
	},
]

# 베이스라인 스킬 (트리 외, 시작 시 자동 보유).
# GameState.skills에 항상 tier 1로 들어 있고, 추가 티어 없음.
const BASELINE: Dictionary = {
	"dash": {"name": "대시", "desc": "짧은 무적 이동", "family": FAMILY_MOBILITY, "active": true, "key": "dash"},
	"double_jump": {"name": "이중점프", "desc": "공중에서 한 번 더 점프", "family": FAMILY_MOBILITY, "active": false},
}

# ─── 스킬-적 상성 (밸런스) ──────────────────────────────────
# 각 적 타입의 약점 스킬. 위협 우선순위 순(방패병=정면 막아 답답 → 저격=원거리 위험 → 드론 → 폭격).
# B(레벨업 추천 ★)와 C(출현 가중)가 공유해 "이 적엔 이 스킬"을 가르친다.
const MATCHUP: Array = [
	{"enemy": "shield", "skill": "explosive"},   # 방향 무시 AoE로 방패 관통
	{"enemy": "sniper", "skill": "barrier"},     # 한 발 막고 사선 통과 (둥지 저격수=회피 대상)
	{"enemy": "drone",  "skill": "glide"},       # 떠서 폭탄 피하고 활강 관통샷으로 처리
	{"enemy": "bomber", "skill": "fire_boost"},  # 붙기 전에 빠른 처치
]

# 현재 맵에 등장하는 적 중, 플레이어가 카운터 스킬을 아직 안 가진 최우선 약점 스킬 id.
# 없으면 빈 문자열. route_id가 비었거나 맵 데이터가 없으면 빈 문자열.
static func matchup_skill_for_route(route_id: String, player_skills: Dictionary) -> String:
	if route_id == "":
		return ""
	var counts: Dictionary = _route_enemy_counts(route_id)
	for m in MATCHUP:
		var entry: Dictionary = m
		var etype: String = str(entry.get("enemy", ""))
		var sk: String = str(entry.get("skill", ""))
		if int(counts.get(etype, 0)) > 0 and not player_skills.has(sk):
			return sk
	return ""

# 맵의 적 타입별 개체 수. enemies(고정 배치) + waves(ARENA) 합산.
static func _route_enemy_counts(route_id: String) -> Dictionary:
	var out: Dictionary = {}
	var layout: Dictionary = MapData.get_layout(route_id)
	if layout.is_empty():
		return out
	var enemies: Dictionary = layout.get("enemies", {})
	for etype in enemies.keys():
		var arr: Array = enemies[etype]
		out[str(etype)] = arr.size()
	for w in layout.get("waves", []):
		var wd: Dictionary = w
		var wen: Dictionary = wd.get("enemies", {})
		for etype in wen.keys():
			var warr: Array = wen[etype]
			out[str(etype)] = int(out.get(str(etype), 0)) + warr.size()
	return out

static func find_line(line_id: String) -> Dictionary:
	for line in LINES:
		var l: Dictionary = line
		if l.get("id", "") == line_id:
			return l
	return {}

# tier는 1~TIER_MAX. 범위 밖이면 빈 Dictionary.
static func find_tier(line_id: String, tier: int) -> Dictionary:
	if tier < 1 or tier > TIER_MAX:
		return {}
	var line: Dictionary = find_line(line_id)
	if line.is_empty():
		return {}
	var tiers: Array = line.get("tiers", [])
	if tier - 1 >= tiers.size():
		return {}
	var t: Dictionary = tiers[tier - 1]
	return t

# 레벨업 카드용 표시 정보. 트리 라인이면 해당 티어 정보, 베이스라인이면 BASELINE 정보.
static func make_card(line_id: String, tier: int) -> Dictionary:
	if BASELINE.has(line_id):
		var base: Dictionary = BASELINE[line_id]
		return {
			"id": line_id, "tier": 1,
			"family": base.get("family", ""),
			"name": base.get("name", line_id),
			"desc": base.get("desc", ""),
			"active": base.get("active", false),
			"key": base.get("key", ""),
		}
	var line: Dictionary = find_line(line_id)
	var tier_def: Dictionary = find_tier(line_id, tier)
	if line.is_empty() or tier_def.is_empty():
		return {}
	return {
		"id": line_id, "tier": tier,
		"family": line.get("family", ""),
		"name": tier_def.get("name", ""),
		"desc": tier_def.get("desc", ""),
		"active": tier_def.get("active", false),
		"key": tier_def.get("key", ""),
	}
