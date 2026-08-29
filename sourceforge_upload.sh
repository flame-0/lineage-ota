#!/usr/bin/env bash
set -e

PROJECT="lineage-ota"
SF_USER="flame-0"
SF_HOST="frs.sourceforge.net"
UPLOAD_DIR="/home/frs/project/${PROJECT}"

if [[ "$#" -lt 1 ]]; then
    echo "usage: $0 <rom.zip> [image1.img] [image2.img] ..."
    exit 1
fi

rom_zip=""
images=()
for file in "$@"; do
    base=$(basename "$file")
    if [[ "$base" =~ ^lineage-[0-9]+\.[0-9]+-[0-9]{8}-[^-]+-[^-]+-signed\.zip$ ]]; then
        if [[ -n "$rom_zip" ]]; then
            echo "multiple rom zips found; only one allowed"
            exit 1
        fi
        rom_zip="$file"
    else
        images+=("$file")
    fi
done

if [[ -z "$rom_zip" ]]; then
    echo "rom zip not found; ensure it matches lineage-{version}-{date}-{type}-{device}-signed.zip"
    exit 1
fi

base=$(basename "$rom_zip" .zip)
IFS='-' read -r -a parts <<< "$base"
version="${parts[1]}"
date="${parts[2]}"
build_type="${parts[3]}"
device="${parts[4]}"

device_dir="${UPLOAD_DIR}/${device}"
date_dir="${device_dir}/${date}"

echo "uploading to sourceforge..."
echo "device: ${device}, version: ${version}, type: ${build_type}, date: ${date}"

echo "creating remote directory: ${date_dir}"
sftp -b - "${SF_USER}@${SF_HOST}" <<EOF
-mkdir ${device_dir}
-mkdir ${date_dir}
bye
EOF

all_files=("$rom_zip" "${images[@]}")
for file in "${all_files[@]}"; do
    echo "uploading ${file}..."
    rsync -avP "$file" "${SF_USER}@${SF_HOST}:${date_dir}/"
done

echo "upload complete."

rom_url="https://downloads.sourceforge.net/project/${PROJECT}/${device}/${date}/$(basename "$rom_zip")"

if command -v python3 &>/dev/null && [[ -f "update.py" ]]; then
    echo "generating ota json..."
    python3 update.py "$rom_url" --local-file "$rom_zip"
else
    echo "update.py not found or python3 missing; skipping ota json generation"
    echo "run: ./update.py ${rom_url} --local-file ${rom_zip}"
fi

echo "updating index.json..."
python3 - "$device" "$date" "$version" "$build_type" "$PROJECT" "$rom_zip" "${images[@]}" <<'PY'
import json, sys, os, hashlib

device = sys.argv[1]
date = sys.argv[2]
version = sys.argv[3]
build_type = sys.argv[4]
project = sys.argv[5]
rom_zip = sys.argv[6]
image_files = sys.argv[7:]

base_url = f"https://downloads.sourceforge.net/project/{project}/{device}/{date}"

def file_info(filepath):
    filename = os.path.basename(filepath)
    size = os.path.getsize(filepath)
    sha256 = hashlib.sha256(open(filepath, 'rb').read()).hexdigest()
    url = f"{base_url}/{filename}"
    return {"filename": filename, "url": url, "size": size, "sha256": sha256}

files = []
files.append(file_info(rom_zip))

for img in image_files:
    files.append(file_info(img))

entry = {
    "device": device,
    "date": date,
    "version": version,
    "type": build_type,
    "files": files
}

try:
    with open("index.json", "r") as f:
        index = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    index = []

index = [e for e in index if e.get("device") != device]
index.append(entry)

with open("index.json", "w") as f:
    json.dump(index, f, indent=4)

print(f"index.json updated with {len(files)} files for {device}")
PY

echo "done"
