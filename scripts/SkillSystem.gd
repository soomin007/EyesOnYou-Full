class_name SkillSystem
extends RefCounted

# 레벨업 시 다음 티어 후보를 굴린다. 각 라인에서 보유 티어 +1이 다음 후보.
# 이미 T3까지 찍은 라인은 후보에서 제외. 베이스라인은 트리 외라 후보에 안 뜸.

# owned: GameState.skills (Dictionary[String, int] — line_id → 보유 티어 0~3).
# route_id가 주어지면 현재 맵의 적 약점 스킬(상성)을 후보에 있을 때 첫 슬롯으로 보장해 출현↑.
static func roll_choices(owned: Dictionary, count: int = 3, route_id: String = "") -> Array:
	var available: Array = []
	for line in SkillTreeData.LINES:
		var line_dict: Dictionary = line
		var line_id: String = line_dict.get("id", "")
		var current_tier: int = int(owned.get(line_id, 0))
		var next_tier: int = current_tier + 1
		if next_tier > SkillTreeData.TIER_MAX:
			continue
		var card: Dictionary = SkillTreeData.make_card(line_id, next_tier)
		if not card.is_empty():
			available.append(card)
	available.shuffle()
	# 상성 가중 — 현재 맵 약점 스킬이 후보에 있으면 셔플 후 첫 슬롯으로 끌어와 픽에 보장.
	var mskill: String = SkillTreeData.matchup_skill_for_route(route_id, owned)
	if mskill != "":
		for i in available.size():
			var c: Dictionary = available[i]
			if str(c.get("id", "")) == mskill:
				if i != 0:
					available[i] = available[0]
					available[0] = c
				break
	var picks: Array = []
	for i in min(count, available.size()):
		var p: Dictionary = available[i]
		picks.append(p)
	return picks

# 단일 스킬(라인) 정보 조회. tier 미지정 시 1티어 정보.
# 베이스라인(dash, double_jump)은 트리 외라 BASELINE 정보 반환.
static func find_by_id(id: String, tier: int = 1) -> Dictionary:
	return SkillTreeData.make_card(id, tier)
