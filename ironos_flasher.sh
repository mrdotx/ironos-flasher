#!/bin/sh

# path:   /home/klassiker/.local/share/repos/ironos-flasher/ironos_flasher.sh
# author: klassiker [mrdotx]
# github: https://github.com/mrdotx/ironos-flasher
# date:   2021-10-30T10:45:21+0200

# auth can be something like sudo -A, doas -- or nothing,
# depending on configuration requirements
auth="sudo"

# config
mnt_dir="/tmp/ironos"
max_attempts=2

script=$(basename "$0")
help="$script [-h/--help] -- script for flashing firmware to compatible devices
  Usage:
    $script [-a/--attempts] <hexfile>

  Settings:
    [-a/--attempts] = maximum attempts until successfully flash the device
                      (default: $max_attempts)
    <hexfile>       = file to be flashed to the device

  Examples:
    $script TS100_EN.hex
    $script -a 1 TS100_EN.hex
    $script --attempts 5 TS100_EN.hex

  Config:
    mnt_dir      = $mnt_dir
    max_attempts = $max_attempts"

gnome_automount() {
    schema="org.gnome.desktop.media-handling"
    key="automount"

    case "$1" in
        disable)
            command -v gsettings > /dev/null 2>&1 \
                || return 1

            gsettings get "$schema" "$key" \
                | grep -q true \
                && automount=1 \
                && gsettings set "$schema" "$key" false
            ;;
        enable)
            [ "$automount" -ne 0 ] \
                && gsettings set "$schema" "$key" true
    esac
}

wait_for_device() {
    device_attached() {
        output=$(lsblk -bro name,model | grep 'DFU.*Disk') \
            || return 1
        device=$(printf "/dev/%s" "$output" | cut -d' ' -f1)
        instructions=0
    }

    while ! device_attached; do
        [ "$instructions" -eq 1 ] \
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
            && instructions=0
        sleep .1
    done
}

mount_device() {
    mkdir -p "$mnt_dir"
    ! $auth mount -t msdos -o rw,umask=0000 "$device" "$mnt_dir" \
        && printf "Failed to mount %s on %s\n" "$device" "$mnt_dir"\
        && exit 1
}

umount_device() {
    [ -d "$mnt_dir" ] \
        && ! (mountpoint -q "$mnt_dir" && $auth umount "$mnt_dir") \
        && printf "Failed to unmount %s\n" "$mnt_dir"\
        && exit 1
    sleep 1
    rm -d "$mnt_dir"
}

check_file() {
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
}

check_integer() {
    ! [ "$1" -eq "$1" ] 2> /dev/null \
        && printf "%s\n\n  %s\n    '%s' %s\n" \
            "$help" \
            "Error:" \
            "$1" \
            "doesn't look like a valid integer." \
        && exit 1
}

flash_device() {
    automount=0
    instructions=1
    max_attempts=$2

    while [ "$max_attempts" -ge 1 ]; do
        gnome_automount "disable"

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
        gnome_automount "enable"

        if [ "$result" = "firmware.rdy" ]; then
            max_attempts=0
            printf "\n  Flashing successful!\n"
        else
            max_attempts=$((max_attempts-1))
            printf "\n  %s\n  %s %d\n  %s\n" \
                "Flashing error!" \
                "Attempts left:" \
                "$max_attempts" \
                "Please wait..."
        fi
    done
}

case "$1" in
    -h | --help | "")
        printf "%s\n" "$help"
        ;;
    -a | --attempts )
        check_integer "$2"
        max_attempts=$2
        shift 2

        check_file "$1"
        flash_device "$1" "$max_attempts"

        printf "\n"
        ;;
    *)
        check_file "$1"
        flash_device "$1" "$max_attempts"

        printf "\n"
        ;;
esac
