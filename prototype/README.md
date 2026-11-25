# Personal Radio pilot and feasibility demo

The [macOS app](build/Personal%20Radio%20Prototype.app) starts in **My playlist**. Import DRM-free music, arrange the playlist and press **Play**. A system voice introduces each song. Switch to **Sample demo** to hear the bundled tracks and try simulated news and Cornwall roadworks.

## Run on this Mac

Double-click **Personal Radio Prototype.app** inside `build`. Press Space to play or pause. Restart returns to the start of the session and Skip advances playback. The session log shows what played and which sample reports were rejected.

Run `bash build-mac.sh` from this folder to build the app using the Mac Command Line Tools and Swift 6. The script generates a local bundle for macOS 14 or later and signs it ad hoc.

## Use Spotify playlists

Choose **Spotify** in **Source**. Save a playlist link or connect your Spotify library, then use **Open in Spotify** to play through Spotify. [Spotify setup instructions](Spotify-Setup.md)

## Import your music

1. Select **My playlist** and choose **Import music files**. Select DRM-free MP3, M4A, WAV or AIFF files that you can use.
2. Use the arrows to change the order and the bin button to remove a track. The app saves private copies and keeps your original files in place. The playlist can hold up to 100 tracks, 100 MB per track and 2 GB in total.
3. Press **Play** to hear the songs in playlist order. Skip during an announcement jumps to its song. Skip during a song advances to the next announcement. Use the device volume for music and speech. Restart or finish the session to edit the playlist.

## Try the sample listening sequence

Select **Sample demo** and choose a scenario. The simulated clock jumps to known song boundaries so a complete scenario takes about a minute.

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

The sample demo ships longer bundled clips for listening. The [feasibility demo test report](UI-Test-Report.md) records the original demo checks.

A signed build on the target iPhone and car is still needed to verify locked playback, interruptions and CarPlay controls. Live news and Cornwall coverage remain pilot milestones. The bundled music is original synthesis. The bundled speech clips use the installed macOS Daniel voice for this personal, non-commercial demo. [Apple macOS licence](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf#page=3)
