class_name SceneRouter
extends RefCounted

const TITLE: String     = "res://scenes/title.tscn"
const TUTORIAL: String  = "res://scenes/tutorial.tscn"
const BRIEFING: String  = "res://scenes/briefing.tscn"
const ROUTE_MAP: String = "res://scenes/route_map.tscn"
const STAGE: String     = "res://scenes/stage.tscn"
# (LEVELUP 제거 — 레벨업은 levelup.tscn 씬이 아니라 LevelUpOverlay 오버레이 방식이라 미사용.
#  존재하지 않는 res://scenes/levelup.tscn을 가리키던 죽은 상수였음.)
const DEATH: String     = "res://scenes/death.tscn"
const ENDING: String    = "res://scenes/ending.tscn"
const SETTINGS: String  = "res://scenes/settings.tscn"
const CREDITS: String   = "res://scenes/credits.tscn"

static func go(tree: SceneTree, path: String) -> void:
	# 안전망: scene 전환 시 paused 무조건 해제 — 직전 scene의 LevelUpOverlay/도전방 fail 등에서
	# 해제 누락 시 새 scene이 freeze되는 패턴 차단.
	tree.paused = false
	tree.change_scene_to_file(path)

static func start_after_title(tree: SceneTree) -> void:
	if not GameState.tutorial_done:
		tree.change_scene_to_file(TUTORIAL)
	else:
		tree.change_scene_to_file(BRIEFING)
