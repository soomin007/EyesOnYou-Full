class_name SceneRouter
extends RefCounted

const TITLE: String     = "res://scenes/title.tscn"
const TUTORIAL: String  = "res://scenes/tutorial.tscn"
const BRIEFING: String  = "res://scenes/briefing.tscn"
const ROUTE_MAP: String = "res://scenes/route_map.tscn"
const STAGE: String     = "res://scenes/stage.tscn"
# (LEVELUP 제거 · 레벨업은 levelup.tscn 씬이 아니라 LevelUpOverlay 오버레이 방식이라 미사용.
#  존재하지 않는 res://scenes/levelup.tscn을 가리키던 죽은 상수였음.)
const DEATH: String     = "res://scenes/death.tscn"
const ENDING: String    = "res://scenes/ending.tscn"
const SETTINGS: String  = "res://scenes/settings.tscn"
const CREDITS: String   = "res://scenes/credits.tscn"
# 14-2 코어 대면 터널(유사 1인칭) · 현재 연습장 프로토 진입만, 실런 배선(14-1 클리어 → 문)은 예정.
const CORE_TUNNEL: String = "res://scenes/core_tunnel.tscn"

static func go(tree: SceneTree, path: String) -> void:
	# 안전망: scene 전환 시 paused 무조건 해제 · 직전 scene의 LevelUpOverlay/도전방 fail 등에서
	# 해제 누락 시 새 scene이 freeze되는 패턴 차단.
	tree.paused = false
	# 씬 전환은 항상 deferred · 입력 전파/물리 콜백 중 동기 전환은 현재 씬을 그 자리에서
	# 트리에서 떼어내 엔진 크래시까지 간다(2026-08-20 크레딧 ESC 연타 사건, known_issues).
	tree.change_scene_to_file.call_deferred(path)

static func start_after_title(tree: SceneTree) -> void:
	if not GameState.tutorial_done:
		tree.change_scene_to_file.call_deferred(TUTORIAL)
	else:
		tree.change_scene_to_file.call_deferred(BRIEFING)
