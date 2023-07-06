#!/bin/env bash

if [ "$#" -lt 1 ]; then
    echo "You must provide a zip for a device."
    exit 1
fi

parse_device_name() {
    echo "$1" | cut -d'-' -f3
}

device=$(parse_device_name "$1")

if [ -z "$device" ]; then
    echo "Not a valid zip."
    exit 1
fi

zip_date=$(echo "$1" | cut -d'-' -f5)

for file in "$@"; do
    sha256sum "$file" | head -c 64 > "$file.sha256sum"
    gh_args+=("$file" "$file.sha256sum")
done

gh release create "${device}-${zip_date}" "${gh_args[@]}" --title "${device}-${zip_date} build" --notes "Please read the changelog at https://download.lineageos.org/devices/${device}/changes instead."
