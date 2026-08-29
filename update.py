#!/usr/bin/env python3

import argparse
import hashlib
import io
import json
import os
import time
import zipfile
from urllib.parse import urlparse

import requests
from tqdm import tqdm

CHUNK_SIZE = 1024 * 1024 * 4

def parse_filename(zip_url: str) -> str:
    """extract the filename from a url"""
    url = urlparse(zip_url)
    return os.path.basename(url.path)


def get_file_data(file_url: str, file_path: str | None) -> bytes:
    """download or read a local file into memory"""
    if file_path is None:
        res = requests.get(file_url, allow_redirects=True, stream=True)
        total_size = int(res.headers.get("content-length", 0))
        content = bytearray()
        progress_bar = tqdm(total=total_size, unit="iB", unit_scale=True)
        for data in res.iter_content(CHUNK_SIZE):
            progress_bar.update(len(data))
            content.extend(data)
        return bytes(content)
    else:
        with open(file_path, "rb") as f:
            return f.read()


def write_json(device: str, update: dict) -> None:
    """write the json array expected by the lineage updater"""
    filename = f"{device}.json"
    with open(filename, "w") as f:
        json.dump([update], f, indent=4)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="update ota metadata for a lineage device")
    parser.add_argument("zip_url", help="direct url to the signed rom zip")
    parser.add_argument("--local-file", help="use a local rom zip instead of downloading", required=False)
    args = parser.parse_args()

    print("parsing filename")
    filename = parse_filename(args.zip_url)
    if not filename.endswith(".zip"):
        raise ValueError("url must point to a .zip file")

    base = filename[:-4]
    parts = base.split("-")

    # expected: lineage-{version}-{date}-{type}-{device}-signed
    if len(parts) != 6:
        raise ValueError("filename must match: lineage-{version}-{date}-{type}-{device}-signed.zip")
    os_name, version, date, build_type, device, signed = parts
    if os_name.lower() != "lineage":
        raise ValueError("not a lineage rom")

    print(f"device: {device}, version: {version}, type: {build_type}, date: {date}")

    print("downloading or reading zip")
    file_content = get_file_data(args.zip_url, args.local_file)
    size = len(file_content)

    datetime = None
    try:
        with zipfile.ZipFile(io.BytesIO(file_content)) as archive:
            metadata = archive.read("META-INF/com/android/metadata")
            for line in metadata.splitlines():
                if line.startswith(b"post-timestamp="):
                    datetime = int(line[15:])
                    break
    except KeyError:
        print("warning: metadata not found, using current time as fallback")
        datetime = int(time.time())
    if datetime is None:
        datetime = int(time.time())

    sha256 = hashlib.sha256(file_content).hexdigest()

    update = {
        "datetime": datetime,
        "files": [
            {
                "filename": filename,
                "sha256": sha256,
                "size": size,
                "url": args.zip_url
            }
        ],
        "type": build_type,
        "version": version
    }

    print("writing json")
    write_json(device, update)
    print(f"done, wrote {device}.json")
