#!/usr/bin/env python3

import subprocess
import control

# Independent on/off features and their systemd services. These run alongside
# any monitoring mode. Mirrors the FEATURE_SERVICES map in
# site/src/feature.php.
FEATURE_SERVICES = {
    'whitenoise': 'bm_whitenoise',
}


def restore_enabled_features():
    """Start the service of every feature whose stored state is enabled.

    Called at boot so that features the user left on are turned back on after a
    reboot or power loss.
    """
    config = control.get_config()
    database = control.get_database(config)
    for feature, service in FEATURE_SERVICES.items():
        settings = control.read_settings(feature, config, database)
        if settings.get('enabled'):
            subprocess.run(['sudo', 'systemctl', 'start', service], check=False)


if __name__ == '__main__':
    restore_enabled_features()
