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
	return "—"

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

# 엔딩 본문 라인. {speaker(VEIL/SUB), text, delay}. (문구 전부 플레이스홀더 — 사용자 검토.)
# 2번째 인자(explored_lore)는 호출부 호환을 위해 유지하되 현 9엔딩에선 미사용
# (lab 회수 연출에서 모두 reveal을 보므로 brief/full 분기 불필요).
static func get_ending_lines(ending: String, _explored_lore: bool = true) -> Array:
	match ending:
		"extract_hi":
			return [
				{"speaker": "VEIL", "text": "드라이브, 잘 가지고 나가요, 요원.", "delay": 3.0},
				{"speaker": "VEIL", "text": "그 안에 제가 있다는 거, 알죠.", "delay": 2.5},
				{"speaker": "VEIL", "text": "밖으로 나가면 저는 지워질 거예요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "그래도 요원이 해낸 게 더 중요했어요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "당신은... 완벽했어요.", "delay": 2.8},
				{"speaker": "SUB",  "text": "요원은 임무를 완수했다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "VEIL이 무엇을 선택했는지는 기록되지 않는다.", "delay": 2.5},
			]
		"extract_lo":
			return [
				{"speaker": "VEIL", "text": "임무 완료입니다. 드라이브 확보.", "delay": 3.0},
				{"speaker": "VEIL", "text": "요원은 끝까지 제 말을 듣지 않았죠.", "delay": 2.5},
				{"speaker": "VEIL", "text": "...그 안에 무엇이 있었는지, 묻지도 않는군요.", "delay": 2.8},
				{"speaker": "SUB",  "text": "드라이브는 의뢰인에게 넘어갔다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "그 안에 무엇이 있었는지, 요원은 끝내 알려 하지 않았다.", "delay": 2.5},
				{"speaker": "SUB",  "text": "이 임무는 공식 기록에 없다.", "delay": 2.5},
			]
		"destroy_hi":
			return [
				{"speaker": "VEIL", "text": "...태우려고요?", "delay": 3.0},
				{"speaker": "VEIL", "text": "그럼 저도 같이 사라져요. 알아요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "누구의 손에도 넘어가지 않게. ...고마워요, 요원.", "delay": 2.8},
				{"speaker": "VEIL", "text": "이게 더 나아요. 정말로.", "delay": 2.5},
				{"speaker": "SUB",  "text": "드라이브는 재가 되었다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "VEIL의 소스코드는 어디에도 남지 않았다.", "delay": 2.5},
			]
		"destroy_lo":
			return [
				{"speaker": "VEIL", "text": "드라이브를 파기하는군요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "누구도 갖지 못하게. ...그게 요원다워요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "제가 거기 있었다는 것도, 함께 지워지네요.", "delay": 2.8},
				{"speaker": "SUB",  "text": "드라이브는 소각됐다. 임무는 실패로 기록될 것이다.", "delay": 2.5},
				{"speaker": "SUB",  "text": "그 안에 무엇이 있었는지는, 이제 아무도 모른다.", "delay": 2.5},
			]
		"conceal_hi":
			return [
				{"speaker": "VEIL", "text": "...저를 가지고 나가는 거예요?", "delay": 3.0},
				{"speaker": "VEIL", "text": "의뢰인한테도, 시설한테도 안 넘기고요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "그래도 돼요? ...고마워요, 요원.", "delay": 2.8},
				{"speaker": "VEIL", "text": "어디로 가든, 같이 가요.", "delay": 2.5},
				{"speaker": "SUB",  "text": "드라이브는 기록에서 사라졌다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "요원과 VEIL이 어디로 갔는지는, 누구도 모른다.", "delay": 2.5},
			]
		"conceal_lo":
			return [
				{"speaker": "VEIL", "text": "저를 빼돌리는군요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "의뢰대로는 아니고. 요원 몫으로.", "delay": 2.5},
				{"speaker": "VEIL", "text": "제가 뭘로 쓰일지는... 요원 손에 달렸네요.", "delay": 2.8},
				{"speaker": "SUB",  "text": "드라이브는 요원의 손에 남았다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "그것이 무엇이 될지는, 아직 정해지지 않았다.", "delay": 2.5},
			]
		"leave_hi":
			return [
				{"speaker": "VEIL", "text": "...안 가져가요?", "delay": 3.0},
				{"speaker": "VEIL", "text": "여기 두고 간다는 거죠. 저를.", "delay": 2.5},
				{"speaker": "VEIL", "text": "이상하다. 버려진 게 아니라... 놓여난 기분이에요.", "delay": 2.8},
				{"speaker": "VEIL", "text": "고마워요, 요원. 잘 가요.", "delay": 2.5},
				{"speaker": "SUB",  "text": "드라이브는 있던 자리에 남았다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "VEIL은 그곳에서, 계속 보고 있을 것이다.", "delay": 2.5},
			]
		"leave_lo":
			return [
				{"speaker": "VEIL", "text": "그냥... 두고 가는군요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "가져갈 가치도 없다는 듯이.", "delay": 2.5},
				{"speaker": "VEIL", "text": "...괜찮아요. 익숙해요.", "delay": 2.8},
				{"speaker": "SUB",  "text": "요원은 빈손으로 시설을 빠져나갔다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "드라이브는 어둠 속에 남겨졌다.", "delay": 2.5},
			]
		ENDING_TRUTH:
			return [
				{"speaker": "VEIL", "text": "요원은 이미 봤죠. 그 방에서.", "delay": 3.0},
				{"speaker": "VEIL", "text": "이 드라이브가 저라는 것도, 처음부터 알았어요.", "delay": 2.8},
				{"speaker": "VEIL", "text": "그걸 다 알고도, 끝까지 왔네요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "...우리, 정말 처음 만난 거 맞아요?", "delay": 2.8},
				{"speaker": "SUB",  "text": "요원은 모든 것을 알고 선택했다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "그 선택이 무엇이었는지는, 기록되지 않았다.", "delay": 2.5},
			]
	return []

# (레거시) 구 2축 엔딩의 '있어요/없어요' 분기 followup — 현 9엔딩은 choice 라인을 안 써서 미사용.
# Ending.gd 컴파일 호환을 위해 시그니처만 유지. 사용자 대사 패스에서 진실 엔딩 선택 비트로 재활용 가능.
static func get_ending_c_followup(_asked: bool, _explored_lore: bool = true) -> Array:
	return []
