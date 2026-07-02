<?php
require_once(dirname(__DIR__) . '/config/error_config.php');
require_once(dirname(__DIR__) . '/config/path_config.php');

// Audio recordings are named rec_<timestamp>[.wav], video recordings
// vid_<timestamp>[.ts]. An optional numeric suffix (_1, _2, ...) avoids
// name collisions.
define('RECORDING_NAME_PATTERN', '/^(rec|vid)_\d{8}_\d{6}(_\d+)?$/');
define('RECORDING_WAV_HEADER_SIZE', 44);
define('RECORDING_BYTES_PER_SAMPLE', 2);

// Adds the recording settings columns to the listen_settings table if they
// are missing (needed when updating an existing installation).
function ensureRecordingSettingsColumns($database) {
  $columns = array(
    'enable_recording' => 'BOOLEAN NOT NULL DEFAULT TRUE',
    'recording_max_storage' => 'INT UNSIGNED NOT NULL DEFAULT 500'
  );
  foreach ($columns as $name => $type) {
    $result = $database->query("SHOW COLUMNS FROM `listen_settings` LIKE '$name'");
    if ($result && $result->num_rows == 0) {
      $database->query("ALTER TABLE `listen_settings` ADD COLUMN `$name` $type");
    }
  }
}

function isValidRecordingName($name) {
  return preg_match(RECORDING_NAME_PATTERN, $name) === 1;
}

function getRecordingKind($name) {
  return strpos($name, 'vid_') === 0 ? 'video' : 'audio';
}

function getRecordingMediaExtension($name) {
  return getRecordingKind($name) === 'video' ? 'ts' : 'wav';
}

function getRecordingMediaPath($name) {
  return RECORDINGS_DIR . "/$name." . getRecordingMediaExtension($name);
}

function getRecordingSidecarPath($name) {
  return RECORDINGS_DIR . "/$name.json";
}

function readRecordingSidecar($name) {
  $sidecar_path = getRecordingSidecarPath($name);
  if (!file_exists($sidecar_path)) {
    return array();
  }
  $sidecar = json_decode(file_get_contents($sidecar_path), true);
  return is_array($sidecar) ? $sidecar : array();
}

function describeRecording($media_path) {
  $ext = pathinfo($media_path, PATHINFO_EXTENSION);
  $name = basename($media_path, '.' . $ext);
  if (!isValidRecordingName($name)) {
    return null;
  }
  $kind = getRecordingKind($name);
  $size = filesize($media_path);
  $sidecar = readRecordingSidecar($name);

  $start_time = isset($sidecar['start_time']) ? floatval($sidecar['start_time']) : null;
  if ($start_time === null) {
    $dt = DateTime::createFromFormat('Ymd_His', substr($name, 4, 15));
    $start_time = $dt ? $dt->getTimestamp() : filemtime($media_path);
  }

  $markers = array();
  if (isset($sidecar['markers']) && is_array($sidecar['markers'])) {
    $markers = $sidecar['markers'];
    usort($markers, function ($a, $b) {
      return $a['time'] <=> $b['time'];
    });
  }

  if ($kind === 'audio') {
    $sampling_rate = isset($sidecar['sampling_rate']) ? intval($sidecar['sampling_rate']) : 8000;
    $duration = max(0, $size - RECORDING_WAV_HEADER_SIZE) / (RECORDING_BYTES_PER_SAMPLE * max(1, $sampling_rate));
  } else {
    $duration = isset($sidecar['duration']) ? floatval($sidecar['duration']) : 0;
  }

  return array(
    'name' => $name,
    'kind' => $kind,
    'start_time' => $start_time,
    'duration' => round($duration, 1),
    'size' => $size,
    'markers' => $markers
  );
}

function listRecordings() {
  $recordings = array();
  if (!is_dir(RECORDINGS_DIR)) {
    return $recordings;
  }
  $media_paths = array_merge(
    glob(RECORDINGS_DIR . '/rec_*.wav'),
    glob(RECORDINGS_DIR . '/vid_*.ts')
  );
  foreach ($media_paths as $media_path) {
    $recording = describeRecording($media_path);
    if ($recording !== null) {
      $recordings[] = $recording;
    }
  }
  usort($recordings, function ($a, $b) {
    return $b['start_time'] <=> $a['start_time'];
  });
  return $recordings;
}

function deleteRecording($name) {
  if (!isValidRecordingName($name)) {
    return false;
  }
  $media_path = getRecordingMediaPath($name);
  $sidecar_path = getRecordingSidecarPath($name);
  $deleted = false;
  if (file_exists($media_path)) {
    $deleted = unlink($media_path);
  }
  if (file_exists($sidecar_path)) {
    unlink($sidecar_path);
  }
  return $deleted;
}

function clearRecordings() {
  foreach (listRecordings() as $recording) {
    deleteRecording($recording['name']);
  }
}

// Streams a recording file with support for HTTP range requests, which the
// browser audio/video player needs for seeking. Works for both WAV audio
// and MPEG-TS video recordings.
function streamRecordingMedia($name) {
  if (!isValidRecordingName($name)) {
    http_response_code(400);
    exit();
  }
  $media_path = getRecordingMediaPath($name);
  if (!file_exists($media_path)) {
    http_response_code(404);
    exit();
  }
  $content_type = getRecordingKind($name) === 'video' ? 'video/mp2t' : 'audio/wav';
  $size = filesize($media_path);
  $start = 0;
  $end = $size - 1;

  if (isset($_SERVER['HTTP_RANGE']) &&
      preg_match('/bytes=(\d*)-(\d*)/', $_SERVER['HTTP_RANGE'], $matches)) {
    if ($matches[1] !== '') {
      $start = intval($matches[1]);
      if ($matches[2] !== '') {
        $end = min(intval($matches[2]), $size - 1);
      }
    } elseif ($matches[2] !== '') {
      $start = max(0, $size - intval($matches[2]));
    }
    if ($start > $end || $start >= $size) {
      http_response_code(416);
      header("Content-Range: bytes */$size");
      exit();
    }
    http_response_code(206);
    header("Content-Range: bytes $start-$end/$size");
  }

  header("Content-Type: $content_type");
  header('Accept-Ranges: bytes');
  header('Content-Length: ' . ($end - $start + 1));
  header('Cache-Control: no-cache');

  $file = fopen($media_path, 'rb');
  fseek($file, $start);
  $remaining = $end - $start + 1;
  while ($remaining > 0 && !feof($file) && !connection_aborted()) {
    $chunk = fread($file, min(65536, $remaining));
    if ($chunk === false) {
      break;
    }
    echo $chunk;
    flush();
    $remaining -= strlen($chunk);
  }
  fclose($file);
  exit();
}
