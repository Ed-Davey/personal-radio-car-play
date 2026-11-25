"""Replay local Street Manager archive files as a historical Cornwall snapshot."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

MAX_NOTIFICATION_BYTES = 64 * 1024
PERMIT_EVENTS = {
    "WORK_START", "WORK_STOP", "WORK_START_REVERTED", "WORK_STOP_REVERTED",
    "PERMIT_SUBMITTED", "PERMIT_GRANTED", "PERMIT_ALTERATION_GRANTED",
    "PERMIT_REFUSED", "PERMIT_CANCELLED", "PERMIT_REVOKED",
    "CURRENT_TRAFFIC_MANAGEMENT_UPDATED",
}
SUPPRESSING_EVENTS = {
    "WORK_STOP", "WORK_START_REVERTED", "PERMIT_CANCELLED", "PERMIT_REVOKED",
    "PERMIT_REFUSED",
}


def timestamp(value: object, field: str) -> datetime:
    if isinstance(value, str) and "T" in value:
        try:
            iso = value[:-1] + "+00:00" if value.endswith("Z") else value
            parsed = datetime.fromisoformat(iso)
            if parsed.tzinfo is not None:
                return parsed.astimezone(timezone.utc)
        except (ValueError, OverflowError):
            pass
    raise ValueError(f"{field} must be a timestamp with a UTC offset")


def utc_text(value: datetime) -> str:
    return value.isoformat().removesuffix("+00:00") + "Z"


def required_text(value: object, field: str) -> str:
    if isinstance(value, str) and value.strip():
        return value.strip()
    raise ValueError(f"{field} must be a non-empty string")


@dataclass(frozen=True)
class PermitEvent:
    reference: int
    permit: str
    occurred_at: datetime
    kind: str
    suppresses: bool
    reported_start: datetime | None
    report: dict | None

    @property
    def order(self) -> tuple[datetime, bool, bool, int]:
        return self.occurred_at, self.suppresses, self.report is not None, self.reference


def parse_notification(record: object) -> PermitEvent | None:
    if not isinstance(record, dict):
        raise ValueError("expected a Street Manager notification object")
    if required_text(record.get("object_type"), "object_type") != "PERMIT":
        return None
    data = record.get("object_data")
    if not isinstance(data, dict):
        raise ValueError("object_data must be an object")
    if required_text(data.get("highway_authority_swa_code"), "highway_authority_swa_code") != "840":
        return None

    reference = record.get("event_reference")
    if type(reference) is not int:
        raise ValueError("event_reference must be an integer")
    permit = required_text(record.get("object_reference"), "object_reference")
    occurred = timestamp(record.get("event_time"), "event_time")
    kind = required_text(record.get("event_type"), "event_type").upper().replace("-", "_")

    start_value = data.get("actual_start_date_time")
    stop_value = data.get("actual_end_date_time")
    started = timestamp(start_value, "actual_start_date_time") if start_value is not None else None
    if stop_value is not None:
        timestamp(stop_value, "actual_end_date_time")
    work_status = data.get("work_status_ref")
    permit_status = data.get("permit_status")
    suppresses = (
        kind in SUPPRESSING_EVENTS
        or stop_value is not None
        or work_status in ("completed", "cancelled")
        or permit_status in ("closed", "cancelled", "revoked", "refused")
    )

    report = None
    if not suppresses and kind in PERMIT_EVENTS and work_status == "in_progress" and started:
        report = {
            "permit_reference": permit,
            "event_reference": reference,
            "source_event_time": utc_text(occurred),
            "reported_started_at": utc_text(started),
            "usrn": required_text(data.get("usrn"), "usrn"),
            "street_name": required_text(data.get("street_name"), "street_name"),
            **{
                field: data[field]
                for field in ("town", "area_name", "road_category", "current_traffic_management_type",
                              "current_traffic_management_type_ref")
                if isinstance(data.get(field), str) and data[field].strip()
            },
        }
    return PermitEvent(reference, permit, occurred, kind, suppresses, started, report)


def replay(records: Iterable[object], as_of: datetime) -> dict:
    latest: dict[str, PermitEvent] = {}
    seen: dict[int, PermitEvent] = {}
    duplicates = 0
    for record in records:
        event = parse_notification(record)
        if event is None or event.occurred_at > as_of:
            continue

        previous = seen.get(event.reference)
        if previous is not None:
            if previous != event:
                raise ValueError(f"conflicting notifications for event {event.reference}")
            duplicates += 1
            continue
        seen[event.reference] = event

        current = latest.get(event.permit)
        if current is None or current.order < event.order:
            latest[event.permit] = event

    in_progress = [
        event.report
        for event in latest.values()
        if event.report is not None and event.reported_start is not None and event.reported_start <= as_of
    ]
    in_progress.sort(key=lambda report: (report["street_name"], report["permit_reference"]))
    return {
        "source": "Department for Transport Street Manager",
        "coverage": "Cornwall Council permit notifications supplied for offline replay",
        "as_of": utc_text(as_of),
        "cornwall_events_replayed": len(seen),
        "duplicate_events_ignored": duplicates,
        "reported_in_progress": in_progress,
    }


def load_records(paths: list[Path]) -> Iterable[object]:
    for path in paths:
        files = sorted(path.glob("*.json")) if path.is_dir() else [path]
        if not files:
            raise ValueError(f"no JSON notifications in {path}")
        for file in files:
            try:
                with file.open("rb") as reader:
                    payload = reader.read(MAX_NOTIFICATION_BYTES + 1)
                if len(payload) > MAX_NOTIFICATION_BYTES:
                    raise ValueError("notification exceeds 64 KiB")
                yield json.loads(payload)
            except (OSError, ValueError, RecursionError) as error:
                raise ValueError(f"{file}: {error}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--as-of", required=True, metavar="TIMESTAMP", help="Replay cutoff with a UTC offset")
    parser.add_argument("paths", nargs="+", type=Path, metavar="PATH", help="JSON file or directory of JSON files")
    args = parser.parse_args()
    try:
        snapshot = replay(load_records(args.paths), timestamp(args.as_of, "--as-of"))
    except ValueError as error:
        print(f"Replay failed. {error}", file=sys.stderr)
        return 1
    print(json.dumps(snapshot, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
