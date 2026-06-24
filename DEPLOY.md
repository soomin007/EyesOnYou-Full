# 배포 자동화 — GitHub Pages

`git push origin main` 하면 자동으로 빌드되어 `https://<user>.github.io/EyesOnYou/`에 올라가는 환경.

---

## 1회 셋업 (한 번만)

### 1. Godot에서 Web 프리셋 만들기

1. Godot 4.6에서 프로젝트 열기
2. 메뉴 → **Project → Export...**
3. **Add...** → **Web** 선택
4. 우측 옵션 패널에서 **Variant → Thread Support** 체크 **해제** (중요!)
   - 이유: GitHub Pages는 SharedArrayBuffer 헤더 못 보내서, Threads 켠 export는 작동 안 함.
   - 단일 스레드 export는 성능 살짝 떨어지지만 이 게임 규모에선 체감 없음.
5. **Export Path**: `build/index.html` (또는 비워둬도 됨 — 워크플로가 지정)
6. 좌하단 **Save Presets** 또는 그냥 창 닫으면 자동 저장됨
7. 결과: 프로젝트 루트에 `export_presets.cfg` 파일 생성됨

### 2. cfg 파일 커밋

```bash
git add export_presets.cfg
git commit -m "chore: Web export preset 추가 (GitHub Pages 자동 배포용)"
```

### 3. GitHub repo Pages 활성화

1. GitHub에서 EyesOnYou repo 열기
2. **Settings → Pages**
3. **Source**: `GitHub Actions` 선택 → 자동 저장
   - (Branch 방식 아님. Actions가 직접 배포해서 별도 gh-pages 브랜치 안 만들어짐.)

### 4. 첫 배포

```bash
git push origin main
```

- GitHub Actions 탭에서 워크플로 진행 상황 확인 가능
- 처음엔 Godot 바이너리(~80MB) + export template(~600MB) 다운로드라 5~7분 걸림
- 두 번째부터는 캐시 사용해 1~2분

---

## 동작 흐름

```
git push origin main
    ↓
.github/workflows/deploy.yml 실행
    ↓
build job:
  1. Godot 4.6 바이너리 + export template 다운로드(첫 회) / 캐시 사용
  2. export_presets.cfg의 "Eyes On You" 프리셋으로 빌드
  3. build/ 디렉토리에 index.html, .wasm, .pck 등 생성
  4. actions/upload-pages-artifact가 build/를 artifact로 업로드
    ↓
deploy job:
  5. actions/deploy-pages가 artifact를 Pages에 직접 배포
    ↓
https://<user>.github.io/EyesOnYou/ 에서 서빙
```

별도 gh-pages 브랜치가 만들어지지 않음 — Actions API로 직접 Pages에 push.

---

## 트러블슈팅

### "export_presets.cfg가 없어요" 에러
→ 셋업 1단계를 안 했음. Godot 에디터에서 Web 프리셋 만들고 cfg 커밋.

### "Web 프리셋이 없어요" 에러
→ cfg는 있는데 프리셋 이름이 다름. Godot에서 프리셋 이름을 정확히 `Web`으로 변경하거나, 워크플로의 `EXPORT_PRESET` env 변수를 실제 이름으로 수정.

### 빌드는 되는데 게임이 검은 화면
→ Threads Support 끄지 않았을 가능성. Godot 에디터에서 다시 확인하고 cfg 커밋.

### "Export templates not found"
→ Godot 버전과 export template 버전 불일치. 워크플로의 `GODOT_VERSION` env가 실제 사용 중인 버전과 같은지 확인.

### "Pages site failed" 에러
→ repo Settings → Pages → Source가 "GitHub Actions"인지 확인. "Deploy from a branch"로 설정돼 있으면 워크플로 deploy 단계가 실패함.

### "Resource not accessible by integration" 에러
→ 워크플로 권한 문제. repo Settings → Actions → General → Workflow permissions에서 "Read and write permissions" 선택. 또는 deploy.yml의 `permissions` 블록 확인.

### itch.io에 올릴 때
→ 별개로 manual export. Godot에서 export → zip → itch에 업로드.
   itch는 "SharedArrayBuffer" 옵션 켜서 Threads ON 빌드 가능 → 성능 ↑.
   GitHub Pages용(Threads OFF)과 itch용(Threads ON) 두 프리셋 만들어 두면 편함.

---

## Manual Export (Godot 에디터에서 직접 빌드할 때)

> **평소엔 manual export 할 일 없음** — `git push origin main`만 하면 GitHub Actions가 자동 빌드/배포한다.
> Manual은 itch.io 업로드용이나 로컬에서 빌드 결과 확인할 때만.

### 핵심 룰: Export Path를 반드시 `build/index.html`로

Godot 에디터 `Project → Export` 창에서 "Web" 프리셋 선택 후 **하단의 Export Path를 `build/index.html`로 지정**한 뒤 "Export Project" 클릭.

```
Export Path:  build/index.html        ← 이렇게
              ^^^^^^^^^^^^^^^^^^^^
              (절대 비워두거나 루트에 그대로 export 하지 말 것)
```

**왜**: 비워두면 산출물 12개 파일(`Eyes on You.html` / `.wasm` ~36MB / `.pck` / `.js` / `.import` 등)이 프로젝트 루트에 깔리고, 매번 청소해야 한다.
`build/` 폴더로 export하면 `.gitignore`에 이미 잡혀 있어 git이 자동으로 무시한다.

### itch.io 업로드 흐름

1. Export Path = `build/index.html`로 export
2. `build/` 안의 모든 파일을 zip으로 묶음
3. itch.io 프로젝트 페이지에 업로드
4. itch는 "SharedArrayBuffer" 옵션 켜서 Threads ON 빌드 가능 → 성능 ↑.
   GitHub Pages용(Threads OFF)과 itch용(Threads ON) 두 프리셋을 따로 만들어 두면 편하다.

### 만약 루트가 이미 `Eyes on You.*`로 어지러워졌다면

```bash
rm "Eyes on You."*
```

`.gitignore`로 이미 막혀 있어 git에는 영향 없다. 안심하고 삭제.

---

## 같은 패턴을 enigma에도 적용하려면

1. enigma repo에 동일한 `.github/workflows/deploy.yml` 복사
2. enigma 프로젝트에서 Web 프리셋 똑같이 만들기 (Threads off)
3. cfg 커밋, push → 자동 배포

워크플로 yaml은 게임 이름 의존성 없어서 그대로 복붙 가능.
