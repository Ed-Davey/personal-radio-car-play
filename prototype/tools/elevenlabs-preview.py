"""Prepare a private ElevenLabs presenter sample for the macOS prototype."""

import argparse
import getpass
import http.client
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import warnings
import wave


DEMO_LINE = "This is Personal Radio. Up next, Harbour Lights by the Breakwater Club."
DEFAULT_VOICE = "6WwXjDDEMyNmFG95zycZ"
API_KEY_ENV = "ELEVENLABS_API_KEY"
MAX_MP3_BYTES = 1024 * 1024
SAMPLE_RATE = 44100
MAX_CLIP_SECONDS = 20


class PreviewError(Exception):
    """An error that can be printed without including credentials or response data."""


def api_key():
    key = os.environ.get(API_KEY_ENV)
    if not key and sys.stdin.isatty():
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", getpass.GetPassWarning)
                key = getpass.getpass("ElevenLabs Text to Speech API key: ")
        except (EOFError, getpass.GetPassWarning):
            raise PreviewError(f"Set {API_KEY_ENV} locally to generate a preview.") from None
    if not key or not re.fullmatch(r"[!-~]{1,256}", key):
        raise PreviewError(f"Set {API_KEY_ENV} to a valid local ElevenLabs API key.")
    return key


def read_mp3(path):
    if path.suffix.lower() != ".mp3":
        raise PreviewError("Choose a downloaded MP3 file.")
    try:
        with os.fdopen(os.open(path, os.O_RDONLY | os.O_NONBLOCK), "rb") as source:
            if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                raise PreviewError("Choose a regular MP3 file.")
            return source.read(MAX_MP3_BYTES + 1)
    except OSError:
        raise PreviewError("Could not open the selected MP3 file.") from None


def generate_mp3(voice_id, key):
    # The path contains only the validated voice ID. HTTPSConnection has no
    # automatic redirect or retry handling that could resend credentials or text.
    if not re.fullmatch(r"[A-Za-z0-9]{1,64}", voice_id):
        raise PreviewError("Enter an ElevenLabs voice ID using letters and numbers.")
    connection = http.client.HTTPSConnection("api.elevenlabs.io", timeout=20)
    try:
        connection.request(
            "POST",
            f"/v1/text-to-speech/{voice_id}?output_format=mp3_44100_128",
            body=json.dumps({"text": DEMO_LINE, "model_id": "eleven_multilingual_v2"}),
            headers={"Content-Type": "application/json", "Accept": "audio/mpeg", "xi-api-key": key},
        )
        response = connection.getresponse()
        if response.status != 200:
            raise PreviewError(f"ElevenLabs returned HTTP {response.status}. Check key access, voice availability and credits.")
        if response.getheader("Content-Type", "").split(";", 1)[0].strip().lower() != "audio/mpeg":
            raise PreviewError("ElevenLabs did not return MP3 audio.")

        lengths = response.headers.get_all("Content-Length", [])
        transfer = response.getheader("Transfer-Encoding", "").strip().lower()
        if transfer == "chunked" and not lengths:
            expected = None
        elif not transfer and len(lengths) == 1 and re.fullmatch(r"[0-9]{1,10}", lengths[0].strip()):
            expected = int(lengths[0])
            if not 0 < expected <= MAX_MP3_BYTES:
                raise PreviewError("ElevenLabs returned an empty or oversized clip.")
        else:
            raise PreviewError("Could not verify the length of the ElevenLabs response.")
        data = response.read(MAX_MP3_BYTES + 1)
        if not 0 < len(data) <= MAX_MP3_BYTES or (expected is not None and len(data) != expected):
            raise PreviewError("ElevenLabs returned an empty, incomplete or oversized clip.")
        return data
    except (OSError, http.client.HTTPException, ValueError):
        raise PreviewError("Could not download a complete clip from ElevenLabs.") from None
    finally:
        connection.close()


def validate_mp3(data):
    if not 4 <= len(data) <= MAX_MP3_BYTES:
        raise PreviewError("Use an MP3 preview of at most 1 MiB.")
    # Downloaded MP3 files may begin with an ID3v2 tag. Its size is a 28-bit
    # sync-safe integer. Check the next MPEG Layer III frame before decoding.
    start = 0
    if data.startswith(b"ID3"):
        if len(data) < 10 or any(byte >= 128 for byte in data[6:10]):
            raise PreviewError("The MP3 tag is incomplete.")
        start = 10 + sum(byte << shift for byte, shift in zip(data[6:10], (21, 14, 7, 0)))
        if data[3] == 4 and data[5] & 0x10:
            start += 10
    frame = data[start:start + 4]
    if len(frame) != 4 or frame[0] != 0xFF or frame[1] & 0xE6 != 0xE2:
        raise PreviewError("The selected clip does not begin with a valid MP3 frame.")


def decode_mp3(data, directory, child_env):
    validate_mp3(data)
    source = directory / "preview.mp3"
    target = directory / "preview.wav"
    source.write_bytes(data)
    try:
        subprocess.run(
            ["/usr/bin/afconvert", "-f", "WAVE", "-d", f"LEI16@{SAMPLE_RATE}", "-c", "1", source, target],
            check=True, timeout=30, env=child_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        with wave.open(str(target), "rb") as audio:
            frames = audio.getnframes()
            if not 0 < frames <= SAMPLE_RATE * MAX_CLIP_SECONDS:
                raise PreviewError(f"Use a spoken clip of {MAX_CLIP_SECONDS} seconds or less.")
            if (
                audio.getparams()[:3] != (1, 2, SAMPLE_RATE)
                or audio.getcomptype() != "NONE"
                or len(audio.readframes(frames)) != frames * 2
            ):
                raise PreviewError("The converted preview is not a complete PCM audio file.")
    except (OSError, EOFError, wave.Error, subprocess.SubprocessError):
        raise PreviewError("Could not decode the selected MP3 with macOS audio tools.") from None
    return target


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, epilog=f"Sample line: {DEMO_LINE}")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--mp3", type=Path, help="prepare an existing MP3 without making a network request")
    source.add_argument("--generate", action="store_true", help="send the sample line once to ElevenLabs using account credits")
    parser.add_argument("--voice-id", default=None, help=f"ElevenLabs voice for --generate (default: Eldrin, {DEFAULT_VOICE})")
    args = parser.parse_args(argv)
    if args.voice_id is not None and not args.generate:
        parser.error("--voice-id requires --generate")
    if sys.platform != "darwin":
        parser.error("this preview builder requires macOS")

    child_env = os.environ.copy()
    child_env.pop(API_KEY_ENV, None)
    build_script = Path(__file__).resolve().parents[1] / "build-mac.sh"
    try:
        if args.generate:
            voice_id = DEFAULT_VOICE if args.voice_id is None else args.voice_id
            data = generate_mp3(voice_id, api_key())
        else:
            data = read_mp3(args.mp3)
        with tempfile.TemporaryDirectory(prefix="personal-radio-presenter-") as directory:
            audio = decode_mp3(data, Path(directory), child_env)
            subprocess.run(
                ["/bin/bash", build_script, "--presenter-preview", audio],
                check=True, env=child_env,
            )
    except PreviewError as error:
        print(f"Presenter preview: {error}", file=sys.stderr)
        return 1
    except (OSError, subprocess.CalledProcessError):
        print("Presenter preview: could not build the macOS preview app.", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
