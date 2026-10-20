<!-- forge-slug: easy-move-resize -->
<!-- task: 1 -->
<!-- tdd: off -->
# Windows 모듈에 easy-move-resize(⌥ + 드래그 이동 / ⌥ + 우클릭 드래그 리사이즈) 추가

## Goal / Non-goals
- Goal: GitHub Issue #4. 수정키(기본 ⌥)를 누른 채 창의 아무 곳이나 좌클릭 드래그하면 창 이동, 우클릭 드래그하면 리사이즈(원본처럼 커서가 있는 창 사분면 기준). Windows 모듈 설정 페인에서 기능 on/off와 modifier(⌃/⌥/⇧/⌘) 선택 가능.
- Non-goals: 다른 모듈/앱 셸 변경, 버전 bump·릴리스, 창 스냅/타일링, 원본의 메뉴바 아이콘·로그인 시 실행·앱별 비활성 목록, 이슈/PR 게시.

## Source of truth
- Glossary terms: none (.forge/CONTEXT.md 없음)
- Related ADRs: none
- 참고 구현: dmarcotte/easy-move-resize (MIT) — 사분면 기반 리사이즈와 mouse-down 흡수 아이디어만 차용, 직접 재작성. 이식한 부분이 있으면 THIRD_PARTY_NOTICES.md 에 고지.
- 기존 코드 관례: `AXWindow`(at/frame/setFrame), `EdgeResizeSnap`(전역 이벤트 모니터), `WindowsModule`(settings.value/set, start/stop), 주석은 영어, UI 문자열은 한국어.
- Definition of Done (loop.md C1–C6 와 동일, 기준선 기록됨):
  1. `(cd Packages/ModWindows && swift test --filter ModifierDragTests 2>&1)` ✔ ≥ 8, ✘ 0 (기준선 0)
  2. `(cd Packages/ModWindows && swift test 2>&1)` exit 0, N ≥ 23, ✘ 0 (기준선 N=15; 기존 15개 통과는 회귀 가드)
  3. `grep -c 'CGEvent.tapCreate' Packages/ModWindows/Sources/ModWindows/*.swift` 합 ≥ 1, `grep -c 'modifierDrag' .../WindowsModule.swift` ≥ 4 (기준선 0)
  4. `xcodegen generate >/dev/null && xcodebuild -project T-Utilities.xcodeproj -scheme T-Utilities -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3` 에 BUILD SUCCEEDED (회귀 가드: 기준선 이미 통과)
  5. README.md · THIRD_PARTY_NOTICES.md 각각 `grep -c 'easy-move-resize'` ≥ 1 (기준선 0)
  6. 범위 가드: loop.md C6 명령 → 0 (회귀 가드: 기준선 이미 0)

## Work slices
- [ ] S1. `ModifierDrag.swift` — 순수 로직(UI/AX 비의존): modifier OptionSet(⌃⌥⇧⌘)과 CGEventFlags 매칭(정확히 일치할 때만), 이동 델타 계산, 리사이즈 사분면 판정 및 최소 크기 보정, 설정 직렬화(기본 ⌥) + `ModifierDragTests.swift` 8개 이상 — completion criterion: DoD 1
- [ ] S2. `ModifierDragController.swift` — `CGEvent.tapCreate` 기반 이벤트 탭(leftMouseDown/Dragged/Up, rightMouseDown/Dragged/Up). modifier 일치 시 mouse-down 흡수, 드래그 중 `AXWindow.at` 로 잡은 창을 S1 로직으로 이동/리사이즈, 탭 비활성화 시 재활성화, stop 시 탭 해제 — completion criterion: DoD 3 앞부분, DoD 4 (depends: S1)
- [ ] S3. `WindowsModule` 배선 + 설정 UI — `modifierDrag` on/off 프로퍼티(기본 on)와 modifier 체크박스 4개, start/stop 연동, 설정 persist. 기존 `edgeVerticalFill`과 같은 패턴 — completion criterion: DoD 2, 3, 4 (depends: S2)
- [ ] S4. README 모듈 표(Windows 행 Based on에 easy-move-resize 추가)·설명, THIRD_PARTY_NOTICES.md 에 easy-move-resize(MIT, © Daniel Marcotte) 항목 추가, PLAN.md Windows 범위에 한 줄 — completion criterion: DoD 5, 6
