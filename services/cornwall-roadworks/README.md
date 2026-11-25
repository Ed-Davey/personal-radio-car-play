# Cornwall roadworks archive replay

Replay downloaded Department for Transport Street Manager permit notifications at a specified time. The output lists works reported in progress by the Cornwall Council permit events supplied. This is a historical comparison tool. Live delivery, current road status, general incidents and complete Cornwall coverage require separate validation.

## Replay the real Bude example

From the repository root, run these commands with Python 3.9 or later.

```sh
python3 services/cornwall-roadworks/replay.py \
    --as-of 2026-10-01T08:55:00Z services/cornwall-roadworks/fixtures
python3 services/cornwall-roadworks/replay.py \
    --as-of 2026-10-01T09:03:00Z services/cornwall-roadworks/fixtures
```

The first snapshot includes Kernow Crescent in Bude, USRN `27400995`, road category `4` as published in the Street Gazetteer field. The second snapshot has no in-progress entry for that permit. The archive has both a start and stop at schema version `1`. This is one verified local-road example. Road category is a separate classification from a road's A or B number. [Street Manager notification schema](https://department-for-transport-streetmanager.github.io/street-manager-docs/api-documentation/json/event-notifier-message.json) · [DfT road reinstatement specification](https://www.gov.uk/government/publications/specification-for-the-reinstatement-of-openings-in-highways)

The fixtures retain the replay fields from two October 2026 Permit archive members. The other source fields were omitted.

- Permit `BC004WH5NW81P-01`, event `165570145`, `WORK_START`, submitted at `2026-10-01T08:54:58.009Z`.
- Same permit, event `165572216`, `WORK_STOP`, submitted at `2026-10-01T09:02:23.173Z`.

Contains public sector information licensed under the Open Government Licence v3.0. Source is the Department for Transport Street Manager monthly permit archive. [Archive listing](https://department-for-transport-streetmanager.github.io/street-manager-docs/archived-notifications/) · [October 2026 archive](https://opendata.manage-roadworks.service.gov.uk/permit/2026/10.zip) · [Licence](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/)

## Replay other records

Download a Permit archive from the DfT, extract the JSON notification files for the cases you want to compare, then pass the individual files or their containing directory to the same command. The October archive is about 1 GB, so the checked-in fixtures are the quickest way to exercise the replay. Supply a cutoff with a UTC offset. The archive's event time records submission to Street Manager and can differ from the actual work time.

The tool filters Permit records by the Cornwall Council authority code `840`, deduplicates event references and chooses the latest event per permit at the cutoff, regardless of file order. Stops, cancellations and revoked permits remove a work from the result. At the same source timestamp, an explicit stop or cancellation takes precedence. A newer report needs both an in-progress status and an actual start time to show as in progress. The report only includes current traffic management fields supplied by the source.

A live receiver must verify the AWS SNS signature and expected topic before using delivered data. Check delivery latency and coverage on selected Cornwall roads against council reports before using this in the car. [DfT delivery documentation](https://department-for-transport-streetmanager.github.io/street-manager-docs/open-data/) · [Cornwall Council notices](https://www.cornwall.gov.uk/transport-parking-and-streets/public-transport/planned-public-transport-service-disruptions/)

Run the regression tests with `python3 -B -m unittest discover -s services/cornwall-roadworks -v`.
