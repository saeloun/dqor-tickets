#!/usr/bin/env python3
"""Verify the deployed source release before preparing a Kamal build context."""
import argparse
import hashlib
from pathlib import Path, PurePosixPath
import tarfile

RELEASE_SHA256 = "a91496ff7aad9232a79ba72017656698388ea02976b97c48cf0921f7205d921e"
REQUIRED = {"campfire-docker/Dockerfile", "campfire-docker/pack/Makefile", "campfire-docker/boot", "campfire-docker/MIT-LICENSE"}


def verify_digest(path, expected=RELEASE_SHA256):
    with path.open("rb") as source:
        actual = hashlib.file_digest(source, "sha256").hexdigest()
    if actual != expected:
        raise ValueError(f"Source archive changed: expected {expected}, got {actual}. Do not build or replace the pin without reviewing the new release.")


def validate_members(members):
    names = set()
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "campfire-docker":
            raise ValueError(f"Unsafe archive path: {member.name}")
        if not (member.isfile() or member.isdir()):
            raise ValueError(f"Unsupported archive entry: {member.name}")
        if member.name in names:
            raise ValueError(f"Duplicate archive entry: {member.name}")
        names.add(member.name)
    if not REQUIRED <= names:
        raise ValueError("Archive lacks required source/build/license files")


def prepare(archive, destination):
    verify_digest(archive)
    if destination.exists():
        raise ValueError(f"Destination already exists: {destination}; retain it or choose another path")
    with tarfile.open(archive, "r:gz") as source:
        members = source.getmembers()
        validate_members(members)
        destination.mkdir(parents=True)
        source.extractall(destination, members=members, filter="data")
    print(f"Verified source context: {destination / 'campfire-docker'}")
    print("No source code executed. Review the retained archive and build recipe before building.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="retained deployed docker.tgz; never a silently refreshed download")
    parser.add_argument("--destination", type=Path, default=Path(".campfire-build"))
    args = parser.parse_args()
    try:
        prepare(args.archive, args.destination)
    except (ValueError, OSError, tarfile.TarError) as error:
        parser.exit(1, f"{error}\n")
