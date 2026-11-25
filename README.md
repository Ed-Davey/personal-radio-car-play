# Personal Radio

Personal Radio is a native SwiftUI prototype for a private in-car listening session. It plays complete songs, introduces the next track, and uses song boundaries to insert fresh news and Cornwall roadworks updates. The pilot targets one iPhone and one CarPlay-equipped car, with setup while parked and playback controls through system Now Playing.

## Current status

The macOS demo uses bundled sample music, spoken introductions, fictional news and simulated roadworks. It exercises normal and late bulletins, expired reports, reopened roads and a simulated disconnect. The iPhone project is included for the next feasibility test. Locked-screen CarPlay playback, live feeds and subscription music remain open.

## Run the prototype on a Mac

From the repository root, with Swift 6 and the Xcode Command Line Tools installed on macOS 14 or later, run:

```sh
bash prototype/build-mac.sh
open 'prototype/build/Personal Radio Prototype.app'
```

Choose a scenario and press **Play**. The session log shows the order of tracks and reports, and records why a stale or reopened report was skipped. The build output is generated locally and ignored by Git.

For a device build, open [the Xcode project](prototype/PersonalRadioPrototype.xcodeproj) in full Xcode and follow the [iPhone setup instructions](prototype/README.md#try-on-iphone). The bundled spoken clips are for personal, non-commercial demo use. [Apple macOS licence](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf#page=3)

## Project documents

| Document | What it covers |
| --- | --- |
| [Feasibility study](Personal-Radio-V1-Feasibility-Study.md) | Music, news and travel sources, rights, technical findings and delivery gates |
| [Private pilot plan](Personal-Radio-Private-Pilot-Shaping-Plan.md) | Pilot scope, architecture and acceptance criteria |
| [Prototype guide](prototype/README.md) | Build instructions and demo scenarios |
| [ElevenLabs presenter preview](prototype/ElevenLabs-Preview.md) | Audition a prepared voice with the Mac prototype |
| [UI test report](prototype/UI-Test-Report.md) | Desktop test coverage, reproduced defects and remaining checks |

## Contributing

Create each feature branch from `dev`. Merge the feature branch into `V1` for integration testing, then open a pull request from that feature branch into `dev`. Keep `V1` available for testing features together while their individual PRs are under review.

Summarise what changed, how you tested it and any device checks still needed. Have Codex review the PR, address its findings and rerun the review on the latest revision. Request human approval when the PR is ready to merge. When build steps, demo behaviour or test results change, update this README and the relevant project document in the same PR.

The [Prototype CI workflow](.github/workflows/prototype-ci.yml) runs on pull requests into `dev` and pushes to `V1`. It runs Swift, Cornwall permit replay and offline ElevenLabs preview tests alongside the macOS and iOS Simulator build checks. Verify locked playback and CarPlay controls on the target iPhone and car.

With full Xcode selected, run the native Swift tests from the repository root. Files ending in `Tests.swift` cover bulletin scheduling, playlist imports and playback transitions. They use temporary audio files and controlled completion events. The playlist tests also read audio through AVFoundation.

```sh
swift test --package-path prototype --disable-xctest
```

Follow the [GitHub workflow setup guide](docs/github-workflow/README.md) to configure the bot account, automatic review and human approval on `dev`.
