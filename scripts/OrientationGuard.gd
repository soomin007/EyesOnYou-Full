extends Node

# 모바일 웹에서 가로 화면을 유도/강제하는 전역 가드(autoload).
#
# 왜 필요한가: project.godot의 window/handheld/orientation은 *네이티브* 빌드에만 먹고, 모바일 웹
# 브라우저는 이를 무시하고 기기 방향을 따른다. 그래서 웹에서 가로를 보장하려면 런타임 처리가 필요하다.
#
# 두 가지를 한다:
#  1) 세로(portrait)일 때 모든 화면(타이틀·메뉴·인게임 공통) 위에 "가로로 돌려주세요" 안내를 띄운다.
#  2) 웹이면 첫 사용자 제스처(터치/클릭)에 fullscreen + screen.orientation.lock('landscape')을 시도한다.
#     안드로이드 크롬 등에서 가로가 자동 잠긴다. iOS Safari는 orientation lock 미지원이라 1)의 안내 +
#     물리적 회전에 의존한다.

const FONT_PATH: String = "res://assets/fonts/Pretendard-Regular.otf"

var _layer: CanvasLayer = null
var _card: Control = null
var _font: Font = null
var _portrait: bool = false
var _lock_tried: bool = false

# 그리기 전용 Control — CanvasLayer는 _draw가 없어 자식 Control의 _draw에서 host._render를 부른다.
class _Card extends Control:
	var host: Object = null
	func _draw() -> void:
		if host != null and host.has_method("_render"):
			host.call("_render", self)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	if _font == null:
		_font = ThemeDB.fallback_font
	_layer = CanvasLayer.new()
	_layer.layer = 128  # 최상위 — 어떤 오버레이(일시정지·레벨업·연습장)보다도 위
	add_child(_layer)
	_card = _Card.new()
	_card.host = self
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_card)
	_refresh()
	get_viewport().size_changed.connect(_refresh)

func _refresh() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_portrait = vs.y > vs.x
	if _card != null:
		_card.position = Vector2.ZERO
		_card.size = vs
		_card.visible = _portrait
		_card.queue_redraw()

func _input(event: InputEvent) -> void:
	# 브라우저는 사용자 제스처 핸들러 안에서만 fullscreen/orientation lock을 허용한다 → 첫 입력에 1회 시도.
	if _lock_tried:
		return
	var pressed: bool = false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	if pressed:
		_lock_tried = true
		_try_web_landscape()

func _try_web_landscape() -> void:
	if not OS.has_feature("web"):
		return
	# canvas를 풀스크린으로 만든 뒤 가로로 잠근다. 실패(iOS 등)는 조용히 무시.
	var js: String = """
	(function(){
	  try {
	    var lock = function(){
	      if (screen.orientation && screen.orientation.lock) {
	        screen.orientation.lock('landscape').catch(function(){});
	      }
	    };
	    var c = document.querySelector('canvas');
	    if (c && c.requestFullscreen) { c.requestFullscreen().then(lock).catch(lock); }
	    else { lock(); }
	  } catch(e) {}
	})();
	"""
	JavaScriptBridge.eval(js, true)

func _render(card: Control) -> void:
	var vs: Vector2 = card.size
	card.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.04, 0.05, 0.98))
	if _font == null:
		return
	var msg: String = "기기를 가로로 돌려주세요"
	card.draw_string(_font, Vector2(0.0, vs.y * 0.5), msg, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 40, Color(0.86, 0.92, 1.0, 0.96))
	var sub: String = "화면 회전 잠금이 켜져 있으면 꺼주세요"
	card.draw_string(_font, Vector2(0.0, vs.y * 0.5 + 46.0), sub, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 22, Color(0.62, 0.72, 0.82, 0.9))
