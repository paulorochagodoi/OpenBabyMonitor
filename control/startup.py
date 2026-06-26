#!/usr/bin/env python3

if __name__ == '__main__':
    import standby
    standby.set_standby()

    import features
    features.restore_enabled_features()
