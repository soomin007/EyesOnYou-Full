class_name BotDriver
extends Node

# 밸런스 계측용 휴리스틱 플레이 봇(2026-08-17 사용자 요청 "사람 같은 플레이로 테스트").
# 학습 모델이 아니라 "대충 하는 사람" 근사: Input 액션을 실제로 눌러 Player의 진짜 코드
# 경로(이동·점프 버퍼·사격 쿨다운)로 조작한다. 실력은 파라미터(반응 지연·교전 거리·
# 같은 높이만 조준)로 조절 · 유도/관통 빌드가 "대충 갈겨도 되는" 정도가 지표로 드러난다.
# 용도: BotRunner 스위트(빌드 × 맵 자동 주파 → [BOT] 지표). 게임 플레이에는 관여하지 않는다.

var reaction_s: float = 0.25        # 표적 인지 → 사격 개시 지연(사람 근사)
var engage_range: float = 520.0     # 교전 개시 거리
var same_level_dy: float = 90.0     # 이 높이 차 이내만 조준(수평 사격 근사)

var _stage: Node = null
var _player: Node2D = null
var _stuck_t: float = 0.0
var _react_t: float = 0.0
var _jump_pulse: int = 0            # >0이면 이번 틱 jump 유지 후 해제
# 포기하고 지나가기(사람 습관) · 같은 표적을 6s 쏴도 못 잡으면(방패병 정면 등) 10s 무시.
var _tgt_id: int = 0
var _tgt_t: float = 0.0
var _ignore: Dictionary = {}        # instance_id → 무시 해제 시각(_clock)
var _clock: float = 0.0
var _hop_t: float = 0.0             # 공중 적 상대 점프 사격 리듬

func _physics_process(delta: float) -> void:
	if _stage == null or not is_instance_valid(_stage):
		_release_all()
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	if bool(_stage.get("goal_reached")):
		_release_all()
		return
	# 점프 펄스 해제(just_pressed 판정을 위해 1틱만 누른다).
	if _jump_pulse > 0:
		_jump_pulse -= 1
		if _jump_pulse == 0:
			Input.action_release("jump")
	# 아레나(전멸형) 모드 · 골 좌표 대신 가장 가까운 적이 목적지(어느 방향이든 교전).
	var arena: bool = str(_stage.get("_goal_type")) == "ENEMY_CLEAR"
	var goal: Vector2 = _stage.get("_goal_pos")
	var goal_dir: float = signf(goal.x - _player.global_position.x)
	if goal_dir == 0.0:
		goal_dir = 1.0
	var arena_near: Node2D = null
	var arena_nd: float = 1e9
	if arena:
		for e0 in get_tree().get_nodes_in_group("enemy"):
			if e0 is Node2D and is_instance_valid(e0) and not bool((e0 as Node2D).get("dead")) \
					and not bool((e0 as Node2D).get("harmless")):
				var dxa: float = absf((e0 as Node2D).global_position.x - _player.global_position.x)
				if dxa < arena_nd:
					arena_nd = dxa
					arena_near = e0
		if arena_near != null:
			goal_dir = signf(arena_near.global_position.x - _player.global_position.x)
			if goal_dir == 0.0:
				goal_dir = 1.0
	# 교전 표적 · 진행 방향 앞 + 같은 높이 근사만(사람의 수평 사격 습관).
	_clock += delta
	var target: Node2D = null
	var best: float = engage_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		if bool((e as Node2D).get("dead")) or bool((e as Node2D).get("harmless")):
			continue
		if _ignore.has(e.get_instance_id()) and _clock < float(_ignore[e.get_instance_id()]):
			continue
		var rel: Vector2 = (e as Node2D).global_position - _player.global_position
		# 아레나는 전방향 조준(다 잡아야 하는 방 · 몸을 돌려 쏜다) · 통과형은 전방만.
		if not arena and rel.x * goal_dir <= 0.0:
			continue
		if absf(rel.y) > same_level_dy:
			continue
		if absf(rel.x) < best:
			best = absf(rel.x)
			target = e
	# 같은 표적 6s 교착 = 포기(방패병 정면 등 · 사람도 지나친다). 10s 뒤 재고려.
	if target != null:
		if target.get_instance_id() == _tgt_id:
			_tgt_t += delta
			if _tgt_t > 6.0:
				_ignore[target.get_instance_id()] = _clock + 10.0
				_tgt_t = 0.0
				target = null
		else:
			_tgt_id = target.get_instance_id()
			_tgt_t = 0.0
	# 이동 · 표적이 사거리 안이면 멈춰 쏘고, 아니면 골 방향 전진(대충 하는 사람의 리듬).
	var move_dir: float = goal_dir
	if target != null and best < engage_range * 0.75:
		move_dir = 0.0
	elif arena and arena_near != null and arena_nd < 90.0:
		# 가장 가까운 적 바로 아래 도착 · dx 부호 진동으로 좌우 떨림 방지(서서 싸운다).
		move_dir = 0.0
	if move_dir > 0.0:
		Input.action_release("move_left")
		Input.action_press("move_right")
	elif move_dir < 0.0:
		Input.action_release("move_right")
		Input.action_press("move_left")
	else:
		Input.action_release("move_right")
		Input.action_release("move_left")
		# 표적을 향해 몸 돌리기(사격 방향 = facing).
		var face: Node2D = target if target != null else arena_near
		var tdir: float = 0.0
		if face != null:
			tdir = signf(face.global_position.x - _player.global_position.x)
		if tdir > 0.0:
			Input.action_press("move_right")
			Input.action_release("move_right")
		elif tdir < 0.0:
			Input.action_press("move_left")
			Input.action_release("move_left")
	# 사격 · 반응 지연 후 꾹(꾹 누르면 쿨다운마다 자동 연발 = 게임 규칙 그대로).
	# 아레나에서 같은 높이 표적이 없고 공중 적만 남으면 "유도 믿고 갈기기". 유도 없는
	# 빌드는 빗나가고 유도 빌드는 맞는다(= 측정하려는 조준 비용 면제 그 자체).
	var blind_fire: bool = false
	if arena and target == null:
		for e2 in get_tree().get_nodes_in_group("enemy"):
			if e2 is Node2D and is_instance_valid(e2) and not bool((e2 as Node2D).get("dead")) \
					and not bool((e2 as Node2D).get("harmless")) \
					and absf((e2 as Node2D).global_position.x - _player.global_position.x) < 620.0:
				blind_fire = true
				break
	if target != null or blind_fire:
		_react_t += delta
		if _react_t >= reaction_s:
			Input.action_press("attack")
	else:
		_react_t = 0.0
		Input.action_release("attack")
	# 점프 사격 리듬, 두 경우: ① 공중 적만 남음(사람이 드론 잡는 습관 · 점프 궤적 중 표적
	# 높이에 걸리면 같은 높이 필터가 잡아 준다) ② 유도 빌드(glide T3)로 교전 중(유도는 공중
	# 사격 한정이라, 그 빌드 유저는 뛰면서 갈긴다 = 사용자가 지적한 "대충 갈기기" 그 자체).
	var homing_hop: bool = target != null and GameState.get_skill_tier("glide") >= 3
	if blind_fire or homing_hop:
		_hop_t += delta
		if _hop_t > 0.9 and _jump_pulse == 0:
			Input.action_press("jump")
			_jump_pulse = 2
			_hop_t = 0.0
	else:
		_hop_t = 0.0
	# 막힘 감지 → 점프(허들·게이트·단차). 오래 막히면 이단 점프.
	if move_dir != 0.0 and absf(float(_player.velocity.x)) < 18.0:
		_stuck_t += delta
		if _stuck_t > 0.35 and _jump_pulse == 0:
			Input.action_press("jump")
			_jump_pulse = 2
			if _stuck_t > 1.0:
				_stuck_t = 0.45   # 다음 펄스(이단 점프) 예약
	else:
		_stuck_t = 0.0

func setup(stage: Node) -> void:
	_stage = stage

func stop() -> void:
	_release_all()

func _release_all() -> void:
	for act in ["move_left", "move_right", "jump", "attack", "dash", "skill"]:
		Input.action_release(act)

func _exit_tree() -> void:
	_release_all()
