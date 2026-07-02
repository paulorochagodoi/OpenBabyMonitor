#!/usr/bin/env python3

import os
import json
import time
import struct
import pathlib
import collections
import numpy as np

WAV_HEADER_SIZE = 44
BYTES_PER_SAMPLE = 2  # 16-bit PCM


def get_recordings_dir():
    return pathlib.Path(
        os.environ.get('BM_RECORDINGS_DIR',
                       os.path.join(os.environ['BM_DIR'], 'recordings')))


class WavSegmentWriter:
    '''Incrementally writes mono 16-bit PCM WAV files, keeping the header
    sizes up to date after every write so the file is always playable even
    if the process is terminated abruptly.'''
    def __init__(self, file_path, sampling_rate):
        self.file_path = file_path
        self.sampling_rate = sampling_rate
        self.n_samples = 0
        self.file = open(file_path, 'wb')
        self._write_header()

    def _write_header(self):
        data_size = self.n_samples * BYTES_PER_SAMPLE
        byte_rate = self.sampling_rate * BYTES_PER_SAMPLE
        header = struct.pack('<4sI4s4sIHHIIHH4sI', b'RIFF',
                             36 + data_size, b'WAVE', b'fmt ', 16, 1, 1,
                             self.sampling_rate, byte_rate, BYTES_PER_SAMPLE,
                             8 * BYTES_PER_SAMPLE, b'data', data_size)
        self.file.seek(0)
        self.file.write(header)
        self.file.seek(0, os.SEEK_END)

    def append(self, samples_int16):
        self.file.write(samples_int16.tobytes())
        self.n_samples += samples_int16.size
        self._write_header()
        self.file.flush()

    @property
    def duration(self):
        return self.n_samples / self.sampling_rate

    def close(self):
        if not self.file.closed:
            self._write_header()
            self.file.close()


class RollingRecorder:
    '''Continuously saves the audio chunks recorded in listen mode as WAV
    segments in the recordings directory, deleting the oldest segments
    when the total storage exceeds the given limit. Moments identified as
    crying can be marked and are stored in a JSON sidecar file next to
    each segment.'''
    def __init__(self,
                 sampling_rate,
                 max_storage_mb=500,
                 segment_duration=600,
                 max_chunk_gap=30,
                 recordings_dir=None):
        self.recordings_dir = pathlib.Path(
            recordings_dir) if recordings_dir else get_recordings_dir()
        self.sampling_rate = sampling_rate
        self.max_storage_bytes = int(max_storage_mb * 1e6)
        self.segment_duration = segment_duration
        self.max_chunk_gap = max_chunk_gap

        self.writer = None
        self.segment_start_time = None
        self.segment_stem = None
        self.markers = []
        self.last_chunk_end_time = None

        # Maps the record time of recent chunks to their position in the
        # recording, so that markers (which arrive with a delay from the
        # inference process) can be placed at the correct audio offset
        self.chunk_positions = collections.deque(maxlen=100)

        self.recordings_dir.mkdir(parents=True, exist_ok=True)
        self.cleanup()

    def add_chunk(self, waveform, record_time):
        if waveform is None or waveform.size == 0:
            return

        chunk_duration = waveform.size / self.sampling_rate
        chunk_start_time = record_time - 0.5 * chunk_duration

        if self._segment_expired(chunk_start_time):
            self._finalize_segment()

        if self.writer is None:
            self._start_segment(chunk_start_time)

        offset = self.writer.duration
        self.chunk_positions.append(
            (record_time, self.segment_stem, offset))

        samples = np.clip(waveform, -1.0, 1.0)
        self.writer.append((samples * 32767).astype('<i2'))

        self.last_chunk_end_time = chunk_start_time + chunk_duration

    def add_marker(self, record_time, marker_type):
        for chunk_record_time, segment_stem, offset in self.chunk_positions:
            if chunk_record_time == record_time:
                self._store_marker(segment_stem, offset, marker_type)
                return

    def _store_marker(self, segment_stem, offset, marker_type):
        sidecar_path = self.recordings_dir / (segment_stem + '.json')
        if segment_stem == self.segment_stem:
            self.markers.append({
                'time': round(offset, 2),
                'type': marker_type
            })
            self._write_sidecar()
        elif sidecar_path.exists():
            # Marker belongs to an already finalized segment
            with open(sidecar_path, 'r') as f:
                sidecar = json.load(f)
            sidecar.setdefault('markers', []).append({
                'time': round(offset, 2),
                'type': marker_type
            })
            self._write_json(sidecar_path, sidecar)

    def _segment_expired(self, chunk_start_time):
        if self.writer is None:
            return False
        if self.writer.duration >= self.segment_duration:
            return True
        if self.last_chunk_end_time is not None and \
                chunk_start_time - self.last_chunk_end_time > self.max_chunk_gap:
            return True
        return False

    def _start_segment(self, start_time):
        self.segment_start_time = start_time
        self.segment_stem = 'rec_{}'.format(
            time.strftime('%Y%m%d_%H%M%S', time.localtime(start_time)))
        self.markers = []
        self.writer = WavSegmentWriter(
            self.recordings_dir / (self.segment_stem + '.wav'),
            self.sampling_rate)
        self._write_sidecar()

    def _finalize_segment(self):
        if self.writer is not None:
            self.writer.close()
            self._write_sidecar()
            self.writer = None
            self.segment_stem = None
            self.markers = []
        self.cleanup()

    def _write_sidecar(self):
        sidecar_path = self.recordings_dir / (self.segment_stem + '.json')
        self._write_json(
            sidecar_path, {
                'start_time': self.segment_start_time,
                'sampling_rate': self.sampling_rate,
                'markers': self.markers
            })

    def _write_json(self, path, content):
        with open(path, 'w') as f:
            json.dump(content, f)

    def cleanup(self):
        segments = sorted(self.recordings_dir.glob('rec_*.wav'))
        sizes = {}
        total_size = 0
        for segment in segments:
            sidecar = segment.with_suffix('.json')
            size = segment.stat().st_size + (sidecar.stat().st_size
                                             if sidecar.exists() else 0)
            sizes[segment] = size
            total_size += size

        for segment in segments:
            if total_size <= self.max_storage_bytes:
                break
            if self.writer is not None and \
                    segment == pathlib.Path(self.writer.file_path):
                continue
            self._remove_if_exists(segment)
            self._remove_if_exists(segment.with_suffix('.json'))
            total_size -= sizes[segment]

    def _remove_if_exists(self, path):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

    def close(self):
        self._finalize_segment()
