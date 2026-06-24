extends Node

# 단일 BGM 재생기. autoload — scene 전환에도 살아남는다.
# 두 개의 AudioStreamPlayer로 crossfade. 트랙별 키:
#   main_theme    : Glass Protocol — 타이틀/튜토리얼/크레딧 (느린 BPM, 메인 테마)
#   early         : Cold Gear      — 외곽/외벽 초중반 맵 (BPM ↑)
#   mid_late      : Cold Wire      — 중후반 맵 (BPM ↑↑)
#   boss          : Chrome Grit    — 보스전 (가장 빠른 BPM)
#   hidden        : Gravity Static — ??? 방
#
# Suno로 생성된 4트랙(메인→보스)은 BPM이 점진적으로 빨라지게 배치된 시리즈.
# 게임 진행 흐름과 매칭 — 사용자 의도를 BGM 트랙 순서로 살림.

const TRACKS: Dictionary = {
	"main_theme":    "res://assets/bgm/Glass Protocol.mp3",
	"early":         "res://assets/bgm/Cold Gear.mp3",
	"mid_late":      "res://assets/bgm/Cold Wire.mp3",
	"boss":          "res://assets/bgm/Chrome Grit.mp3",
	"hidden":        "res://assets/bgm/Gravity Static.mp3",
	"ending_a":      "res://assets/bgm/Ending A.mp3",
	"ending_b":      "res://assets/bgm/Ending B.mp3",
	"ending_c":      "res://assets/bgm/Ending C.mp3",
	"ending_d":      "res://assets/bgm/Ending D.mp3",
}

const FADE_IN: float = 1.2
const FADE_OUT: float = 0.9
const BASE_DB: float = -8.0     # 1.0 master에서 적당히 들리도록
const SILENT_DB: float = -80.0
# 사망 화면 등에서 BGM을 dB 감쇠로 먹먹하게 — 트랙 전환 없이 즉시 ducking.
const DUCKED_OFFSET_DB: float = -12.0
const DUCK_FADE: float = 0.4

var _players: Array[AudioStreamPlayer] = []
var _active_idx: int = 0
var _current_track: String = ""
var _tween_in: Tween = null
var _tween_out: Tween = null
var _ducked: bool = false
var _tween_duck: Tween = null
# 현재 트랙에 누적되는 추가 감쇠 dB (양수 = 감쇠 안 함, 음수 = 더 작게).
# 맵 진행률 따라 BGM 페이드아웃 같은 점진 효과에 사용. 트랙이 바뀌면 0으로 리셋.
var _extra_db: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)

# 트랙 전환. 같은 트랙이면 재시작하지 않음 (장면 전환 시 끊기지 않게).
func play(track_id: String) -> void:
	if track_id == _current_track and _players[_active_idx].playing:
		return
	if not TRACKS.has(track_id):
		stop()
		return
	# 트랙이 바뀌면 누적 감쇠 리셋 — 다음 트랙(엔딩 등)이 silent에서 시작하지 않도록.
	_extra_db = 0.0
	var path: String = TRACKS[track_id]
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	# MP3는 명시적으로 loop=true 지정해야 자동 반복.
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_current_track = track_id
	var next_idx: int = (_active_idx + 1) % 2
	var prev: AudioStreamPlayer = _players[_active_idx]
	var next: AudioStreamPlayer = _players[next_idx]
	if _tween_in != null and _tween_in.is_valid():
		_tween_in.kill()
	if _tween_out != null and _tween_out.is_valid():
		_tween_out.kill()
	next.stream = stream
	next.volume_db = SILENT_DB
	next.play()
	_tween_in = create_tween()
	_tween_in.tween_property(next, "volume_db", _target_db(), FADE_IN)
	if prev.playing:
		_tween_out = create_tween()
		_tween_out.tween_property(prev, "volume_db", SILENT_DB, FADE_OUT)
		_tween_out.tween_callback(Callable(prev, "stop"))
	_active_idx = next_idx

func stop() -> void:
	_current_track = ""
	if _tween_in != null and _tween_in.is_valid():
		_tween_in.kill()
	if _tween_out != null and _tween_out.is_valid():
		_tween_out.kill()
	for p in _players:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", SILENT_DB, FADE_OUT)
			tw.tween_callback(Callable(p, "stop"))

# 마스터 볼륨 슬라이더 변경 시 호출 — 현재 재생 중인 트랙 dB만 즉시 갱신.
func refresh_volume() -> void:
	if _current_track == "":
		return
	if _active_idx >= _players.size():
		return
	var active: AudioStreamPlayer = _players[_active_idx]
	# 페이드인 진행 중이면 tween을 죽이고 곧장 목표 dB로.
	if _tween_in != null and _tween_in.is_valid():
		_tween_in.kill()
	active.volume_db = _target_db()

func _target_db() -> float:
	var v: float = clampf(GameState.bgm_volume, 0.0, 1.0)
	if v <= 0.001:
		return SILENT_DB
	# linear → dB. 0.5 master ≈ -6dB on top of BASE_DB. ducked일 때 추가 감쇠.
	var base: float = BASE_DB + linear_to_db(v)
	if _ducked:
		base += DUCKED_OFFSET_DB
	base += _extra_db
	return base

# 점진 감쇠 — 매 프레임 호출 가능. 맵 끝 가까워질수록 BGM 페이드아웃 같은 효과에.
# db_offset = 0 이면 감쇠 없음. -60 정도면 거의 무음.
# 즉시 active player의 volume_db 반영 — 트윈 없이 매끄러운 슬라이드는 호출자가 매 프레임 누적.
func set_extra_attenuation_db(db_offset: float) -> void:
	if is_equal_approx(_extra_db, db_offset):
		return
	_extra_db = db_offset
	if _current_track == "" or _active_idx >= _players.size():
		return
	# 진행 중인 fade-in 트윈은 죽이고 즉시 새 dB로. (지속 호출 시 자연스럽게 슬라이드됨)
	if _tween_in != null and _tween_in.is_valid():
		_tween_in.kill()
	_players[_active_idx].volume_db = _target_db()

# 사망 같은 임시 상황에서 BGM을 살짝 죽임. 트랙 전환은 안 하고 dB만 천천히 깎음.
# 다시 stage로 복귀할 때 set_ducked(false)로 원복.
func set_ducked(value: bool) -> void:
	if _ducked == value:
		return
	_ducked = value
	if _current_track == "":
		return
	if _active_idx >= _players.size():
		return
	var active: AudioStreamPlayer = _players[_active_idx]
	if _tween_duck != null and _tween_duck.is_valid():
		_tween_duck.kill()
	_tween_duck = create_tween()
	_tween_duck.tween_property(active, "volume_db", _target_db(), DUCK_FADE)
