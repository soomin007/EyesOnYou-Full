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
var _touch_cached: int = -1  # -1 미판정, 0 아님, 1 터치 기기
# [임시 진단] 웹에서 수집한 터치 지원 값 — 화면 상단 DBG 바에 표시.
var _dbg_maxtouch: int = -1
var _dbg_ontouch: int = -1

# 터치 기기 여부(캐시). Stage/Main의 터치 UI 게이팅이 이걸 쓴다.
# DisplayServer.is_touchscreen_available()은 모바일 *웹*에서 false를 흔히 반환하므로(알려진 문제),
# 웹이면 navigator.maxTouchPoints/ontouchstart로 직접 확인한다.
func is_touch_device() -> bool:
	if _touch_cached == -1:
		_touch_cached = 1 if _detect_touch() else 0
	return _touch_cached == 1

func _detect_touch() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	if OS.has_feature("web"):
		var r: Variant = JavaScriptBridge.eval("(('ontouchstart' in window)||((navigator.maxTouchPoints||0)>0))?1:0", true)
		if r != null:
			return int(r) == 1
	return false

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
	# [임시 진단] 웹 터치/방향 값을 1회 수집(maxTouchPoints 등은 안 변함). 진단 끝나면 제거.
	if OS.has_feature("web"):
		var a: Variant = JavaScriptBridge.eval("(navigator.maxTouchPoints||0)", true)
		_dbg_maxtouch = int(a) if a != null else -1
		var b: Variant = JavaScriptBridge.eval("('ontouchstart' in window)?1:0", true)
		_dbg_ontouch = int(b) if b != null else -1
	_refresh()
	get_viewport().size_changed.connect(_refresh)

# [임시 진단] 매 프레임 진단 텍스트를 갱신(lock/scene 상태 변화 반영). 진단 끝나면 _process 제거.
func _process(_delta: float) -> void:
	if _card != null:
		_card.queue_redraw()

func _refresh() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_portrait = vs.y > vs.x
	if _card != null:
		_card.position = Vector2.ZERO
		_card.size = vs
		_card.visible = true  # [임시 진단] 진단 바를 항상 보이게(원래는 _portrait). 진단 끝나면 되돌리기.
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
	# documentElement를 풀스크린으로 만든 뒤 가로로 잠근다(canvas 요소 선택 실패를 피함).
	# 실패(iOS Safari 등 orientation.lock 미지원)는 조용히 무시 — 세로 안내로 폴백.
	var js: String = """
	(function(){
	  var lock = function(){
	    try { if (screen.orientation && screen.orientation.lock) { screen.orientation.lock('landscape').catch(function(){}); } } catch(e){}
	  };
	  try {
	    var el = document.documentElement;
	    var req = el.requestFullscreen || el.webkitRequestFullscreen || el.mozRequestFullScreen;
	    if (req) {
	      var p = req.call(el);
	      if (p && p.then) { p.then(lock).catch(lock); } else { lock(); }
	    } else { lock(); }
	  } catch(e) { lock(); }
	})();
	"""
	JavaScriptBridge.eval(js, true)

func _render(card: Control) -> void:
	var vs: Vector2 = card.size
	# 세로일 때만 풀스크린 어둠 + "가로로 돌려주세요" 안내.
	if _portrait:
		card.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.04, 0.05, 0.98))
		if _font != null:
			var msg: String = "기기를 가로로 돌려주세요"
			card.draw_string(_font, Vector2(0.0, vs.y * 0.5), msg, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 40, Color(0.86, 0.92, 1.0, 0.96))
			var sub: String = "화면 회전 잠금이 켜져 있으면 꺼주세요"
			card.draw_string(_font, Vector2(0.0, vs.y * 0.5 + 46.0), sub, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 22, Color(0.62, 0.72, 0.82, 0.9))
	# [임시 진단] 화면 상단에 항상 표시 — 사용자가 읽어주면 원인 확정. 진단 끝나면 이 블록 삭제.
	if _font != null:
		var scn: Node = get_tree().current_scene
		var sn: String = scn.name if scn != null else "?"
		var l1: String = "DBG web=%s touch=%s maxT=%d ots=%d" % [str(OS.has_feature("web")), str(is_touch_device()), _dbg_maxtouch, _dbg_ontouch]
		var l2: String = "vp=%dx%d P=%s lock=%s scene=%s" % [int(vs.x), int(vs.y), str(_portrait), str(_lock_tried), sn]
		card.draw_rect(Rect2(0.0, 0.0, vs.x, 52.0), Color(0.0, 0.0, 0.0, 0.72))
		card.draw_string(_font, Vector2(8.0, 20.0), l1, HORIZONTAL_ALIGNMENT_LEFT, vs.x - 16.0, 18, Color(1.0, 1.0, 0.55))
		card.draw_string(_font, Vector2(8.0, 44.0), l2, HORIZONTAL_ALIGNMENT_LEFT, vs.x - 16.0, 18, Color(1.0, 1.0, 0.55))
