<?php
require_once(dirname(__DIR__) . '/config/path_config.php');
require_once(SRC_DIR . '/session.php');
require_once(dirname(__DIR__) . '/config/database_config.php');
require_once(SRC_DIR . '/feature.php');

abortIfSessionExpired();

if (isset($_POST['feature']) && isset($_POST['enabled'])) {
  $feature = $_POST['feature'];
  $enabled = ($_POST['enabled'] === '1' || $_POST['enabled'] === 'true');
  echo applyFeatureState($_DATABASE, $feature, $enabled);
}
