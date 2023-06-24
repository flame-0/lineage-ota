#!/bin/env bash

if [ "$#" -ne 1 ]
then
    echo "You must provide a zip for a device."
    exit 1
fi

parse_device_name() {
    parts="(${1//-/ })"
    echo "${parts}"
}

device=$(parse_device_name "$1")

if [ -z "$device" ]; then
    echo "Not a valid zip."
    exit 1
fi

zip="$1"
date="$(echo "$zip" | grep -oP '\d{8}')"
gh release create "$device-$date" "$1" --title "$device-$date build" --notes "Please read the changelog at https://download.lineageos.org/devices/$device/changes instead."
