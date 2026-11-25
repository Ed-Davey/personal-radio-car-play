import json
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

from replay import replay, timestamp

ROOT = Path(__file__).resolve().parent
START = json.loads((ROOT / "fixtures/bude-start.json").read_text())
STOP = json.loads((ROOT / "fixtures/bude-stop.json").read_text())
AFTER_START = "2026-10-01T08:55:00Z"
AFTER_STOP = "2026-10-01T09:03:00Z"


def snapshot(records, cutoff=AFTER_STOP):
    return replay(records, timestamp(cutoff, "test cutoff"))


class CornwallReplayTest(unittest.TestCase):
    def test_archived_bude_start_and_stop_share_schema_version(self):
        self.assertEqual(START["version"], STOP["version"])
        before_stop = snapshot([STOP, START], AFTER_START)
        self.assertEqual(before_stop["cornwall_events_replayed"], 1)
        [report] = before_stop["reported_in_progress"]
        self.assertEqual(report["street_name"], "KERNOW CRESCENT")
        self.assertEqual(report["usrn"], "27400995")
        self.assertEqual(report["road_category"], "4")
        self.assertNotIn("current_traffic_management_type", report)

        after_stop = snapshot([STOP, START, START])
        self.assertEqual(after_stop["cornwall_events_replayed"], 2)
        self.assertEqual(after_stop["duplicate_events_ignored"], 1)
        self.assertEqual(after_stop["reported_in_progress"], [])

    def test_filters_by_council_code_and_permit_object_type(self):
        other_authority = deepcopy(START)
        other_authority["object_data"]["highway_authority_swa_code"] = "11"
        activity = dict(START, object_type="ACTIVITY")
        self.assertEqual(snapshot([other_authority, activity])["cornwall_events_replayed"], 0)

    def test_latest_current_traffic_management_overrides_planned(self):
        current = deepcopy(START)
        current.update(event_reference=START["event_reference"] + 1,
                       event_type="CURRENT_TRAFFIC_MANAGEMENT_UPDATED",
                       event_time="2026-10-01T08:55:05Z")
        current["object_data"].update(traffic_management_type_ref="road_closure",
                                      current_traffic_management_type="Two-way signals",
                                      current_traffic_management_type_ref="two_way_signals")
        [report] = snapshot([current, START])["reported_in_progress"]
        self.assertEqual(report["current_traffic_management_type"], "Two-way signals")
        self.assertEqual(report["current_traffic_management_type_ref"], "two_way_signals")
        self.assertNotIn("traffic_management_type_ref", report)

    def test_terminal_event_wins_over_start_at_same_timestamp(self):
        for kind in ("WORK_STOP", "WORK_START_REVERTED", "PERMIT_CANCELLED", "PERMIT_REVOKED"):
            with self.subTest(kind=kind):
                terminal = dict(START, event_reference=START["event_reference"] - 1, event_type=kind)
                self.assertEqual(snapshot([terminal, START])["reported_in_progress"], [])
                self.assertEqual(snapshot([START, terminal])["reported_in_progress"], [])

    def test_later_stop_reversion_restores_reported_in_progress_state(self):
        reverted = dict(START, event_reference=STOP["event_reference"] + 1,
                        event_type="WORK_STOP_REVERTED", event_time="2026-10-01T09:02:30Z")
        [report] = snapshot([STOP, reverted, START])["reported_in_progress"]
        self.assertEqual(report["event_reference"], reverted["event_reference"])

    def test_conflicting_event_reference_fails_replay(self):
        conflict = dict(START, event_type="PERMIT_CANCELLED")
        with self.assertRaisesRegex(ValueError, "conflicting notifications"):
            snapshot([START, conflict])

    def test_cli_rejects_oversized_notification_and_ambiguous_timestamp(self):
        with tempfile.TemporaryDirectory() as directory:
            oversized = Path(directory) / "oversized.json"
            oversized.write_bytes(b" " * (64 * 1024 + 1))
            for cutoff, path, expected in (
                (AFTER_STOP, oversized, "exceeds 64 KiB"),
                ("2026-10-01T09:03:00", ROOT / "fixtures", "UTC offset"),
            ):
                with self.subTest(expected=expected):
                    result = subprocess.run(
                        [sys.executable, "-B", str(ROOT / "replay.py"), "--as-of", cutoff, str(path)],
                        capture_output=True, text=True, check=False,
                    )
                    self.assertEqual(result.returncode, 1)
                    self.assertIn(expected, result.stderr)
                    self.assertEqual(result.stdout, "")
