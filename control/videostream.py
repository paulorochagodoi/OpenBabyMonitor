#!/usr/bin/env python3

import os
import time
import signal
import threading
import subprocess
import pathlib
import control
import mic
import recording

MODE = 'videostream'
HORIZONTAL_RESOLUTIONS = {480: 640, 720: 1280, 1080: 1920}


def stream_video():
    control.enter_mode(
        MODE, lambda mode, config, database: stream_video_with_settings(
            **control.read_settings(mode, config, database),
            **control.read_setting('audiostream', 'gain', config, database),
            **control.read_settings('listen', config, database)))


def stream_video_with_settings(encrypted=True,
                               vertical_resolution=720,
                               use_variable_framerate=True,
                               framerate=30,
                               rotation=0,
                               flip_horizontally=False,
                               flip_vertically=False,
                               exposure_mode='auto',
                               metering='average',
                               exposure_value_compensation=0,
                               exposure_time=100,
                               iso=400,
                               white_balance_mode='greyworld',
                               red_gain=0.0,
                               blue_gain=0.0,
                               capture_audio=True,
                               show_time=True,
                               gain=100,
                               enable_recording=True,
                               recording_max_storage=500,
                               **kwargs):
    picam_dir = os.environ['BM_PICAM_DIR']
    output_dir = os.environ['BM_PICAM_STREAM_DIR']
    log_path = os.environ['BM_SERVER_LOG_PATH']
    mic_id = mic.get_mic_id()

    mic.update_current_mic_volume(gain)

    assert vertical_resolution in HORIZONTAL_RESOLUTIONS, \
        'Vertical resolution ({}) is not one of {}'.format(
        vertical_resolution, ', '.join(list(HORIZONTAL_RESOLUTIONS.keys())))
    resolution_args = [
        '--width',
        str(HORIZONTAL_RESOLUTIONS[vertical_resolution]), '--height',
        str(vertical_resolution)
    ]

    fps_args = ['--vfr'] if use_variable_framerate else [
        '--fps', str(framerate)
    ]

    orientation_args = ['--rotation', str(rotation)]
    if flip_horizontally:
        orientation_args += ['--hflip']
    if flip_vertically:
        orientation_args += ['--vflip']

    brightness_args = ['--metering', metering, '--ex', exposure_mode]
    if exposure_mode == 'off':
        brightness_args += [
            '--evcomp',
            str(exposure_value_compensation), '--shutter',
            str(exposure_time), '--iso',
            str(iso)
        ]

    color_args = ['--wb', white_balance_mode]
    if white_balance_mode == 'off':
        color_args += ['--wbred', str(red_gain), '--wbblue', str(blue_gain)]

    audio_args = ['--alsadev', mic_id] if capture_audio else ['--noaudio']

    time_args = ['--time', '--timeformat', r'%a %d.%m.%Y %T'
                 ] if show_time else []

    if encrypted:
        with open(os.path.join(output_dir, 'stream.hexkey')) as f:
            encryption_key = f.read()
        encryption_args = [
            '--hlsenc', '--hlsenckeyuri', 'stream.key', '--hlsenckey',
            encryption_key
        ]
    else:
        encryption_args = []

    output_args = ['--hlsdir', output_dir]

    picam_args = [os.path.join(picam_dir, 'picam')] + \
        output_args + encryption_args + resolution_args + fps_args + \
        orientation_args + brightness_args + color_args + audio_args + \
        time_args

    recorder = VideoRecordingController(
        picam_dir, output_dir,
        recording_max_storage) if enable_recording else None

    control.signal_mode_started(MODE)

    stopping = {'requested': False}

    with open(log_path, 'a') as log_file:
        process = subprocess.Popen(picam_args,
                                   stdout=subprocess.DEVNULL,
                                   stderr=log_file,
                                   cwd=output_dir)

        # Terminate picam cleanly when systemd stops the mode, so that the
        # recording is finalized before we move it to persistent storage
        def handle_termination(*args):
            stopping['requested'] = True
            if recorder is not None:
                recorder.stop()
            if process.poll() is None:
                process.terminate()

        signal.signal(signal.SIGTERM, handle_termination)
        signal.signal(signal.SIGINT, handle_termination)

        try:
            if recorder is not None:
                recorder.start()
            returncode = process.wait()
        finally:
            if recorder is not None:
                recorder.finalize()

    # A non-zero return code is expected when we deliberately stopped picam on
    # a mode switch; only propagate an unexpected crash.
    if returncode != 0 and not stopping['requested']:
        raise subprocess.CalledProcessError(returncode, picam_args)


class VideoRecordingController:
    '''Drives picam's built-in recording via its hook files and moves the
    finished MPEG-TS files into the persistent recordings directory, applying
    the same rolling storage limit as the audio recordings.'''
    # picam finalizes recordings into a directory named 'rec/archive'
    # relative to its working directory; the working directory lives in
    # shared memory, so we move the results onto persistent storage
    def __init__(self, picam_dir, output_dir, max_storage_mb):
        self.picam_dir = pathlib.Path(picam_dir)
        self.output_dir = pathlib.Path(output_dir)
        self.max_storage_mb = max_storage_mb
        self.hooks_dir = self.output_dir / 'hooks'
        self.start_time = None
        self._start_timer = None

    def start(self):
        self.start_time = time.time()
        # Give picam a moment to initialize before requesting a recording
        self._start_timer = threading.Timer(2.0, self._touch_start_record)
        self._start_timer.start()

    def _touch_start_record(self):
        try:
            self.hooks_dir.mkdir(parents=True, exist_ok=True)
            (self.hooks_dir / 'start_record').touch()
        except OSError:
            pass

    def stop(self):
        if self._start_timer is not None:
            self._start_timer.cancel()
        try:
            self.hooks_dir.mkdir(parents=True, exist_ok=True)
            (self.hooks_dir / 'stop_record').touch()
        except OSError:
            pass
        # Give picam a moment to flush the recording to disk
        time.sleep(1.0)

    def finalize(self):
        if self._start_timer is not None:
            self._start_timer.cancel()
        if self.start_time is None:
            return
        source_dirs = [
            self.output_dir / 'rec' / 'archive',
            self.picam_dir / 'rec' / 'archive',
            self.picam_dir / 'archive',
        ]
        try:
            recording.finalize_video_recordings(
                recording.get_recordings_dir(),
                source_dirs,
                self.start_time,
                max_storage_mb=self.max_storage_mb)
        except Exception:
            pass


if __name__ == '__main__':
    stream_video()
