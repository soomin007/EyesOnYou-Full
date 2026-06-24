extends Control

# 포스터 렌더 하니스 — PosterCanvas를 정확한 포스터 해상도의 SubViewport에 담아 그리고,
# 화면엔 창 비율에 맞춰 미리보기를 띄우며, PNG로 캡처해 저장한다.
# 생성 전용 실행: godot --path . res://scenes/poster.tscn --gen  → 4종 저장 후 자동 종료.
#   ① 기본 1240×1754  ② 2배 고해상 2480×3508(A4 ~300dpi, 인쇄용)  ③ 썸네일 150  ④ 썸네일 300
# 일반 실행: S=다시 저장, ESC=종료(미리보기 확인용).
# ⚠️ 반드시 창모드(--headless 금지)로 실행해야 실제 픽셀이 렌더된다. 헤드리스는 빈 이미지.

const PW: int = 1240
const PH: int = 1754
const THUMB_RENDER: int = 600
const OUT_PATH: String = "res://poster_out/eyes_on_you_poster.png"
const OUT_PATH_2X: String = "res://poster_out/eyes_on_you_poster_2x.png"
const OUT_THUMB_150: String = "res://poster_out/eyes_on_you_thumb_150.png"
const OUT_THUMB_300: String = "res://poster_out/eyes_on_you_thumb_300.png"

var _sv: SubViewport
var _canvas: PosterCanvas

func _ready() -> void:
	_sv = SubViewport.new()
	_sv.size = Vector2i(PW, PH)
	_sv.disable_3d = true
	_sv.transparent_bg = false
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)

	_canvas = PosterCanvas.new()
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
	# SubViewport이 실제로 그려질 때까지 몇 프레임 대기.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

func _capture_when_ready() -> void:
	await _wait_frames()
	_save()
	if "--gen" in OS.get_cmdline_args():
		await _save_hires()
		await _save_thumbs()
		await get_tree().create_timer(0.2).timeout
		get_tree().quit()

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("res://poster_out")
	_save_image(_grab(_sv), OUT_PATH)

# 2배 고해상 — 별도 2배 SubViewport에 PosterCanvas를 scale 2로 그려 진짜 2배 해상도 렌더.
func _save_hires() -> void:
	var sv2: SubViewport = SubViewport.new()
	sv2.size = Vector2i(PW * 2, PH * 2)
	sv2.disable_3d = true
	sv2.transparent_bg = false
	sv2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv2)
	var c2: PosterCanvas = PosterCanvas.new()
	c2.scale = Vector2(2.0, 2.0)
	sv2.add_child(c2)
	await _wait_frames()
	await _wait_frames()
	_save_image(_grab(sv2), OUT_PATH_2X)
	sv2.queue_free()

# 정사각 썸네일 — 600 렌더 후 150/300 다운스케일.
func _save_thumbs() -> void:
	var svt: SubViewport = SubViewport.new()
	svt.size = Vector2i(THUMB_RENDER, THUMB_RENDER)
	svt.disable_3d = true
	svt.transparent_bg = false
	svt.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(svt)
	var ct: ThumbCanvas = ThumbCanvas.new()
	svt.add_child(ct)
	await _wait_frames()
	await _wait_frames()
	var img: Image = _grab(svt)
	if img != null:
		var i300: Image = img.duplicate()
		i300.resize(300, 300, Image.INTERPOLATE_LANCZOS)
		_save_png(i300, OUT_THUMB_300)
		var i150: Image = img.duplicate()
		i150.resize(150, 150, Image.INTERPOLATE_LANCZOS)
		_save_png(i150, OUT_THUMB_150)
	svt.queue_free()

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
	_save_png(img, path)

func _save_png(img: Image, path: String) -> void:
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
