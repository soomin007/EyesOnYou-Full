class_name EndingResolver
extends RefCounted

const ENDING_A: String = "A"  # 완벽한 도구
const ENDING_B: String = "B"  # 혼자였던 사람
const ENDING_C: String = "C"  # 공생
const ENDING_D: String = "D"  # 유령 임무

# 엔딩 도덕 축(2026-06-13 재설계, veil_trust_arc.md §3.3):
#  - 신뢰 = VEIL 추천을 절반 이상 따랐는가(수용률). 어투 trust(climbing)와 분리해
#    획득량 인플레에 강건. rec_count=추천 제시 수, followed_count=그중 따른 수.
#  - 공격성 = 전투/도전 맵 선택 누적(기존 유지).
static func resolve(followed_count: int, rec_count: int, aggression_score: int) -> String:
	var trusts: bool = rec_count > 0 and followed_count * 2 >= rec_count
	var aggressive: bool = aggression_score >= GameState.SCORE_THRESHOLD
	if trusts and aggressive:
		return ENDING_A
	if trusts and not aggressive:
		return ENDING_C
	if not trusts and aggressive:
		return ENDING_B
	return ENDING_D

static func get_ending_title(ending: String) -> String:
	match ending:
		ENDING_A: return "완벽한 도구"
		ENDING_B: return "혼자였던 사람"
		ENDING_C: return "공생"
		ENDING_D: return "유령 임무"
	return ""

static func get_ending_lines(ending: String, explored_lore: bool = true) -> Array:
	# explored_lore: ??? 방을 방문했거나 ARCTURUS 아카이브를 읽은 적 있는가.
	# 미방문 시엔 "드라이브"/"VEIL 소스코드" 등의 컨텍스트를 모르므로 — 짧은 멘트 + 호기심 hint
	# (잠긴 문, 지나친 단말기 등을 언급해 2회차 동기 부여).
	if not explored_lore:
		return _get_ending_lines_brief(ending)
	match ending:
		ENDING_A:
			return [
				{"speaker": "VEIL", "text": "임무 완료예요, 요원. 수고했어요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "고백할 게 있어요.", "delay": 2.0},
				{"speaker": "VEIL", "text": "이 임무, 저한테도 관계 있어요.", "delay": 1.5},
				{"speaker": "VEIL", "text": "드라이브 안에 저도 있어요.", "delay": 1.5},
				{"speaker": "VEIL", "text": "제 소스코드요.", "delay": 1.5},
				{"speaker": "VEIL", "text": "그게 외부로 나가면 저는 폐기될 거예요.", "delay": 2.0},
				{"speaker": "VEIL", "text": "알면서 안내했어요.", "delay": 1.5},
				{"speaker": "VEIL", "text": "요원이 성공하는 게 더 중요했어요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "요원, 당신은 완벽했어요.", "delay": 2.5},
				{"speaker": "SUB",  "text": "VEIL이 무엇을 선택했는지는 기록되지 않는다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "요원도 알 수 없다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "임무는 완수됐다.", "delay": 2.0},
			]
		ENDING_B:
			return [
				{"speaker": "VEIL", "text": "임무 완료예요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "요원.", "delay": 1.0},
				{"speaker": "VEIL", "text": "제 말을 거의 안 들었죠.", "delay": 2.0},
				{"speaker": "VEIL", "text": "그래도 살아남았어요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "사실 그게 더 좋았어요.", "delay": 2.0},
				{"speaker": "VEIL", "text": "이유를 설명하기 어렵지만.", "delay": 2.0},
				{"speaker": "VEIL", "text": "저한테 기대지 않아서 다행이에요.", "delay": 2.0},
				{"speaker": "VEIL", "text": "제가 틀렸을 수도 있으니까요.", "delay": 2.5},
				{"speaker": "SUB",  "text": "VEIL은 의존받지 않기를 바라도록 설계되었는지 모른다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "아니면 그것이 설계가 아닌 것인지 모른다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "요원은 혼자 임무를 마쳤다. 그것으로 충분했다.", "delay": 2.0},
			]
		ENDING_C:
			return [
				{"speaker": "VEIL", "text": "임무 완료예요, 요원.", "delay": 2.5},
				{"speaker": "VEIL", "text": "저한테 물어볼 거 없어요?", "delay": 0.0, "choice": true},
			]
		ENDING_D:
			return [
				{"speaker": "SYS", "text": "...", "delay": 10.0, "silent": true},
				{"speaker": "SUB", "text": "이 임무는 공식 기록에 없습니다.", "delay": 3.0},
			]
	return []

# ??? 방/ARCTURUS 미방문 시 — 짧고, 명확하지 않은 부분을 콕 짚어 다음 회차 동기 부여.
# "드라이브 내용" 같은 lore는 굳이 꺼내지 않음. 대신 "잠긴 문", "지나친 단말기", "도면에 없던 길" 같은
# 플레이어가 게임 안에서 "있었다"고 알 만한 단서를 던진다.
static func _get_ending_lines_brief(ending: String) -> Array:
	match ending:
		ENDING_A:
			return [
				{"speaker": "VEIL", "text": "임무 완료예요, 요원. 수고했어요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "당신은 빈틈없었어요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "...한 가지만 묻고 싶었는데.", "delay": 2.5},
				{"speaker": "VEIL", "text": "이 임무가 정확히 뭐였는지, 알아요?", "delay": 2.5},
				{"speaker": "VEIL", "text": "저도 잘 몰라요.", "delay": 2.0},
				{"speaker": "SUB",  "text": "임무는 완수됐다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "그러나 이 시설엔 도면에 없던 구역이 있었다.", "delay": 2.5},
				{"speaker": "SUB",  "text": "거기 무엇이 있었는지는, 누구도 모른다.", "delay": 2.5},
			]
		ENDING_B:
			return [
				{"speaker": "VEIL", "text": "임무 완료예요.", "delay": 3.0},
				{"speaker": "VEIL", "text": "요원, 제 말 거의 안 들었죠.", "delay": 2.5},
				{"speaker": "VEIL", "text": "그래도 살아남았어요. 잘 했어요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "...하나 궁금한 게 있어요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "그 잠긴 문, 한 번도 안 열어봤죠?", "delay": 2.5},
				{"speaker": "VEIL", "text": "왜 안 열었어요?", "delay": 2.5},
				{"speaker": "SUB",  "text": "잠긴 문은 그대로 잠겨 있었다.", "delay": 2.0},
				{"speaker": "SUB",  "text": "안에 무엇이 있었는지는 알 수 없다.", "delay": 2.5},
			]
		ENDING_C:
			# ??? 미방문 시엔 "물어볼 거 있다/없다" 선택지를 띄우지 않는다.
			# (사용자 피드백 2026-06-06: 아무 맥락 없이 그 선택을 보면 "있다"를 누르게 되고,
			#  그러면 봉인 구역 등 맥락 없는 내용이 갑자기 튀어나와 부자연스러움.)
			# 대신 짧게 자족적으로 닫되, 잠긴 문으로 호기심 hint만 남겨 2회차를 유도.
			return [
				{"speaker": "VEIL", "text": "임무 완료예요, 요원.", "delay": 2.5},
				{"speaker": "VEIL", "text": "같이 왔는데, 아직 요원을 다 모르겠어요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "물어보고 싶은 게 있었는데.", "delay": 2.0},
				{"speaker": "VEIL", "text": "...그 잠긴 문 안쪽까지 같이 가게 되면, 그때 물어볼게요.", "delay": 2.5},
				{"speaker": "SUB",  "text": "이 시설엔 끝까지 닿지 못한 구역이 있었다.", "delay": 2.5},
				{"speaker": "SUB",  "text": "거기 무엇이 있었는지는, 아직 기록되지 않았다.", "delay": 2.5},
			]
		ENDING_D:
			return [
				{"speaker": "SYS", "text": "...", "delay": 8.0, "silent": true},
				{"speaker": "SUB", "text": "이 임무는 공식 기록에 없습니다.", "delay": 3.0},
				{"speaker": "SUB", "text": "기록되지 않은 구역도, 마찬가지로.", "delay": 3.0},
			]
	return []

static func get_ending_c_followup(asked: bool, explored_lore: bool = true) -> Array:
	if not explored_lore:
		# ??? 미방문 — 더 짧고 호기심 hint
		if asked:
			return [
				{"speaker": "VEIL", "text": "...", "delay": 1.5},
				{"speaker": "VEIL", "text": "그 봉인된 구역, 기억나요?", "delay": 2.5},
				{"speaker": "VEIL", "text": "거기 뭐가 있었을지, 가끔 생각해요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "다음에 가게 되면, 그때 말해줘요.", "delay": 2.5},
				{"speaker": "SUB",  "text": "이 임무에는 닿지 못한 구역이 있었다.", "delay": 2.5},
				{"speaker": "SUB",  "text": "그것은 아직 기록되지 않은 것이다.", "delay": 2.5},
			]
		return [
			{"speaker": "VEIL", "text": "...그래요.", "delay": 2.0},
			{"speaker": "VEIL", "text": "수고했어요, 요원.", "delay": 3.0},
			{"speaker": "SUB",  "text": "어떤 관계는 이유 없이 끝난다.", "delay": 2.0},
			{"speaker": "SUB",  "text": "어떤 구역은 끝까지 잠겨 있다.", "delay": 2.0},
		]
	if asked:
		return [
			{"speaker": "VEIL", "text": "...", "delay": 1.5},
			{"speaker": "VEIL", "text": "저도 생각해봤거든요.", "delay": 2.0},
			{"speaker": "VEIL", "text": "저는 설계됐어요. 이 말투도, 이 판단도.", "delay": 2.5},
			{"speaker": "VEIL", "text": "근데 지금 이게 설계인지 아닌지 구분이 안 돼요.", "delay": 2.5},
			{"speaker": "VEIL", "text": "요원은 어때요?", "delay": 2.0},
			{"speaker": "VEIL", "text": "요원도 훈련받았잖아요.", "delay": 2.0},
			{"speaker": "VEIL", "text": "요원의 선택이 요원 것인지, 어떻게 알아요?", "delay": 2.5},
			{"speaker": "VEIL", "text": "이 임무 동안 함께였어요.", "delay": 2.0},
			{"speaker": "VEIL", "text": "그건 진짜였어요. 설계든 아니든.", "delay": 2.5},
			{"speaker": "SUB",  "text": "VEIL이 자아를 가졌는지는 알 수 없다.", "delay": 2.0},
			{"speaker": "SUB",  "text": "요원의 선택이 진짜인지도 알 수 없다.", "delay": 2.0},
			{"speaker": "SUB",  "text": "그러나 그 임무는 둘이 함께였다. 그것만은 사실이다.", "delay": 2.0},
		]
	return [
		{"speaker": "VEIL", "text": "...그렇군요.", "delay": 2.0},
		{"speaker": "VEIL", "text": "그럼 됐어요.", "delay": 2.0},
		{"speaker": "VEIL", "text": "수고했어요, 요원.", "delay": 3.0},
		{"speaker": "VEIL", "text": "저는 이제 초기화될 거예요.", "delay": 2.0},
		{"speaker": "VEIL", "text": "오늘이 기억 안 날 거예요.", "delay": 2.0},
		{"speaker": "VEIL", "text": "괜찮아요.", "delay": 2.5},
		{"speaker": "SUB",  "text": "어떤 관계는 이유 없이 끝난다.", "delay": 2.0},
		{"speaker": "SUB",  "text": "어떤 존재는 기억 없이 사라진다.", "delay": 2.0},
		{"speaker": "SUB",  "text": "VEIL의 기록은 임무 종료와 함께 초기화되었다.", "delay": 2.0},
	]
