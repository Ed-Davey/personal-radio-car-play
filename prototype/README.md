# Personal Radio feasibility demo

The [macOS app](build/Personal%20Radio%20Prototype.app) plays three original sample tracks, presenter intros, a fictional news bulletin and a sample Cornwall roadworks report. It plays everything locally. The simulated clock moves to known song boundaries so a complete scenario takes about a minute.

## Run on this Mac

Double-click **Personal Radio Prototype.app** inside `build`, select a scenario, and press **Play**. Press Space to play or pause. Restart returns to the start of the current scenario, and Skip advances playback. The session log shows what played and which reports were rejected.

Build again from this folder with `bash build-mac.sh`. The build uses the Mac Command Line Tools and Swift 6. It generates a local bundle for macOS 14 or later and signs it ad hoc. No dependencies need downloading.

## Try the listening sequence

| Scenario | What to check |
| --- | --- |
| Normal bulletin | After the first track finishes, hear the sample bulletin, roadworks report, next-song intro and next song in that order. |
| Late bulletin | The first boundary happens before the bulletin is ready. A fresh roadworks report can still play, then music continues. Hear the bulletin after the second track. |
| Expired reports | Past the freshness window, the stale bulletin and road report are skipped. |
| Road reopened | The updated road status suppresses the closure report. |
| Car disconnect | During playback, choose **Simulate car disconnect**. The current item pauses and stays paused until you explicitly play again. |

The two source switches can disable news or roadworks. Skip a song to advance to the next song’s introduction. Skip during an intro or report to return directly to music.

## Try on iPhone

Open `PersonalRadioPrototype.xcodeproj` in full Xcode. Select the **PersonalRadioPrototype** target, set a unique bundle identifier if needed, and choose your development team under **Signing & Capabilities**. Select a connected iPhone running iOS 17 or later and Run. The target declares background audio and uses system Now Playing. With the car parked, start on the iPhone, lock it, then check the car’s Now Playing screen and buttons. The project has no dedicated CarPlay tile.

## Verification and scope

The macOS app was built and opened locally. Five muted playback checks using short WAV fixtures passed for normal ordering, late news, stale reports, reopened roads and pause/skip/resume/reset after a simulated disconnect. The demo ships longer bundled clips for listening.

A signed build on the actual iPhone and car is still needed to establish locked playback, interruptions and CarPlay controls. Live feeds, subscription music, and live Cornwall coverage are outside this prototype. Music is original synthesis. The speech clips use the installed macOS Daniel voice and are for this personal, non-commercial demo. [Apple macOS licence](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf#page=3)
