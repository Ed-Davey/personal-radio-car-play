# Personal Radio prototype UI test report

**18 November 2026 · macOS 26.6.2, Apple silicon · demo 0.1**

All four scenarios completed in the running desktop app. Two UI defects reproduced. The playback controller continued to respect the source and transport settings in the cases tested. The demo was returned to **Ready to listen** on **Normal bulletin**, with both sources enabled and the volume at 80%.

## Defects reproduced in the app

| Impact | Reproduction | Observed result and expected behaviour |
| --- | --- | --- |
| Misleading queue | Start **Normal bulletin** with both sources enabled. While the news is playing, turn off **Cornwall roadworks**. | **Up next** still lists the roadworks item. The playback controller suppresses it at dispatch. The queue should reflect that it will be skipped. [Queue and dispatch logic](Sources/PlaybackModel.swift#L91) |
| Misleading completion after failure | Remove `track-1.wav` from a disposable copy, then start **Normal bulletin** and wait for the introduction to finish. | The player reports **Missing or invalid audio for Harbour Lights** alongside **Session complete**. The session stopped before the first song, so the heading should indicate a playback failure. Restart clears the warning and restores the ready screen. [Asset failure path](Sources/PlaybackModel.swift#L218) |

## Desktop UI coverage

| Area | Cases verified |
| --- | --- |
| Normal bulletin | The first song finished before news and travel started. The next introduction preceded its song. Each bulletin played once. The final song ended, the queue became empty and Skip and Simulate car disconnect became disabled. |
| Late bulletin | At the first boundary, the log showed the bulletin waiting. Roadworks played and the second song completed. The bulletin played once at the second boundary. |
| Expired reports | The log recorded news and travel expiry at the simulated 10:16 boundary. Both reports were suppressed and music finished. |
| Road reopened | The closure was suppressed and the news played. The app completed the session while a separate test window was foregrounded. |
| Transport | Started and paused with Space. Paused progress held. Resumed explicitly after a simulated disconnect. Skipped an introduction while paused, a song to the next introduction, news and travel to the next song, and the final track to the end state. |
| Session lifecycle | Restarted from playing and paused, with the log and queue reset. Replayed a completed session without retaining previous events. Changed scenarios during playback and verified that the new one waited for Play. Escape cancelled the scenario picker without changing selection or transport state. |
| Source and volume controls | Both feeds switched off before a boundary produced music only. Re-enabling roadworks made it eligible at the next boundary. Source settings survived a session restart. Volume controls stopped at both limits. |
| Layout and windows | Checked the wide two-column layout and the narrow stacked Mac layout while playing. Scrolled to lower sections and to the oldest log entry. A second window showed the same session. Closing it left a single session running in the original window. |
| Accessibility tree | Checked the headings, scenario picker, source checkboxes, transport labels, progress indicator, volume slider and disabled states. The visual elapsed and total times are hidden from the accessibility tree. The progress bar exposes a fractional value. [Progress display](Sources/PrototypeView.swift#L100) |

Turning off a source leaves its current clip loaded. The news could still pause and resume after its switch was turned off. Roadworks also kept playing after disable. Source toggles govern upcoming playback. The UI does not explain that behaviour, so it is easy to expect the current clip to stop.

## Playback failure and concurrency checks

Ran **22/22 controller checks** with muted native playback and short WAV fixtures and **1/1 audio-output failure check**. The controller checks covered complete scenario order, pause, skip and disconnect from each audio phase, replay, source toggles, rapid input, bounded logging, and stale callbacks after reset. They also reproduced the queue and failure-state defects above. The assertions checked both supported playback behaviours and the observed error states.

- Missing intros and a corrupt news clip were logged and skipped. A successful next clip immediately cleared the inline warning, leaving the session log as the only record of the missing or corrupt optional clip.
- Missing and corrupt songs stopped the session. A failed song did not trigger a report boundary.
- When the output could not start, the controller displayed an error and allowed Play to retry. Restart cleared the error.

## App bundle and rebuild checks

- The current app passed strict signature verification. All eight bundled WAV files matched the source files byte for byte and decoded as valid PCM.
- A stale Swift cache from the earlier build relocation blocked compilation on this Mac. The cache was moved aside and a fresh build and signature check passed in a disposable workspace.
- A separate forced compile failure in a disposable copy showed that the build script can overwrite resources in an existing app before compilation succeeds. If assets change and the compile then fails, the prior app's signature can become invalid. The currently delivered app passed verification. [Build script](build-mac.sh#L8)

## Coverage limits

Desktop playback was checked muted. The UI observations cover transport, progress, sequence and error states. Audible output quality, VoiceOver reading and focus order, iPhone locked-screen playback, live car controls and live sources require separate tests. The iPhone project, scheme and background audio settings passed static checks. This Mac has no configured iPhone SDK or signing team for a device run.
