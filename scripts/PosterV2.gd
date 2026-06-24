extends Control

# 포스터 v2 렌더 하니스 — PosterCanvasV2를 포스터 해상도 SubViewport에 담아 그리고 PNG로 캡처한다.
# 생성 전용 실행: godot --path . res://scenes/poster_v2.tscn --gen  → 2종 저장 후 자동 종료.
#   ① 기본 1240×1754  ② 2배 고해상 2480×3508 (A4 ~300dpi, 인쇄용)
# 일반 실행: S=다시 저장, ESC=종료(미리보기 확인용).
# ⚠️ 반드시 창모드(--headless 금지)로 실행해야 실제 픽셀이 렌더된다. 헤드리스는 빈 이미지.

const PW: int = 1240
const PH: int = 1754
const OUT_PATH: String = "res://poster_out/eyes_on_you_poster_v2.png"
const OUT_PATH_2X: String = "res://poster_out/eyes_on_you_poster_v2_2x.png"

var _sv: SubViewport
var _canvas: PosterCanvasV2

func _ready() -> void:
	_sv = SubViewport.new()
	_sv.size = Vector2i(PW, PH)
	_sv.disable_3d = true
	_sv.transparent_bg = false
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)

	_canvas = PosterCanvasV2.new()
	_sv.add_child(_canvas)

	var tr: TextureRect = TextureRect.new()
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.texture = _sv.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)

	_capture_when_ready.call_deferred()

func _wait_frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

func _capture_when_ready() -> void:
	await _wait_frames()
	_save()
	if "--gen" in OS.get_cmdline_args():
		await _save_hires()
		await get_tree().create_timer(0.2).timeout
		get_tree().quit()

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("res://poster_out")
	_save_image(_grab(_sv), OUT_PATH)

func _save_hires() -> void:
	var sv2: SubViewport = SubViewport.new()
	sv2.size = Vector2i(PW * 2, PH * 2)
	sv2.disable_3d = true
	sv2.transparent_bg = false
	sv2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv2)
	var c2: PosterCanvasV2 = PosterCanvasV2.new()
	c2.scale = Vector2(2.0, 2.0)
	sv2.add_child(c2)
	await _wait_frames()
	await _wait_frames()
	_save_image(_grab(sv2), OUT_PATH_2X)
	sv2.queue_free()

func _grab(sv: SubViewport) -> Image:
	var tex: Texture2D = sv.get_texture()
	if tex == null:
		print("POSTER: null texture")
		return null
	return tex.get_image()

func _save_image(img: Image, path: String) -> void:
	if img == null:
		print("POSTER: null image for ", path)
		return
	var err: int = img.save_png(path)
	var abs_path: String = ProjectSettings.globalize_path(path)
	if err == OK:
		print("POSTER SAVED: ", abs_path)
	else:
		print("POSTER SAVE FAILED err=", err, " path=", abs_path)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_S:
			_save()
		elif k.keycode == KEY_ESCAPE:
			get_tree().quit()
