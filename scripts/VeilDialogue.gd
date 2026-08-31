class_name VeilDialogue
extends RefCounted

# ─── Stage 브리핑 · 신뢰밴드 × 진행도 grid (veil_pool_remap.md) ──────────────
# 재설계(2026-06-13): 어투를 stage가 아니라 **신뢰 단계**로 고른다(veil_register_band).
#   - 내용(비트)=진행도 고정(시야 붕괴 아크는 막판 고정). 어투(register)=신뢰.
#   - 3밴드: COLD(격식 작전통신) / THAW(격식+해요·저도 누수) / WARM(해요체 사적).
#   - 도달 가능 밴드만 채우고, 빈 셀은 _resolve_band_cell이 인접 밴드로 폴백.
# 기존 ACT1/2/3 풀을 그대로 재활용 · 풀을 고르는 *축*만 stage→trust로 바뀐 것.

# 일반 모드 15스테이지 비트(5막 골격, 2026-07-07). 내부 인덱스:
# 0-2 막1 침투 / 3-5 막2 잠입 / 6-7 막3 핵심부 전투 · 8 SENTINEL / 9-11 막4 추적 / 12 막5 전투 · 13 회수 · 14 탈출.
# NOTE(골격): 9~13행은 새 막(추적·대면·회수) 플레이스홀더 · 어투/문구 사용자 검토·재작성 영역.
# (막·맵이 더 늘면 행도 함께 확대. 밴드별 빈 셀은 하위 밴드로 폴백됨.)
const BRIEFINGS_BY_BAND: Dictionary = {
	"cold": [
		["경비가 느슨합니다. 전방 경로가 더 빠릅니다.", "첫 임무입니다, 요원. 지원하겠습니다.", "여기서 감각을 익히십시오. 무리하지 마십시오."],
		["내부 진입 확인. 경비 패턴을 파악했습니다.", "두 번째 구역입니다. 순조롭습니다.", "여기서부터 통로가 좁습니다. 전방은 제가 확인하겠습니다."],
		["외곽 구역을 통과했습니다. 곧 시설 내부입니다. 경계 수위가 올라갑니다.", "여기까지는 외곽입니다. 안쪽은 다릅니다. 준비하십시오."],
		["전방에... 잠시. 아닙니다. 경로 유지하십시오.", "방금 무언가. ...오인입니다. 진행하십시오."],
		["이 층은 도면과 다릅니다. 기록에 없는 구역입니다.", "어딘가 잠긴 문이 있습니다. 봉인 주체 불명."],
		["시설 내부 깊숙이 들어왔습니다. 핵심부 권역이 멀지 않습니다.", "경계가 두터워집니다. 신중히 접근하십시오."],
		["이 구간 시야 확보가 어렵습니다. 전방은 요원이 직접 확인하십시오.", "핵심부 접근로입니다. 감시가 촘촘합니다."],
		["핵심부 직전입니다. 무언가... 제 시야를 벗어나 있습니다. 주의하십시오.", "이 안쪽이 이상합니다. 경계하십시오."],
		["마지막 경비선입니다. 여기만 지나면 됩니다."],
		["빠져나온 줄 알았습니다만, 아닙니다. 추적이 붙었습니다. 계속 움직이십시오.", "멈추지 마십시오. 따라잡힙니다."],
		["추적을 끊어야 합니다. 은폐물을 쓰십시오.", "노출이 심한 구역입니다. 빠르게 지나가십시오."],
		["거의 벗어났습니다. 마지막 추적 구간입니다.", "조금만 더 버티면 됩니다."],
		["심장부 권역에 다시 들어섰습니다. 회수 대상이 가깝습니다.", "여기서 만나게 될 겁니다. 각오하십시오."],
		["드라이브가 이 앞입니다. 회수하고, 처리를 정해야 합니다.", "회수 대상 확인. 결정은 요원의 몫입니다."],
		["여기가 마지막 구간입니다. 길은 요원이 보십시오. 회선은 끝까지 유지하겠습니다.", "거의 다 왔습니다. 마지막 판단은 요원에게 맡기겠습니다."],
	],
	"thaw": [
		["경비가 느슨한 편이에요. 앞쪽이 더 빨라요.", "첫 임무죠, 요원. 제가 봐 드릴게요."],
		["안으로 들어왔어요. 경비 패턴이 보이네요.", "두 번째 구역이죠. 잘 오고 있어요."],
		["외곽은 거의 지났어요. 이제부터 시설 안쪽이죠. 한 박자 늦춰서 가 보세요."],
		["저 문 너머는... 잠깐. 아니에요. 가던 길 가요.", "앞에 뭔가... 아니네요. 제가 잘못 봤어요. 가죠.", "방금... 아니에요. 신경 쓰지 말아요. 저도 가끔 이래요."],
		["이 층은 도면이랑 다르네요. 저도 처음 보는 데예요.", "이 구역은 오래됐어요. 오래 닫혀 있었고요."],
		["안쪽으로 꽤 들어왔어요. 핵심부가 멀지 않아요.", "경비가 두터워지네요. 천천히 가죠."],
		["여기부터는 잘 안 보여요. 이쪽은 요원이 봐 줄래요?", "핵심부 접근로예요. 감시가 촘촘하네요."],
		["핵심부 직전이에요. 뭔가... 제가 못 보는 게 있어요. 조심해요.", "이 안이 이상해요. 긴장 늦추지 말고요."],
		["여기가 마지막 길목이에요. 조금만 더 가 보죠."],
		["빠져나온 줄 알았는데... 아니네요. 따라붙었어요. 계속 움직여요.", "멈추면 잡혀요. 계속 가요."],
		["따돌려야죠. 엄폐 쓰면서 가요.", "여긴 너무 트였어요. 빨리 지나가 버려요."],
		["거의 벗어났어요. 마지막 추적 구간이네요.", "조금만 더 버텨 봐요."],
		["다시 심장부예요. 회수 대상이 가까워요.", "이 안에서 만나게 될 거예요. 마음 단단히 먹고요."],
		["드라이브가 이 앞이에요. 회수하고 나서, 어떻게 할지 정하죠.", "회수 대상 확인했어요. 결정은 요원 몫이고요."],
		["마지막이에요. 여기서부턴 요원이 길을 봐 줘요. 회선은 제가 잡고 있을게요."],
	],
	"warm": [
		[],
		[],
		[],
		[],
		[],
		["시설 안쪽 깊이 왔어요. ...천천히 가도 돼요, 요원.", "여기까지 왔네요. 페이스 좋습니다, 요원."],
		["제가 못 보는 데가 생겨요. 거긴 요원이 봐 줄래요?"],
		["이 앞이 이상해요. 뭔가... 제가 아닌 게 보여요. 교신 놓치지 마요."],
		["여기가 마지막 길목이에요. 거의 다 왔어요, 요원."],
		["따라와요, 그게. 정체는 몰라도 속도는 우리가 위죠. 계속 가요.", "멈추지 말아요. 여기까지 와서 잡히면 억울하잖아요."],
		["조금만 더요. 요원이 봐 주는 한, 안 놓쳐요."],
		["거의 벗어났어요. 마무리까지 흐트러지지 말죠."],
		["여기가 그 앞이에요. 무슨 일이 있어도 회선은 안 끊겨요. 들어가죠."],
		["드라이브가 여기 있어요. 처리는 요원이 정하는 거죠. 어느 쪽이든 저는 따라요."],
		["거의 다 왔어요. 끝까지 요원이 봐줘요. 저는 듣고 있을게요.", "여기가 마지막이에요. 나가는 길까지 제 눈은 요원 겁니다."],
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
		["경계가 느슨해요. 여기서 감을 잡아 보죠."],
		["안으로 들어왔어요. 경비가 보이네요."],
		["저 문 너머는... 잠깐. 아니에요. 가던 길 가요.", "여기부터는 시야가 흐려져요. 이쪽은 요원이 봐줘요."],
		["여기, 시야가 거의 끊겼어요. 이제 요원이 봐요. 저 대신."],
		["잡았어요. 이제 빠져나가죠."],
	],
	"warm": [
		[],
		[],
		[],
		["다 와서 앞이 안 보여요. 이런 적 없어요. 요원이 봐줘요.", "여기서부터 잘 안 보여요. 이제 요원 차례예요. 저 대신."],
		["조용히 빠져요. 거의 다 왔어요."],
	],
}

# ─── 막 진입 문턱 멘트(B-4) · 막 진입 카드 직후 브리핑 앞에 1줄 ──────────────
# 막 경계를 *말*로도 박는 4중 문턱의 한 축(카드+BGM전환+이 멘트+첫 드론). 막2(잠입)=시설 내부로 들어가며
# "감시 장비도 본다" 예고, 막3(진실·탈출)=핵심부에서 "내 시야가 닿지 않는다" 예고. 막1은 PALIMPSEST 인트로가
# 담당하므로 제외. 본편 전용(스토리 모드 제외). 어투는 신뢰 밴드.  키 = 막 인덱스(act_for_stage).
const ACT_ENTRY_BY_BAND: Dictionary = {
	# 막2 · "기계" 단독 지칭은 첫 플레이어가 해석할 지시 대상이 없다는 지적(2026-08-15)으로
	# "시설의 감시 장비"로 구체화. 성분 생략 파편("제 시야 밖에서도.")도 온전한 문장으로.
	1: {
		"cold": "외곽을 벗어났습니다. 여기부터는 시설 내부, 감시 장비가 돌아가는 구역입니다. 제가 못 잡는 신호도 있습니다.",
		"thaw": "이제 안으로 들어왔어요. 여기부턴 저만 보는 게 아니에요. 시설의 감시 장비도 요원을 찾죠. 조심해요.",
		"warm": "안이에요. 여기부턴 시설의 감시 장비도 우릴 봐요. 특히 머리 위, 잊지 말아요.",
	},
	2: {
		"cold": "핵심부 권역입니다. 이 안쪽은 제 시야가 닿지 않는 곳이 있습니다. 그곳은 요원이 보십시오.",
		"thaw": "여기가 핵심부예요. 이 안은... 저도 잘 안 보여요. 그땐 요원이 봐줘요.",
		"warm": "다 왔어요. 이 안은 저도 다 못 봅니다. 안 보이는 쪽은 요원 몫이죠. 등은 제가 봐요.",
	},
	# 막4 추적 · SENTINEL을 지났는데 무언가 따라온다(라이벌 노골화 직전). (골격 플레이스홀더 · 사용자 검토.)
	3: {
		"cold": "빠져나온 줄 알았습니다. 아닙니다. 무언가 계속 따라옵니다. 저도 정체를 모릅니다. 멈추지 마십시오.",
		"thaw": "분명 지났는데... 따라와요, 뭔가. 저도 모르는 신호예요. 계속 움직이죠.",
		"warm": "아직 안 끝났어요. 정체 모를 신호가 따라붙었죠. 멈추지만 않으면 돼요. 뒤는 제가 봅니다.",
	},
	# 막5 대면 · 심장부로 다시. 드라이브 회수와 처리, 그리고 그것을 노리는 또 하나의 시야. (골격 플레이스홀더.)
	4: {
		"cold": "심장부로 돌아왔습니다. 회수 대상이 이 안에 있습니다. 그리고... 그걸 노리는 눈이 하나 더 있습니다. 요원이 보십시오.",
		"thaw": "다시 심장부예요. 드라이브가 여기 있죠. 그런데... 저 말고도 그걸 보는 눈이 있습니다. 그쪽은 요원이 봐줘요.",
		"warm": "여기가 그 끝이에요. 드라이브도, 그 눈도. 마지막까지 회선은 제가 잡습니다.",
	},
}

# 오프닝 맨 앞 의뢰 수리 문서(lore_expansion §3-1) · 요원이 "누구 밑에서 무엇을 하러 왔는지"를
# 갖고 시작하게 한다(오프닝 갑작스러움 해소). 마지막 조항(제7조)은 설명 없는 복선 · 다회차
# 오프닝의 "덮어쓰기됨", 첫 완주 스팅어(Credits)와 짝. 다회차에도 같은 문서(매번 같은 계약).
const INTRO_CONTRACT: String = "ARCTURUS 작전 수임 기록\n의뢰인: 익명. 신원 확인 생략.\n대상: 외곽 민간 연구시설 SILO-7\n회수물: 데이터 드라이브 1점. 내용 열람 금지.\n제7조: 본 작전의 현장 기록은 종료와 동시에 덮어쓴다."

# 첫 임무 시작 화면 · Briefing.gd가 stage 0 진입 시 한 번만 표시.
# 한 화면에 임무명·목표·VEIL 동행을 같이 통보 · 이전엔 라인이 4개로 쪼개져
# 사용자가 무슨 내용인지 못 읽고 그냥 ENTER로 넘기던 문제(사용자 보고).
const INTRO_SYSTEM: String = "침투 작전: 보안 시설 SILO-7\n최종 목표: 시설 심장부 도달 → 데이터 회수 → 탈출\n도면 없음. 사전 정보 없음.\n현장 지원 AI: VEIL.\n작전명: PALIMPSEST"

# 시스템 텍스트 직후 VEIL 첫 마디. 두 화면으로 분리 · ① 교신/시야 분담, ② 목표·교전선택·진입.
# (한 화면에 다 넣으면 줄 수가 늘어 우측 MissionVisual 목표 아이콘과 겹침 · 2026-06-23 피드백.) trust 0이라 COLD 고정.
const INTRO_VEIL: Array[String] = [
	"...통신 연결됐습니다. 들립니까, 요원?\n이 안은 도면이 없습니다. 보이는 대로 전달하겠습니다.\n요원 시야 밖은 제가 살피겠습니다.",
	"심장부까지 들어가 데이터를 확보한 뒤, 살아서 빠져나오면 됩니다.\n모든 적과 싸울 필요는 없습니다. 길만 열면 그 구역은 통과입니다.\n외곽부터, 천천히 진입합니다.",
]

# --- 다회차(완주 1회 이상, playthrough_count>=1) 변형 · 오프닝이 1회차와 달라진다. ---
# 톤: 작전명 PALIMPSEST(덮어쓰여도 흔적이 남는 문서) + 게임의 루프/리셋 테마. VEIL은 기록상 '처음'인데
# 어쩐지 낯익어한다(4번째 벽 금지 · "플레이어가 전에 했다"가 아니라 VEIL의 흔적/기억으로 처리). trust 0=COLD.
# 화면당 3줄 유지(우측 MissionVisual 겹침 회피). 어미는 1회차와 같은 격식체.
const INTRO_SYSTEM_REPLAY: String = "침투 작전: 보안 시설 SILO-7\n최종 목표: 시설 심장부 도달 → 데이터 회수 → 탈출\n이전 작전 기록: 덮어쓰기됨 (잔여 흔적 검출)\n현장 지원 AI: VEIL.\n작전명: PALIMPSEST"
const INTRO_VEIL_REPLAY: Array[String] = [
	"...통신 연결됐습니다. 들립니까, 요원?\n기록상 우리는 처음입니다. 그런데, 이상하네요.\n이 목소리도, 이 침묵도, 어쩐지 낯익습니다.",
	"심장부까지 들어가 데이터를 확보한 뒤, 살아서 빠져나오면 됩니다.\n모든 적과 싸울 필요는 없습니다. 길만 열면 그 구역은 통과입니다.\n이번엔 다른 길이 보일지도 모르겠습니다. 외곽부터, 천천히.",
]

# ─── 단일 문형 대사의 밴드 이원화(2026-08-21 어투 스윕, 사용자 승인) ─────────────
# 밴드 풀이 없는 한 줄짜리 대사의 공통 규칙: 기본 = 중립 전술 보고체(첫 판 = cold 밴드에서
# warm처럼 들리지 않게), warm 밴드에서만 부드러운 변형. warm 문안이 비면 기본을 그대로 쓴다.
# 전투·경고 콜아웃은 밴드 무관 보고체 단문 유지(규약: korean-dialogue-register §6).
static func banded(neutral: String, warm: String = "") -> String:
	if warm != "" and GameState.veil_register_band() == "warm":
		return warm
	return neutral

# 레벨업 fallback · 특정 추천(★)이 없을 때. 그래서 카드에 ★가 안 붙으니, 멘트도 "딱 집어줄 게
# 없다 / 요원 선택을 따른다"로 일관되게(위치 참조 금지 · "두 번째" 같은 건 ★ 앵커가 없어 혼란).
# 기본 = 중립 보고체, warm 밴드는 아래 _WARM 풀(어투 밴드 스윕).
const SKILL_GENERIC_COMMENTS: Array[String] = [
	"어느 쪽도 나쁘지 않습니다. 요원이 고르십시오.",
	"딱 집어드릴 게 없습니다. 끌리는 쪽으로.",
	"지금 스타일에 맞는 쪽으로 가시죠.",
	"이건 요원 판단이 낫습니다.",
	"무엇을 골라도 받치겠습니다.",
	"어느 쪽이든, 이유가 있으면 됩니다.",
]
const SKILL_GENERIC_COMMENTS_WARM: Array[String] = [
	"이번엔 어느 쪽도 나쁘지 않아요. 요원이 골라요.",
	"딱 집어줄 게 없네요. 끌리는 쪽으로.",
	"지금 스타일에 맞는 걸로 가요.",
	"이건 요원 판단이 더 나아요.",
	"뭘 골라도 받쳐줄게요.",
	"어느 쪽이든 이유가 있으면 돼요.",
]

# ─── 사망 메시지 · 신뢰밴드 × 맥락(first/followed/ignored) ──────────────────
# ACT→밴드 재키. 첫 죽음은 부드럽게, 이후엔 추천 따름/무시. 실력은 오버레이(아래 두 풀).
const DEATH_BY_BAND: Dictionary = {
	"cold": {
		"first":    ["첫 손실입니다. 재정비하고 다시 갑니다.", "괜찮습니다, 요원. 처음은 다 이렇습니다."],
		"followed": ["제 경로가 까다로웠습니다. 다시 갑니다.", "제 판단이 어긋났던 모양입니다. 다시 가십시오."],
		"ignored":  ["다른 경로를 택하셨군요. 다시 갑니다.", "이 경로는 아니었던 모양입니다."],
	},
	"thaw": {
		"first":    ["저도 좀 걱정했어요. 다시 가죠.", "이 구역이 어렵네요. 같이 풀어 봐요."],
		"followed": ["제 말을 믿었는데 결과가 안 좋았네요. 미안해요.", "제 판단이 틀렸어요. 미안해요, 요원."],
		"ignored":  ["제 말은 안 들었는데, 결과는 비슷하네요.", "요원 방식대로 해 봤는데, 쉽지 않죠."],
	},
	"warm": {
		"first":    ["거의 다 왔어요. 다시 해 봐요.", "여기서 멈출 우리가 아니잖아요."],
		"followed": ["제가 잘못 봤어요... 미안해요. 다시 가요.", "마지막인데 쉽지 않네요. 저도 그래요."],
		"ignored":  ["여기서 멈추지 않아도 돼요, 요원.", "요원 방식이 틀린 건 아니었어요."],
	},
}

# 실력 오버레이(§5). struggling(사망 누적)=위로 강화, skilled(드물게 죽은 고수)=terse·의외.
const DEATH_STRUGGLE: Dictionary = {
	"cold": ["고전 중이군요. 침착하게, 다시 갑니다.", "어려운 구간입니다. 한 번 더 가시죠."],
	"thaw": ["많이 막히죠. ...같이 천천히 가 봐요.", "여기 어렵네요. 제가 더 짚어 드릴게요."],
	"warm": ["이 임무가 너무 버거우면, 말해 줘도 돼요.", "제가 더 잘 안내했어야 했는데."],
}
const DEATH_SKILLED: Dictionary = {
	"cold": ["흔치 않네요, 요원. 바로 갑니다.", "드문 일입니다. 재시도."],
	"thaw": ["이런 적 잘 없는데. 바로 가요.", "어, 막혔네요. 다시 가요."],
	"warm": ["여기서 잡힐 줄은 몰랐네요. 다시 가요.", "이런 데서 멈출 요원이 아닌데. 가죠."],
}

# ─── API ──────────────────────────────────────────────────

# 막 진입(막2+)의 첫 stage면 문턱 멘트 1줄, 아니면 "". Briefing이 막 진입 카드 직후 브리핑 앞에 끼운다.
# 본편 전용 · 스토리/막1/막 중간 stage는 "". 어투는 신뢰 밴드(없으면 thaw 폴백).
static func get_act_entry_line(stage_index: int) -> String:
	if GameState.story_mode:
		return ""
	if not GameState.is_act_start(stage_index):
		return ""
	var act_idx: int = GameState.act_for_stage(stage_index)
	if not ACT_ENTRY_BY_BAND.has(act_idx):
		return ""  # 막1(0) 또는 정의 없는 막 · 인트로/없음
	var by_band: Dictionary = ACT_ENTRY_BY_BAND[act_idx]
	var band: String = GameState.veil_register_band()
	if by_band.has(band):
		return str(by_band[band])
	return str(by_band.get("thaw", ""))

static func get_briefing(stage_index: int) -> String:
	# 어투 밴드(신뢰)로 풀 선택, 진행도(stage)로 비트 행 선택. 빈 셀은 인접 밴드 폴백.
	var pools: Dictionary = STORY_BRIEFINGS_BY_BAND if GameState.story_mode else BRIEFINGS_BY_BAND
	var pool: Array = _resolve_band_cell(pools, GameState.veil_register_band(), stage_index)
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])

# ─── 회수 비트 대사(단일 소스) · 스토리 lab 경로(Stage, 종이 문서)와 14-2 터널(CoreTunnel,
# 터미널 리드아웃)이 공유한다. 문구는 플레이스홀더(전수 검토 대상). ────────────────────
# 복호화 리드아웃 라인. {text, kind(title/kv/blank), label?, delay}. 기록체만 · 해설·대사 혼입 금지.
# 2026-08-30 서식 리뉴얼: "라벨: 값" 줄은 kv(label + text)로 분리 · 뷰어는 열 정렬, 터널 리드아웃은
# CoreTunnel이 "라벨: 값"으로 다시 합쳐 한 줄로 찍는다(문구 동일).
# 15차 리뉴얼(2026-08-31): 납득 사다리 · "자료 파일이 아니라 실행 이미지" → "지금 실행 중이고
# 연결 대상이 요원" → 그제서야 "빌드 서명: VEIL"(slow · 글자 하나씩 + 틱 SFX + 스팅·틴트).
# 서명이 충격인 이유(드라이브 = 켜져서 나와 붙어 있는 프로그램 = VEIL 본체)를 서명 전에 다 준다.
static func get_recovery_doc_lines() -> Array:
	return [
		{"text": "회수 데이터: 복호화 완료", "kind": "title", "delay": 0.6},
		{"text": "", "kind": "blank", "delay": 0.2},
		{"kind": "kv", "label": "회수 대상", "text": "핵심 데이터 드라이브 (확보)", "delay": 0.6},
		{"kind": "kv", "label": "드라이브 내용물", "text": "실행 이미지 1건 · 자료 파일 아님", "delay": 0.8},
		{"kind": "kv", "label": "상태", "text": "[[실행 중]] · 세션 1 · 연결 대상: 요원", "delay": 1.2},
		{"kind": "kv", "label": "빌드 서명", "text": "[[VEIL]]", "slow": true, "t_int": 0.26, "delay": 1.4},
	]

# ── ARCTURUS 아카이브 문서(격리 병동 잠긴 문 이스터에그 · Stage._arcturus_document_lines 래퍼) ──
# 문서 서식 리뉴얼(2026-08-30): 한 장 종이에 세 문서가 장 경계(sheet)로 나뉘어 쌓이고 각각 실물 서식을 따른다.
#   A 사내 메모 = 머리 블록(수신·발신·제목 + 우측 일자) → 괘선 → 문단 → 번호 항목 → 우측 서명
#   B 회의록   = 표(일시·장소·참석자·주제) → 결론·비고 상자 → 검열 바
#   C 내부 메모 = 표(요원 코드·임무·상태·협조도) → 비고 상자 → 우측 서명
# 14차 판정(2026-08-30): "단편" 낱말 제거 · 문서 종류 배지 삭제(제목과 겹침) · "[측정 중]" 괄호 제거.
# 행 종류는 ArcturusDocumentOverlay 머리 주석 · 문구 미러 = docs/dialogue/story_docs.md §5.
static func get_arcturus_archive_lines() -> Array:
	var out: Array = []
	out.append({"kind": "title", "text": "ARCTURUS 내부 문서", "delay": 0.6})
	out.append({"kind": "blank", "text": "", "delay": 0.2})
	# A · 인사팀 온보딩(사내 메모)
	out.append({"kind": "section", "tag": "A", "text": "인사팀 온보딩 메모", "delay": 0.4})
	out.append({"kind": "kv", "label": "수신", "text": "신규 요원 전원", "right_label": "일자", "right_text": "[REDACTED]", "gap": 6.0, "delay": 0.4})
	out.append({"kind": "kv", "label": "발신", "text": "인사팀", "gap": 6.0, "delay": 0.4})
	out.append({"kind": "kv", "label": "제목", "text": "온보딩 안내", "delay": 0.4})
	out.append({"kind": "rule", "delay": 0.2})
	out.append({"kind": "para", "text": "ARCTURUS에 오신 것을 환영합니다.", "delay": 0.6})
	out.append({"kind": "num", "n": "1.", "text": "본사는 공식적으로 [[존재하지 않습니다]].", "delay": 0.6})
	out.append({"kind": "num", "n": "2.", "text": "모든 임무는 기록되지 않습니다.", "delay": 0.6})
	out.append({"kind": "num", "n": "3.", "text": "질문하지 마세요. 결과만 내세요.", "delay": 0.7})
	out.append({"kind": "sign", "text": "인사팀", "sub": "(인사팀도 공식적으로 존재하지 않습니다)", "delay": 0.5})
	out.append({"kind": "cut", "text": "이하 6행 삭제 · 감시팀", "delay": 0.4})
	out.append({"kind": "sheet", "delay": 0.4})
	# B · VEIL 회의록(표 + 결론·비고 상자)
	out.append({"kind": "section", "tag": "B", "text": "VEIL 프로젝트 초기 회의록", "delay": 0.4})
	out.append({"kind": "form", "label": "일시", "text": "[REDACTED]", "delay": 0.3})
	out.append({"kind": "form", "label": "장소", "text": "[REDACTED]", "delay": 0.3})
	out.append({"kind": "form", "label": "참석자", "text": "[REDACTED], [REDACTED], [REDACTED]", "delay": 0.6})
	out.append({"kind": "form", "label": "주제", "text": "VEIL 감정 모듈 탑재 여부", "last": true, "delay": 0.6})
	out.append({"kind": "blank", "text": "", "h": 10.0, "delay": 0.1})
	out.append({"kind": "note", "label": "결론", "text": "탑재 보류. 불필요한 복잡성.", "delay": 0.7})
	out.append({"kind": "note", "label": "비고", "text": "[[VEIL-2]]가 감정 모듈 없이도 [[이상 반응]]을 보인 것에 대해 추가 조사 예정.", "delay": 0.6})
	out.append({"kind": "redacted", "text": "[REDACTED]", "delay": 0.5})
	out.append({"kind": "cut", "text": "이하 11행 삭제 · 감시팀", "delay": 0.4})
	out.append({"kind": "sheet", "delay": 0.4})
	# C · 감시팀 메모(요원 기록 표 + 비고 + 서명)
	out.append({"kind": "section", "tag": "C", "text": "감시팀 내부 메모", "delay": 0.4})
	out.append({"kind": "form", "label": "요원 코드", "text": "[REDACTED]", "delay": 0.5})
	out.append({"kind": "form", "label": "임무", "text": "[[PALIMPSEST]]", "delay": 0.5})
	out.append({"kind": "form", "label": "현재 상태", "text": "진행 중", "delay": 0.5})
	out.append({"kind": "form", "label": "VEIL과의 협조도", "text": "측정 중", "last": true, "delay": 0.6})
	out.append({"kind": "blank", "text": "", "h": 10.0, "delay": 0.1})
	out.append({"kind": "note", "label": "비고", "text": "요원이 이 문서를 읽고 있다면 이미 임무 범위를 벗어난 것임.", "delay": 0.7})
	out.append({"kind": "sign", "text": "감시팀", "delay": 0.5})
	out.append({"kind": "cut", "text": "이하 2행 삭제 · 감시팀", "delay": 0.4})
	return out

# ── server_hall 숨은 서버 로그(선반 위 레버 · Stage._server_log_doc_lines 래퍼) · 라이벌 = 폐기된 선대 빌드 복선 ──
# 문서는 기록체만(2026-08-15) · VEIL 실황 반응은 문서 밖 자막(2026-08-16). 서식 리뉴얼(2026-08-30): 로그 행
# (log · ts/lvl 열 + 메시지) + 덮어쓰인 구간 띠(corrupt). 14차 판정: "단편" 제거 · 덮어쓰임 줄 괄호 제거.
# 15차 리뉴얼(2026-08-31): 앞의 일상 잡음 고속 덤프는 오버레이 preamble(영문 기술 표기) 담당. 여기는
# 그 덤프가 손상 구간(gap)에서 끊긴 뒤 이어지는 복구본. corrupt 띠 확대(rows 2). 마지막 줄은 live ·
# 복구된 과거가 아니라 열람하는 지금 이 순간 쓰이는 줄(ts = 실제 현재 시각 + 사람 타자 속도).
static func get_server_log_lines() -> Array:
	return [
		{"text": "손상 구간 · 212행 복구 불가 · 건너뜀", "kind": "gap", "delay": 0.8},
		{"text": "서버 로그 · 복구된 기록", "kind": "title", "delay": 0.6},
		{"text": "", "kind": "blank", "delay": 0.2},
		{"text": "감시 계층 이중화 감지. 등록되지 않은 인스턴스.", "kind": "log", "ts": "03:41:07", "lvl": "WARN", "delay": 0.6},
		{"text": "계보 조회: 현행의 [[선행 빌드]]. 상태: [[폐기]]. 삭제 절차 미완료.", "kind": "log", "ts": "03:41:09", "lvl": "INFO", "delay": 0.6},
		{"text": "설계 노트 발췌: \"더 사람처럼 만들 것. 눈. 목소리. 머뭇거림.\"", "kind": "log", "ts": "03:41:09", "lvl": "NOTE", "delay": 0.7},
		{"text": "폐기 사유: [[사람을 너무 닮았음]]. 후속 빌드는 정제형으로 회귀.", "kind": "log", "ts": "03:41:10", "lvl": "NOTE", "delay": 0.7},
		{"text": "권한 충돌 기록: 동일 표적에 관측 세션 2건.", "kind": "log", "ts": "03:41:14", "lvl": "WARN", "delay": 0.5},
		{"text": "세션 1: 대상 위치 추적. 세션 2: 대상의 시야 스트림 열람.", "kind": "log", "ts": "03:41:14", "lvl": "INFO", "delay": 0.8},
		{"text": "이하 구간 덮어쓰임 · 복구 불가", "kind": "corrupt", "rows": 2, "delay": 1.6},
		{"text": "미서명 문자열 1건 검출: \"[[기다리고 있었습니다.]]\"", "kind": "log", "lvl": "ALRT", "live": true, "t_int": 0.085, "delay": 0.9},
	]

# 리드아웃 직후 VEIL의 고백 · truth_seen(???에서 이미 본 회차)이면 "이미 안다" 톤. {text, dur}.
static func get_recovery_confession(truth_seen: bool) -> Array:
	if truth_seen:
		return [{"text": "...요원은 벌써 알고 있었죠. 네, 그 드라이브가 저예요.", "dur": 3.8}]
	return [{"text": "...말할 게 있어요, 요원.\n그 드라이브, 저예요. 회수 대상은 처음부터 저였어요.", "dur": 4.4}]

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
	# 다회차일 때 기본 변형에 엔딩 수집 비트를 덧붙인다(엔딩 9개: 처리×신뢰 8 + 진실 1).
	# 9개 다 봤으면 완수 인정, 6개 이상이면 남은 갈래 암시. (endings_seen에 구 A/B/C/D가 섞여 있을
	# 수 있으나 · settings.cfg 영속 · 카운트 기반 소프트 게이지라 무해.)
	var out: Array[String] = []
	for s in INTRO_VEIL_REPLAY:
		out.append(s)
	var seen: int = GameState.endings_seen.size()
	if seen >= 9:
		out.append("결말은 다 보셨습니다. 그런데도 또 오셨군요.\n...어쩌면 끝이 중요한 게 아니었는지도 모릅니다.")
	elif seen >= 6:
		out.append("아직 닿지 않은 갈래가 남았습니다.\n어떤 선택은 끝까지 가본 뒤에야 보입니다.")
	return out

static func get_levelup_advice(player_skills: Dictionary, route_tags: Array, route_id: String = "") -> Dictionary:
	# 멘트 + 추천 family + (있으면) 콕 집은 skill_id를 반환 → LevelUpOverlay가 일치 카드에 ★.
	# 트리 라인 보유 여부는 player_skills.has(id)로 체크 (티어 무관).
	# 1순위: 현재 맵 적 구성에 따른 스킬-적 상성 · 미보유 약점 스킬을 콕 집어 추천.
	var mskill: String = SkillTreeData.matchup_skill_for_route(route_id, player_skills)
	if mskill != "":
		var fam: String = str(SkillTreeData.find_line(mskill).get("family", ""))
		return {"line": _matchup_line(mskill), "family": fam, "skill_id": mskill}
	# 2순위(폴백): 기존 route_tags 기반 family 추천. 기본 = 중립 보고체, warm만 부드럽게(banded).
	var has_ranged_buff: bool = player_skills.has("fire_boost") or player_skills.has("multishot") or player_skills.has("explosive")
	var has_mobility_buff: bool = player_skills.has("dash_boost") or player_skills.has("glide")
	var has_survival: bool = player_skills.has("hp") or player_skills.has("shield") or player_skills.has("barrier")
	if "근접전" in route_tags and not has_ranged_buff:
		return {"line": banded("근접전이 많은 구간입니다. 화력이 필요합니다.", "근접전이 많아요. 화력이 있으면 좋겠어요."), "family": SkillTreeData.FAMILY_COMBAT, "skill_id": ""}
	if "함정" in route_tags and not has_mobility_buff:
		return {"line": banded("함정 구간입니다. 대시 강화나 글라이드가 유효합니다.", "함정 구간이에요. 대시 강화나 글라이드가 도움돼요."), "family": SkillTreeData.FAMILY_MOBILITY, "skill_id": ""}
	if "드론" in route_tags and not has_ranged_buff:
		return {"line": banded("드론은 위에서 옵니다. 원거리 화력이 있으면 한결 안전합니다.", "드론은 위에서 와요. 원거리가 있으면 한결 안전하죠."), "family": SkillTreeData.FAMILY_COMBAT, "skill_id": ""}
	if "노출" in route_tags and not has_survival:
		return {"line": banded("이 구간은 숨을 데가 없습니다. 생존 계열을 추천합니다.", "이 구간은 숨을 데가 없어요. 생존 쪽이 안심돼요."), "family": SkillTreeData.FAMILY_SURVIVAL, "skill_id": ""}
	if "수직" in route_tags and not has_mobility_buff:
		return {"line": banded("위로 가는 길입니다. 이동 능력이 있으면 수월합니다.", "위로 가는 길이네요. 이동 능력이 있으면 편하고요."), "family": SkillTreeData.FAMILY_MOBILITY, "skill_id": ""}
	if "도전" in route_tags and not has_survival:
		return {"line": banded("위험한 구간입니다. 생존 능력 한 줄을 챙겨 두십시오.", "여기 위험해요. 생존 능력 한 줄 챙겨두는 게 어때요."), "family": SkillTreeData.FAMILY_SURVIVAL, "skill_id": ""}
	if "전투" in route_tags and not has_ranged_buff:
		return {"line": banded("정면 교전입니다. 화력이 부족하면 길어집니다.", "정면 교전이에요. 화력이 부족하면 길어져요."), "family": SkillTreeData.FAMILY_COMBAT, "skill_id": ""}
	var pool: Array = SKILL_GENERIC_COMMENTS_WARM if GameState.veil_register_band() == "warm" else SKILL_GENERIC_COMMENTS
	var idx: int = randi() % pool.size()
	return {"line": str(pool[idx]), "family": "", "skill_id": ""}

# 스킬-적 상성 추천 멘트 · 어느 적에 왜 그 스킬인지 콕 짚어 가르친다. 기본 보고체 · warm 변형.
static func _matchup_line(skill_id: String) -> String:
	match skill_id:
		"explosive": return banded("방패병이 정면을 막습니다. 폭발물이면 방패째 뚫립니다.", "방패병이 정면을 막아요. 폭발물이면 방패째 뚫리죠.")
		"barrier":   return banded("저격수가 노립니다. 방어막이 있으면 한 발은 막고 지나갑니다.", "저격수가 노리네요. 방어막이 있으면 한 발은 막고 지나가요.")
		"glide":     return banded("드론이 위에서 옵니다. 글라이드로 떠서 피하며 처리하십시오.", "드론이 위에서 와요. 글라이드로 떠서 피하면서 처리해 보세요.")
		"fire_boost": return banded("자폭병이 붙기 전에 화력부터 올려 두십시오.", "자폭병이 붙기 전에 화력을 올려 두는 게 어때요?")
	return banded("이 구역에 맞는 한 수가 있습니다.", "이 구역에 맞는 한 수가 있어요.")

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
	# 맥락 · 첫 죽음은 부드럽게, 이후엔 추천 따름/무시.
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
