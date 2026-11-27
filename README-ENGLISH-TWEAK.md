# Reloc English UI Tweak

This is a jailbreak tweak for the Reloc app (dev.reloc.ios) from this repository.

## What it does

- Translates SwiftUI string-literal localization lookups from Simplified Chinese to English at runtime.
- Translates common UIKit labels, buttons, navigation titles, search placeholders, text views, and alert text.
- Targets only the Reloc bundle identifier. It does not patch or replace the IPA.

## Packages

The GitHub Actions workflow builds two Debian packages:

- RelocEnglish-rootless.deb for rootless jailbreak layouts.
- RelocEnglish-rootful.deb for rootful jailbreak layouts.

Install only the package matching the jailbreak layout on the device. After installation, fully close and reopen Reloc.

## Limitations

Reloc is primarily a SwiftUI app. Text created from runtime Swift String values may bypass Apple's LocalizedStringKey lookup and may not be translated if SwiftUI does not expose that text through UIKit. This tweak also cannot translate text rendered inside remote map tiles, Apple system Settings, or third-party system interfaces. Device-level UI validation is still required.

## Build

The workflow uses Theos and Apple's iOS SDK on a macOS GitHub Actions runner. Run the workflow named Build Reloc English Tweak to produce the .deb artifacts.
