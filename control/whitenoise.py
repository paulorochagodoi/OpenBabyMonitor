#!/usr/bin/env python3

import os
import sys
import signal
import subprocess
import control
import speaker

# White noise is an independent feature, not one of the mutually exclusive
# monitoring modes: it runs alongside whatever mode is active and therefore does
# not touch the 'modes' table the way control.enter_mode does.
FEATURE = 'whitenoise'

# Maps the stored sound type to an ffmpeg 'anoisesrc' colour.
NOISE_COLORS = {'white': 'white', 'pink': 'pink', 'brown': 'brown'}

_process = None


def handle_shutdown(*args):
    global _process
    if _process is not None and _process.poll() is None:
        _process.terminate()
        try:
            _process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            _process.kill()
    sys.exit(0)


def play():
    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)

    config = control.get_config()
    database = control.get_database(config)
    settings = control.read_settings(FEATURE, config, database)
    play_with_settings(database, **settings)


def play_with_settings(database,
                       enabled=True,
                       sound_type='pink',
                       volume=50,
                       timer_minutes=0,
                       **kwargs):
    global _process

    if not enabled:
        return

    color = NOISE_COLORS.get(sound_type, 'pink')
    amplitude = max(0.0, min(1.0, float(volume) / 100.0))
    timer_minutes = int(timer_minutes)
    device = speaker.get_speaker_device()
    log_path = os.environ['BM_SERVER_LOG_PATH']

    # anoisesrc is an endless source, so the noise loops seamlessly for as long
    # as the process runs. The amplitude (0..1) acts as the volume control.
    input_args = [
        '-f', 'lavfi', '-i',
        'anoisesrc=color={}:amplitude={:.4f}'.format(color, amplitude)
    ]
    duration_args = ['-t', str(timer_minutes * 60)] if timer_minutes > 0 else []
    output_args = ['-f', 'alsa', device]

    command = (['ffmpeg', '-hide_banner', '-loglevel', 'fatal', '-nostdin'] +
               input_args + duration_args + output_args)

    with open(log_path, 'a') as log_file:
        _process = subprocess.Popen(command,
                                    stdout=subprocess.DEVNULL,
                                    stderr=log_file)
        returncode = _process.wait()

    # If ffmpeg ended on its own because the auto-off timer elapsed (rather than
    # being stopped via SIGTERM), clear the enabled flag so the web UI and the
    # boot-time state restore both reflect that the feature is now off.
    if timer_minutes > 0 and returncode == 0:
        with database as open_database:
            open_database.update_values_in_table(FEATURE + '_settings',
                                                 dict(id=0, enabled=0))


if __name__ == '__main__':
    play()
