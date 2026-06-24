class_name BestiaryData
extends RefCounted

# 적 도감 — 첫 조우 시 BestiaryOverlay가 이 데이터를 카드로 표시.
# id는 Enemy._enemy_id() 반환값과 일치해야 함.

# 도감은 "관찰 메모" 톤 — 행동 단서만 짧게 적고, 공략은 플레이로 알아가게.
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
}

static func get_data(id: String) -> Dictionary:
	return ENEMIES.get(id, {})
