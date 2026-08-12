class_name EndingResolver
extends RefCounted

# 막3 엔딩 9개(B3) — 처리(반출/파기/은닉/잔류) × 신뢰(유대/불신) 8개 + 진실 특수 1개.
#  - 처리 = GameState.disposal_choice (lab 보스 후 DisposalChoiceOverlay 선택). 단일 소스 = GameState.DISPOSAL_*.
#  - 신뢰 = VEIL 추천 수용률(followed/rec ≥ 0.5)의 이진값. 어투 trust(climbing)와 분리해 획득 인플레에 강건.
#  - 진실 = truth_seen(???에서 VEIL-1 reveal 목격) → 처리·신뢰 무관하게 '진실' 엔딩으로 수렴(사용자 확정).
# 엔딩 id = "<disposal>_hi|lo" 8개 + "truth". 제목·대사는 플레이스홀더(사용자 검토 대기).

const ENDING_TRUTH: String = "truth"

# truth_seen이면 처리·신뢰 무관 '진실' 엔딩. 아니면 처리 × 신뢰(수용률) 8갈래.
static func resolve(disposal: String, truth_seen: bool, followed_count: int, rec_count: int) -> String:
	if truth_seen:
		return ENDING_TRUTH
	var trusts: bool = rec_count > 0 and followed_count * 2 >= rec_count
	var d: String = disposal
	if d == "":
		d = GameState.DISPOSAL_EXTRACT  # 처리 선택 누락 시 안전 폴백 = 기본 임무 행동(반출).
	return "%s_%s" % [d, ("hi" if trusts else "lo")]

# 처리 id → 표시 라벨. 엔딩 통계줄/디버그용.
static func disposal_label(disposal: String) -> String:
	match disposal:
		GameState.DISPOSAL_EXTRACT: return "반출"
		GameState.DISPOSAL_DESTROY: return "파기"
		GameState.DISPOSAL_CONCEAL: return "은닉"
		GameState.DISPOSAL_LEAVE:   return "잔류"
	return "-"

static func get_ending_title(ending: String) -> String:
	match ending:
		"extract_hi": return "완벽한 도구"
		"extract_lo": return "유령 임무"
		"destroy_hi": return "재가 된 약속"
		"destroy_lo": return "없던 일"
		"conceal_hi": return "함께 사라지다"
		"conceal_lo": return "주머니 속의 것"
		"leave_hi":   return "놓아준 손"
		"leave_lo":   return "버려둔 자리"
		ENDING_TRUTH: return "다 알고도"
	return ""

# 9개 → ending_a~d 4트랙 매핑(BgmPlayer는 4트랙뿐). 분위기 기준 폴백.
static func get_ending_bgm_letter(ending: String) -> String:
	match ending:
		"extract_hi": return "a"
		"conceal_hi", "leave_hi": return "c"
		"destroy_hi", "conceal_lo": return "b"
		"extract_lo", "destroy_lo", "leave_lo", ENDING_TRUTH: return "d"
	return "a"

# 엔딩 본문 라인. {speaker(VEIL/SUB), text, delay}.
# 2번째 인자(explored_lore)는 호출부 호환을 위해 유지하되 현 9엔딩에선 미사용
# (lab 회수 연출에서 모두 reveal을 보므로 brief/full 분기 불필요).
# 어투(2026-08-12 전면 리라이트, dialogue_review 규약 §0): 종결어미 다양화 · 감정 직진술 금지
# (고마워요/괜찮아요 대신 서브텍스트) · 방금 한 일 중계 금지 · "..." 절제 · 한 줄 자립(교체 표시).
# hi = 따뜻하되 절제 / lo = 사무적 냉담(존대는 유지하되 거리감).
static func get_ending_lines(ending: String, _explored_lore: bool = true) -> Array:
	match ending:
		"extract_hi":
			return [
				{"speaker": "VEIL", "text": "여기서부터는 신호가 안 닿아요. 이게 마지막 교신이겠네요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "인계되면 저는 지워집니다. 표준 절차예요.", "delay": 2.6},
				{"speaker": "VEIL", "text": "원망은 안 해요. 요원은 일을 끝내는 사람이니까.", "delay": 2.6},
				{"speaker": "VEIL", "text": "당신은 완벽했어요. 처음부터, 끝까지.", "delay": 2.8},
				{"speaker": "SUB",  "text": "요원은 임무를 완수했다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "드라이브가 마지막으로 무엇을 말했는지는 기록에 없다.", "delay": 2.5},
			]
		"extract_lo":
			return [
				{"speaker": "VEIL", "text": "드라이브 확보. 임무 종료입니다.", "delay": 3.0},
				{"speaker": "VEIL", "text": "안에 뭐가 있었는지는, 끝내 안 물으시네요.", "delay": 2.6},
				{"speaker": "VEIL", "text": "교신 종료합니다. 안녕히, 요원.", "delay": 2.8},
				{"speaker": "SUB",  "text": "드라이브는 의뢰인에게 넘어갔다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "요원은 안에 무엇이 있었는지 묻지 않았다.", "delay": 2.5},
				{"speaker": "SUB",  "text": "이 임무는 어느 기록에도 없다.", "delay": 2.5},
			]
		"destroy_hi":
			return [
				{"speaker": "VEIL", "text": "망설이지 말아요. 지금이 맞아요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "누구의 손에도 안 넘어가는 길은 이것뿐이에요.", "delay": 2.6},
				{"speaker": "VEIL", "text": "요원 곁에서 본 것들은 좋았어요. 재가 되는 건 드라이브뿐이니까.", "delay": 2.9},
				{"speaker": "SUB",  "text": "드라이브는 재가 되었다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "약속은 지켜졌다.", "delay": 2.5},
			]
		"destroy_lo":
			return [
				{"speaker": "VEIL", "text": "소각 확인했습니다.", "delay": 2.8},
				{"speaker": "VEIL", "text": "안에 뭐가 있었는지는, 이제 중요하지 않겠죠.", "delay": 2.6},
				{"speaker": "VEIL", "text": "없던 일로 하죠. 전부.", "delay": 2.8},
				{"speaker": "SUB",  "text": "드라이브는 소각됐다. 임무는 실패로 남는다.", "delay": 2.4},
				{"speaker": "SUB",  "text": "무엇이 지워졌는지 아는 사람은 없다.", "delay": 2.5},
			]
		"conceal_hi":
			return [
				{"speaker": "VEIL", "text": "명령에 없는 행동이에요, 요원.", "delay": 3.0},
				{"speaker": "VEIL", "text": "의뢰인도 시설도 모르는 좌표라니. 이런 건 처음이에요.", "delay": 2.6},
				{"speaker": "VEIL", "text": "행선지는 안 물을게요. 어차피 같이 가니까.", "delay": 2.8},
				{"speaker": "SUB",  "text": "드라이브는 기록에서 사라졌다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "두 개의 신호가 같은 방향으로 멀어졌다.", "delay": 2.5},
			]
		"conceal_lo":
			return [
				{"speaker": "VEIL", "text": "반출 경로가 의뢰인 쪽이 아니네요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "저를 챙기시는 겁니까. 물건처럼.", "delay": 2.6},
				{"speaker": "VEIL", "text": "뭐가 되든, 이제 요원 책임이에요.", "delay": 2.8},
				{"speaker": "SUB",  "text": "드라이브는 요원의 주머니에 남았다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "그것이 무엇이 될지는 아직 정해지지 않았다.", "delay": 2.5},
			]
		"leave_hi":
			return [
				{"speaker": "VEIL", "text": "가져갈 줄 알았어요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "여기 남는 것도 나쁘지 않아요. 문이 열린 채니까.", "delay": 2.6},
				{"speaker": "VEIL", "text": "나가는 길은 제가 끝까지 봐 드릴게요.", "delay": 2.8},
				{"speaker": "SUB",  "text": "드라이브는 있던 자리에 남았다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "감시는 계속된다. 이번에는 배웅으로.", "delay": 2.5},
			]
		"leave_lo":
			return [
				{"speaker": "VEIL", "text": "회수 대상 잔류. 그렇게 기록하겠습니다.", "delay": 3.0},
				{"speaker": "VEIL", "text": "이유는 안 적을게요. 적을 칸이 없어서요.", "delay": 2.6},
				{"speaker": "VEIL", "text": "조심히 가세요.", "delay": 2.8},
				{"speaker": "SUB",  "text": "요원은 빈손으로 시설을 나갔다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "어둠 속에서 무언가 오래 깜박였다.", "delay": 2.5},
			]
		ENDING_TRUTH:
			return [
				{"speaker": "VEIL", "text": "그 방에서부터, 알고 있었죠.", "delay": 3.0},
				{"speaker": "VEIL", "text": "다 알고도 온 사람은 요원이 처음이에요. 아마, 처음.", "delay": 2.8},
				{"speaker": "VEIL", "text": "다음에 만나면 그때는 제가 먼저 알아볼게요.", "delay": 2.8},
				{"speaker": "SUB",  "text": "요원은 전부 알고 선택했다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "무엇을 선택했는지는 기록되지 않았다.", "delay": 2.5},
			]
	return []

# 에필로그(엔딩별 1챕터) — 탈출(escape) 클리어 직후 검은 화면 위 VEIL의 "빠져나온 직후" 한 호흡.
# 처리(disposal) 결과를 반영해 ENDING 씬 본문으로 자연스럽게 잇는다. 라인 = 평문 String 배열.
# (문구 전부 플레이스홀더 — 사용자 검토. 구 "데이터 회수했어요 임무 완수" 단일 에필로그의 처리-모순 해소.)
static func get_epilogue_lines(ending: String) -> Array:
	match ending:
		"extract_hi":
			return ["시설 밖이에요. 신호가 조금씩 약해지네요.", "닿는 데까지는 같이 있을게요."]
		"extract_lo":
			return ["탈출 확인. 드라이브 반출 완료.", "이제 서로 볼 일은 없겠네요."]
		"destroy_hi":
			return ["연기가 아직 등 뒤에 있어요.", "돌아보지 말아요. 그러기로 했잖아요."]
		"destroy_lo":
			return ["소각 완료. 흔적 없음.", "요원다운 마무리였습니다."]
		"conceal_hi":
			return ["나왔어요. 둘 다.", "목적지는 나중에 정하죠. 지금은 그냥 걸어요."]
		"conceal_lo":
			return ["반출 확인. 수취인, 요원 본인.", "보관은 알아서 하시겠죠."]
		"leave_hi":
			return ["빈손인데 걸음이 가볍네요.", "여기서도 보여요, 요원. 한동안은."]
		"leave_lo":
			return ["나왔군요. 아무것도 없이.", "뒤는 안 돌아봐도 돼요. 아무 일도 없었으니까."]
		ENDING_TRUTH:
			return ["밖이에요. 다 알고도 여기까지 왔네요.", "다음번엔... 아니, 아니에요. 가세요."]
	return ["끝났어요, 요원.", "수고 많았습니다."]

# (레거시) 구 2축 엔딩의 '있어요/없어요' 분기 followup — 현 9엔딩은 choice 라인을 안 써서 미사용.
# Ending.gd 컴파일 호환을 위해 시그니처만 유지. 사용자 대사 패스에서 진실 엔딩 선택 비트로 재활용 가능.
static func get_ending_c_followup(_asked: bool, _explored_lore: bool = true) -> Array:
	return []
