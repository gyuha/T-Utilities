# CPU · 메모리 최적화 세션 가이드

작성: 2026-10-20, 기준 버전 **v0.1.2** (커밋 `cdd0f2a` 이후). PLAN.md 부록 B를 대체·보완함.

## 1. 진행 방식

1. **기준선 측정** — 코드 변경 전, 같은 조건으로 전체·모듈별 CPU/메모리를 측정해 CSV로 저장.
2. **최적화** — 후보(§6)를 하나씩 적용. 변경마다 커밋을 나눠 효과를 분리해서 볼 수 있게 함.
3. **재측정** — 같은 스크립트·같은 조건으로 다시 측정하고 기준선과 비교(§7 양식).
4. **회귀 확인** — §8 체크리스트로 기능이 그대로인지 사용자와 확인.

비교가 의미 있으려면 **빌드 종류, 측정 시간, 사용 중인 앱 환경, 모듈 설정값**이 전후로 같아야 함.

## 2. 측정 전 준비와 주의사항

- **측정은 Release 빌드로.** Debug 빌드는 `T-Utilities.debug.dylib` 구조라 메모리 수치가 다름.
  - 기준선: 설치된 `/Applications/T-Utilities.app`(v0.1.2, brew 설치).
  - 최적화 후: Release 빌드(아래)로 측정하고, 기준선도 같은 방법으로 빌드한 v0.1.2(`git checkout v0.1.2`)로 다시 재는 것이 가장 공정함.
  ```sh
  xcodegen generate
  xcodebuild -project T-Utilities.xcodeproj -scheme T-Utilities -configuration Release \
    -derivedDataPath build/ReleaseDerivedData build
  # → build/ReleaseDerivedData/Build/Products/Release/T-Utilities.app
  ```
  - 같은 번들 ID라 설정·권한(TCC)은 공유됨. 서명 인증서 "T-Utilities Dev"가 같으면 권한이 유지됨.
- **실행 중인 앱의 번들을 덮어쓰지 말 것.** Mouse 모듈의 이벤트 탭이 활성인 상태에서 앱 번들이 교체·삭제되면 macOS가 앱을 "권한 없음"으로 보고 시스템 전체 스크롤/클릭이 멈출 수 있음(최대 3초 뒤 감시 로직이 탭을 제거). **빌드 전에 앱을 종료**: `osascript -e 'quit app id "com.taegyu.tutilities"'`.
- 강제 종료(`kill`)는 피할 것: Mouse 포인터 값 복원, Awake 뚜껑 설정 복원이 정상 종료 경로에서 일어남. (뚜껑 설정은 `AwakeGuard` 헬퍼가 EOF 시 복원하므로 안전장치는 있음.)
- 설정 백업: `defaults export com.taegyu.tutilities ~/tutilities-prefs.plist` (측정 스크립트는 자동으로 백업·복원함).
- Claude 셸에서는 화면 캡처와 `log show`가 안 됨. UI 확인·로그 확인은 사용자에게 요청.

## 3. 측정 방법

### 3.1 자동 측정 — `Scripts/measure.sh`

구성마다 앱 종료 → `modules.enabled` 설정 → 실행 → 워밍업 → 측정 구간의 CPU/메모리 기록. 끝나면(중단 시에도) 원래 설정을 복원하고 앱을 다시 띄움.

```sh
# 기본: none, 각 모듈 단독, all — 워밍업 20 s, 측정 120 s, 설치된 앱
Scripts/measure.sh

# 빌드 지정 · 구간 · 출력 파일
APP=build/ReleaseDerivedData/Build/Products/Release/T-Utilities.app \
DURATION=300 WARMUP=30 OUT=Docs/measurements/after-1.csv Scripts/measure.sh none clipboard all
```

| CSV 열 | 의미 |
|---|---|
| `config` / `modules` | `none`(셸만), 모듈 단독(`awake` … `mouse`), `all`(6개 모두) |
| `footprint_mb` | `footprint`의 phys_footprint — **메모리 비교 기준값** |
| `footprint_peak_mb` | 프로세스 시작 후 최대치 (워밍업 중 일시적 사용 포함) |
| `rss_mb` | 참고용 (공유 프레임워크 포함이라 비교에는 부적합) |
| `cpu_avg_pct` | 측정 구간 누적 CPU 시간 증가분 ÷ 구간 길이 × 100 |
| `cpu_seconds` | 측정 구간에 쓴 CPU 시간(초) — `ps` 해상도 0.01 s라 **구간은 120 s 이상** 권장 |

- **모듈별 비용 = (모듈 단독) − (none).** `all`과 단독 합계의 차이도 같이 볼 것.
- 유휴 측정은 **3회 반복 후 중앙값**. 측정 중에는 마우스·키보드 사용을 최소화.
- 단독 구성에서도 각 모듈 설정값(예: Awake 모드, Clipboard 기록 수)은 그대로이므로, 측정 시 값을 §7 양식에 함께 기록.
- 스크립트 확인 결과(2026-10-20, 10 s 시험): `none` 13.0 MB, `clock` 13.0 MB — 동작 확인용이며 기준선 아님.

### 3.2 시나리오 측정 (수동)

유휴 측정으로는 안 보이는 비용. 각 시나리오 전후로 `footprint -p $(pgrep -x T-Utilities)`의 phys_footprint/peak를 기록.

| 시나리오 | 방법 | 볼 것 |
|---|---|---|
| 팝오버 열기/닫기 10회 | 메뉴바 아이콘 클릭 | 닫은 뒤 메모리가 돌아오는지 |
| 설정창 열기/닫기 | 모든 페이지 한 번씩 방문 후 닫기 | 창이 유지되므로(`isReleasedWhenClosed=false`) 닫아도 메모리가 남는지 |
| Clipboard 이미지 | 스크린샷 20장 복사 → 팝오버에서 스크롤 | 썸네일 캐시(300개 상한)·원본 캐시(20개) |
| Cable | 팝오버 USB-C 행 → 포트 서브메뉴 열기 반복 | 15 s 주기 스냅샷 + 서브메뉴 `NSHostingView` 생성 |
| Awake 자동 모드 | 자동 모드 + Claude/Codex 세션 실행 중 | 5 s마다 에이전트 파일 검사 |
| Mouse | 휠 스크롤·측면 버튼 1분 | 이벤트 탭 콜백 CPU |
| Windows | 창 위·아래 가장자리 드래그 반복 | 전역 마우스 모니터 + 드래그당 AX 조회 |
| 모듈 끄기 | 설정에서 모듈을 끄고 5 s 후 | 메모리 해제 여부 (P0에서 109→47 MB 확인) |

### 3.3 프로파일링 도구

```sh
P=$(pgrep -x T-Utilities)
footprint -p $P                         # phys_footprint / peak
vmmap --summary $P                      # 영역별 메모리
sample $P 30 -file /tmp/t.txt           # 30 s 콜스택 샘플 (메인 스레드 점유 확인)
xcrun xctrace record --template 'Time Profiler' --attach $P --time-limit 60s --output /tmp/tp.trace
xcrun xctrace record --template 'Allocations'   --attach $P --time-limit 60s --output /tmp/alloc.trace
leaks $P                                # 누수 (앱은 정상 실행 중이어야 함)
sudo powermetrics --samplers tasks -i 5000 -n 6 | grep -i t-utilities   # wakeups/s (sudo 필요)
```
- `top`의 IDLEW 값은 이 Mac에서 고정값(4)만 보여 신뢰할 수 없었음 → wakeup은 `powermetrics` 사용.
- 앱 로그(모듈 해제 누수 검사 포함)는 사용자 터미널에서: `log stream --predicate 'subsystem == "com.taegyu.tutilities"'`.

## 4. 참고 수치 (공식 기준선 아님)

2026-10-20, 설치된 v0.1.2, 활성 모듈 awake·clipboard·clock·mouse·windows, 유휴:
- phys_footprint **59 MB**, **peak 275 MB** ← 시작 직후 또는 특정 동작 중 일시적으로 크게 쓰는 구간이 있음. 원인 미확인 (§6-1).
- CPU 약 1분간 누적 0.04 s 증가 → 평균 약 0.07 %.
- 모듈 없음(`none`): 13 MB.

## 5. 구조 요약

- 앱 셸(`App/Sources`): `AppDelegate` → `ModuleRegistry`(TUCore) + `StatusItemController`(NSStatusItem + NSPopover/SwiftUI `PopoverView`) + `SettingsWindowController`(첫 표시 때 생성, 닫아도 유지) + `Updater`.
- 모듈 = 로컬 SPM 패키지(`Packages/Mod*`), `TUModule` 프로토콜. 켜면 인스턴스 생성 → `start()`, 끄면 `stop()` → 참조 해제 → 2 s 뒤 weak 참조로 누수 검사(로그).
- 모듈 ID: `awake`, `clipboard`, `cable`, `clock`, `windows`, `mouse` (설정 키 `modules.enabled`).

### 5.1 주기 작업 · 상주 리소스 (v0.1.2)

| 위치 | 주기 | 실행 스레드 | 내용 |
|---|---|---|---|
| `ClipboardMonitor` | 0.5 s | utility 큐 | `NSPasteboard.changeCount` 비교, 변경 시에만 읽기. 가장 잦은 wakeup |
| `AwakeModule.tick` | 5 s | 메인 (탐지는 `Task.detached`) | 정책 평가. 자동 모드일 때만 `AgentDetector`(Paseo JSON + transcript glob·stat) |
| `LidSleepGuard` heartbeat | 10 s | 메인 | 뚜껑 닫힘 방지 중에만 `AwakeGuard`에 1바이트 |
| `AwakeGuard` (별도 프로세스) | poll 30 s | — | 무응답·EOF 시 복원 후 종료 |
| `ClockModule` | 분 경계 1회 | 메인 | 메뉴바 텍스트 |
| `CableModule` | 15 s + 팝오버 열 때 | 메인 액터 (WhatCable `snapshot()`이 `@MainActor`, 1회 약 50 ms) | WhatCable 전체 스냅샷 + `PortReport` 빌드. `CableSnapshotContext`를 요약용으로 한 번 더 생성 |
| `MouseModule` 이벤트 탭 | 이벤트 | 메인 런루프 | otherMouse·scrollWheel 전부 통과 (콜백은 분기만) |
| `MouseModule` 탭 감시 | 3 s | 백그라운드 | 임시 탭 생성·해제로 권한 확인 |
| `MouseModule` 배터리 | 300 s + 장치 알림 | 메인 | HID++ 요청 |
| `WindowsModule` 높이 채우기 | 이벤트 | 메인 | 전역 마우스 모니터(좌클릭 down/drag/up). 드래그 시작 시 AX 조회 1회, 가장자리 도달 시 AX 조회 |
| `Updater` | 1 h 루프, 네트워크는 24 h 1회 | 메인 | GitHub API |
| 설정 화면 일부 | 1 s | 메인 | TCC 권한 폴링 (해당 뷰가 보일 때만) |

## 6. 최적화 후보 (가설 — 측정으로 확인 후 적용)

우선순위는 기대 효과 순. 각 항목은 "측정으로 확인 → 적용 → 재측정".

1. **peak 275 MB 원인 찾기** — 시작 직후인지(Clipboard 기록·이미지 로드, Cable 첫 스냅샷, SwiftUI 초기화) 특정 동작인지. `measure.sh`의 단독 구성 peak 값으로 모듈을 좁힌 뒤 Allocations로 확인.
   - **결과 (2026-10-20): 팝오버·창 전환 때 시스템 그래픽 버퍼 — 앱이 줄일 수 없음.** 시작 직후 peak는 모든 구성에서 17 MB 이하. 실사용 중 팝오버 열기·닫기, 설정창 열기·닫기마다 0.5~1.5 s 동안 280~297 MB로 튀고, `footprint --sample 0.1`로 보면 증가분은 거의 전부 `Owned physical footprint (unmapped) (graphics)`(1.9 → 218 MB): WindowServer/CoreAnimation이 창 합성용으로 잡아 앱 몫으로 계산하는 GPU 메모리. Finder 창을 열어도 Finder의 같은 항목이 4 → 196 MB로 같은 모양(화면 3개: 내장 XDR + 4K 2대). 팝오버는 이미 `animates = false`. 셸에서 앱 활성화·텍스트 복사만 해서는 재현 안 됨. → **`peak`는 UI를 띄운 구간에서는 앱 비교 지표로 부적합**(유휴 측정값만 비교).
   - OCR(Vision `VNRecognizeTextRequest`)은 별도 원인: 앱과 같은 설정을 별도 프로세스로 돌리면 peak 233~291 MB(`.fast`·언어 보정 끔·영어만이어도 263~283 MB, 1200×200 이미지도 162 MB → Vision 고정 비용). 끝나면 반환되고 약 15 MB 남음. 앱 안에서는 OCR 시 464~466 MB까지 기록(위 그래픽 급증과 겹친 것으로 보임). 4K 이미지 복사(캡처 경로)는 +33 MB(비트맵 1장).
   - 실사용 후 상주 메모리는 17 → 80 MB(그중 Malloc Small 38 MB) — §6-4에서 따로 볼 것.
   - VisionKit `ImageAnalyzer`는 인식을 `mediaanalysisd`에서 하므로 호출 프로세스 peak 61 MB(데몬 +45 MB), 1.2~1.9 s. 하지만 같은 이미지에서 문자 오류율 약 3~7%(Vision `.accurate` 0.43%). Preview 라이브 텍스트도 VisionKitCore → Vision·TextRecognition·MediaAnalysisServices를 링크하나, 실제 경로는 사용자 동작(호버)이 필요해 셸에서 확인 못 함.
   - **결정:** 정확도 때문에 Vision 유지. OCR을 앱 번들 안 헬퍼 프로세스로 옮기는 안(상주 17 MB·일시 250 MB 제거)도 보류 — 셸에서 새 프로세스로 돌리면 매번 11~14 s 걸려(앱 안은 1~2 s) 지연 위험.
2. **Cable 15 s 스냅샷** — 팝오버가 닫혀 있을 때도 IOKit 전체 순회. 후보: 팝오버/메뉴가 열릴 때만 갱신, 요약용 `CableSnapshotContext` 중복 생성 제거, 스냅샷이 메인 스레드에서 도는지 확인 후 백그라운드로. WhatCable의 static watcher 상태가 모듈을 꺼도 남는 문제(알려진 한계)도 메모리에 영향.
   - **결과 (2026-10-20):** `sample` 60 s 기준 메인 스레드 사용 218 ms 중 97%가 `snapshot()`(그중 `DisplayTimingReader.readNodes` 약 55%). 요약용 `CableSnapshotContext` 중복은 1% 미만이라 그대로 둠. 백그라운드 이전은 vendored WhatCable 수정이 필요해 제외. **주기 갱신 제거 → 시작 1회 + 팝오버 열 때 + 설정 페이지 표시 시** 적용: cable CPU 0.325 → 0.000 %, all 0.425 → 0.108 % (§7.1).
3. **Clipboard 0.5 s 폴링** — 타이머 leeway 지정, 폴링 간격 조정. 복사 감지 지연(체감)과의 트레이드오프.
4. **설정창·팝오버 유지 비용** — 설정창은 닫아도 SwiftUI 뷰 트리가 남음. 닫을 때 해제하면 메모리 절약, 다시 열 때 비용 증가.
   - **결과 (2026-10-20):** 새로 띄운 앱(13 MB)에서 단계별 상주 증가: 팝오버 첫 열기 +31 MB, 설정창 첫 열기(모든 페이지) +19 MB, OCR 첫 실행 +17 MB → 80 MB. 모두 첫 1회만 늘고 반복해도 그대로(팝오버 5회·설정창 재열기 0 MB). 힙 살아 있는 객체 6.6 → 63 MB(타입 없는 malloc +25 MB, TextRecognition·Espresso 약 7.5 MB — `CRImageReaderOutput` 19,828개, Swift 메타데이터·SwiftUI 그래프 등). `leaks`는 시스템 XPC(`com.apple.linkd.autoShortcut`) 20 KB뿐 → 누수 아님, 프레임워크 초기화·캐시.
   - 설정창을 닫을 때 해제(`willCloseNotification` → `window = nil`)해 보니 창 객체는 해제되지만 줄어든 건 약 4 MB(닫은 뒤 62~63 → 58.7~59.4 MB). 나머지 약 15 MB는 SwiftUI 쪽이 유지. 효과가 작아 **되돌림**. 팝오버도 같은 이유로 해제하지 않음(자주 열어 재생성 비용이 더 큼).
5. **Clipboard 이미지 캐시** — 썸네일 300개·원본 20개 상한이 실제 메모리에 얼마인지. 바이트 기준 `totalCostLimit` 검토.
6. **Mouse 3 s 탭 감시** — WindowServer IPC 비용 측정. 간격을 늘리면 권한 상실 시 입력이 멈추는 시간이 늘어남(§8 제약).
7. **Windows 전역 마우스 모니터** — 모든 좌클릭 드래그마다 AX 조회 1회. 비용이 보이면 조회를 가장자리 근처에서 시작한 드래그로 제한.
8. **Awake 5 s tick** — 수동/끔 모드에서는 가벼움(탐지 생략). 자동 모드에서 transcript 수가 많을 때만 의미 있음.

## 7. 결과 기록 양식

측정 CSV는 `Docs/measurements/`에 `baseline-YYYYMMDD.csv`, `after-<변경>.csv`로 저장하고 아래 표로 요약.

| config | footprint 전 → 후 (MB) | peak 전 → 후 (MB) | CPU 전 → 후 (%) | 비고 |
|---|---|---|---|---|
| none | | | | |
| awake | | | | 모드: |
| clipboard | | | | 기록 수: / 이미지 수: |
| cable | | | | |
| clock | | | | |
| windows | | | | |
| mouse | | | | |
| all | | | | |

환경 기록: macOS 버전, 빌드 종류(설치본/Release), 커밋, `DURATION`/`WARMUP`, 연결된 장치(G304, USB-C 장치 수), 실행 중인 에이전트 수.

### 7.1 Cable 주기 갱신 제거 (2026-10-20)

전: `baseline-20261020.csv` (설치된 v0.1.2, release.sh Release 빌드). 후: `after-cable-on-demand.csv` (Release 빌드, v0.1.2 + Cable 변경). 각 3회 중앙값.

| config | footprint 전 → 후 (MB) | peak 전 → 후 (MB) | CPU 전 → 후 (%) | 비고 |
|---|---|---|---|---|
| none | 13 → 12 | 13 → 13 | 0.000 → 0.008 | |
| awake | 13 | 14 | 0.008 | 모드: 수동(기간 0) |
| clipboard | 13 | 13 | 0.017 | 기록 수: 11 / 이미지 수: 1 |
| cable | 16 → 15 | 16 → 15 | **0.325 → 0.000** | |
| clock | 14 | 14 | 0.017 | |
| windows | 13 | 13 | 0.000 | |
| mouse | 13 | 14 | 0.017 | |
| all | 17 → 16 | 17 → 16 | **0.425 → 0.108** | 후 3회: 0.058 / 0.108 / 0.167 |

환경: macOS 27.0.1 (26A434), AC 전원, `DURATION=120` `WARMUP=20`, `caffeinate -i`로 OS 잠자기 방지(이 Mac은 잠자기 1분 설정), USB-C 2개(G304 receiver, 모니터), claude 2·codex 2 실행 중. 단독 모듈 행에 하나만 있는 값은 기준선만 잰 것.

## 8. 깨면 안 되는 동작 (회귀 체크리스트)

- **Mouse**
  - 손쉬운 사용 권한을 끄면 3 s 안에 입력 멈춤이 풀리고, 다시 켜면 버튼·스크롤이 복구됨.
  - 모듈을 끄거나 앱을 종료하면 포인터 값 복원(해상도 400, 가속 0.6875).
  - 측면 버튼 3 → 바탕화면 보기, 4 → Mission Control. G304 배터리 % 표시.
- **Awake**
  - 수동/자동/끔 전환.
  - 뚜껑 닫힘 방지: `AwakeGuard` heartbeat 10 s / 무응답 30 s 복원 구조 유지.
  - 앱이 죽으면 뚜껑 닫을 때 잠듦.
- **Clipboard**: 복사 감지(지연 체감 없음), Return 자동 붙여넣기(옵션), 이미지·OCR.
- **Windows**
  - ⌃⌥↩ 최대화 / 다시 누르면 복원.
  - 다음·이전 디스플레이.
  - 위·아래 가장자리 높이 채우기(미리보기, 좌우 이동 시 유지, 위아래 이동 시 복원).
- **Cable**: 팝오버 요약과 포트별 서브메뉴 정보.
- **공통**
  - 모듈을 끄면 메모리가 해제되고 누수 로그가 없음.
  - 앱 안 업데이트가 종료·재실행까지 완료됨.
  - 설정창 레이아웃(권한 경고 시 밀림 없음).
