# 막4/5 BGM 보강 계획

> 2026-08-10 사용자 피드백("act3 끝나고 다음 맵에서 다시 돌아오는 BGM이 더 박진감 있는 새 것 필요").
> **✅ 적용 완료(2026-08-10 세션 2, 커밋 2b744b5)**: 사용자가 Broken Wire·Violet Signal 생성 →
> 커버 제거·꼬리 트림 → §4 배선(막 기반 선곡 + confront 루프 오프셋 25s) + lab 보스 인트로 컷씬까지.
> Violet Signal은 계획과 달리 막5 전용이 아니라 **lab 보스전 + 막5 겸용**으로 확정(빌드업=인트로 구간).
> 남은 것: 실플레이 청취(전환 이음매·루프)와 탈출 s14 분리 여부.

## 1. 진단: "다시 돌아오는 그 곡" = Cold Wire

- `BgmPlayer.gd`: TRACKS 사전(9곡 mp3), 크로스페이드 전환(1.2s/0.9s), AudioStreamMP3 네이티브 루프.
- `Stage.gd` `_ROUTE_TRACKS`: **막(act) 개념 없이 라우트 단위 매핑**. 사전에 없으면 "early" 폴백.
- `GameState.ACTS`의 `bgm` 필드는 코드 어디서도 읽지 않는 문서용 필드(실재생과 무관).
- 실재생: 막2~3 전투(s3~7) mid_late=**Cold Wire** → 막3 보스(s8) boss=Chrome Grit →
  **막4(s9~11) 전부 mid_late=Cold Wire 복귀** → 막5 전투(s12)도 Cold Wire.
  최악의 경우 Cold Wire가 15스테이지 중 10개 안팎을 덮는다. 보스 고점 직후 익숙한 곡 복귀 =
  "라이벌 영역 진입" 서사 파열이 음악에선 후퇴로 들림.
- **발견된 버그**: `route_core_recovery`(s13 회수 클라이맥스)가 _ROUTE_TRACKS에 누락 →
  가장 이완된 초반곡 Cold Gear 폴백. → 2026-08-10 잠정 수정: "boss"(Chrome Grit) 매핑.
  신곡 도입 시 막 기반 선곡으로 재배선.

## 2. 신곡 2곡 제안

기존 시리즈 = 진행할수록 BPM 상승(Glass Protocol → Cold Gear → Cold Wire → Chrome Grit).
막4/5는 단순히 더 빠른 곡이 아니라 같은 산업 전자 톤에 이질감(디튠·글리치·정전기)을 섞은 변절 파트.

### 곡 1 · 막4 추적(pursuit) · 핵심, 피드백의 직접 응답

- 곡명 후보: **Broken Wire**(추천: Cold Wire가 침식당해 돌아온다는 서사) / Violet Vector / Static Chase
- 정서(act_identity §6): 멈추면 잡힌다, 판이 무너진다, 내 눈도 온전치 않다. 보스보다 무겁기보다 빠르고 쫓기는 결.
- Suno 스타일 프롬프트(가사 칸 비움):

```
[Instrumental] dark industrial electronic chase theme, relentless driving beat around 150 bpm, pulsing distorted bass, glitchy detuned synth stabs, radio static and signal interference textures, cold mechanical tension, no vocals
```

### 곡 2 · 막5 대면(confront)

- 곡명 후보: **Violet Signal**(추천) / Core Descent / Dead Frequency
- 정서(§7): 심장부 수렴, 시안과 바이올렛이 같은 심장에서. 속도보다 압도·장엄·불협.
  향후 14-1 라이벌 보스 BGM 겸용 가능한 강도로.

```
[Instrumental] ominous cinematic industrial electronic, heavy pounding drums over fast dark arpeggios around 140 bpm, deep distorted sub bass, dissonant choir-like synth pads, final confrontation dread, no vocals
```

- 곡마다 2~3 take 생성해 좋은 것 선택. 최소안(곡 1만, 막5는 Chrome Grit 재사용)도 가능하나
  Chrome Grit은 SENTINEL(시설)의 곡이라 라이벌 정체성과 겹침 → 2곡안 추천.

## 3. 파일 스펙

- **mp3 유지**(기존 9곡 전부 mp3 48kHz, BgmPlayer가 AudioStreamMP3 분기로 루프). Suno 출력도 mp3.
- 커버 아트 제거: `ffmpeg -i in.mp3 -vn -c:a copy out.mp3`(기존 9곡 전부 mjpeg 커버 내장 확인 ·
  기존분 일괄 제거는 별도 용량 다이어트 건).
- 음량: BASE_DB -8.0 기준. volumedetect로 Cold Wire·Chrome Grit과 비교, ±2dB 넘으면 volume= 보정.
- 루프: 네이티브 loop=true(끝→처음 즉시 점프)라 페이드아웃 아웃트로를 마디 경계에서 트림이 핵심.
  목표 2:30~4:00. 인트로 빌드업이 긴 take는 루프 복귀 시 김이 빠지므로 비트 바로 시작하는 take 선택.
- 원본 take는 `assets_src/`(신설, .gdignore) 보관.

## 4. 배선 계획 (구현 시)

1. `BgmPlayer.gd` TRACKS에 `"pursuit"`·`"confront"` 추가.
2. `Stage.gd` `_apply_bgm_for_current_route()`를 막 인지형으로: 라우트 특수 케이스(lab→boss,
   hidden→hidden) 우선, 그 외 막4+는 `GameState.act_def(stage)["bgm"]` 기반. 막1~3은 기존
   _ROUTE_TRACKS 유지. → 막4/5에 겹쳐 등장하는 라우트가 스테이지 따라 자동 분기 + core_recovery
   폴백 버그 원천 해소.
3. `GameState.gd` ACTS bgm 필드 실데이터 승격: act4 "pursuit" / act5 "confront".
4. 막4 진입 전환은 기존 막 카드 + 크로스페이드(1.2s)가 자동으로 문턱 연출이 됨.
5. 탈출(s14) 선곡: 막 기반이면 confront 유지. 이완을 원하면 escape만 특수 케이스(사용자 확인).
6. 검증: 부팅 스모크 + s9·s13 트랙 전환 + 실플레이 청취(이음매).

## 5. 역할 분담

- 사용자: Suno 생성(위 프롬프트 2건, take 2~3개씩) + 곡명 선택.
- Claude: 커버 제거·음량 보정·루프 트림 → assets/bgm 배치 → 배선(§4) → 검증 → 커밋.
