import hashlib
import importlib.util
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("prepare", Path(__file__).with_name("prepare.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class ArchiveTests(unittest.TestCase):
    def members(self):
        return [tarfile.TarInfo(name) for name in sorted(prepare.REQUIRED)]

    def test_changed_release_rejected_before_extracting(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / "archive"
            archive.write_bytes(b"unreviewed replacement")
            destination = Path(tmp) / "output"
            with self.assertRaisesRegex(ValueError, "Source archive changed"):
                prepare.prepare(archive, destination)
            self.assertFalse(destination.exists())

    def test_checksum_matches_exact_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / "archive"
            archive.write_bytes(b"reviewed fixture")
            prepare.verify_digest(archive, hashlib.sha256(b"reviewed fixture").hexdigest())

    def test_regular_source_members_accepted(self):
        prepare.validate_members(self.members())

    def test_traversal_and_absolute_paths_rejected(self):
        for path in ["/tmp/escape", "campfire-docker/../../escape", "other/file"]:
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "Unsafe archive path"):
                prepare.validate_members(self.members() + [tarfile.TarInfo(path)])

    def test_links_and_special_files_rejected(self):
        for kind in [tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.CHRTYPE, tarfile.FIFOTYPE]:
            member = tarfile.TarInfo("campfire-docker/escape")
            member.type = kind
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, "Unsupported archive entry"):
                prepare.validate_members(self.members() + [member])

    def test_missing_and_duplicate_members_rejected(self):
        with self.assertRaisesRegex(ValueError, "lacks required"):
            prepare.validate_members([])
        members = self.members()
        with self.assertRaisesRegex(ValueError, "Duplicate archive"):
            prepare.validate_members(members + [members[0]])


if __name__ == "__main__":
    unittest.main()
