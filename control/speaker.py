#!/usr/bin/env python3

import sys
import os
import subprocess
import re
import pathlib


def get_speaker_dir_path():
    return pathlib.Path(os.path.dirname(__file__)) / '.speaker'


def get_speaker_device_file_path():
    return get_speaker_dir_path() / 'device'


def detect_speaker_device():
    """Return an ALSA playback device string suitable as an ffmpeg output.

    Prefers the analog headphone jack (the 3.5 mm output present on the
    Raspberry Pi 4B), falling back to the first available playback card, and
    finally to the ALSA 'default' device if detection is not possible.
    """
    try:
        output = subprocess.check_output(['aplay', '-l'], text=True)
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return 'default'

    matches = re.findall(r'^card (\d+): (.*?), device (\d+): (.*)$',
                         output,
                         flags=re.MULTILINE)
    if not matches:
        return 'default'

    preferred = None
    for match in matches:
        name = (match[1] + ' ' + match[3]).lower()
        if 'headphone' in name or 'bcm2835' in name:
            preferred = match
            break

    match = preferred if preferred is not None else matches[0]
    return 'plughw:{},{}'.format(match[0], match[2])


def set_speaker_device(device):
    dir_path = get_speaker_dir_path()
    dir_path.mkdir(parents=True, exist_ok=True)
    with open(get_speaker_device_file_path(), 'w') as f:
        f.write(device)


def get_speaker_device():
    file_path = get_speaker_device_file_path()
    if file_path.exists():
        with open(file_path, 'r') as f:
            device = f.read().strip()
        if device:
            return device

    device = detect_speaker_device()
    try:
        set_speaker_device(device)
    except OSError:
        pass
    return device


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--select-speaker', action='store_true')
    parser.add_argument('--get-speaker-device', action='store_true')
    args = parser.parse_args()

    if args.select_speaker:
        set_speaker_device(detect_speaker_device())
    if args.get_speaker_device:
        print(get_speaker_device())
