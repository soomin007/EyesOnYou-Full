extends Node

# 접근성 오버레이 — autoload. scene 전환에도 살아남아 전 화면에 일괄 적용한다.
#   · 화면 밝기 (blend mode 오버레이 — 셰이더 불필요, GL Compatibility/웹 안전)
#   · 효과음 자막 (SfxPlayer.sfx_played 구독 → 의미 있는 효과음을 텍스트로)
# 색약 모드는 화면 post-process 셰이더가 필요해 별도 단계에서 추가 예정(layer 120 자리 예약).
#
# 레이어: 밝기 post-process = 120 (게임/HUD/오버레이 위), 자막 = 125 (항상 그 위 — 가독성 유지).
# 값의 단일 진실은 GameState (settings.cfg 영속). apply()가 GameState를 읽어 반영.

# ─── 밝기 ─────────────────────────────────────────────
var _fx_layer: CanvasLayer
var _brightness_rect: ColorRect
var _bright_mat: CanvasItemMaterial

# ─── 효과음 자막 ──────────────────────────────────────
var _caption_layer: CanvasLayer
var _caption_box: VBoxContainer
var _captions: Array = []  # [{box: Control, t: float, text: String}]

const CAPTION_LIFETIME: float = 2.4
const CAPTION_FADE: float = 0.6
const CAPTION_MAX: int = 4
const CAPTION_DEDUP_WINDOW: float = 0.5  # 같은 자막 연속 발생 시 새 줄 대신 타이머만 리셋

# 자막을 띄울 의미 있는 효과음만 매핑. 빈번한 잡음(발소리/사격/UI음/XP)은 제외 —
# 무음 플레이 시 "안 보이는 위협 / 중요한 상태 변화"를 글로 알리는 게 목적.
const CAPTION_MAP: Dictionary = {
	# 적 행동 — 화면 밖/소리로만 예고되는 위협
	"enemy_patrol_fire": "[적 사격]",
	"enemy_sniper_charge": "[저격 조준]",
	"enemy_sniper_fire": "[저격 발사]",
	"enemy_drone_drop": "[드론 강하]",
	"enemy_bomber_beep": "[자폭 카운트다운]",
	"enemy_bomber_explode": "[자폭 폭발]",
	"enemy_death": "[적 처치]",
	# 보스 — 누가 하는 공격인지 분명하게 "보스" 접두.
	"boss_phase_change": "[보스 단계 전환]",
	"boss_missile_launch": "[보스 미사일 발사]",
	"boss_self_destruct_alarm": "[보스 자폭 경보]",
	"boss_self_destruct_disarm": "[보스 자폭 해제]",
	"boss_death": "[보스 파괴]",
	"boss_alert_text": "[보스 경고]",
	# 폭발물 / 투사체 (bomb_throw는 보스 전용 — 보스 폭탄)
	"bomb_throw": "[보스 폭탄 투척]",
	"bomb_explode": "[폭발]",
	"bullet_deflect_shield": "[방패에 튕김]",
	# 환경 위협 / 상호작용
	"spike_hit": "[가시 작동]",
	"siren_flash": "[경보등]",
	"blackout_fade_in": "[정전]",
	"gate_unlock": "[문 열림]",
	"hatch_open": "[해치 열림]",
	"lever_pull": "[레버 작동]",
	"drop_platform_descend": "[발판 하강]",
	# 플레이어 상태
	"player_hurt": "[피격]",
	"player_death": "[쓰러짐]",
	# 진행 / 보상
	"hp_collect": "[체력 회복]",
	"levelup": "[레벨 업]",
	"challenge_clear": "[도전 성공]",
	"challenge_fail": "[도전 실패]",
	"stage_clear_chime": "[구역 클리어]",
	"arcturus_enter": "[기록 접근]",
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_brightness_overlay()
	_build_caption_overlay()
	if SfxPlayer.has_signal("sfx_played"):
		SfxPlayer.sfx_played.connect(_on_sfx_played)
	apply()

# Main.gd가 GameState.load_settings() 직후 호출. Settings에서 값 바꿀 때도 호출.
func apply() -> void:
	_apply_brightness()

# Settings에서 자막 토글을 켤 때 한 줄 예시를 띄워 위치/모양을 보여준다 (플래그와 무관하게 1회).
func preview_caption() -> void:
	_add_caption("[효과음 자막 예시]")

# ─── 밝기 구현 ────────────────────────────────────────
func _build_brightness_overlay() -> void:
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 120
	add_child(_fx_layer)
	_brightness_rect = ColorRect.new()
	_brightness_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_brightness_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bright_mat = CanvasItemMaterial.new()
	_brightness_rect.material = _bright_mat
	_brightness_rect.visible = false
	_fx_layer.add_child(_brightness_rect)

func _apply_brightness() -> void:
	var b: float = clampf(GameState.screen_brightness, 0.5, 1.5)
	if absf(b - 1.0) < 0.005:
		_brightness_rect.visible = false
		return
	_brightness_rect.visible = true
	if b < 1.0:
		# 화면을 b배로 곱해 어둡게 (result = dst * b)
		_bright_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		_brightness_rect.color = Color(b, b, b, 1.0)
	else:
		# (b-1)만큼 빛을 더해 밝게 (result = dst + add)
		_bright_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		var add: float = b - 1.0
		_brightness_rect.color = Color(add, add, add, 1.0)

# ─── 효과음 자막 구현 ─────────────────────────────────
func _build_caption_overlay() -> void:
	_caption_layer = CanvasLayer.new()
	_caption_layer.layer = 125
	add_child(_caption_layer)
	_caption_box = VBoxContainer.new()
	# 우하단 한 점에 고정 → 내용에 맞춰 위·왼쪽으로 자란다 (최신 자막이 맨 아래).
	_caption_box.anchor_left = 1.0
	_caption_box.anchor_top = 1.0
	_caption_box.anchor_right = 1.0
	_caption_box.anchor_bottom = 1.0
	_caption_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_caption_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption_box.offset_left = -28.0
	_caption_box.offset_right = -28.0
	_caption_box.offset_top = -110.0   # 하단 VEIL 자막/HUD와 안 겹치게 살짝 띄움
	_caption_box.offset_bottom = -110.0
	_caption_box.alignment = BoxContainer.ALIGNMENT_END
	_caption_box.add_theme_constant_override("separation", 6)
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_layer.add_child(_caption_box)

func _on_sfx_played(id: String) -> void:
	if not GameState.sfx_captions:
		return
	if not CAPTION_MAP.has(id):
		return
	var text: String = str(CAPTION_MAP[id])
	# 같은 자막이 짧은 시간에 연속 발생하면 새 줄 대신 직전 줄 타이머만 리셋 (스팸 방지).
	if _captions.size() > 0:
		var last: Dictionary = _captions[_captions.size() - 1]
		if str(last.get("text", "")) == text and float(last.get("t", 99.0)) < CAPTION_DEDUP_WINDOW:
			last["t"] = 0.0
			var lb := last.get("box") as CanvasItem
			if lb != null and is_instance_valid(lb):
				lb.modulate.a = 1.0
			return
	_add_caption(text)

func _add_caption(text: String) -> void:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.86)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.55, 0.62, 0.78, 0.45)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	_caption_box.add_child(pc)
	_captions.append({"box": pc, "t": 0.0, "text": text})
	while _captions.size() > CAPTION_MAX:
		var old: Dictionary = _captions.pop_front()
		var ob := old.get("box") as Node
		if ob != null and is_instance_valid(ob):
			ob.queue_free()

func _process(delta: float) -> void:
	if _captions.is_empty():
		return
	var still: Array = []
	for c in _captions:
		var cc: Dictionary = c
		var box := cc.get("box") as CanvasItem
		if box == null or not is_instance_valid(box):
			continue
		var t: float = float(cc.get("t", 0.0)) + delta
		cc["t"] = t
		if t >= CAPTION_LIFETIME:
			box.queue_free()
			continue
		var fade_start: float = CAPTION_LIFETIME - CAPTION_FADE
		if t > fade_start:
			box.modulate.a = clampf(1.0 - (t - fade_start) / CAPTION_FADE, 0.0, 1.0)
		still.append(cc)
	_captions = still
