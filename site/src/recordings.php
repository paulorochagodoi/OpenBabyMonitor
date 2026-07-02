<?php
require_once(dirname(__DIR__) . '/config/error_config.php');
require_once(dirname(__DIR__) . '/config/path_config.php');

define('RECORDING_NAME_PATTERN', '/^rec_\d{8}_\d{6}$/');
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

function getRecordingWavPath($name) {
  return RECORDINGS_DIR . "/$name.wav";
}

function getRecordingSidecarPath($name) {
  return RECORDINGS_DIR . "/$name.json";
}

function listRecordings() {
  $recordings = array();
  if (!is_dir(RECORDINGS_DIR)) {
    return $recordings;
  }
  foreach (glob(RECORDINGS_DIR . '/rec_*.wav') as $wav_path) {
    $name = basename($wav_path, '.wav');
    if (!isValidRecordingName($name)) {
      continue;
    }
    $size = filesize($wav_path);
    $sidecar_path = getRecordingSidecarPath($name);
    $sampling_rate = 8000;
    $start_time = null;
    $markers = array();
    if (file_exists($sidecar_path)) {
      $sidecar = json_decode(file_get_contents($sidecar_path), true);
      if (is_array($sidecar)) {
        $sampling_rate = isset($sidecar['sampling_rate']) ? intval($sidecar['sampling_rate']) : 8000;
        $start_time = isset($sidecar['start_time']) ? floatval($sidecar['start_time']) : null;
        if (isset($sidecar['markers']) && is_array($sidecar['markers'])) {
          $markers = $sidecar['markers'];
        }
      }
    }
    if ($start_time === null) {
      // Fall back to parsing the timestamp in the file name
      $dt = DateTime::createFromFormat('Ymd_His', substr($name, 4));
      $start_time = $dt ? $dt->getTimestamp() : filemtime($wav_path);
    }
    usort($markers, function ($a, $b) {
      return $a['time'] <=> $b['time'];
    });
    $duration = max(0, $size - RECORDING_WAV_HEADER_SIZE) / (RECORDING_BYTES_PER_SAMPLE * max(1, $sampling_rate));
    $recordings[] = array(
      'name' => $name,
      'start_time' => $start_time,
      'duration' => round($duration, 1),
      'size' => $size,
      'markers' => $markers
    );
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
  $wav_path = getRecordingWavPath($name);
  $sidecar_path = getRecordingSidecarPath($name);
  $deleted = false;
  if (file_exists($wav_path)) {
    $deleted = unlink($wav_path);
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

// Streams a recording WAV file with support for HTTP range requests,
// which the browser audio player needs for seeking.
function streamRecordingAudio($name) {
  if (!isValidRecordingName($name)) {
    http_response_code(400);
    exit();
  }
  $wav_path = getRecordingWavPath($name);
  if (!file_exists($wav_path)) {
    http_response_code(404);
    exit();
  }
  $size = filesize($wav_path);
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

  header('Content-Type: audio/wav');
  header('Accept-Ranges: bytes');
  header('Content-Length: ' . ($end - $start + 1));
  header('Cache-Control: no-cache');

  $file = fopen($wav_path, 'rb');
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
