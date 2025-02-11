
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

        event_occured = False
        for event in events:
            event_occured = True

        with open("/sys/class/backlight/backlight@0/bl_power", "r") as f:
            screen_state = f.read().strip()
        event_occured = screen_state != last_screen_state
        last_screen_state = screen_state

        if not event_occured:
            continue
        print("trigger")
#        control_by_state(screen_state != "4")

    except Exception as e:
        print(f"Error occurred: {e}")
