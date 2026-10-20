# RUN — 클립보드 plain text 붙여넣기 전역 단축키

워크플로우 없이 메인 세션에서 직접 실행(소규모 작업, TDD: 테스트 먼저 → 컴파일 실패 red 확인 → 구현 green).

- S1 PlainTextPaste(스냅샷·plain 교체·복원) + 테스트 4개 — ✅ 계획대로
- S2 ClipboardModule 핫키(`clipboard.plainTextPaste`, 기본 ⌥⇧⌘V) 등록 + 등록 테스트 — ✅ 계획대로 (Accessibility 미허용 시 권한 요청 후 중단)
- S3 빌드·회귀 — ✅ 계획대로

## 이탈
- 테스트에서 `pasteboard.types == [.string]` 단언이 OS가 추가하는 동의 타입 때문에 실패 → "html/rtf 없음 + string 있음"으로 완화(의미 동일, 서식 제거 검증은 유지).
- `Paster.postCommandV`를 private → internal로 변경(재사용).

## DoD baseline → after
- C1: PlainText 테스트 0 → 5 통과(전체 14 통과)
- C2: BUILD SUCCEEDED → BUILD SUCCEEDED (회귀 방지, 기준선부터 통과)
- C3: hotkey 테스트 0 → 1 통과
- C4: TUCore 8 → 8 통과 (회귀 방지)
- 미검증: 실제 앱 붙여넣기(Accessibility 필요, 사람 확인)
