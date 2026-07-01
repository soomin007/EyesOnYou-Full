extends Node

# 모바일 웹 가로 유도/강제 + 터치 기기 감지 + 탭 진행 헬퍼 (autoload).
#
# 1) 세로(portrait)일 때 모든 화면 위에 "가로로 돌려주세요" 안내(layer 128).
# 2) 웹이면 첫 사용자 제스처에 fullscreen + screen.orientation.lock('landscape') 시도(안드로이드 자동 가로).
# 3) is_touch_device(): 모바일 웹에서 부정확한 DisplayServer.is_touchscreen_available() 대신
#    navigator.maxTouchPoints로 터치 기기를 판정(Stage/Tutorial/Main 게이팅이 사용).
# 4) is_tap(event): 키보드 없는 폰에서 오프닝·브리핑·엔딩 등 진행성 화면이 화면 탭을 진행 입력으로 받게.

const FONT_PATH: String = "res://assets/fonts/Pretendard-Regular.otf"
# 폰에선 메뉴/설정/브리핑 UI가 데스크톱 비율(1280×720) 그대로라 너무 작아 누르기 어렵다 → 확대.
# 인게임(stage 그룹)은 월드 프레이밍·밸런스 보존 위해 1.0. 값은 실측으로 조정.
const MENU_UI_SCALE: float = 1.4

var _layer: CanvasLayer = null
var _card: Control = null
var _font: Font = null
var _portrait: bool = false
var _lock_tried: bool = false
var _touch_cached: int = -1  # -1 미판정, 0 아님, 1 터치 기기

# 터치 기기 여부(캐시). is_touchscreen_available()은 모바일 웹에서 false를 흔히 반환하므로 웹은 JS로 직접 확인.
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

# 화면 탭(터치)을 "진행/확인" 입력으로 받기 위한 헬퍼 — 진행성 화면이 jump/ui_skip 조건 옆에 OR로 쓴다.
# ScreenTouch만 인정한다(emulate 마우스 중복 방지 + 데스크톱 마우스 클릭엔 영향 없음).
func is_tap(event: InputEvent) -> bool:
	return event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed

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

# 터치 기기에서 메뉴 UI를 확대(인게임은 1.0). 씬 전환마다 반영되게 매 프레임 목표값을 맞춘다.
func _process(_delta: float) -> void:
	if not is_touch_device():
		return
	var play: bool = get_tree().get_first_node_in_group("stage") != null
	var target: float = 1.0 if play else MENU_UI_SCALE
	var win: Window = get_window()
	if win != null and not is_equal_approx(win.content_scale_factor, target):
		win.content_scale_factor = target

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
	card.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.04, 0.05, 0.98))
	if _font == null:
		return
	var msg: String = "기기를 가로로 돌려주세요"
	card.draw_string(_font, Vector2(0.0, vs.y * 0.5), msg, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 40, Color(0.86, 0.92, 1.0, 0.96))
	var sub: String = "화면 회전 잠금이 켜져 있으면 꺼주세요"
	card.draw_string(_font, Vector2(0.0, vs.y * 0.5 + 46.0), sub, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 22, Color(0.62, 0.72, 0.82, 0.9))
