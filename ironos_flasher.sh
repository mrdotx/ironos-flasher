#!/bin/sh

# path:   /home/klassiker/.local/share/repos/ironos-flasher/ironos_flasher.sh
# author: klassiker [mrdotx]
# github: https://github.com/mrdotx/ironos-flasher
# date:   2021-10-28T12:54:52+0200

script=$(basename "$0")
help="$script [-h/--help] -- script for flashing firmware to compatible devices
  Usage:
    $script <hexfile>

  Settings:
    <hexfile> = file to be flashed to the device

  Examples:
    $script TS100_EN.hex"

mnt_dir="/tmp/ironos"
max_retries=2
gautomount=0
instructions=0
result=

disable_gautomount() {
    which gsettings > /dev/null \
        || return 1

    ! gsettings get org.gnome.desktop.media-handling automount \
        | grep true > /dev/null \
        && gautomount=1  \
        && gsettings set org.gnome.desktop.media-handling automount false
}

enable_gautomount() {
    [ "$gautomount" -ne 0 ] \
        && gsettings set org.gnome.desktop.media-handling automount true
}

device_attached() {
    output=$(lsblk -bro name,model | grep 'DFU.*Disk') \
        || return 1
    device=$(printf "/dev/%s" "$output" | cut -d' ' -f1)
    instructions=1
}

wait_for_device() {
    while ! device_attached; do
        [ "$instructions" -eq 0 ] \
            && printf "%s\n" \
                "" \
                "#######################################################" \
                "#                                                     #" \
                "#      Waiting for config disk device to appear       #" \
                "#                                                     #" \
                "#  Connect the soldering iron with a USB cable while  #" \
                "#    holding the button closest to the tip pressed    #" \
                "#                                                     #" \
                "#######################################################" \
            && instructions=1
        sleep .1
    done
}

mount_device() {
    mkdir -p "$mnt_dir"
    ! sudo mount -t msdos -o rw,umask=0000 "$device" "$mnt_dir" \
        && printf "Failed to mount %s on %s\n" "$device" "$mnt_dir"\
        && exit 1
}

umount_device() {
    [ -d "$mnt_dir" ] \
        && ! (mountpoint "$mnt_dir" > /dev/null && sudo umount "$mnt_dir") \
        && printf "Failed to unmount %s\n" "$mnt_dir"\
        && exit 1
    sleep 1
    rm -d "$mnt_dir"
}

flash_device() {
    disable_gautomount

    wait_for_device
    printf "\nFound config disk device on %s\n" "$device"

    mount_device
    printf "Mounted config disk drive, flashing...\n"
    cat "$1" > "$mnt_dir/firmware.hex"

    printf "Remounting config disk drive\n"
    umount_device
    wait_for_device
    mount_device

    result=$(find "$mnt_dir" -type f -iname 'firmware.*' \
        | cut -d"/" -f4 \
        | tail -n1 \
    )

    umount_device
    enable_gautomount
}

case "$1" in
    -h | --help | "")
        printf "%s\n" "$help"
        ;;
    *)
        if [ ! -f "$1" ] \
            || [ "$(head -c1 "$1")" != ":" ] \
            || [ "$(tail -n1 "$1" | head -c1)" != ":" ]; then
                printf "%s\n\n  %s\n    '%s' %s\n    %s\n" \
                    "$help" \
                    "Error:" \
                    "$1" \
                    "doesn't look like a valid HEX file." \
                    "Please provide a regular HEX file to flash..."
                exit 1
        fi

        while [ $max_retries -ge 1 ]; do
                flash_device "$1"
                if [ "$result" = "firmware.rdy" ]; then
                    max_retries=0
                    printf "\n  Flashing successful!\n"
                else
                    max_retries=$((max_retries-1))
                    printf "\n  Flashing error! Try again %d more time...\n" \
                        "$max_retries"
                fi
        done

        printf "\n"
        ;;
esac
