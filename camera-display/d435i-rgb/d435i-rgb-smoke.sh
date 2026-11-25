#!/usr/bin/env bash
# Run on BBAI64 after attaching a D435i. Prints diagnostics and discards frames.
set -euo pipefail
export LC_ALL=C

if [[ $# != 0 && $# != 5 ]]; then
    echo "Usage: bash $0 [/dev/videoN width height fourcc fps]" >&2
    exit 2
fi
command -v v4l2-ctl >/dev/null
command -v lsusb >/dev/null
lsusb -t
v4l2-ctl --list-devices
if [[ $# == 0 ]]; then
    exit 0
fi

node=$1
if [[ ! $node =~ ^/dev/video[0-9]+$ || ! -c $node ||
      ! $2 =~ ^[1-9][0-9]*$ || ! $3 =~ ^[1-9][0-9]*$ ||
      ! $4 =~ ^[A-Z0-9]{4}$ || ! $5 =~ ^[1-9][0-9]*$ ]]; then
    echo 'Expected a video node, positive dimensions and fps, and a fourcc.' >&2
    exit 2
fi

usb_device=$(readlink -f "/sys/class/video4linux/${node##*/}/device")
while [[ $usb_device != / && ! -r $usb_device/idVendor ]]; do
    usb_device=$(dirname "$usb_device")
done
if [[ ! -r $usb_device/idProduct ||
      $(cat "$usb_device/idVendor") != 8086 ||
      $(cat "$usb_device/idProduct") != 0b3a ]]; then
    echo "The selected node does not belong to USB device 8086:0b3a (D435i)." >&2
    exit 2
fi
printf 'USB speed (Mbit/s): %s\n' "$(cat "$usb_device/speed")"

v4l2-ctl -d "$node" --list-formats-ext
# The caller selects the RGB node and a mode advertised by this command.
v4l2-ctl -d "$node" --set-fmt-video="width=$2,height=$3,pixelformat=$4" \
    --set-parm="$5" --get-fmt-video --get-parm
timeout 60s v4l2-ctl -d "$node" --stream-mmap=4 --stream-count=300 \
    --stream-to=/dev/null --verbose
