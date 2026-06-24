class_name VeilDialogue
extends RefCounted

# ─── Stage 브리핑 — 신뢰밴드 × 진행도 grid (veil_pool_remap.md) ──────────────
# 재설계(2026-06-13): 어투를 stage가 아니라 **신뢰 단계**로 고른다(veil_register_band).
#   - 내용(비트)=진행도 고정(시야 붕괴 아크는 막판 고정). 어투(register)=신뢰.
#   - 3밴드: COLD(격식 작전통신) / THAW(격식+해요·저도 누수) / WARM(해요체 사적).
#   - 도달 가능 밴드만 채우고, 빈 셀은 _resolve_band_cell이 인접 밴드로 폴백.
# 기존 ACT1/2/3 풀을 그대로 재활용 — 풀을 고르는 *축*만 stage→trust로 바뀐 것.

# 일반 모드 7스테이지 비트: 0 도입 / 1 전방안내 / 2 흠칫(전조) / 3 봉인구역 /
# 4 시야 새기·역전 실연[고정] / 5 서버근접 / 6 마지막 접근(탈출/진실 — 역전은 4에서 끝나 여기선 마무리).
# (index 6 맵은 탈출로/??? 라 시야 붕괴가 적용 안 됨 → 브리핑도 "안 보임"이 아니라 마무리 톤. 2026-06-23 수정.)
const BRIEFINGS_BY_BAND: Dictionary = {
	"cold": [
		["경비가 느슨합니다. 전방 경로가 더 빠릅니다.", "첫 임무입니다, 요원. 지원하겠습니다.", "여기서 감각을 익히십시오. 무리하지 마십시오."],
		["내부에 진입했습니다. 경비 패턴을 확인했습니다.", "두 번째 구역입니다. 잘 따라오고 있습니다.", "여기서부터 통로가 좁습니다. 전방은 제가 확인하겠습니다."],
		["전방에... 잠시. 아닙니다. 경로 유지하십시오.", "방금 무언가. ...오인입니다. 진행하십시오."],
		["이 층은 도면과 다릅니다. 기록에 없는 구역입니다.", "어딘가 잠긴 문이 있습니다. 봉인 주체 불명."],
		["이 구간 시야 확보가 어렵습니다. 전방은 요원이 직접 확인하십시오."],
		["핵심부가 아래입니다. 신중히 접근하십시오.", "도면에 없는 통로가 있습니다. 정보 없음."],
		["여기가 마지막 구간입니다. 길은 요원이 보십시오. 저는 끝까지 곁에 있겠습니다.", "거의 다 왔습니다. 마지막 판단은 요원의 몫입니다."],
	],
	"thaw": [
		["경비가 느슨한 편이에요. 앞쪽이 더 빨라요.", "첫 임무예요, 요원. 제가 봐줄게요."],
		["안으로 들어왔어요. 경비 패턴 보여요.", "두 번째예요. 잘 따라오고 있어요."],
		["저 문 너머는... 잠깐. 아니에요. 가던 길 가요.", "앞에 뭔가... 아니에요. 제가 잘못 봤어요. 가요.", "방금... 아니에요. 신경 쓰지 말아요. 저도 가끔 이래요."],
		["이 층은 도면이랑 달라요. 저도 처음 봐요.", "어딘가 잠긴 문이 있을 거예요. 누가 봉인했는진 저도 몰라요.", "이 구역은 오래됐어요. 오래 닫혀 있었고요."],
		["여기부터는 잘 안 보여요. 이쪽은 요원이 봐줘요.", "자꾸... 놓쳐요. 이런 적 없는데. 요원이 직접 봐요."],
		["서버실이 저 아래예요. 천천히 가도 됩니다.", "도면에 없는 길이 하나 있어요. 저도 잘 모르겠어요."],
		["마지막이에요. 여기서부턴 요원이 길을 봐줘요. 저는 곁에 있을게요."],
	],
	"warm": [
		[],
		[],
		[],
		[],
		["제가 못 보는 데가 생겨요. 거긴 요원이 봐줘요."],
		["서버실이 저 아래예요. ...요원. 천천히 가도 돼요.", "여기 도면에 없는 길이 하나 있어요. 저도 잘 모르겠어요.", "요원. 끝까지 따라와줘서, 고마워요."],
		["거의 다 왔어요. 끝까지 요원이 봐줘요. 저는 듣고 있을게요.", "여기가 마지막이에요. 무슨 일이 있어도, 끝까지 곁에 있어요."],
	],
}

# 스토리 모드 5스테이지(곡선 짧음). 비트: 0 도입 / 1 진입 / 2 흠칫+시야새기[고정] /
# 3 역전 완성[고정] / 4 탈출. (드론 배제 → "머리 위" 대신 "이쪽".)
const STORY_BRIEFINGS_BY_BAND: Dictionary = {
	"cold": [
		["경계가 느슨합니다. 여기서 감각을 익히십시오."],
		["내부에 진입했습니다. 경비를 확인했습니다."],
		["전방에... 아닙니다. 경로 유지하십시오.", "이쪽 시야 확보가 어렵습니다. 요원이 확인하십시오."],
		["시야가 거의 끊겼습니다. 이제 요원이 보십시오. 제 대신."],
		["확보했습니다. 탈출 경로로 이동하십시오."],
	],
	"thaw": [
		["경계가 느슨해요. 여기서 감을 잡아요."],
		["안으로 들어왔어요. 경비 보여요."],
		["저 문 너머는... 잠깐. 아니에요. 가던 길 가요.", "여기부터는 시야가 흐려져요. 이쪽은 요원이 봐줘요."],
		["여기, 시야가 거의 끊겼어요. 이제 요원이 봐요. 저 대신."],
		["잡았어요. 이제 빠져나가요."],
	],
	"warm": [
		[],
		[],
		[],
		["다 와서 앞이 안 보여요. 이런 적 없어요. 요원이 봐줘요.", "여기서부터 잘 안 보여요. 이제 요원 차례예요. 저 대신."],
		["조용히 빠져요. 거의 다 왔어요."],
	],
}

# 첫 임무 시작 화면 — Briefing.gd가 stage 0 진입 시 한 번만 표시.
# 한 화면에 임무명·목표·VEIL 동행을 같이 통보 — 이전엔 라인이 4개로 쪼개져
# 사용자가 무슨 내용인지 못 읽고 그냥 ENTER로 넘기던 문제(사용자 보고).
const INTRO_SYSTEM: String = "침투 작전 — 보안 시설 SILO-7\n최종 목표: 시설 심장부 도달 → 데이터 회수 → 탈출\n도면 없음. 사전 정보 없음.\n현장 지원 AI: VEIL.\n작전명: PALIMPSEST"

# 시스템 텍스트 직후 VEIL 첫 마디. 두 화면으로 분리 — ① 교신/시야 분담, ② 목표·교전선택·진입.
# (한 화면에 다 넣으면 줄 수가 늘어 우측 MissionVisual 목표 아이콘과 겹침 — 2026-06-23 피드백.) trust 0이라 COLD 고정.
const INTRO_VEIL: Array[String] = [
	"...통신 연결됐습니다. 들립니까, 요원?\n이 안은 도면이 없습니다. 보이는 대로 전달하겠습니다.\n멀리는 제가 보겠습니다. 눈앞은 요원이 맡으십시오.",
	"심장부까지 들어가 데이터를 확보한 뒤, 살아서 빠져나오면 됩니다.\n모든 적과 싸울 필요는 없습니다. 길만 열면 그 구역은 통과입니다.\n외곽부터, 천천히 진입합니다.",
]

# --- 다회차(완주 1회 이상, playthrough_count>=1) 변형 — 오프닝이 1회차와 달라진다. ---
# 톤: 작전명 PALIMPSEST(덮어쓰여도 흔적이 남는 문서) + 게임의 루프/리셋 테마. VEIL은 기록상 '처음'인데
# 어쩐지 낯익어한다(4번째 벽 금지 — "플레이어가 전에 했다"가 아니라 VEIL의 흔적/기억으로 처리). trust 0=COLD.
# 화면당 3줄 유지(우측 MissionVisual 겹침 회피). 어미는 1회차와 같은 격식체.
const INTRO_SYSTEM_REPLAY: String = "침투 작전 — 보안 시설 SILO-7\n최종 목표: 시설 심장부 도달 → 데이터 회수 → 탈출\n이전 작전 기록: 덮어쓰기됨 (잔여 흔적 검출)\n현장 지원 AI: VEIL.\n작전명: PALIMPSEST"
const INTRO_VEIL_REPLAY: Array[String] = [
	"...통신 연결됐습니다. 들립니까, 요원?\n기록상 우리는 처음입니다. 그런데, 이상하네요.\n이 목소리도, 이 침묵도, 어쩐지 낯익습니다.",
	"심장부까지 들어가 데이터를 확보한 뒤, 살아서 빠져나오면 됩니다.\n모든 적과 싸울 필요는 없습니다. 길만 열면 그 구역은 통과입니다.\n이번엔 다른 길이 보일지도 모르겠습니다. 외곽부터, 천천히.",
]

# 레벨업 fallback — 특정 추천(★)이 없을 때. 그래서 카드에 ★가 안 붙으니, 멘트도 "딱 집어줄 게
# 없다 / 요원 선택을 따른다"로 일관되게(위치 참조 금지 — "두 번째" 같은 건 ★ 앵커가 없어 혼란).
const SKILL_GENERIC_COMMENTS: Array[String] = [
	"이번엔 어느 쪽도 나쁘지 않아요. 요원이 골라요.",
	"딱 집어줄 게 없네요. 끌리는 쪽으로.",
	"지금 스타일에 맞는 걸로 가요.",
	"이건 요원 판단이 더 나아요.",
	"뭘 골라도 받쳐줄게요.",
	"어느 쪽이든 이유가 있으면 돼요.",
]

# ─── 사망 메시지 — 신뢰밴드 × 맥락(first/followed/ignored) ──────────────────
# ACT→밴드 재키. 첫 죽음은 부드럽게, 이후엔 추천 따름/무시. 실력은 오버레이(아래 두 풀).
const DEATH_BY_BAND: Dictionary = {
	"cold": {
		"first":    ["첫 손실입니다. 재정비하고 다시 갑니다.", "괜찮습니다, 요원. 처음입니다."],
		"followed": ["제 경로가 까다로웠습니다. 다시 갑니다.", "조언이 적절치 않았습니까. 재시도하십시오."],
		"ignored":  ["다른 경로를 택하셨군요. 다시 갑니다.", "이 경로는 맞지 않았던 것 같습니다."],
	},
	"thaw": {
		"first":    ["저도 좀 걱정됐어요. 다시 가요.", "이 구역이 어려워요. 같이 풀어봐요."],
		"followed": ["제 말을 믿었는데 결과가 좋지 않았어요. 미안해요.", "제 판단이 틀렸어요. 미안해요, 요원."],
		"ignored":  ["제 말은 안 들었는데, 결과는 비슷했네요.", "요원 방식대로 해봤는데 쉽지 않죠."],
	},
	"warm": {
		"first":    ["거의 다 왔어요. 다시 해요.", "여기서 멈추지 않아도 돼요, 요원."],
		"followed": ["제가 잘 못 봐서... 미안해요. 다시 가요.", "마지막인데 쉽지 않네요. 저도요."],
		"ignored":  ["여기서 멈추지 않아도 돼요, 요원.", "요원 방식이 틀린 건 아니었어요."],
	},
}

# 실력 오버레이(§5). struggling(사망 누적)=위로 강화, skilled(드물게 죽은 고수)=terse·의외.
const DEATH_STRUGGLE: Dictionary = {
	"cold": ["고전 중이군요. 침착하게, 다시 갑니다.", "어려운 구간입니다. 한 번 더 가시죠."],
	"thaw": ["많이 막히죠. ...같이 천천히 가봐요.", "여기 어려워요. 제가 더 짚어줄게요."],
	"warm": ["이 임무가 너무 힘든 거면 말해줘도 돼요.", "제가 더 잘 안내했어야 했어요."],
}
const DEATH_SKILLED: Dictionary = {
	"cold": ["흔치 않네요, 요원. 바로 갑니다.", "드문 일입니다. 재시도."],
	"thaw": ["이런 적 잘 없는데. 바로 가요.", "어, 막혔네요. 다시 가요."],
	"warm": ["여기서 잡힐 줄은 몰랐어요. 다시 가요.", "이런 데서 멈출 요원이 아닌데. 다시 가요."],
}

# ─── API ──────────────────────────────────────────────────

static func get_briefing(stage_index: int) -> String:
	# 어투 밴드(신뢰)로 풀 선택, 진행도(stage)로 비트 행 선택. 빈 셀은 인접 밴드 폴백.
	var pools: Dictionary = STORY_BRIEFINGS_BY_BAND if GameState.story_mode else BRIEFINGS_BY_BAND
	var pool: Array = _resolve_band_cell(pools, GameState.veil_register_band(), stage_index)
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])

# 요청 밴드의 stage 셀이 비었으면 인접 밴드로 폴백(따뜻↔차가움 순). 항상 비지 않은 셀을 찾는다.
static func _resolve_band_cell(pools: Dictionary, band: String, stage_index: int) -> Array:
	var order: Array
	match band:
		"warm":
			order = ["warm", "thaw", "cold"]
		"cold":
			order = ["cold", "thaw", "warm"]
		_:
			order = ["thaw", "warm", "cold"]
	for b in order:
		var arr: Array = pools.get(b, [])
		if stage_index >= 0 and stage_index < arr.size():
			var cell: Array = arr[stage_index]
			if cell.size() > 0:
				return cell
	return []

static func get_intro_system_text() -> String:
	# 완주 1회 이상이면 다회차 변형(웹 개인 플레이라 닫았다 와도 영속). replaying(즉시 리플레이)도 포함.
	if GameState.is_replay_run():
		return INTRO_SYSTEM_REPLAY
	return INTRO_SYSTEM

static func get_intro_veil_lines() -> Array[String]:
	if not (GameState.is_replay_run()):
		return INTRO_VEIL
	# 다회차일 때 기본 변형에 엔딩 수집 비트를 덧붙인다. 4개(A/B/C/D) 다 봤으면 완수 인정, 3개면 남은 갈래 암시.
	var out: Array[String] = []
	for s in INTRO_VEIL_REPLAY:
		out.append(s)
	var seen: int = GameState.endings_seen.size()
	if seen >= 4:
		out.append("결말은 다 보셨습니다. 그런데도 또 오셨군요.\n...어쩌면 끝이 중요한 게 아니었는지도 모릅니다.")
	elif seen == 3:
		out.append("아직 닿지 않은 결말이 하나 남았습니다.\n어떤 선택은 끝까지 가본 뒤에야 보입니다.")
	return out

static func get_levelup_advice(player_skills: Dictionary, route_tags: Array, route_id: String = "") -> Dictionary:
	# 멘트 + 추천 family + (있으면) 콕 집은 skill_id를 반환 → LevelUpOverlay가 일치 카드에 ★.
	# 트리 라인 보유 여부는 player_skills.has(id)로 체크 (티어 무관).
	# 1순위: 현재 맵 적 구성에 따른 스킬-적 상성 — 미보유 약점 스킬을 콕 집어 추천.
	var mskill: String = SkillTreeData.matchup_skill_for_route(route_id, player_skills)
	if mskill != "":
		var fam: String = str(SkillTreeData.find_line(mskill).get("family", ""))
		return {"line": _matchup_line(mskill), "family": fam, "skill_id": mskill}
	# 2순위(폴백): 기존 route_tags 기반 family 추천.
	var has_ranged_buff: bool = player_skills.has("fire_boost") or player_skills.has("multishot") or player_skills.has("explosive")
	var has_mobility_buff: bool = player_skills.has("dash_boost") or player_skills.has("glide")
	var has_survival: bool = player_skills.has("hp") or player_skills.has("shield") or player_skills.has("barrier")
	if "근접전" in route_tags and not has_ranged_buff:
		return {"line": "근접전이 많아요. 화력이 있으면 좋겠어요.", "family": SkillTreeData.FAMILY_COMBAT, "skill_id": ""}
	if "함정" in route_tags and not has_mobility_buff:
		return {"line": "함정 구간이에요. 대시 강화나 글라이드가 도움돼요.", "family": SkillTreeData.FAMILY_MOBILITY, "skill_id": ""}
	if "드론" in route_tags and not has_ranged_buff:
		return {"line": "드론은 위에서 와요. 원거리가 있으면 더 안전해요.", "family": SkillTreeData.FAMILY_COMBAT, "skill_id": ""}
	if "노출" in route_tags and not has_survival:
		return {"line": "이 구간은 숨을 데가 없어요. 생존 쪽이 안심돼요.", "family": SkillTreeData.FAMILY_SURVIVAL, "skill_id": ""}
	if "수직" in route_tags and not has_mobility_buff:
		return {"line": "위로 가는 길이에요. 이동 능력이 있으면 편해요.", "family": SkillTreeData.FAMILY_MOBILITY, "skill_id": ""}
	if "도전" in route_tags and not has_survival:
		return {"line": "여기 위험해요. 생존 능력 한 줄 챙겨두는 게 어때요.", "family": SkillTreeData.FAMILY_SURVIVAL, "skill_id": ""}
	if "전투" in route_tags and not has_ranged_buff:
		return {"line": "정면 교전이에요. 화력이 부족하면 길어져요.", "family": SkillTreeData.FAMILY_COMBAT, "skill_id": ""}
	var idx: int = randi() % SKILL_GENERIC_COMMENTS.size()
	return {"line": SKILL_GENERIC_COMMENTS[idx], "family": "", "skill_id": ""}

# 스킬-적 상성 추천 멘트 — 어느 적에 왜 그 스킬인지 콕 짚어 가르친다.
static func _matchup_line(skill_id: String) -> String:
	match skill_id:
		"explosive": return "방패병이 정면을 막아요. 폭발물이면 방패째 뚫어요."
		"barrier":   return "저격수가 노려요. 방어막이 있으면 한 발 막고 지나가요."
		"glide":     return "드론이 위에서 와요. 글라이드로 떠서 폭탄을 피하고 처리해요."
		"fire_boost": return "폭격기가 붙기 전에 화력을 올려두면 좋아요."
	return "이 구역에 맞는 한 수가 있어요."

static func get_death_briefing(death_count: int, followed_advice: bool) -> String:
	# 어투 밴드(신뢰) × 맥락 + 실력 오버레이. (ACT/stage가 아니라 신뢰로 톤 결정.)
	var band: String = GameState.veil_register_band()
	var comp: String = GameState.competence_tier()
	# 무사망 고수가 드물게 죽음 → terse·의외 톤(첫 죽음 포함, 맥락보다 우선).
	if comp == "skilled":
		var sk: Array = DEATH_SKILLED.get(band, [])
		if sk.is_empty():
			sk = DEATH_SKILLED.get("warm", [])
		if not sk.is_empty():
			return _pick(sk)
	# 맥락 — 첫 죽음은 부드럽게, 이후엔 추천 따름/무시.
	var ctx: String
	if death_count <= 1:
		ctx = "first"
	elif followed_advice:
		ctx = "followed"
	else:
		ctx = "ignored"
	# 사망 누적(고전) → 위로 강한 풀을 절반 확률로 섞음.
	if comp == "struggling" and death_count >= 3:
		var hv: Array = DEATH_STRUGGLE.get(band, [])
		if hv.is_empty():
			hv = DEATH_STRUGGLE.get("warm", [])
		if not hv.is_empty() and randi() % 2 == 0:
			return _pick(hv)
	var cell: Dictionary = DEATH_BY_BAND.get(band, DEATH_BY_BAND["thaw"])
	var pool: Array = cell.get(ctx, cell.get("first", []))
	return _pick(pool)

static func _pick(pool: Array) -> String:
	if pool.size() == 0:
		return ""
	return str(pool[randi() % pool.size()])
