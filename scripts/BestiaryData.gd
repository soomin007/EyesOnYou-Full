class_name BestiaryData
extends RefCounted

# 적 도감 · 첫 조우 시 BestiaryOverlay가 이 데이터를 카드로 표시.
# id는 Enemy._enemy_id() 반환값과 일치해야 함.

# 도감은 "관찰 메모" 톤 · 행동 단서만 짧게 적고, 공략은 플레이로 알아가게.
# (사용자 디자인 방향: 글로 명시 설명 < 체험으로 체득)
const ENEMIES: Dictionary = {
	"patrol": {
		"name": "정찰병",
		"blurb": "좌우 순찰. 중거리에선 멈춰서 사격(노란 점멸), 가까이 가면 머리 LED가 붉게 깜빡이며 돌진한다.",
	},
	"sniper": {
		"name": "저격수",
		"blurb": "한 자리에 박혀 붉은 조준선을 쏜다. 시야가 끊기면 사격이 취소된다.",
	},
	"drone": {
		"name": "공습 드론",
		"blurb": "공중에서 머리 위로 따라온다. 그림자를 본다.",
	},
	"bomber": {
		"name": "자폭병",
		"blurb": "느리게 배회. 시야에 들면 따라붙고, 빨갛게 깜빡인다.",
	},
	"shield": {
		"name": "방패병",
		"blurb": "정면에 큰 방패. 정면 사격은 튕겨낸다.",
	},
	"jammer": {
		"name": "교란기",
		"blurb": "고정된 방출 장치. 바이올렛 반경 안에선 VEIL의 표시가 꺼진다. 부수면 시야가 돌아온다.",
	},
	"caller": {
		"name": "호출병",
		"blurb": "직접 싸우지 않는다. 안테나에 신호가 퍼지면 곧 증원이 온다. 불려 온 병력은 잡아도 얻는 게 없다. 먼저 끊는 쪽이 이득.",
	},
	# 엘리트(라이벌의 군대) · 타입 무관 단일 카드. 첫 조우 시 기반 타입 카드가 우선(Enemy._check_first_encounter).
	"elite": {
		"name": "강화 개체",
		"blurb": "보랏빛 계급장을 단 개체. 다른 신호를 받는다. 더 빠르고, 더 오래 버틴다. 상대하는 법은 같다.",
	},
}

static func get_data(id: String) -> Dictionary:
	return ENEMIES.get(id, {})
