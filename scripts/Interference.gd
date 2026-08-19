class_name Interference
extends Node

# 통신 중계소 시그니처 · 전파 간섭 펄스(무해) — 주기적으로 VEIL 마커·위협 콜이 흐려진다.
# 재머(국소·상시·파괴 가능)의 시간판: 전역이지만 지나간다. 시각은 VeilSight 마커 알파에만
# 작용(광과민: 점멸 없음, 0.6s 램프로 흐려졌다 돌아온다). 정찰 보상(recon)은 관통(VeilSight).
# 사용: MapData "interference" = {"period": 평시 s, "blur": 간섭 유지 s, "lever_stops": bool}.
# lever_stops는 Stage._open_mid_gate가 읽어 halt()를 부른다(송신 차단기 서사).

const RAMP: float = 0.6

var period: float = 10.0
var blur: float = 2.4
var sight: Node = null      # VeilSight — Stage가 주입
var _t: float = 0.0
var _halted: bool = false
var _pulsing: bool = false  # 펄스 시작 블립 1회용

func setup(cfg: Dictionary, sight_ref: Node) -> void:
	period = maxf(float(cfg.get("period", 10.0)), 3.0)
	blur = maxf(float(cfg.get("blur", 2.4)), 0.8)
	sight = sight_ref
	add_to_group("interference")
	_t = period * 0.55   # 첫 펄스를 이르게 — 방에 들어와서 곧 규칙을 배운다

# 레버(송신 차단기)로 간섭 종료 — 이후 이 방에서 다시 오지 않는다.
func halt() -> void:
	_halted = true
	_apply(0.0)

func _physics_process(delta: float) -> void:
	if _halted or sight == null or not is_instance_valid(sight):
		return
	_t += delta
	var cycle: float = period + RAMP + blur + RAMP
	var ph: float = fmod(_t, cycle)
	var k: float = 0.0
	if ph <= period:
		_pulsing = false
	else:
		var u: float = ph - period
		if not _pulsing:
			_pulsing = true
			SfxPlayer.play("veil_subtitle_in", -14.0)   # 펄스 시작 저음 블립(예고)
		if u < RAMP:
			k = u / RAMP
		elif u < RAMP + blur:
			k = 1.0
		else:
			k = 1.0 - (u - RAMP - blur) / RAMP
	_apply(clampf(k, 0.0, 1.0))

func _apply(v: float) -> void:
	if sight != null and is_instance_valid(sight):
		sight.set("interference", v)
