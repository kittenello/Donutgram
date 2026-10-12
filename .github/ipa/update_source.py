#!/usr/bin/env python3
"""Writes the AltStore-format source for a freshly published build.

An installer offers an update when the source's newest `version` differs from
the version it recorded when the app was installed from that source. The app
version in versions.json stays the same for many builds, so each entry's
`version` carries the build number too (`13.0.1234`).

The branch that hosts the source keeps only the newest IPA, so the source
lists only that build.

Usage: update_source.py <output path>
Reads the build from the environment (see the publish job in build.yml).
"""

import datetime
import json
import os
import sys

REPOSITORY = os.environ["GITHUB_REPOSITORY"]
REPOSITORY_URL = f"https://github.com/{REPOSITORY}"
ICON_URL = f"https://raw.githubusercontent.com/{REPOSITORY}/master/Telegram/Telegram-iOS/DgDonut3D.alticon/DgDonut3D@3x.png"
BUNDLE_ID = "com.kittenello.donutgram"


def changelog(commit_message):
    lines = [line.strip() for line in commit_message.strip().splitlines()]
    # A merged pull request's commit reads "Merge pull request #N from …",
    # followed by a blank line and the pull request's title.
    if lines and lines[0].startswith("Merge pull request") and len(lines) > 2:
        lines = lines[2:]
    text = "\n".join(line for line in lines if line)
    return text or "Новая сборка"


def main():
    output_path = sys.argv[1]

    app_version = os.environ["APP_VERSION"]
    build_number = os.environ["BUILD_NUMBER"]
    latest = {
        "version": f"{app_version}.{build_number}",
        "buildVersion": build_number,
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": changelog(os.environ.get("COMMIT_MESSAGE", "")),
        "downloadURL": os.environ["DOWNLOAD_URL"],
        "size": os.path.getsize(os.environ["IPA_PATH"]),
        "minOSVersion": "15.0",
    }

    source = {
        "name": "Donutgram",
        "identifier": "com.kittenello.donutgram.source",
        "subtitle": "Сборки Пончика с master",
        "description": "Каждая сборка master публикуется сюда автоматически.",
        "iconURL": ICON_URL,
        "website": REPOSITORY_URL,
        "tintColor": "#E8508C",
        "apps": [
            {
                "name": "Donutgram",
                "bundleIdentifier": BUNDLE_ID,
                "developerName": "kittenello",
                "subtitle": "Telegram с пончиком",
                "localizedDescription": "Неофициальный клиент Telegram на основе Telegram iOS.",
                "iconURL": ICON_URL,
                "tintColor": "#E8508C",
                "category": "social",
                "versions": [latest],
                # Legacy single-version fields for older AltStore-format readers.
                "version": latest["version"],
                "versionDate": latest["date"],
                "versionDescription": latest["localizedDescription"],
                "downloadURL": latest["downloadURL"],
                "size": latest["size"],
            }
        ],
        "news": [],
    }

    with open(output_path, "w", encoding="utf-8") as file:
        json.dump(source, file, ensure_ascii=False, indent=2)
        file.write("\n")


if __name__ == "__main__":
    main()
