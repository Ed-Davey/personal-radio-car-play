"""Offline tests for the preview tool's local input and API boundaries."""

from email.message import Message
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


script = Path(__file__).resolve().parents[1] / "elevenlabs-preview.py"
spec = importlib.util.spec_from_file_location("elevenlabs_preview", script)
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)

MP3_HEADER = b"\xff\xfb\x90\x64"
TEST_KEY = "unit-test-key"


class ElevenLabsPreviewTests(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(preview.http.client, "HTTPSConnection")
        self.connect = patcher.start()
        self.addCleanup(patcher.stop)

    def mock_response(self, status=200, content_type="audio/mpeg", lengths=("4",),
                      transfer=None, body=MP3_HEADER):
        response = mock.Mock(status=status, headers=Message())
        response.headers["Content-Type"] = content_type
        for length in lengths:
            response.headers["Content-Length"] = length
        if transfer:
            response.headers["Transfer-Encoding"] = transfer
        response.getheader.side_effect = response.headers.get
        response.read.return_value = body
        self.connect.reset_mock()
        self.connect.return_value.getresponse.return_value = response
        return self.connect, response

    def test_generate_sends_only_the_fixed_demo_line(self):
        connect, response = self.mock_response()

        self.assertEqual(preview.generate_mp3(preview.DEFAULT_VOICE, TEST_KEY), MP3_HEADER)

        connect.assert_called_once_with("api.elevenlabs.io", timeout=20)
        request = connect.return_value.request
        request.assert_called_once()
        method, path = request.call_args.args
        self.assertEqual(method, "POST")
        self.assertEqual(path, f"/v1/text-to-speech/{preview.DEFAULT_VOICE}?output_format=mp3_44100_128")
        self.assertEqual(json.loads(request.call_args.kwargs["body"]), {
            "text": preview.DEMO_LINE,
            "model_id": "eleven_multilingual_v2",
        })
        self.assertEqual(request.call_args.kwargs["headers"]["xi-api-key"], TEST_KEY)
        response.read.assert_called_once_with(preview.MAX_MP3_BYTES + 1)
        connect.return_value.close.assert_called_once()

    def test_accepts_an_explicitly_chunked_mp3_response(self):
        _, response = self.mock_response(lengths=(), transfer="chunked")

        self.assertEqual(preview.generate_mp3(preview.DEFAULT_VOICE, TEST_KEY), MP3_HEADER)
        response.read.assert_called_once_with(preview.MAX_MP3_BYTES + 1)

    def test_rejects_redirect_without_following_it(self):
        connect, response = self.mock_response(status=307)
        response.headers["Location"] = "https://example.com/redirect"

        with self.assertRaisesRegex(preview.PreviewError, "HTTP 307"):
            preview.generate_mp3(preview.DEFAULT_VOICE, TEST_KEY)
        connect.return_value.request.assert_called_once()
        response.read.assert_not_called()
        connect.return_value.close.assert_called_once()

    def test_rejects_bad_content_type_and_unsafe_response_lengths(self):
        invalid = (
            {"content_type": "text/html"},
            {"lengths": ("4", "4")},
            {"lengths": (), "transfer": None},
            {"lengths": (str(preview.MAX_MP3_BYTES + 1),)},
            {"lengths": ("9",), "body": MP3_HEADER},
        )
        for settings in invalid:
            with self.subTest(settings=settings):
                connect, _ = self.mock_response(**settings)
                with self.assertRaises(preview.PreviewError):
                    preview.generate_mp3(preview.DEFAULT_VOICE, TEST_KEY)
                connect.return_value.close.assert_called_once()

    def test_rejects_voice_id_with_path_punctuation_before_connecting(self):
        with self.assertRaises(preview.PreviewError):
            preview.generate_mp3("voice/other", TEST_KEY)
        self.connect.assert_not_called()

    def test_local_import_builds_without_a_network_request_or_child_key(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "local.mp3"
            source.write_bytes(MP3_HEADER)
            with (
                mock.patch.dict(preview.os.environ, {preview.API_KEY_ENV: TEST_KEY}),
                mock.patch.object(preview.sys, "platform", "darwin"),
                mock.patch.object(preview, "generate_mp3") as generate,
                mock.patch.object(preview, "decode_mp3") as decode,
                mock.patch.object(preview.subprocess, "run") as build,
            ):
                decode.side_effect = lambda data, output, _: output / "preview.wav"
                self.assertEqual(preview.main(["--mp3", str(source)]), 0)

        generate.assert_not_called()
        self.assertEqual(decode.call_args.args[0], MP3_HEADER)
        self.assertNotIn(preview.API_KEY_ENV, decode.call_args.args[2])
        self.assertNotIn(preview.API_KEY_ENV, build.call_args.kwargs["env"])
        self.assertIn("--presenter-preview", build.call_args.args[0])

    def test_rejects_a_truncated_id3_header(self):
        with self.assertRaisesRegex(preview.PreviewError, "MP3 tag"):
            preview.validate_mp3(b"ID3\x04\x00")


if __name__ == "__main__":
    unittest.main()
