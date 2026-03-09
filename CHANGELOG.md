# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0+alpha.3] - 2026-03-10

### Changed

- Moved platform build settings (deployment targets, SDKROOT, supported platforms) to project level
- Added app category (Utilities) and explicit code sign identity

## [1.0.0+alpha.2] - 2026-03-10

### Changed

- Set ITSAppUsesNonExemptEncryption to NO in build settings

## [1.0.0+alpha.1] - 2026-03-10

### Added

- pixivFANBOX provider support
- Patreon provider support
- SubscribeStar.adult provider support
- MHTML archiving with RFC 2557 compliance
- PDF export
- Media file downloads with concurrent processing
- Lazy content loading via scroll-based IntersectionObserver triggering
- iOS background task support with BGContinuedProcessingTask
- URL redirect resolution before enqueueing
- Per-file progress tracking for media downloads
- Where Froms and Finder Tags xattr metadata options
- Overwrite confirmation for existing post folders
- Content dates metadata on post folders
- Service folder in save path structure
- String Catalog localization support
- App icon for Icon Composer
- iOS Files app access to Documents directory
- App Store metadata document
- Test plan and UI tests
- GitHub funding configuration

### Fixed

- Cookie domain matching with dot-boundary validation per RFC 6265
- Content-Disposition filename parsing to remove trailing quotes
- Preloader scroll not awaited by callAsyncJavaScript
- iOS render window covering app UI
- RedirectTracker to only track main frame navigations
- Race condition between jobs by awaiting about:blank load completion
- Fanbox date parsing and job row display
- Swift concurrency warnings across codebase

### Changed

- Redesigned UI with NavigationStack, toolbar URL input, and HIG-compliant interactions
- Extracted core logic into PatronArchiverKit Swift package
- Encoded MHTML Subject header with RFC 2047 B-encoding
- Used WKWebView desktop User-Agent for URLSession resource downloads
- Replaced JSON stringify/parse roundtrip with native WKWebView object bridging
- Used Data instead of String for MHTML assembly and QP encoding
- Embedded LazyContentLoader.js via SPM resources
- Adopted Swift 6.0 strict concurrency with MainActor isolation
- Replaced glob-based URL matching with Swift Regex

[Unreleased]: https://github.com/sinoru/PatronArchiver/compare/v1.0.0+alpha.3...HEAD
[1.0.0+alpha.3]: https://github.com/sinoru/PatronArchiver/compare/v1.0.0+alpha.2...v1.0.0+alpha.3
[1.0.0+alpha.2]: https://github.com/sinoru/PatronArchiver/compare/v1.0.0+alpha.1...v1.0.0+alpha.2
[1.0.0+alpha.1]: https://github.com/sinoru/PatronArchiver/releases/tag/v1.0.0+alpha.1
