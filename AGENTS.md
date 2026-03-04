# PatronArchiver

후원 플랫폼(Fanbox, Patreon, Fantia, itch.io, SubscribeStar) 포스트를 MHTML + PDF + 미디어로 아카이빙하는 macOS/iOS SwiftUI 앱. 로그인 필요한 유료 플랫폼 대상이며, WKWebView 기반으로 인증·렌더링·캡처를 수행한다.

## 핵심 원칙

### DOM 비간섭 (Non-invasive DOM)

**가장 중요한 원칙.** 페이지의 HTML/DOM을 직접 수정하지 않는다.

- `img.src` 직접 설정, CSS 클래스/`style` 속성 변경 금지. 사이트 JS가 상태를 전환하도록 Preloader 스크롤로 유도한다.
- DOM **읽기**(querySelector, getComputedStyle, outerHTML)는 허용.
- 유일한 예외: MHTML 직렬화를 위해 불가피한 경우(adopted stylesheet → `<style>` 삽입 등)에만 최소한으로 허용.

### Preloader = 콘텐츠 완전성 보장

페이지 덤퍼(MHTML, PDF)는 현재 DOM을 있는 그대로 캡처한다. 콘텐츠가 완전히 로드된 상태를 만드는 것은 Preloader의 책임이다. 페이지 덤퍼에서 로딩 문제를 해결하지 않는다.

### Chrome MHTML 기준 검증

MHTML 품질은 동일 페이지의 Chrome 저장 결과와 리소스 파트 수·인코딩 방식·렌더링 결과를 비교하여 검증한다.

### 표준 준수

MHTML(RFC 2557), Quoted-Printable(RFC 2045, 줄 끝 공백/탭 인코딩 포함), Date 헤더(RFC 2822). 불확실하면 추측하지 말고 확인한다.

### 써드파티 없음

Foundation, WebKit, SwiftUI 등 Apple 프레임워크만 사용한다.

## 데이터 흐름

```
URL 입력 → 사이트 식별(PatronServiceManager)
→ WebView 로드 + 로그인 체크
→ Preloader(공통 스크롤) + SitePlugin.preloadContent(사이트 특화)
→ 병렬: 페이지 덤프(MHTML + PDF) / 미디어 추출 → 다운로드
→ StorageManager 저장(폴더 생성 + xattr)
```

## 플랫폼

| | macOS | iOS |
|---|---|---|
| 최소 버전 | macOS 26.0+ | iOS 26.0+ |
| 기본 저장 경로 | `~/Downloads` | 앱 Documents |
| WKWebView 렌더링 | 숨김 NSWindow, frame 너비 설정 | 숨김 UIWindow, scene에 부착 |
| 백그라운드 | 제한 없음 | `BGContinuedProcessingTaskRequest` |

양 플랫폼 모두 사용자가 폴더를 직접 선택하고, security-scoped bookmark으로 권한을 유지한다.

## 구현 상세

### WKWebView 제약

- `@MainActor` — WebView 조작은 메인 스레드
- View hierarchy에 부착되어야 렌더링됨 (숨김 윈도우 사용)
- `WKHTTPCookieStore` ↔ `HTTPCookieStorage`는 자동 동기화 안 됨 → `CookieHelper`로 URLRequest에 쿠키 수동 설정

### Preloader 스크롤 전략

빠른 스크롤은 lazy load 누락을 유발한다. 반드시 단계적으로:

1. 뷰포트 50%씩 점진적 스크롤 (설정 가능한 딜레이)
2. 맨 아래 도달 → 대기 → 맨 위 복귀
3. `src` 없는 `<img>`를 개별 스크롤하여 IntersectionObserver 자연 트리거
4. 로딩 중 이미지 완료 대기
5. 2회 반복 (1차 로드로 새 콘텐츠가 추가될 수 있음)

### MHTML 리소스 수집: 2-pass

1. **JS pass** — DOM 순회로 리소스 URL 수집 (img, link, style url(), CSSOM, adopted stylesheets, iframe)
2. **CSS pass** — 다운로드된 CSS에서 Swift Regex로 `url()` 추출 → 추가 다운로드

텍스트 리소스(text/\*, svg, js, json)는 quoted-printable, 바이너리는 base64.

### PDF

`WKWebView.pdf(configuration:)` + JS `scrollHeight`로 단일 긴 페이지 생성. A4 페이지네이션 없음.

### SitePlugin

- `PatronServiceProvider` 프로토콜을 구현하는 struct. URL glob 패턴으로 사이트 매칭.
- DOM 접근은 `evaluateJavaScript`/`callAsyncJavaScript`로 수행
- styled-components 환경에서는 `[class*="PostTitle"]` 같은 부분 매치 셀렉터 사용
- 미디어/메타데이터는 JSON.stringify로 직렬화 → Swift `parseMediaJSON`/`parseMetadataJSON`으로 파싱

### 저장 구조

```
[기본 저장 경로]/[작가명]/[포스트ID] - [제목] ([날짜 UTC])/
  ├─ [페이지 타이틀].mhtml
  ├─ [페이지 타이틀].pdf
  ├─ 01 - image.png
  └─ 02 - video.mp4
```

- xattr: `kMDItemWhereFroms`(원본 URL 체인), `_kMDItemUserTags`(포스트 태그) — Safari/Finder 호환
- 날짜 형식: `yyyy-MM-dd'T'HHmmss'Z'` (UTC), 수정일 우선

## 코드 컨벤션

- 인스턴스 불필요한 utility → `enum` (예: `Preloader`, `StorageManager`, `CookieHelper`)
- WKWebView 기능 확장 → `extension WKWebView` (예: `mhtml(dataStore:)`, `fullPagePDF()`)
- Protocol 공통 헬퍼 → protocol extension default implementation
- JS: IIFE로 전역 오염 방지, 비동기는 `callAsyncJavaScript` + async IIFE
- 로깅: `OSLog` `Logger`, subsystem `com.sinoru.PatronArchiver`, 개인정보는 `.private`
