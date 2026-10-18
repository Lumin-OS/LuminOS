#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The authenticated DB's package hashes must fail closed on corruption."""
import hashlib
import io
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import unittest

VERIFY = pathlib.Path(__file__).with_name("verify-published.py")
NAMES = ("luminos-base", "luminos-desktop", "luminos-keyring", "luminos-dawn")


class PublishedPackages(unittest.TestCase):
    def verify(self, *, corrupt=False, missing=False, traversal=False, obsolete=None):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            with tarfile.open(root / "luminos-repository.db", "w:gz") as db:
                for name in NAMES[:-1] if missing else NAMES:
                    filename = f"{name}-1-1-any.pkg.tar.zst"
                    content = name.encode()
                    (root / filename).write_bytes(content)
                    digest = hashlib.sha256(content).hexdigest()
                    if corrupt and name == NAMES[0]:
                        (root / filename).write_bytes(b"tampered")
                    if traversal and name == NAMES[0]:
                        filename = "../" + filename
                    version = obsolete[1] if obsolete and name == obsolete[0] else "1-1"
                    desc = (
                        f"%NAME%\n{name}\n\n%VERSION%\n{version}\n\n%FILENAME%\n{filename}\n\n"
                        f"%SHA256SUM%\n{digest}\n\n"
                    ).encode()
                    member = tarfile.TarInfo(f"{name}-1-1/desc")
                    member.size = len(desc)
                    db.addfile(member, io.BytesIO(desc))
            return subprocess.run(
                [sys.executable, str(VERIFY), directory],
                text=True, capture_output=True, check=False,
            )

    def test_all_packages_match(self):
        self.assertEqual(self.verify().returncode, 0)

    def test_modified_package_rejected(self):
        result = self.verify(corrupt=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum mismatch", result.stderr)

    def test_missing_package_rejected(self):
        result = self.verify(missing=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing published packages", result.stderr)

    def test_native_cpu_release_rejected_before_build(self):
        result = self.verify(obsolete=("luminos-dawn", "0.1.0-1"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Publish the M6 replacement", result.stderr)

    def test_old_trust_key_release_rejected_before_build(self):
        result = self.verify(obsolete=("luminos-keyring", "20260928-1"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Publish the M6 replacement", result.stderr)

    def test_path_outside_repository_rejected(self):
        result = self.verify(traversal=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid package filename", result.stderr)


if __name__ == "__main__":
    unittest.main()
