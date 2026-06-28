<?php
require_once(dirname(__DIR__) . '/config/error_config.php');
require_once(dirname(__DIR__) . '/config/env_config.php');
require_once(dirname(__DIR__) . '/config/database_config.php');
require_once(__DIR__ . '/database.php');

if (!defined('FEATURE_ACTION_OK')) {
  define('FEATURE_ACTION_OK', 0);
}

// Independent on/off features (not mutually exclusive modes). Each maps to its
// own systemd service that can run alongside any monitoring mode. New entries
// are added here as features are implemented.
define('FEATURE_SERVICES', array(
  'whitenoise' => 'bm_whitenoise',
  'nightlight' => 'bm_nightlight',
));

function featureServiceName($feature) {
  if (!array_key_exists($feature, FEATURE_SERVICES)) {
    bm_error("Unknown feature: $feature");
  }
  return FEATURE_SERVICES[$feature];
}

// Start/restart or stop the feature service to match the desired state. Using
// 'restart' when enabling makes a running service pick up new settings and
// starts a stopped one. Failures are logged but not fatal, so saving settings
// is never blocked if the service is momentarily unavailable.
function reconcileFeatureService($feature, $enabled) {
  $service = featureServiceName($feature);
  $action = $enabled ? 'restart' : 'stop';
  $output = null;
  $result_code = null;
  exec('sudo systemctl ' . $action . ' ' . $service . ' 2>&1', $output, $result_code);
  if ($result_code != 0) {
    bm_warning("Request to $action $service failed with error code $result_code:\n" . join("\n", $output));
  }
  return $result_code;
}

// Persist the on/off state in the feature's settings table.
function setFeatureEnabled($database, $feature, $enabled) {
  featureServiceName($feature); // validate feature name
  updateValuesInTable($database, $feature . '_settings', withPrimaryKey(array('enabled' => $enabled ? 1 : 0)));
}

// Used by the toggle endpoint: persist the new state and reconcile the service.
function applyFeatureState($database, $feature, $enabled) {
  setFeatureEnabled($database, $feature, $enabled);
  reconcileFeatureService($feature, $enabled);
  return FEATURE_ACTION_OK;
}
