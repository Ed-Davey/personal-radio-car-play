# Try an ElevenLabs presenter on the Mac

Build a listening preview and hear the chosen voice introduce **Harbour Lights** in the sample programme. The next song starts when the recording finishes. Use macOS 14 or later, Swift 6 Command Line Tools and Python 3.

## Use a recording from ElevenLabs

1. In ElevenLabs Text to Speech, choose a voice available to your account. **Eldrin – Crisp British Baritone** is a candidate from the licensed Infinity collection. [ElevenLabs voice guide](https://elevenlabs.io/docs/help-center/product/voices/my-voices/what-are-default-voices)
2. Generate this fictional sample and download it as MP3.

   > This is Personal Radio. Up next, Harbour Lights by the Breakwater Club.

3. From the Personal Radio repository, run the preview tool with the downloaded file.

   ```sh
   python3 prototype/tools/elevenlabs-preview.py --mp3 "$HOME/Downloads/presenter.mp3"
   ```

4. In Terminal, run the `open` command printed by the tool. Select **Sample demo** if the app starts in **My playlist**, then press **Play**. The first introduction uses your recording. Listen for intelligibility, pacing and relative volume.

## Generate the preview through the API

With a Text to Speech API key from a plan that supports your selected voice, use:

```sh
python3 prototype/tools/elevenlabs-preview.py --generate
```

The tool uses Eldrin by default. For another voice, add `--voice-id YOUR_VOICE_ID`. Enter your key at the hidden Terminal prompt or provide it through the local `ELEVENLABS_API_KEY` environment variable. Scope the key to Text to Speech and set a credit limit for the trial. The generation request spends account credits and sends the fixed sample text to ElevenLabs. Voice Library API voices require paid access under the published plan rules. [API authentication](https://elevenlabs.io/docs/api-reference/authentication) · [Create speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert) · [Voice Library](https://elevenlabs.io/docs/eleven-creative/voices/voice-library/)

The prepared preview plays offline and stays in the ignored `prototype/build` folder. The original app is available through the standard build command. Preview files and keys belong on your Mac. Review ElevenLabs' attribution requirements before sharing output. [Usage rights](https://elevenlabs.io/docs/overview/administration/billing)

## Pilot scope

This is a one-introduction Mac preview to select a voice. Playlist introductions on the phone still need per-track clip mapping and the system speech fallback. Preview generation sends only the sample line. ElevenLabs' standard API data handling applies. [Zero retention availability](https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode)
