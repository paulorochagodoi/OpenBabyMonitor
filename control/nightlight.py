#!/usr/bin/env python3

import os
import math
import time
import signal
import control

# The night light is an independent feature, not one of the mutually exclusive
# monitoring modes: it runs alongside whatever mode is active and therefore does
# not touch the 'modes' table the way control.enter_mode does.
FEATURE = 'nightlight'

# Number of LEDs on the WS2812/NeoPixel ring or strip. Override with the
# BM_NIGHTLIGHT_NUM_LEDS environment variable to match your hardware.
NUM_PIXELS = int(os.environ.get('BM_NIGHTLIGHT_NUM_LEDS', '12'))

# Duration of one full fade-in/fade-out cycle of the 'breathe' effect.
BREATHE_PERIOD_S = 6.0

_pixels = None
_running = True


def hex_to_rgb(color):
    color = color.lstrip('#')
    if len(color) != 6:
        return (255, 180, 108)
    return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))


def scale_rgb(rgb, brightness):
    factor = max(0.0, min(1.0, brightness / 100.0))
    return tuple(int(round(channel * factor)) for channel in rgb)


def get_pixels():
    # The hardware libraries are imported lazily so this module stays importable
    # on machines without the Raspberry Pi GPIO/SPI stack.
    global _pixels
    if _pixels is None:
        import board
        import neopixel_spi as neopixel
        spi = board.SPI()
        _pixels = neopixel.NeoPixel_SPI(spi, NUM_PIXELS, auto_write=False)
    return _pixels


def set_all(rgb):
    pixels = get_pixels()
    pixels.fill(rgb)
    pixels.show()


def turn_off():
    try:
        set_all((0, 0, 0))
    except Exception:
        pass


def handle_shutdown(*args):
    global _running
    _running = False


def run():
    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)

    config = control.get_config()
    database = control.get_database(config)
    settings = control.read_settings(FEATURE, config, database)
    run_with_settings(**settings)


def run_with_settings(enabled=True,
                      color='#ffb86c',
                      brightness=40,
                      effect='solid',
                      **kwargs):
    if not enabled:
        return

    rgb = hex_to_rgb(color)
    try:
        if effect == 'breathe':
            run_breathe(rgb, brightness)
        else:
            set_all(scale_rgb(rgb, brightness))
            while _running:
                time.sleep(0.2)
    finally:
        turn_off()


def run_breathe(rgb, max_brightness):
    start = time.monotonic()
    while _running:
        phase = (time.monotonic() - start) / BREATHE_PERIOD_S * 2 * math.pi
        level = (1 - math.cos(phase)) / 2  # smoothly oscillates between 0 and 1
        set_all(scale_rgb(rgb, max_brightness * level))
        time.sleep(0.05)


if __name__ == '__main__':
    run()
