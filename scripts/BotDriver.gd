class_name BotDriver
extends Node

# 밸런스 계측용 휴리스틱 플레이 봇(2026-08-17 사용자 요청 "사람 같은 플레이로 테스트").
# v2(2026-08-18 사용자 "봇을 좀 더 나같이"): 일반인 근사에서 **이 사용자 근사**로.
# GameState.get_playstyle()(실플레이 실측 프로필, user://playstyle.cfg)을 읽어 습관을 맞춘다:
#   사냥 성향(hunt_ratio) → 골 직행 대신 근처 적 소탕(사용자 실측: 런당 처치 133 ≈ 전멸)
#   대시(dash_pm) → 이동 중 리듬 대시 + 날아오는 탄 회피 대시
#   공중 사격(air_shot_ratio) → 교전 중 점프 사격 리듬
#   교전 거리(avg_fire_dist) → 사격 개시 거리
# 학습 모델이 아니라 Input 액션을 실제로 눌러 Player의 진짜 코드 경로로 조작하는 근사이며,
# 결과 지표(시간·피탄·처치)와 습관 빈도를 맞출 뿐 판단의 뉘앙스까지는 못 담는다.
# 데드락 가드(known_issues): 사격 표적 6s 교착 포기 · 사냥 목적지 7s 교착 포기 ·
# 허공 갈기기 8s 무진전 중단. 킬이 나면 전부 리셋(진전 중엔 포기하지 않는다).

var reaction_s: float = 0.25        # 표적 인지 → 사격 개시 지연(사람 근사)
var engage_range: float = 520.0     # 교전 개시 거리(프로필 avg_fire_dist로 보정)
var same_level_dy: float = 90.0     # 이 높이 차 이내만 조준(수평 사격 근사)
var hunt: bool = true               # 전멸 성향(프로필 hunt_ratio ≥ 0.6)
var hunt_range: float = 760.0       # 사냥 탐지 반경(통과형 맵에서 우회 한도)
var hunt_dy: float = 280.0          # 사냥 목적지 높이 한도(등반 불가 지형 제외)

var _stage: Node = null
var _player: Node2D = null
var _stuck_t: float = 0.0
var _react_t: float = 0.0
var _jump_pulse: int = 0            # >0이면 이번 틱 jump 유지 후 해제
var _dash_pulse: int = 0
# 포기하고 지나가기(사람 습관) · 같은 표적을 6s 쏴도 못 잡으면(방패병 정면 등) 10s 무시.
var _tgt_id: int = 0
var _tgt_t: float = 0.0
var _nav_id: int = 0                # 사냥 목적지 교착 가드(공중 적 밑 대치 등)
var _nav_t: float = 0.0
var _ignore: Dictionary = {}        # instance_id → 무시 해제 시각(_clock)
var _giveup: Dictionary = {}        # instance_id → 포기 횟수 · 2회면 영구 무시(사람도 두 번 막히면 버린다)
var _clock: float = 0.0
var _hop_t: float = 0.0             # 교전 중 점프 사격 리듬
var _hop_period: float = 1.2        # air_shot_ratio에서 유도(작을수록 자주 뛴다)
var _climb_t: float = 0.0           # 머리 위 목적지 등반 리듬
var _climb_seq: int = 0             # 0 대기 → 1 점프 직후(더블점프 예약) → 2 휴지
var _dash_travel_t: float = 0.0     # 이동 대시 리듬
var _dash_period: float = 15.0      # dash_pm에서 유도
var _dodge_cd: float = 0.0          # 회피 대시 재시도 쿨
var _blind_t: float = 0.0           # 허공 갈기기 무진전 시간
var _blind_cd: float = 0.0          # 무진전 시 억제 해제 시각(_clock)
var _gren_hold: float = -1.0        # ≥0이면 수류탄 차징 중(홀드 시간)
var _gren_cd: float = 0.0
var _use_grenade: bool = false
var _kills_seen: int = 0
var _pull_pulse: int = 0            # 레버 당기기(공격 키 just_pressed 펄스)
var _pull_t: float = 0.0
# 레버 스테이징(2026-08-21 펌프장 실측): 레버가 더블점프(~190px)로 안 닿는 높이면 바로 밑에서
# 수직 점프만 반복하는 교착이 난다(계단식 접근 맵). 밑에서 일정 시간 막히면 옆(±230px)을
# 경유 목표로 잡아 계단 발판을 밟고 오른다 · 좌우 교대로 시도.
var _lever_stuck_t: float = 0.0
var _lever_stage_dx: float = 0.0
var _lever_stage_until: float = -1.0
# 사용자 기법 이식(2026-08-18 직접 설명): 방패병 크로스 · 대공 점프샷.
var _cross_t: float = -1.0          # ≥0이면 방패병 뛰어넘기 진행 중
var _cross_dir: float = 0.0
var _cross_id: int = 0
var _aa_id: int = 0                 # 대공 표적(드론) 교착 추적
var _aa_t: float = 0.0
var _cross_count: Dictionary = {}   # 방패병당 크로스 시도 횟수(2회 제한 · 초과 시 포기 경로)

func setup(stage: Node) -> void:
	_stage = stage
	var prof: Dictionary = GameState.get_playstyle()
	hunt = float(prof.get("hunt_ratio", 0.9)) >= 0.6
	engage_range = clampf(float(prof.get("avg_fire_dist", 420.0)) * 1.25, 320.0, 700.0)
	_dash_period = 60.0 / maxf(float(prof.get("dash_pm", 4.0)), 0.5)
	_hop_period = lerpf(2.2, 0.7, clampf(float(prof.get("air_shot_ratio", 0.5)), 0.0, 1.0))
	_use_grenade = GameState.get_skill_tier("explosive") > 0
	_kills_seen = GameState.kills_total

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
	_clock += delta
	# 진전(킬)이 나면 교착 타이머 전부 리셋 · 포기는 무진전일 때만.
	if GameState.kills_total != _kills_seen:
		_kills_seen = GameState.kills_total
		_tgt_t = 0.0
		_nav_t = 0.0
		_blind_t = 0.0
	# 펄스 해제(just_pressed 판정을 위해 1틱만 누른다).
	if _jump_pulse > 0:
		_jump_pulse -= 1
		if _jump_pulse == 0:
			Input.action_release("jump")
	if _dash_pulse > 0:
		_dash_pulse -= 1
		if _dash_pulse == 0:
			Input.action_release("dash")
	if _pull_pulse > 0:
		_pull_pulse -= 1
		if _pull_pulse == 0:
			Input.action_release("attack")
	var arena: bool = str(_stage.get("_goal_type")) == "ENEMY_CLEAR"
	var goal: Vector2 = _stage.get("_goal_pos")
	var goal_dir: float = signf(goal.x - _player.global_position.x)
	if goal_dir == 0.0:
		goal_dir = 1.0
	# 사냥 목적지 · 아레나(전멸형)는 맵 전체에서, 통과형은 hunt 성향일 때 반경/높이 한도 안에서
	# 가장 가까운 적을 목적지로(사용자의 "다 잡고 지나간다" 습관). 없으면 골 방향.
	var nav: Node2D = null
	var nav_dx: float = 1e9
	# 표적 고정(대공과 동형 · 2026-08-19) · 적 무리가 겹쳐 다니면 "최근접"이 프레임마다
	# 스왑되어 교착 타이머가 리셋 → 포기가 안 온다. 기존 목적지가 유효하면 유지.
	if _nav_id != 0 and (arena or hunt):
		var heldn: Node2D = instance_from_id(_nav_id) as Node2D
		if heldn != null and is_instance_valid(heldn) and not bool(heldn.get("dead")) \
				and not bool(heldn.get("harmless")) \
				and not (_ignore.has(_nav_id) and _clock < float(_ignore[_nav_id])):
			var reln: Vector2 = heldn.global_position - _player.global_position
			var etn: Variant = heldn.get("enemy_type")
			if (etn == null or int(etn) != 2) \
					and (arena or (absf(reln.x) <= hunt_range and absf(reln.y) <= hunt_dy)):
				nav = heldn
				nav_dx = absf(reln.x)
	if nav == null and (arena or hunt):
		for e0 in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e0) or not (e0 is Node2D):
				continue
			if bool((e0 as Node2D).get("dead")) or bool((e0 as Node2D).get("harmless")):
				continue
			if _ignore.has(e0.get_instance_id()) and _clock < float(_ignore[e0.get_instance_id()]):
				continue
			# 드론(공중 추적 유닛)은 사냥 목적지에서 제외 · 따라오는 적이라 찾아갈 필요가 없고,
			# 밑에서 등반 점프만 반복하며 시간·피해를 낭비한다(2026-08-18 냉각 TIMEOUT 실측).
			var et0: Variant = (e0 as Node2D).get("enemy_type")
			if et0 != null and int(et0) == 2:
				continue
			var rel0: Vector2 = (e0 as Node2D).global_position - _player.global_position
			if not arena and (absf(rel0.x) > hunt_range or absf(rel0.y) > hunt_dy):
				continue
			if absf(rel0.x) < nav_dx:
				nav_dx = absf(rel0.x)
				nav = e0
	if nav != null:
		goal_dir = signf(nav.global_position.x - _player.global_position.x)
		if goal_dir == 0.0:
			goal_dir = 1.0
		# 목적지 교착(공중 적 밑 대치 · 못 오르는 단차 등) 7s → 12s 무시하고 지나간다.
		if nav.get_instance_id() == _nav_id:
			_nav_t += delta
			if _nav_t > 7.0:
				_mark_giveup(nav.get_instance_id())
				_nav_t = 0.0
				nav = null
		else:
			_nav_id = nav.get_instance_id()
			_nav_t = 0.0
	# 교전 표적 · 같은 높이 근사만(사람의 수평 사격 습관). 사냥/아레나는 전방향, 통과형 직행은 전방만.
	var target: Node2D = null
	var best: float = engage_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if bool((e as Node2D).get("dead")) or bool((e as Node2D).get("harmless")):
			continue
		if _ignore.has(e.get_instance_id()) and _clock < float(_ignore[e.get_instance_id()]):
			continue
		var rel: Vector2 = (e as Node2D).global_position - _player.global_position
		if not (arena or hunt) and rel.x * goal_dir <= 0.0:
			continue
		if absf(rel.y) > same_level_dy:
			continue
		if absf(rel.x) < best:
			best = absf(rel.x)
			target = e
	# 같은 표적 6s 교착 = 포기(방패병 정면 등 · 사람도 지나친다). 10s 뒤 재고려 ·
	# 2회 포기면 영구(hunt 성향이 못 잡는 적에게 무한 회귀하던 TIMEOUT 차단).
	if target != null:
		if target.get_instance_id() == _tgt_id:
			_tgt_t += delta
			if _tgt_t > 6.0:
				_mark_giveup(target.get_instance_id())
				_tgt_t = 0.0
				target = null
		else:
			_tgt_id = target.get_instance_id()
			_tgt_t = 0.0
	# 중간 관문(레버 모드) · 격벽이 닫혔고 근처까지 왔으면 레버가 목적지(사람의 우회 동선).
	# 교전 중엔 전투 우선 · 레버 근처 허공 갈기기는 끈다(공격 키 홀드가 당기기 입력을 막는다).
	var lever_pos: Vector2 = Vector2.INF
	if str(_stage.get("_mid_gate_mode")) == "lever" and not bool(_stage.get("_mid_gate_opened")):
		var md: Variant = _stage.get("_map_data")
		if md is Dictionary:
			var mg: Dictionary = (md as Dictionary).get("mid_gate", {})
			var lp: Variant = mg.get("lever")
			if lp is Vector2 and absf(_player.global_position.x - float(mg.get("x", 0.0))) < 1100.0:
				lever_pos = lp
	var lever_dx: float = (lever_pos.x - _player.global_position.x) if lever_pos != Vector2.INF else 1e9
	# 방패병 크로스(사용자 기법: "뛰어넘어 등을 갈긴다" · 방패는 정면만 막는다).
	# 정면 교착 1.2s면 그쪽으로 점프해 넘어가고, 반대편 착지 후 표적 창을 새로 연다(등 노출).
	if _cross_t >= 0.0:
		_cross_t += delta
		var ct: Node2D = instance_from_id(_cross_id) as Node2D
		if ct == null or not is_instance_valid(ct) or bool(ct.get("dead")) or _cross_t > 1.6:
			_cross_t = -1.0
		else:
			var cdx: float = ct.global_position.x - _player.global_position.x
			if signf(cdx) == -_cross_dir and absf(cdx) > 60.0:
				_cross_t = -1.0   # 반대편 착지 완료 · 이제 등이 이쪽
	elif target != null and _tgt_t > 1.2 and best < 300.0:
		var et_t: Variant = target.get("enemy_type")
		# 크로스는 방패당 2회까지 · 그래도 못 잡으면 기존 6s 스톨 → 포기 경로로(영구 씨름 방지).
		if et_t != null and int(et_t) == 4 and int(_cross_count.get(target.get_instance_id(), 0)) < 2:
			_cross_dir = signf(target.global_position.x - _player.global_position.x)
			if _cross_dir == 0.0:
				_cross_dir = 1.0
			_cross_id = target.get_instance_id()
			_cross_count[_cross_id] = int(_cross_count.get(_cross_id, 0)) + 1
			_cross_t = 0.0
			_tgt_t = 0.0
			if _jump_pulse == 0:
				Input.action_press("jump")
				_jump_pulse = 2
	# 대공 표적(사용자 기법: "옆에 비껴 서서 점프샷") · 지상 사냥감(nav)이 다 떨어졌을 때만.
	# 지상 적보다 우선하면 봇이 드론과 씨름하느라 전진·사냥이 전부 멈춘다(2026-08-18 실측).
	var aa: Node2D = null
	# 표적 고정 · 드론 무리가 겹쳐 다니면 "최근접"이 프레임마다 스왑되어 교착 타이머가
	# 계속 리셋 → 포기가 영원히 안 오는 무한 교착(2026-08-19 실측). 죽거나 포기할 때까지 유지.
	if _aa_id != 0 and (arena or hunt) and target == null and _cross_t < 0.0 and lever_pos == Vector2.INF:
		var held: Node2D = instance_from_id(_aa_id) as Node2D
		if held != null and is_instance_valid(held) and not bool(held.get("dead")) \
				and not (_ignore.has(_aa_id) and _clock < float(_ignore[_aa_id])):
			var relh: Vector2 = held.global_position - _player.global_position
			if relh.y < -60.0 and absf(relh.x) < 460.0:
				aa = held
	if aa == null and (arena or hunt) and target == null and nav == null and _cross_t < 0.0 and lever_pos == Vector2.INF:
		var aa_best: float = 360.0
		for e3 in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e3) or not (e3 is Node2D):
				continue
			if bool((e3 as Node2D).get("dead")) or bool((e3 as Node2D).get("harmless")):
				continue
			var et3: Variant = (e3 as Node2D).get("enemy_type")
			if et3 == null or int(et3) != 2:
				continue
			if _ignore.has(e3.get_instance_id()) and _clock < float(_ignore[e3.get_instance_id()]):
				continue
			var rel3: Vector2 = (e3 as Node2D).global_position - _player.global_position
			if rel3.y > -80.0:
				continue
			if absf(rel3.x) < aa_best:
				aa_best = absf(rel3.x)
				aa = e3
	# 대공 교착 · 같은 드론 5s 무진전이면 포기(2회면 영구 · 킬 시 _kills_seen 리셋이 풀어준다).
	if aa != null:
		if aa.get_instance_id() == _aa_id:
			_aa_t += delta
			if _aa_t > 5.0:
				_mark_giveup(aa.get_instance_id())
				_aa_t = 0.0
				aa = null
		else:
			_aa_id = aa.get_instance_id()
			_aa_t = 0.0
	var aa_dx: float = (aa.global_position.x - _player.global_position.x) if aa != null else 1e9
	var aa_fire: bool = false
	# 이동 · 우선순위: 크로스 기동 > 레버 > 교전 정지 > 대공 자리잡기 > 사냥 목적지 > 골.
	var move_dir: float = goal_dir
	if _cross_t >= 0.0:
		move_dir = _cross_dir
	elif lever_pos != Vector2.INF and target == null:
		# 레버 감지 Area가 40px 폭(반폭 20) · 정지 문턱이 넓으면 감지 밖에 서서 헛사격한다.
		# 스테이징 중엔 경유 x(레버 ± 오프셋)로 · 계단 발판을 먼저 밟는다.
		var lever_tx: float = lever_pos.x + (_lever_stage_dx if _clock < _lever_stage_until else 0.0)
		var lever_tdx: float = lever_tx - _player.global_position.x
		move_dir = signf(lever_tdx) if absf(lever_tdx) > 14.0 else 0.0
	elif target != null and best < engage_range * 0.75:
		move_dir = 0.0
	elif aa != null:
		# 수평탄이라 바로 밑에선 못 맞힌다 · 옆 80~190px 밴드에 서서 정점 사격.
		if absf(aa_dx) < 70.0:
			move_dir = -signf(aa_dx) if signf(aa_dx) != 0.0 else 1.0
		elif absf(aa_dx) > 190.0:
			move_dir = signf(aa_dx)
		else:
			move_dir = 0.0
			aa_fire = true
	elif nav != null and nav_dx < 90.0:
		# 목적지 바로 아래 도착 · dx 부호 진동으로 좌우 떨림 방지(서서 싸운다).
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
		var face: Node2D = target if target != null else (aa if aa != null else nav)
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
	# 같은 높이 표적이 없어도 근처에 적이 남았으면(공중 드론 등) "유도 믿고 갈기기" ·
	# 유도 없는 빌드는 빗나간다(= 측정하려는 조준 비용 면제 그 자체). 단 8s 무진전이면
	# 억제(사람도 안 맞는 갈기기는 관둔다 · 데드락 가드).
	# 레버 "바로 앞"에서만 허공 갈기기 금지(공격 홀드가 당기기 입력을 막는다) · 접근 중엔 허용
	# (유도 빌드가 레버 상공 드론을 지울 수 있어야 한다 · 2026-08-18 냉각 max TIMEOUT 실측).
	var at_lever: bool = lever_pos != Vector2.INF and absf(lever_dx) < 120.0
	var blind_fire: bool = false
	if (arena or hunt) and target == null and _clock >= _blind_cd and not at_lever:
		for e2 in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e2) and e2 is Node2D and not bool((e2 as Node2D).get("dead")) \
					and not bool((e2 as Node2D).get("harmless")) \
					and absf((e2 as Node2D).global_position.x - _player.global_position.x) < 620.0:
				blind_fire = true
				break
	if blind_fire:
		_blind_t += delta
		if _blind_t > 8.0:
			_blind_cd = _clock + 12.0
			_blind_t = 0.0
			blind_fire = false
	else:
		_blind_t = 0.0
	if _cross_t >= 0.0:
		# 크로스 기동 중엔 사격 중지(정면 방패에 낭비 방지 · 착지 후 등을 노린다).
		Input.action_release("attack")
		_react_t = 0.0
	elif target != null or blind_fire or aa_fire:
		_react_t += delta
		if _react_t >= reaction_s:
			Input.action_press("attack")
	else:
		_react_t = 0.0
		if _pull_pulse == 0:   # 레버 당기기 펄스 중엔 해제하지 않는다(당기기 입력 보호)
			Input.action_release("attack")
	# 점프 사격 리듬(프로필 air_shot_ratio) · 유도 빌드(glide T3)는 풀 리듬("뛰면서 갈기기"),
	# 그 외는 1/3 빈도(유도 없이 지상 표적 상대로 뛰면 수평탄이 넘어가 손해 · 사람도 덜 뛴다).
	# 허공 갈기기 중엔 항상 풀 리듬(점프 궤적에서 같은 높이 필터가 공중 적을 잡아 준다).
	var hop_period: float = _hop_period
	if GameState.get_skill_tier("glide") < 3 and not blind_fire:
		hop_period = _hop_period * 3.0
	if target != null or blind_fire:
		_hop_t += delta
		if _hop_t > hop_period and _jump_pulse == 0:
			Input.action_press("jump")
			_jump_pulse = 2
			_hop_t = 0.0
	else:
		_hop_t = 0.0
	# 레버 교착 감지 · 바로 밑(수평 근접) 지면에서 더블점프로 안 닿는 높이차. 2.2s 지속 시
	# 스테이징 발동(좌 → 우 교대 · 3.5s 유지). ⚠ 판정은 **접지 상태에서만** · 점프 정점에서
	# 높이차가 순간적으로 좁혀져 타이머가 매번 리셋되는 구멍이 있었다(2026-08-21 펌프장 실측:
	# 등반 점프 사이클마다 리셋 → 스테이징이 영영 발동 안 함). 공중에서는 판정을 건너뛴다.
	if lever_pos != Vector2.INF and target == null and absf(lever_dx) < 70.0:
		if _player is CharacterBody2D and (_player as CharacterBody2D).is_on_floor():
			if _player.global_position.y - lever_pos.y > 210.0:
				_lever_stuck_t += delta
				if _lever_stuck_t > 2.2:
					_lever_stage_dx = -230.0 if _lever_stage_dx >= 0.0 else 230.0
					_lever_stage_until = _clock + 3.5
					_lever_stuck_t = 0.0
			else:
				_lever_stuck_t = 0.0   # 계단 위(레버 높이대) 도달 · 교착 아님
	else:
		_lever_stuck_t = 0.0
	# 머리 위 목적지(발판 위 저격수·레버) · 밑에서 등반 점프 리듬(이단 점프는 공중 재입력).
	# 스테이징 경유 지점에서도 등반이 나가야 하므로 게이트 폭 220→260(오프셋 230 커버).
	var climb_up: float = 0.0
	if lever_pos != Vector2.INF and target == null and absf(lever_dx) < 260.0:
		climb_up = _player.global_position.y - lever_pos.y
	elif aa_fire:
		# 대공 점프샷 · 더블점프 정점(~190)이 드론 고도(-220) 언저리의 조준 밴드에 든다.
		climb_up = _player.global_position.y - aa.global_position.y
	elif nav != null and nav_dx < 220.0:
		climb_up = _player.global_position.y - nav.global_position.y
	# 사람의 등반 = 점프 직후 더블점프(합산 ~190px). 단발 점프 반복으로는 높은 발판(Δ>104)에
	# 못 올라 레버·저격 둥지 접근이 실패한다(2026-08-18 냉각 레버 TIMEOUT 실측).
	# 시퀀스 진행 중엔 climb_up 게이트를 무시 · 1단 상승 중 높이 차가 좁혀지며 게이트가 꺼져
	# 더블점프 입력이 영영 안 나가는 자가 리셋이 있었다(y 진동 무한 반복의 원인).
	# 레버 목표일 땐 게이트 60px · 계단 마지막 단(Δ~100)에서 player 중심 기준 climb_up이
	# 100 밑으로 내려와 점프가 영영 안 나가고 걸어서 떨어지는 루프가 있었다(2026-08-21 펌프장 실측).
	var climb_gate: float = 60.0 if (lever_pos != Vector2.INF and target == null) else 100.0
	if climb_up > climb_gate or _climb_seq != 0:
		_climb_t += delta
		if _climb_seq == 0 and climb_up > climb_gate and _climb_t > 0.4 and _jump_pulse == 0:
			Input.action_press("jump")
			_jump_pulse = 2
			_climb_seq = 1
			_climb_t = 0.0
		elif _climb_seq == 1 and _climb_t > 0.3 and _jump_pulse == 0:
			Input.action_press("jump")   # 공중 재입력 = 더블점프
			_jump_pulse = 2
			_climb_seq = 2
			_climb_t = 0.0
		elif _climb_seq == 2 and _climb_t > 0.9:
			_climb_seq = 0
			_climb_t = 0.0
	else:
		_climb_seq = 0
		_climb_t = 0.0
	# 레버 앞 도착 · 당기기(공격 키 = 상호작용 · just_pressed 필요라 펄스로 누른다). 0.6s 재시도.
	if at_lever and target == null and not blind_fire \
			and absf(lever_dx) < 46.0 and absf(_player.global_position.y - lever_pos.y) < 96.0:
		_pull_t += delta
		if _pull_t > 0.6 and _pull_pulse == 0:
			Input.action_press("attack")
			_pull_pulse = 2
			_pull_t = 0.0
	else:
		_pull_t = 0.6   # 도착 즉시 첫 시도가 나가게
	# 대시 ① 회피 · 날아오는 적탄이 가까우면 대시(무적 프레임 · 사람의 "보고 피하기").
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	if _dodge_cd <= 0.0 and _dash_pulse == 0:
		for b in get_tree().get_nodes_in_group("enemy_bullet"):
			if not is_instance_valid(b) or not (b is Node2D):
				continue
			var bv: Variant = b.get("velocity")
			if not (bv is Vector2):
				continue   # 존재 불확실 속성 방어(known_issues: null 생성자 크래시)
			var to_me: Vector2 = _player.global_position - (b as Node2D).global_position
			if to_me.length() < 260.0 and (bv as Vector2).dot(to_me) > 0.0:
				Input.action_press("dash")
				_dash_pulse = 2
				_dodge_cd = 0.5
				break
	# 대시 ② 이동 리듬(프로필 dash_pm) · 전진 중 주기 대시(사람의 이동 습관).
	# 목표(사냥 적·레버)가 가까우면 억제 · 사람의 대시는 긴 전진 구간에서 몰아 쓰는 것이고,
	# 기계적 주기 대시는 관성 오버슈트로 정밀 접근을 망친다(2026-08-18 src=user 첫 계측에서
	# dash_pm 29.9가 그대로 이식되자 검수 존 왕복 TIMEOUT 실측).
	var dash_ok: bool = true
	if nav != null and nav_dx < 420.0:
		dash_ok = false
	if lever_pos != Vector2.INF and absf(lever_dx) < 420.0:
		dash_ok = false
	if target != null:
		dash_ok = false
	if move_dir != 0.0 and dash_ok and _dash_pulse == 0:
		_dash_travel_t += delta
		if _dash_travel_t > _dash_period:
			Input.action_press("dash")
			_dash_pulse = 2
			_dash_travel_t = 0.0
	# 수류탄(explosive 보유 시) · 표적 교착 1.2s(방패병 정면 등)면 차징 투척(엄폐 너머 타격).
	_gren_cd = maxf(_gren_cd - delta, 0.0)
	if _gren_hold >= 0.0:
		_gren_hold += delta
		Input.action_press("skill")
		if _gren_hold >= 0.5:
			Input.action_release("skill")
			_gren_hold = -1.0
			_gren_cd = 4.0
	elif _use_grenade and _gren_cd <= 0.0 and target != null and _tgt_t > 1.2 and best < 600.0:
		_gren_hold = 0.0
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

# 포기 등록 · 1회차는 10~12s 무시 후 재고려, 2회차부터 영구 무시(못 잡는 적 무한 회귀 차단).
func _mark_giveup(id: int) -> void:
	_giveup[id] = int(_giveup.get(id, 0)) + 1
	_ignore[id] = _clock + (999999.0 if int(_giveup[id]) >= 2 else 11.0)

func stop() -> void:
	_release_all()

func _release_all() -> void:
	for act in ["move_left", "move_right", "jump", "attack", "dash", "skill"]:
		Input.action_release(act)
	_gren_hold = -1.0

func _exit_tree() -> void:
	_release_all()
