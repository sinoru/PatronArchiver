# PatronArchiver

후원 플랫폼 포스트를 MHTML + PDF + 미디어로 아카이빙하는 macOS/iOS SwiftUI 앱.

### 플랫폼별 구현 상태

| 플랫폼 | 상태 |
|--------|------|
| pixivFANBOX | 구현 완료 |
| Patreon | 구현 완료 |
| Fantia | 차후 구현 예정 |
| itch.io | 차후 구현 예정 |
| SubscribeStar | 차후 구현 예정 |

## 절대 원칙

### DOM 비간섭 (Non-invasive DOM)

**가장 중요한 원칙.** 페이지의 HTML/DOM을 직접 수정하지 않는다.

- `img.src` 직접 설정, CSS 클래스/`style` 속성 변경 금지. 사이트 JS가 상태를 전환하도록 `LazyContentLoader` 스크롤로 유도한다.
- DOM **읽기**(querySelector, getComputedStyle, outerHTML)는 허용.
- 유일한 예외: MHTML 직렬화를 위해 불가피한 경우(adopted stylesheet → `<style>` 삽입 등)에만 최소한으로 허용.

### LazyContentLoader ↔ 덤퍼 책임 경계

콘텐츠가 완전히 로드된 상태를 만드는 것은 **`LazyContentLoader`(`WKWebView.loadLazyContent`)의 책임**이다. 페이지 덤퍼(MHTML, PDF)는 현재 DOM을 있는 그대로 캡처만 한다. 덤퍼에서 로딩 문제를 해결하려 하지 않는다.

### 써드파티 없음

Foundation, WebKit, SwiftUI 등 Apple 프레임워크만 사용한다.

## 표준·검증

- MHTML(RFC 2557), Quoted-Printable(RFC 2045, 줄 끝 공백/탭 인코딩 포함), Date 헤더(RFC 2822). 불확실하면 추측하지 말고 검색하여 확인한다.
- MHTML 품질은 동일 페이지의 **Chrome 저장 결과**와 리소스 파트 수·인코딩 방식·렌더링 결과를 비교하여 검증한다.

## Gotchas

- `WKWebView`는 view hierarchy에 부착되어야 렌더링됨. 현재 SwiftUI `ArchiveWebViewRepresentable`으로 표시하며, `window != nil` 대기 후 진행한다.
- `WKHTTPCookieStore` ↔ `HTTPCookieStorage`는 자동 동기화 안 됨 → `WKWebsiteDataStore.urlRequest(for:)`로 쿠키 수동 설정.
- 빠른 스크롤은 lazy load 누락을 유발한다. `LazyContentLoader`는 뷰포트 50%씩 점진적으로 스크롤해야 IntersectionObserver가 정상 트리거된다.
- `callAsyncJavaScript`는 스크립트를 async function body로 감싸므로 top-level `await` 사용 가능. async IIFE로 감싸면 Promise가 반환되지 않아 즉시 완료된다.
- styled-components 환경에서는 `[class*="PostTitle"]` 같은 부분 매치 셀렉터를 사용한다 (클래스명이 빌드마다 변경됨).
- iOS 백그라운드: `BGContinuedProcessingTaskRequest` 구현 예정 (미구현).

## 코드 컨벤션

- 특정 타입에 의존적인 기능 → `extension` (예: `WKWebView.mhtml(dataStore:)`)
- 독립적인 utility → 관련 class/struct에 `static func`으로 배치
- Protocol 공통 헬퍼 → protocol extension default implementation
- JS 동기 스크립트(`evaluateJavaScript`)는 IIFE로 전역 오염 방지
- 로깅: `OSLog` `Logger`, subsystem `com.sinoru.PatronArchiver`, 개인정보는 `.private`
