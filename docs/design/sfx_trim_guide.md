# SFX 후처리 가이드

ElevenLabs SFX는 종종 앞뒤에 짧은 무음/노이즈 꼬리가 붙어 나옴. 게임 액션에
바로 들리지 않거나 미세하게 늦게 들리면 이 무음이 원인.

## 우선 — 그냥 한 번 들어보기

대부분의 ElevenLabs 짧은 SFX는 무음이 50~150ms 수준이라 빠른 액션
게임에서는 거의 인지가 안 됨. **먼저 게임 안에서 한 번 플레이해보고**, 거슬리면
아래 방법 중 하나로 trim.

## 방법 1 — Audacity (무료 GUI, 가장 추천)

1. 다운로드: https://www.audacityteam.org/  (Windows 설치 파일)
2. 파일 열기: `File → Open` → `assets/sfx/<id>.mp3`
3. 파형에서 시작 부분 무음 영역 마우스 드래그로 선택
4. `Edit → Delete` (또는 키보드 `Ctrl+K`)
5. 같은 방식으로 끝부분 노이즈 꼬리도 잘라내기
6. 저장: `File → Export → Export as MP3` → 같은 파일에 덮어쓰기
7. Godot 에디터를 한 번 켰다 끄거나 `--import` 명령으로 reimport.

소요 시간: 파일당 30초 이내. 12개 파일이면 5~10분.

### Audacity 팁
- `View → Zoom In` (`Ctrl+1`)으로 파형 확대해서 무음 경계를 정확히 보기.
- 시작 무음만 잘라도 충분. 끝부분은 페이드아웃이라 거의 안 거슬림.
- 여러 파일 한꺼번에 처리하려면 `File → Open` 후 각 트랙을 별도 창으로 작업.

## 방법 2 — ffmpeg one-liner (CLI 친한 사람용)

PowerShell에서 `assets/sfx` 폴더에서:

```powershell
# 단일 파일 — 시작/끝 무음 자동 제거
ffmpeg -i player_jump.mp3 -af "silenceremove=start_periods=1:start_silence=0.05:start_threshold=-50dB:detection=peak,areverse,silenceremove=start_periods=1:start_silence=0.05:start_threshold=-50dB:detection=peak,areverse" -y player_jump_trimmed.mp3

# 결과 확인 후 원본 덮어쓰기
mv player_jump_trimmed.mp3 player_jump.mp3
```

ffmpeg 없으면 `winget install ffmpeg` (Windows 11) 또는 https://ffmpeg.org/.

## 방법 3 — 그냥 두기 (실전 권장)

게임 안에서 효과음은 다른 시각/물리 피드백과 함께 들리고, 50ms 무음은 거의
체감 안 됨. 특히:
- `player_jump` / `player_dash` — 즉각성 중요. 거슬리면 trim.
- `player_step` — 발걸음. 약간 늦어도 자연스러움.
- `player_hurt` / `player_death` — 임팩트 SFX. 약간 늦어도 OK.

## SfxPlayer가 자동 처리하는 것

- **확장자 자동 탐색**: .mp3 / .ogg / .wav 순서로 첫 매치 사용.
- **variant 자동 등록**: `<id>1.mp3`, `<id>2.mp3` ... 9까지 자동 스캔.
- **MP3 loop=false 강제**: AudioStreamMP3 기본 loop=true인데 SFX는 단발이라
  명시적으로 loop=false로 강제. trim 안 해도 무한 반복은 안 됨.

## 새 SFX 추가 시 워크플로

1. ElevenLabs로 생성 → mp3 다운로드
2. 파일명을 `<sfx_list.md ID>.mp3`로 저장 (예: `player_jump.mp3`)
3. variant 여러 개면 `<id>1.mp3`, `<id>2.mp3` ... 형태로
4. `assets/sfx/`에 복사
5. (선택) Audacity로 trim
6. Godot 에디터 한 번 켜기 → 자동 import
7. 게임에서 해당 액션 실행 → 자동 재생 확인

## 코드 호출 예시

이미 연결된 곳:
- `Player.gd::_try_jump` → `SfxPlayer.play("player_jump")` / `"player_double_jump"`
- `Player.gd::_try_dash` → `SfxPlayer.play("player_dash")`
- `Player.gd::take_hit` → `SfxPlayer.play("player_hurt")` (variant 랜덤)
- `Player.gd::_physics_process` → 착지 시 `"player_land"`, 이동 중 `"player_step"`
- `Player.gd::take_hit` 사망 분기 → `SfxPlayer.play("player_death")`

새 카테고리 SFX(combat / enemy / boss 등) 받아오면 같은 패턴으로 호출 추가.
