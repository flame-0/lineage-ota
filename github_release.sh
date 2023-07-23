#!/usr/bin/env bash

if [[ "$#" -lt 1 ]]; then
    echo "You must provide a zip for a device."
    exit 1
fi

device=$(echo "$1" | cut -d'-' -f3)

if [[ -z "$device" ]]; then
    echo "Not a valid zip."
    exit 1
fi

zip_date=$(echo "$1" | cut -d'-' -f5)

files=()
notes=""
process_notes=false
for arg in "$@"; do
    if [[ "$arg" == "-n" ]] || [[ "$arg" == "--note" ]]; then
        process_notes=true
    elif [[ "$process_notes" = true ]]; then
        notes+="$arg"$'\n'
    else
        files+=("$arg")
    fi
done

for file in "${files[@]}"; do
    sha256sum "$file" | head -c 64 > "$file.sha256sum"
    gh_args+=("$file" "$file.sha256sum")
done

note_formatted=$(echo "$notes" | sed 's/^/- /' | sed '$ d')
note_features="- Visit the [website](https://kenvyra.xyz/features/) for a complete list of features"
note_default="Read the device changelog at https://download.lineageos.org/devices/${device}/changes."

if [[ -n "$notes" ]]; then
    notes="**Changelog**"$'\n\n'"${note_formatted}"$'\n'"${note_features}"$'\n\n'"${note_default}"
else
    notes="**Changelog**"$'\n\n'"${note_features}"$'\n\n'"${note_default}"
fi

gh release create "${device}-${zip_date}" "${gh_args[@]}" --title "${device}-${zip_date} build" --notes "${notes}"
