#!/usr/bin/env python3
import argparse
import hashlib
import io
import json
import os
import time
import uuid
import zipfile
from urllib.parse import urlparse

import requests
from tqdm import tqdm

CHUNK_SIZE = 1024 * 1024 * 4  # 4MB

DEVICE_DATA = {
    "datetime": None, # To be filled in
    "filename": None,  # To be filled in
    "id": None, # To be filled in
    "size": None,  # To be filled in
    "url": None,  # To be filled in
    "version": "13.0",
}


def parse_filename(zip_url: str) -> str:
    url = urlparse(zip_url)
    file_name = os.path.basename(url.path)

    return file_name


def get_file_data(file_url: str, file_path: str | None) -> bytes:
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
        with open(file_path, "rb") as file:
            return file.read()


def write_data(flavor: str, device: str) -> None:
    filename = f"{device}_{flavor.lower()}.json"

    with open(filename, "w") as file:
        json.dump({"response": [DEVICE_DATA]}, file, indent=4)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Update the OTA data for a device.")
    parser.add_argument("zip_url", nargs="?", help="static link to the flashable zip")
    parser.add_argument(
        "--local-file",
        type=str,
        nargs="?",
        required=False,
        help="path to local version of flashable zip (else will be downloaded)",
    )

    args = parser.parse_args()

    print("Parsing filename...")

    filename = parse_filename(args.zip_url)

    print("Validating extension...")

    if filename[-4:] != ".zip":
        raise ValueError("Provided URL does not end in .zip")

    parts = filename[:-4].split("-")

    print("Validating file name...")

    if len(parts) != 6:
        raise ValueError("Filename does not contain exactly 6 parts")

    os_name, version, device_name, build_type, date, flavor = parts

    print("Validating OS name...")

    if os_name != "Kenvyra":
        raise ValueError(f"File is for {os_name}, not Kenvyra")

    print("Downloading or opening ZIP...")

    file_content = get_file_data(args.zip_url, args.local_file)
    size = len(file_content)

    with zipfile.ZipFile(io.BytesIO(file_content)) as archive:
        metadata = archive.read("META-INF/com/android/metadata")
        for line in metadata.splitlines():
            if line.startswith(b"post-timestamp="):
                DEVICE_DATA["datetime"] = int(line[15:])

    sha256 = hashlib.sha256(file_content).hexdigest()

    DEVICE_DATA["id"] = sha256
    DEVICE_DATA["filename"] = filename
    DEVICE_DATA["size"] = size
    DEVICE_DATA["url"] = args.zip_url

    print("Writing JSON...")

    write_data(flavor, device_name)

    print("Make sure to update the changelog in the Wiki!")
