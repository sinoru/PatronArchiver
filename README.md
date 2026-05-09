# PatronArchiver

A macOS/iOS app that archives posts from patron platforms into MHTML + PDF + media files.

## Download

[![Download on the App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/app/id6760197229)

## Supported Platforms

- [pixivFANBOX](https://www.fanbox.cc/)
- [Patreon](https://www.patreon.com/)
- [SubscribeStar.adult](https://subscribestar.adult/)

## Features

- **Multi-format archives** — each post is saved as a PDF, an MHTML web archive, and individual media files in a single folder
- **Fully offline** — all archives live on your device; no account or internet connection required to re-read them
- **Complete capture** — text, images, videos, attachments, and comments, including lazy-loaded content
- **Auto-organized** — posts are grouped by creator and title; on Mac, Finder tags and origin URLs are attached for search
- **iPhone, iPad, and Mac** — background archiving on iOS lets you keep using your device

## Privacy

PatronArchiver does not collect, transmit, or share any personal data. There are no analytics, advertising SDKs, or trackers. All archived content is stored exclusively on your device. The app uses an embedded `WKWebView` to access creator platform websites; cookies set during sign-in are stored locally within that web view and are sent only to their originating sites.

## Requirements

- macOS 26.0+ / iOS 26.0+
- Xcode 26.0+ (for building from source)

## Build

1. Clone the repository
2. Open `PatronArchiver.xcodeproj` in Xcode
3. Select your target and build

## License

This project is licensed under the [Mozilla Public License 2.0](LICENSE).
