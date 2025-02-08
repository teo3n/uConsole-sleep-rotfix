import os
import time
from inotify_simple import INotify, flags


inotify = INotify()
watch_flags = flags.MODIFY
inotify.add_watch("/sys/class/backlight/backlight@0/bl_power", watch_flags)

last_screen_state = ""
while True:
    try:
        events = inotify.read(1000)
        print(f">{events}")
        event_occured = False
        for event in events:
            event_occured = True
        with open("/sys/class/backlight/backlight@0/bl_power", "r") as f:
            screen_state = f.read().strip()
        last_screen_state = screen_state

        if not event_occured and screen_state == last_screen_state:
            print("state not changed")
            continue

        print("chaged")

    except Exception as e:
        print(f"Error occurred: {e}")
