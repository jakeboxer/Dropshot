#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_dir="$script_dir/build"
app_dir="$output_dir/DropshotDragSource.app"
contents_dir="$app_dir/Contents"
executable_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
fixture="$script_dir/../../DropshotTests/Fixtures/oriented-metadata.heic"

mkdir -p "$executable_dir" "$resources_dir"
xcrun swiftc \
    -module-cache-path "$output_dir/module-cache" \
    -framework AppKit \
    -framework CryptoKit \
    -framework UniformTypeIdentifiers \
    "$script_dir/main.swift" \
    -o "$executable_dir/DropshotDragSource"
cp "$script_dir/Info.plist" "$contents_dir/Info.plist"
cp "$fixture" "$resources_dir/oriented-metadata.heic"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"

printf '%s\n' "Built $app_dir"
