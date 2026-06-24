# 효과음 목록 (SFX)

`assets/sfx/<id>.mp3`로 채울 효과음 전수 목록. 코드에서는 `SfxPlayer.play(id)`로 호출.
각 항목은 짧은 단발(0.1~1.5s) 또는 명시된 loop. 볼륨은 `GameState.sfx_volume` 슬라이더 ×
`SfxPlayer.VOLUME_OFFSETS[id]` 보정으로 결정.

## 표기
- **상태**: ✅ 파일 존재 + 코드 wire-up 완료 / ⬜ 미작업 / ⚠ 파일은 있으나 미사용 또는 미연결
- **우선순위 P0~P2**: P0 핵심 피드백 / P1 시스템 보강 / P2 분위기 연출
- **트리거 코드**: 실제 `SfxPlayer.play()` 호출 위치 (파일:심볼 단위)

## ElevenLabs 사용 가이드
- 영문 prompt가 잘 먹힘. duration_seconds는 ElevenLabs UI에 그대로 입력. prompt_influence 0.4~0.6 권장.
- 게임 톤: **사이버펑크 / 시설 침투 / 정밀한 SF**. 음악적이지 않게, 무톤(non-tonal) 또는 짧은 sub-bass.
- 공통 prefix(원하면 모든 prompt 앞에 붙임): `cyberpunk infiltration game sfx, dry studio recording, no music, no reverb tail, mono`
- 실제 loop 처리: `drone_hover`만 (positional AudioStreamPlayer2D). 결과를 Audacity에서 zero-crossing trim. 그 외 alarm/beep 류는 단발 재생.
- 변주 필요한 SFX(`player_step`, `player_hurt`)는 같은 prompt로 N개 생성 → 코드가 자동으로 `<id>1`, `<id>2` … 인식.

### 청취 부담 원칙 (장시간 플레이 기준)
**고빈도 SFX는 "들리지만 거슬리지 않게"**. 매분 수십 번 듣는 항목(`xp_collect`, `ui_*`, `plate_step_*`, `terminal_typewrite`, `veil_subtitle_in`)은 다음 금지어를 피한다:
- `bright`, `high-frequency`, `sharp`, `metallic ring`, `crystalline`, `chime`, `sparkle`, `stab`, `ping`, `sizzle`
- 대신: `warm`, `muted`, `rounded`, `soft`, `low-mid`, `wooden`, `breath`, `dull`

이벤트성 SFX(`siren_flash`, `boss_*`, `challenge_*`, `levelup`)는 임팩트가 필요하지만 **harshness ≠ impact** — piercing high-freq 대신 **low-frequency 무게**로 임팩트를 만든다.

### 음악 해석 주의 (음 시퀀스가 들어가는 prompt)
ElevenLabs는 음악 용어를 그대로 해석한다 — **모호한 단어는 의도와 다르게 나온다**:
- `chord` = **동시 화음** (도-미-솔 동시 울림)
- `notes / tones` 만 쓰면 **동시인지 순차인지 불명확** → ElevenLabs는 화음으로 해석할 때가 많음
- 순차 멜로디를 원하면 **`sequential` / `played one after another` / `arpeggio`** 같이 명시
- 동시 화음을 원하면 **`chord` / `simultaneous`** 명시
- `two-tone` / `three-note` 같은 표현은 그 자체로 모호 — 항상 sequential/simultaneous 보강
- `phrase` / `sequence` 도 음악 해석상 약함 — sequential인지 다시 강조 필요

빈도 분류:
- **고빈도** (매 분 N회): xp_collect, ui_focus, ui_confirm, ui_slider_tick, plate_step_*, terminal_typewrite, veil_subtitle_in, skill_active_use
- **중빈도** (스테이지당 N회): hp_collect, skill_pick, lever_pull, hatch_open, spike_hit, bullet_impact_*
- **저빈도 / 이벤트** (한두 번): levelup, gate_unlock, siren_flash, challenge_*, stage_clear_chime, arcturus_enter, bestiary_first_seen, boss_alert_text, boss_*, blackout_fade_in

---

## 1. Player

### `player_jump` ✅ P0 (0.2s)
- **트리거**: `Player.gd::_do_jump` (첫 점프 + 더블 점프 둘 다 재사용)
- **현재 보정**: `-10dB` (사용자 피드백 — 너무 큼)
- **prompt**: Short pneumatic jump push, soft fabric whoosh with quick mechanical click at the attack, dry, no reverb.

### `player_land` ✅ P1 (0.25s)
- **트리거**: `Player.gd::_handle_input` floor 착지 순간
- **현재 보정**: `+5dB`
- **prompt**: Soft thud of boots landing on metal grating, low frequency thump with very short metallic tap, dry.

### `player_dash` ✅ P0 (0.35s)
- **트리거**: `Player.gd::_do_dash`
- **현재 보정**: `-8dB`
- **prompt**: Sharp horizontal whoosh with electric crackle layered, fast attack, very short tail, sci-fi dash.

### `player_hurt` ✅ P0 (0.3s, 3 variants)
- **트리거**: `Player.gd::take_hit`
- **prompt**: Quick masculine grunt cut short, layered with low metallic impact, no music, dry. (variant마다 grunt 톤 살짝 다르게)

### `player_death` ✅ P0 (0.7s)
- **트리거**: `Player.gd::take_hit` hp 0 분기
- **prompt**: Heavy body collapse on metal floor, single low thump fading into electronic data corruption glitch, no music.

### `player_step` ✅ P2 (0.15s, 4 variants)
- **트리거**: `Player.gd::_handle_input` 이동 중 timer
- **현재 보정**: `+6dB`
- **prompt**: Soft single boot step on metal grating walkway, dry, mono, no reverb tail.

---

## 2. Combat — 사격 / 폭발

### `bullet_fire` ✅ P0 (0.15s)
- **트리거**: `Player.gd::_try_attack` (multishot이어도 1회)
- **현재 보정**: `-8dB` (너무 큼 — 연발이라 더 부담)
- **prompt**: Suppressed pistol shot, quick metallic pew with subtle electronic snap, very dry, no echo. Tight low-mid body, no high sizzle.

### `bullet_impact_wall` ✅ P1 (0.1s)
- **트리거**: `Bullet.gd::_on_body_entered` StaticBody2D 충돌 (단, `boundary_wall` 그룹 제외 — 맵 끝 경계벽은 무음)
- **현재 보정**: `-5dB`
- **prompt**: Single sharp metallic ping of small caliber bullet hitting steel plate, very short tick, no decay, dry.

### `bullet_impact_enemy` ✅ P0 (0.15s)
- **트리거**: `Enemy.gd::take_damage` / `TutorialDummy.gd::take_damage` (from_dir != 0, 방패 막힘 제외)
- **prompt**: Dull thud of bullet hitting armored synthetic body, low frequency punch with subtle soft impact, dry, no ring.

### `bullet_deflect_shield` ✅ P0 (0.25s)
- **트리거**: `Enemy.gd::take_damage` SHIELD 정면 막힘 + `TutorialDummy.gd::take_damage` 스킬 더미 튕김
- **prompt**: Loud metallic clang of bullet ricocheting off heavy steel shield, bright high frequency ring with short tail, sci-fi armor deflect.

### `bomb_throw` ✅ P0 (0.2s) — **보스 전용**
- **트리거**: `BossSentinel.gd::_drop_bomb`. (드론은 `enemy_drone_drop`만 재생 — 음향 분리.)
- **현재 보정**: `-2dB`
- **prompt**: Heavy launch thunk of large ordnance leaving a turret — short pneumatic punch with low-mid metallic body, no whoosh tail. Distinctly boss-scale, not handheld.

### `bomb_explode` ✅ P0 (0.5s)
- **트리거**: `Bomb.gd::_explode`
- **현재 보정**: `+6dB`
- **prompt**: Compact close-range explosion, mid-low frequency thump with debris crackle and brief shrapnel hiss, short controlled tail, no big reverb.

---

## 3. Enemy

### `enemy_patrol_fire` ✅ P0 (0.18s)
- **트리거**: `Enemy.gd::_patrol_fire` (Patrol FIRING 상태에서 `EnemyBullet` 발사 시)
- **prompt**: Mid-range military pistol shot, slightly muffled and heavier than player_fire, single dry crack with very small low-end punch, no high sparkle.

### `enemy_sniper_charge` ✅ P0 (0.45s)
- **트리거**: `Enemy.gd::_start_aim` (조준선 생성 순간)
- **prompt**: Rising electric hum charge-up, faint pulsing rhythm at increasing rate, ends WITHOUT release/click, sci-fi targeting laser warming up. Should sound incomplete on its own — paired with sniper_fire.

### `enemy_sniper_fire` ✅ P0 (0.18s)
- **트리거**: `Enemy.gd::_fire_at_player`
- **prompt**: Sharp cracking high-velocity rifle shot, bright snap with brief tail, distinctly louder and harsher than enemy_patrol_fire, single shot only.

### `enemy_drone_hover` ✅ P1 (3s seamless loop) — **positional, AudioStreamPlayer2D**
- **트리거**: `Enemy.gd::_setup_drone_hover_audio` — 드론 spawn 시 1회 attach 후 자동 loop. SfxPlayer 경유 안 함.
- **거리 감쇠**: `max_distance=900px`, `attenuation=1.6` (가까울수록 가속 커짐). base `volume_db=-14dB`에 `GameState.sfx_volume` 동기화.
- **prompt**: Steady low electric drone hum with quadcopter rotor whine layered on top, seamless 3-second loop, no variation across the loop. The loop must be cleanly cuttable — no fade in/out within the sample. Texture should be present but unobtrusive so multiple drones don't cumulatively overwhelm.

### `enemy_drone_drop` ✅ P1 (0.2s)
- **트리거**: `Enemy.gd::_drop_bomb` (드론이 폭탄 투하 직전)
- **현재 보정**: `-8dB` (너무 큼)
- **prompt**: Brief mechanical release click followed by faint object detachment whoosh, dry, subtle. NOT explosive — just the moment of release.

### `enemy_bomber_beep` ✅ P0 (1.5s, loop+accelerating recommended)
- **트리거**: `Enemy.gd::_tick_bomber` ARMING 진입 1회 (현재 단발 — 추후 loop 전환 검토)
- **prompt**: Electronic warning beep that accelerates from slow (≈3Hz) to fast (≈10Hz) over 1.5 seconds, single pulse tone, sci-fi proximity arming alarm. Each pulse should be very short and clean.

### `enemy_bomber_explode` ✅ P0 (0.6s)
- **트리거**: `Enemy.gd::_bomber_explode`
- **prompt**: Closer compact explosion than bomb_explode, sharper attack, slight glass-and-metal debris crackle, brief sub-bass thump under, no long tail.

### `enemy_hurt` ✅ P0 (0.12s, variants OK)
- **트리거**: `Enemy.gd::take_damage` (hp > 0)
- **현재 보정**: `-4dB`
- **prompt**: Brief mechanical buzz layered with a subtle low robotic grunt, dry. Short — should not linger past 0.15s.

### `enemy_death` ✅ P0 (0.35s)
- **트리거**: `Enemy.gd::_die` (Bomber 제외 — `_bomber_explode`가 죽음 소리 역할)
- **prompt**: Robotic shutdown thud, mid-low frequency drop with brief electronic dissipation tail and tiny servo whine fading out.

---

## 4. Boss (SENTINEL)

### `boss_phase_change` ⬜ P0 (0.6s)
- **트리거**: `BossSentinel.gd::_transition_to` (P1→P2, P2→P3 진입 순간)
- **prompt**: Heavy mechanical impact with deep sub-bass slam, brief electronic surge tail, ominous sci-fi power-up. Should feel weighty and final — the boss is entering a new phase.

### `boss_missile_launch` ⬜ P1 (0.25s)
- **트리거**: `BossSentinel.gd::_fire_missiles` (좌/우 두 발이지만 1회 재생)
- **prompt**: Compact twin missile launch hiss with mechanical ka-chunk, dry, slight metallic resonance, no reverb. Two-burst feel implied even though it's a single sample.

### `boss_hurt` ⬜ P1 (0.2s)
- **트리거**: `BossSentinel.gd::take_damage` (hp > 0)
- **prompt**: Heavy metallic dull impact, deeper and more resonant than enemy_hurt, brief electronic shudder tail, NO grunt — purely mechanical.

### `boss_self_destruct_alarm` ⬜ P0 (3s seamless loop)
- **트리거**: `BossSentinel.gd::_arm_self_destruct` (HP가 HP_SELF_DESTRUCT 이하로 떨어진 순간 — 현재 단발 재생, 추후 loop 전환 검토)
- **prompt**: Loud urgent mechanical klaxon repeating roughly every 0.6s, slight metallic clang on each pulse, low-mid alarm tone, seamless 3-second loop, dread-inducing sci-fi self-destruct warning.

### `boss_self_destruct_disarm` ⬜ P1 (1.2s)
- **트리거**: `BossSentinel.gd::_die` (자폭 전 처치한 경우 — 카운트다운 진행 중)
- **prompt**: Power-down hum descending in pitch over 1 second, system relaxing, soft electronic sigh tail. Sense of relief — the threat just got neutralized.

### `boss_death` ⬜ P0 (1.6s)
- **트리거**: `BossSentinel.gd::_die`
- **prompt**: Massive mechanical explosion with prolonged metallic tearing tail, sub-bass slam followed by debris and brief electric arcs fading. Should sound bigger than enemy_bomber_explode.

> **제거됨**: `boss_charge_telegraph` / `boss_charge_dash` — BossSentinel은 charge 공격이 없음 (bomb + missile + self-destruct only). 기존 design doc 잔재.

---

## 5. Pickups / Skills

### `xp_collect` ✅ P0 (0.15s) — **고빈도 / poly**
- **트리거**: `ExpOrb.gd` magnet 흡수
- **prompt**: Single very soft brief pickup sound with warm low-mid body, like a muted soft impact or rounded thud (NOT a plucked string, NOT a chime, NOT a bell), no high sparkle, no metallic ring, decays naturally in 0.15s. Designed so many can overlap without harshness — must remain pleasant after hundreds of plays.

### `hp_collect` ✅ P0 (0.35s)
- **트리거**: `HpOrb.gd` 흡수
- **prompt**: Brief soft muted whoosh of warm air being absorbed, completely non-tonal — no pitch, no chord, no chime, no bell character. Single low-mid body like a cushioned cloth settling or a quiet exhale. Dry, 0.35s gentle decay.
- **참고**: "heal/restoration/health" 같은 단어는 ElevenLabs가 bright fantasy chime으로 해석함 → prompt에서 의도적으로 제거. 대신 물리적 이벤트(공기 흡수/천 접힘)로 묘사.

### `levelup` ✅ P0 (0.7s) — **이벤트성**
- **트리거**: `LevelUpOverlay.gd` 진입
- **prompt**: Three warm rounded notes played sequentially one after another in rising pitch (like do-mi-sol arpeggio, NOT a chord), each note brief and clean, mid-low body without crystalline shimmer or high sparkle, decisive but not piercing, total duration 0.7s with gentle decay on the last note.
- **참고**: "chord" 쓰면 동시 화음으로 해석됨 → `sequentially one after another` + `NOT a chord` 명시.

### `skill_pick` ✅ P1 (0.22s)
- **트리거**: `LevelUpOverlay.gd` 카드 confirm
- **prompt**: Muted digital tap of selection, soft warm low-mid click, no holographic sweep or sparkle, dry and brief, 0.22s.

### `skill_active_use` ✅ P0 (0.25s) — **고빈도**
- **트리거**: `Player.gd::_try_skill` (액티브 스킬 발동 — 폭발물 등)
- **prompt**: Brief warm pneumatic release with muted low-mid punch, sci-fi gadget engaging, no electric zap or crackle, no high frequencies, dry and focused.

---

## 6. Environment / Hazards

### `spike_hit` ✅ P0 (0.18s)
- **트리거**: `Stage.gd` spike 충돌 처리
- **prompt**: Single dull low-mid body impact with brief muted thud, mechanical NOT vocal, no metallic ring, no high-frequency stab, grounded and brief 0.18s.

### `lever_pull` ✅ P0 (0.35s)
- **트리거**: `LeverInteractable.gd::try_pull`
- **prompt**: Heavy mechanical lever motion, low-mid ratchet body with weighted contact thunk, dry industrial, no metallic resonance or high overtones.

### `plate_step_inactive` ✅ P2 (0.2s) — **고빈도**
- **트리거**: `PressurePlate.gd` armed=false 상태에서 step
- **prompt**: Dull muted footstep on dead plate, very brief low thud, no resonance, designed to feel ignored — should not register strongly.

### `plate_step_active` ✅ P0 (0.3s) — **고빈도**
- **트리거**: `PressurePlate.gd` armed plate stepped
- **prompt**: Soft pneumatic engage click followed by a single brief warm power-on hum in mid-low range (single sustained tone, not a melody), plate confirming under foot, no bright chime or sparkle, total 0.3s.

### `hatch_open` ✅ P1 (0.55s)
- **트리거**: `Stage.gd::_open_hatch`
- **prompt**: Gentle pneumatic release with low-mid panel sliding, soft motor whir, dry and unobtrusive, no sharp hiss.

### `drop_platform_descend` ✅ P1 (0.7s)
- **트리거**: `Stage.gd::_descend_drop_platform`
- **prompt**: Low hydraulic rumble of platform lowering, warm low-mid body, soft thud landing at the end, no high mechanical detail.

### `gate_unlock` ✅ P0 (0.55s) — **이벤트성**
- **트리거**: `Stage.gd` 도전방 게이트 fade
- **prompt**: Warm low magnetic disengage with muted panel slide, sci-fi access tone in mid range, no electric click sparkle, satisfying without harshness.

### `siren_flash` ✅ P0 (0.8s) — **이벤트성**
- **트리거**: `Stage.gd::_play_siren_flash`
- **prompt**: Two short mid-low alarm whoops in quick succession (≈0.3s apart), warm warning tone, urgent but NOT piercing — no high-frequency klaxon edge.

### `blackout_fade_in` ✅ P1 (1.2s) — **이벤트성**
- **트리거**: challenge_dark_root fade in
- **prompt**: Deep ominous sub-bass swell rising slowly, oppressive sci-fi atmosphere, no high frequencies, ends sustained in low register.

### `challenge_clear` ✅ P0 (0.7s) — **이벤트성**
- **트리거**: 도전방 골 도달
- **prompt**: Two or three soft warm rounded tones played sequentially one after another in rising pitch (arpeggio style, NOT simultaneous chord), each tone brief with gentle attack, relieved feeling, no crystalline sparkle or high shimmer, total 0.7s with soft decay on the last tone.

### `challenge_fail` ✅ P0 (0.55s) — **이벤트성**
- **트리거**: `Stage.gd::_challenge_fail`
- **prompt**: Low descending muted tone of failure, warm mid-low body, abrupt but not harsh, dry, no buzzer edge or high-frequency cut.

---

## 7. UI / Menu

### `ui_focus` ✅ P1 (0.06s) — **고빈도 / 거의 안 들릴 정도**
- **트리거**: 메뉴 버튼 focus_entered
- **prompt**: Almost imperceptible soft tap, very brief muted mid-tone tick, no high-frequency edge, designed to be felt more than heard.

### `ui_confirm` ✅ P0 (0.14s) — **고빈도**
- **트리거**: 메뉴 버튼 pressed
- **prompt**: Two soft warm muted tones played in very quick succession (one after another, NOT simultaneous), brief low-mid body, no chime brightness or sparkle, dry total 0.14s.

### `ui_cancel` ✅ P1 (0.12s)
- **트리거**: ESC / B
- **prompt**: Brief low descending muted click, soft negative tone, no sharp edge, dry 0.12s.

### `ui_slider_tick` ✅ P2 (0.05s) — **최고빈도 / 가장 부드러워야**
- **트리거**: volume slider 값 변경
- **prompt**: Micro soft tick, single muted grain, extremely brief, no tonal character, nearly subliminal — many can fire in rapid succession without fatigue.

### `ui_pause_open` ✅ P2 (0.25s)
- **트리거**: pause overlay open
- **prompt**: Soft muffled woosh pulling inward, brief low-frequency dip, warm sci-fi pause-in, no sharp transient or high air.

---

## 8. Story / Special

### `veil_subtitle_in` ✅ P2 (0.12s) — **고빈도 / 대사마다**
- **트리거**: VEIL 자막 fade in
- **prompt**: Faintest soft data tick, very brief muted comm chirp at low volume, no high-frequency edge — must not interrupt the spoken line or fatigue the listener.

### `arcturus_enter` ✅ P1 (0.9s) — **이벤트성**
- **트리거**: `ArcturusDocumentOverlay.gd` 진입
- **prompt**: Deep ominous low swell with soft paper rustle and hush, warm mysterious archive opening, sense of stepping into something older, no high frequencies.

### `terminal_typewrite` ✅ P2 (0.05s, one-shot click; code loops per char) — **최고빈도 / 글자마다**
- **트리거**: ARCTURUS 문서 타자 per-char
- **prompt**: Very soft muted key tap, brief warm wooden-like click without mechanical edge or resonance, extremely short, designed to layer hundreds of times without becoming harsh.

### `bestiary_first_seen` ✅ P2 (0.35s) — **이벤트성**
- **트리거**: `BestiaryData.gd::mark_enemy_seen` 첫 조우
- **prompt**: Warm low resonant tone, single rounded note of catalog acknowledgment, brief weight without bell sparkle or high overtones.

### `stage_clear_chime` ✅ P1 (0.7s) — **이벤트성**
- **트리거**: `Stage.gd::_begin_clear_sequence`
- **prompt**: Three soft warm notes played sequentially one after another in rising pitch (arpeggio style, NOT a chord), each note rounded and brief, mid-low warmth without crystalline ring or sparkle, satisfied accomplishment feeling, total 0.7s with gentle decay on the last note.

### `boss_alert_text` ✅ P1 (0.3s) — **이벤트성**
- **트리거**: `Stage.gd::_show_boss_alert`
- **prompt**: Low warm alarm sting with mid-range warning pulse, danger emphasis through weight not piercing edge, no high-frequency stab, brief 0.3s.

---

## 코드 연결 메모

- 파일 위치: `assets/sfx/<id>.mp3`. 확장자 mp3/ogg/wav 모두 가능 (`SfxPlayer._SFX_EXTENSIONS` 순서대로 시도).
- variant: `<id>1.mp3`, `<id>2.mp3` … 자동 등록. `SfxPlayer.play(id)`가 무작위 하나 재생.
- 볼륨 보정은 `scripts/SfxPlayer.gd::VOLUME_OFFSETS` 사전에 dB 값 추가.
- loop 처리: `drone_hover`만 `AudioStreamPlayer2D` positional loop (`Enemy.gd::_setup_drone_hover_audio`). `enemy_bomber_beep` / `boss_self_destruct_alarm`은 단발 재생 유지 결정.
- 신규 SFX ID 추가 시 `KNOWN_SFX` 배열에도 등록.
