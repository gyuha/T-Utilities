<!-- forge-slug: plain-text-paste-hotkey -->
<!-- task: 1 -->
<!-- tdd: on -->
# 클립보드 plain text 붙여넣기 전역 단축키 (GitHub #9)

## 목표 / 비목표
- 목표: 서식 있는 클립보드(웹·Word 등)의 텍스트를 서식 없이 포커스된 앱에 붙여넣는 전역 단축키를 클립보드 모듈에 추가한다. 단축키는 기존 설정 화면(KeyboardShortcuts.Recorder)에서 변경 가능하다. 기본값은 ⌥⇧⌘V(기존 열기/닫기 ⌘⇧V와 겹치지 않음).
- 비목표: 히스토리 저장 방식 변경(이미 plain `.string`), 팝오버 UI 변경, OCR 경로 변경, 릴리스/버전 bump.

## Source of truth
- Glossary terms: none
- Related ADRs: none
- 동작: 단축키 발동 → 현재 `NSPasteboard.general`에서 문자열 추출 → 문자열이 없으면 no-op → 원본 아이템 스냅샷 저장 → 클립보드를 `.string` 하나로 교체(`willWriteToClipboard`로 모니터 억제) → 포커스된 앱에 ⌘V 전송(`Paster.postCommandV`, Accessibility 권한 필요) → 짧은 지연 후 원본 서식 아이템 복원(복원도 모니터 억제).
- Definition of Done: loop.md의 C1~C4 모두 통과. C1/C3의 새 테스트는 구현 전(red)에 실패하고 구현 후(green) 통과해야 한다. 기준선에서 C2·C4는 이미 통과 — 회귀 방지용(forward check 아님).
- 자동화 불가 항목: 실제 앱 붙여넣기 UAT는 Accessibility 권한 필요로 제외(사람 확인).

## 작업 슬라이스
- [ ] S1. `PlainTextPaste` 로직(테스트 가능하도록 pasteboard를 주입받는 순수 부분: 스냅샷·plain 교체·복원)과 단위 테스트(이름에 `PlainText` 포함, ≥ 4개: rich→plain 변환 · 텍스트 없으면 no-op · 원본 서식 복원 · 복원 바이트 동일) — 완료 기준: `swift test --filter PlainText` 통과 ≥ 4
- [ ] S2. `ClipboardModule`에 `KeyboardShortcuts.Name`(기본 ⌥⇧⌘V)과 `HotkeyDefinition` 등록 + 발동 시 S1 호출 및 `Paster` 사용, 모니터 억제 연결, 단축키 등록 단위 테스트(이름에 `hotkey` 포함) — 완료 기준: `swift test` 전체 통과, hotkey 테스트 ≥ 1 (depends: S1)
- [ ] S3. 전체 빌드·회귀 확인 — 완료 기준: C2 `BUILD SUCCEEDED`, C4 TUCore 테스트 통과 (depends: S2)
