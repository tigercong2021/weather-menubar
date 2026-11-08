#!/usr/bin/env python3
"""Reproduce/verify the bright-star subset and Swift constants without network access."""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parents[1]
COMMIT = "c7f7f883fe678cc7680169a50ccd7dcc49b060ce"
SOURCE_HASHES = {
    "hygdata_v41.csv": "d9f69fd86bbf90a4e4d52b4c5c53eacfa6dfc0bfdef85bfd94f095e0bebe4ebd",
    "HYG-LICENSE.md": "f404190403d31e0ce7223f4cb7af954485ad88077358330754dc5c892a856627",
    "HYG-README.md": "81f765951e60131e49ccc91376815791e130ad1db46047eb1384d3ba6bcb5af4",
    "CC-BY-SA-4.0.txt": "28a9529c7d0bb4dc51f4bf5c116a3d16ef247a052f7591466768ddf563fd1cf5",
}
PC_TO_LY = 3.262  # Conversion recommended by the pinned HYG README, not an exact constant.


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def produce(path, data, write):
    if path.exists():
        if path.read_bytes() != data:
            raise RuntimeError(f"Existing output differs; refusing to replace: {path}")
    elif write:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("xb") as output:
            output.write(data)
    else:
        raise RuntimeError(f"Missing generated output: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Create missing outputs; never replace differing files")
    args = parser.parse_args()
    for name, expected in SOURCE_HASHES.items():
        actual = digest((ROOT / "original" / name).read_bytes())
        if actual != expected:
            raise RuntimeError(f"Source hash mismatch: {name}")

    with (ROOT / "original/hygdata_v41.csv").open(newline="") as source:
        rows = list(csv.DictReader(source))
    selected = []
    original_selected = []
    excluded_sun = []
    for row in rows:
        mag = float(row["mag"])
        if not math.isfinite(mag) or mag > 3:
            continue
        if row["id"] == "0" or row["proper"] == "Sol":
            excluded_sun.append(row["id"])
            continue
        ra, dec, distance = (float(row[key]) for key in ("ra", "dec", "dist"))
        if not all(math.isfinite(x) for x in (ra, dec, distance)):
            raise RuntimeError(f"Nonfinite bright-star coordinates/distance: {row['id']}")
        if not (0 <= ra < 24 and -90 <= dec <= 90 and 0 < distance < 100000):
            raise RuntimeError(f"Out-of-range or missing bright-star coordinates/distance: {row['id']}")
        # Verify the hours/degrees interpretation against the independent radian columns.
        if abs(math.radians(ra * 15) - float(row["rarad"])) > 2e-7:
            raise RuntimeError(f"RA unit mismatch: {row['id']}")
        if abs(math.radians(dec) - float(row["decrad"])) > 2e-7:
            raise RuntimeError(f"Declination unit mismatch: {row['id']}")
        selected.append({
            "id": "hyg-" + row["id"],
            "name": row["proper"] or row["bf"] or "HIP " + row["hip"],
            "rightAscensionHours": ra,
            "declinationDegrees": dec,
            "distanceLightYears": round(distance * PC_TO_LY, 7),
            "visualMagnitude": mag,
        })
        original_selected.append(row)
    selected.sort(key=lambda row: (row["visualMagnitude"], int(row["id"][4:])))
    assert len(rows) == 119626 and len(selected) == 179 and excluded_sun == ["0"]
    assert len({row["id"] for row in selected}) == len(selected)
    by_name = {row["name"]: row for row in selected}
    assert by_name["Sirius"]["rightAscensionHours"] == 6.752481
    assert by_name["Sirius"]["visualMagnitude"] == -1.44
    assert by_name["Canopus"]["declinationDegrees"] < -50
    assert by_name["Polaris"]["declinationDegrees"] > 89

    # Coverage check: at each 5-degree latitude and 15-minute local-sidereal-time
    # grid point, there is a selected star above 10 degrees. This is a sampled
    # catalog-coverage check, not a claim of visibility through weather or terrain.
    minimum_best_altitude = 90.0
    for latitude in range(-90, 91, 5):
        phi = math.radians(latitude)
        for tick in range(96):
            sidereal_hours = tick / 4
            best_altitude = max(math.degrees(math.asin(max(-1, min(1,
                math.sin(phi) * math.sin(math.radians(star["declinationDegrees"]))
                + math.cos(phi) * math.cos(math.radians(star["declinationDegrees"]))
                * math.cos(math.radians(15 * (sidereal_hours - star["rightAscensionHours"])))
            )))) for star in selected)
            minimum_best_altitude = min(minimum_best_altitude, best_altitude)
    assert minimum_best_altitude > 10

    json_output = encoded({
        "catalog": "HYG v4.1, apparent visual magnitude <= 3; Sun excluded",
        "creator": "David Nash / Astronexus",
        "sourceCommit": COMMIT,
        "sourceSHA256": SOURCE_HASHES["hygdata_v41.csv"],
        "license": "CC-BY-SA-4.0",
        "licenseURL": "https://creativecommons.org/licenses/by-sa/4.0/",
        "epochAndEquinox": "J2000.0",
        "distanceConversion": "HYG dist in parsecs multiplied by the documented approximate factor 3.262",
        "stars": selected,
    })
    swift = """// Generated by assets/star-catalog/scripts/prepare_bright_stars.py. Do not edit by hand.
// Star data: HYG v4.1, David Nash / Astronexus, CC BY-SA 4.0.
// https://github.com/astronexus/HYG-Database/tree/c7f7f883fe678cc7680169a50ccd7dcc49b060ce
// https://creativecommons.org/licenses/by-sa/4.0/
// Adaptation: magnitude <= 3, Sun removed, selected fields, parsecs converted to light-years.
// Original sources, license, exact hashes and reproducible filter: assets/star-catalog/.

struct BrightStar: Sendable {
    let id: String
    let name: String
    /// J2000.0 epoch and equinox; hours, not degrees. Proper motion is not advanced here.
    let rightAscensionHours: Double
    let declinationDegrees: Double
    /// HYG catalog distance, converted with its documented approximate pc-to-ly factor 3.262.
    let distanceLightYears: Double
    /// Catalog nominal apparent V magnitude; lower is brighter, not current measured flux.
    let visualMagnitude: Double
}

enum BrightStarCatalog {
    static let attribution = "HYG v4.1 · David Nash / Astronexus · CC BY-SA 4.0"
    // No network, observer location, fabricated points, or runtime resource lookup.
    // Components and variable stars retain the catalog's nominal magnitudes.
    static let stars: [BrightStar] = [
"""
    for star in selected:
        values = ", ".join(f"{key}: {json.dumps(value, ensure_ascii=False)}" for key, value in star.items())
        swift += f"        BrightStar({values}),\n"
    swift += "    ]\n}\n"
    swift_output = swift.encode()
    outputs = {
        ROOT / "bright-stars-v41-mag3.json": json_output,
        PROJECT / "source/BrightStarCatalog.swift": swift_output,
    }
    for path, data in outputs.items():
        produce(path, data, args.write)

    manifest = {
        "createdDate": "2026-11-08",
        "scope": "Personal weather menu-bar local trial. No upload or public publication performed.",
        "provider": "David Nash / Astronexus",
        "upstreamRepository": "https://github.com/astronexus/HYG-Database",
        "upstreamCommit": COMMIT,
        "upstreamMaintenanceNote": "Pinned archived v4.1 snapshot; author has moved later development to https://codeberg.org/astronexus/hyg.",
        "sourceBlobSHA1": "ba2dec4eb0f6768914c7fc1051258100214ddf84",
        "sources": [{"path": "original/" + name, "sha256": expected,
                     "bytes": (ROOT / "original" / name).stat().st_size}
                    for name, expected in SOURCE_HASHES.items()],
        "license": "CC-BY-SA-4.0",
        "licenseURL": "https://creativecommons.org/licenses/by-sa/4.0/",
        "adaptedDataLicense": "CC-BY-SA-4.0",
        "filter": {"maximumApparentVisualMagnitude": 3, "excludeSun": True,
                   "originalRows": len(rows), "selectedRows": len(selected),
                   "epochAndEquinox": "J2000.0", "distanceParsecToLightYear": PC_TO_LY},
        "checks": {"sourceHashesVerified": True, "coordinateUnitsCheckedAgainstRadianColumns": True,
                   "allDistancesPositiveAndBelowUnknownSentinel": True,
                   "uniqueIDs": True, "northernStars": sum(s["declinationDegrees"] >= 0 for s in selected),
                   "southernStars": sum(s["declinationDegrees"] < 0 for s in selected),
                   "coverageGrid": "latitude -90...90 step 5 degrees; local sidereal time 0...23.75 step 0.25 hours",
                   "minimumHighestStarAltitudeOnCoverageGridDegrees": round(minimum_best_altitude, 6),
                   "maxCatalogProperMotionMasPerYear": round(max(math.hypot(float(r["pmra"]), float(r["pmdec"])) for r in original_selected), 6)},
        "limitations": [
            "Nominal catalog V magnitude is not live photometry; variable stars vary.",
            "Resolved catalog components are not recombined into unresolved naked-eye system brightness.",
            "This subset retains J2000.0 positions; the consumer must handle frame/date transforms and observer location.",
            "Proper motion is retained in the original CSV but not applied by this static API.",
            "Atmospheric extinction, terrain, buildings, clouds and light pollution are not encoded in the catalog.",
        ],
        "outputs": [{"path": str(path.relative_to(PROJECT)), "bytes": len(data), "sha256": digest(data)}
                    for path, data in outputs.items()],
        "scripts": [{"path": "scripts/" + name, "sha256": digest((ROOT / "scripts" / name).read_bytes())}
                    for name in ("fetch_hyg_source.py", "prepare_bright_stars.py")],
    }
    produce(ROOT / "manifest-20261108.json", encoded(manifest), args.write)
    print(json.dumps({"status": "passed", "stars": len(selected), "sourceSHA256": SOURCE_HASHES["hygdata_v41.csv"],
                      "minimumBestAltitudeOnCoverageGrid": round(minimum_best_altitude, 3),
                      "outputs": [str(path.relative_to(PROJECT)) for path in outputs]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
