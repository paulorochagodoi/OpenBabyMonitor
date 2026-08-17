<?php
require_once(dirname(__DIR__) . '/config/path_config.php');
require_once(SRC_DIR . '/session.php');
require_once(SRC_DIR . '/recordings.php');

if (!isLoggedIn()) {
  http_response_code(403);
  exit();
}

if (!isset($_GET['name'])) {
  http_response_code(400);
  exit();
}

streamRecordingMedia($_GET['name']);
