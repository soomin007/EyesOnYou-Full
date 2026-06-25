class_name GameInfo
extends RefCounted

# 패치노트 + 로딩 팁의 단일 소스.
# - 패치노트: Title 화면 "최근 업데이트" 패널이 최신 1건을 표시. 메인 메뉴 "업데이트 내역"에서
#   역대 패치를 좌측 목록으로 골라 우측 패널에 펼쳐볼 수 있다(Title.STATE_PATCHNOTES).
# - 팁: 맵 진입 브리핑에서 1개씩 로테이션(피드백 "게임이 안 알려준다" 보완).
# 새 내용은 여기 배열에만 추가하면 UI가 자동 반영(하드코딩 분산 금지).
# 표시 텍스트라 em dash(—) 금지 — 쉼표/마침표/가운뎃점(·)으로.

# 최신순(맨 위가 최신). date = 표시용, items = 변경점 줄.
const PATCH_NOTES: Array = [
	{
		"date": "2026-06-25",
		"title": "키 설정 안내",
		"items": [
			"키 설정 안내 보강. 화면에 안 보이는 기본 보조 키(점프 Z·↑, 사격 좌클릭 등)도 함께 작동해요.",
		],
	},
	{
		"date": "2026-06-24",
		"title": "조작 개편",
		"items": [
			"키보드 조작 정리 — 이동 WASD/화살표, 점프 W·Space·Z·↑, 사격 J/X, 대시 K/C, 스킬 L/V",
			"키는 설정 > 키 설정에서 자유롭게 바꿀 수 있어요",
			"점프 손맛 개선 — 가장자리에서도 점프가 정확히 나가고, 착지 직전 입력도 먹혀요",
			"외벽 옥상·감시탑 등반 난이도 완화 — 더블점프로 여유있게 오르도록 발판 재배치",
		],
	},
]

# 맵 진입 시 1개씩 보여줄 팁. 조작·전략·세계관 힌트(피드백 반영).
const TIPS: Array = [
	"점프는 W·Space·Z·↑ 무엇이든. 더블점프로 한 번 더 뛰어 높은 곳까지 닿아요.",
	"조작 키가 불편하면 설정 > 키 설정에서 바꿀 수 있어요.",
	"모든 적과 싸울 필요는 없어요. 길만 열면 지나가도 됩니다.",
	"방패병은 정면 총알이 막혀요. 폭발물(L · 마우스 우클릭)로 처치하세요.",
	"저격수 둥지는 못 잡아도 괜찮아요. 사선만 피해 지나가면 돼요.",
	"레벨업 카드의 ★는 지금 이 맵에 유리한 추천이에요.",
	"대시(K · C)로 적의 공격을 빠르게 피할 수 있어요.",
	"엔딩은 하나가 아니에요. 다른 길을 택해 다시 플레이해보세요.",
	"드론은 공중을 떠다녀요. 활강·점프로 높이를 맞춰 노리세요.",
	"맵 선택의 권장 스킬 칩을 보면 어떤 적이 나올지 가늠할 수 있어요.",
]

# 가장 최근 패치 1건(Title 패널용). 없으면 빈 Dictionary.
static func latest_patch() -> Dictionary:
	if PATCH_NOTES.is_empty():
		return {}
	var first: Dictionary = PATCH_NOTES[0]
	return first

# 팁 1개 — index로 결정적 선택(맵마다 다르게 돌리되 Math.random 없이).
static func tip_at(index: int) -> String:
	if TIPS.is_empty():
		return ""
	var i: int = index % TIPS.size()
	var t: String = TIPS[i]
	return t
