#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check the four real packages against an already signature-verified DB."""
import hashlib
import pathlib
import sys
import tarfile

root = pathlib.Path(sys.argv[1])
required = {"luminos-base", "luminos-desktop", "luminos-keyring", "luminos-dawn"}
with tarfile.open(root / "luminos-repository.db", "r:gz") as db:
    for member in db.getmembers():
        if not member.name.endswith("/desc"):
            continue
        entry = db.extractfile(member).read().decode()
        fields = {}
        for block in entry.strip().split("\n\n"):
            lines = block.splitlines()
            fields[lines[0]] = lines[1:]
        name = fields["%NAME%"][0]
        if name not in required:
            continue
        filename = fields["%FILENAME%"][0]
        if pathlib.Path(filename).name != filename:
            sys.exit("Invalid package filename in repository database")
        with (root / filename).open("rb") as archive:
            digest = hashlib.file_digest(archive, "sha256").hexdigest()
        if digest != fields["%SHA256SUM%"][0]:
            sys.exit(f"Package checksum mismatch: {filename}")
        print(f"Verified published package: {filename}")
        required.remove(name)
if required:
    sys.exit(f"Missing published packages: {sorted(required)}")
