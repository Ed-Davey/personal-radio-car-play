"""Check that a prototype app contains its playable demo audio fixtures."""

import argparse
import filecmp
import plistlib
import sys
import wave
from pathlib import Path


SOURCE_AUDIO = Path(__file__).resolve().parent / "Assets" / "Audio"
REQUIRED_AUDIO = {
    "intro-1.wav", "intro-2.wav", "intro-3.wav",
    "track-1.wav", "track-2.wav", "track-3.wav",
    "news.wav", "travel.wav",
}


def check_audio(resources):
    source_names = {path.name for path in SOURCE_AUDIO.glob("*.wav")}
    missing = REQUIRED_AUDIO - source_names
    if missing:
        raise ValueError(f"Missing source audio fixtures: {', '.join(sorted(missing))}")

    for name in sorted(source_names):
        packaged = resources / "Audio" / name
        if not packaged.is_file():
            raise ValueError(f"Missing bundled audio fixture: {name}")
        if not filecmp.cmp(SOURCE_AUDIO / name, packaged, shallow=False):
            raise ValueError(f"Bundled audio differs from its source: {name}")

        try:
            with wave.open(str(packaged), "rb") as clip:
                frames = clip.getnframes()
                expected_size = frames * clip.getnchannels() * clip.getsampwidth()
                if (
                    not frames
                    or clip.getframerate() <= 0
                    or expected_size > packaged.stat().st_size
                    or len(clip.readframes(frames)) != expected_size
                ):
                    raise ValueError(f"Bundled audio is empty, truncated or has an invalid sample rate: {name}")
        except (EOFError, wave.Error) as error:
            raise ValueError(f"Bundled audio is not valid PCM WAV: {name}") from error

    return len(source_names)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="path to the built app bundle")
    parser.add_argument("--ios", action="store_true", help="check an iOS simulator bundle")
    args = parser.parse_args()
    resources = args.app if args.ios else args.app / "Contents" / "Resources"

    try:
        count = check_audio(resources)
        if args.ios:
            with (args.app / "Info.plist").open("rb") as handle:
                info = plistlib.load(handle)
            modes = info.get("UIBackgroundModes") if isinstance(info, dict) else None
            if not isinstance(modes, list) or "audio" not in modes:
                raise ValueError("The packaged iOS Info.plist lacks the background audio mode.")
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(error, file=sys.stderr)
        return 1

    print(f"Verified {count} packaged PCM WAV fixtures.")
    if args.ios:
        print("Verified the packaged iOS background audio mode.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
