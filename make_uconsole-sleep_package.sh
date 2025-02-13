#!/bin/bash

mkdir -p uconsole-sleep/DEBIAN
mkdir -p uconsole-sleep/usr/local/bin
mkdir -p uconsole-sleep/usr/local/src/uconsole-sleep
mkdir -p uconsole-sleep/etc/systemd/system

cat << 'EOF' > uconsole-sleep/usr/local/src/uconsole-sleep/README
Requirement: python3-full, venv(pip)
1. Edit make.sh
2. chmod +x make.sh
3. Execute make.sh
EOF

cp $0 uconsole-sleep/usr/local/src/uconsole-sleep/make.sh

cat << 'EOF' > uconsole-sleep/usr/local/src/uconsole-sleep/find_backlight.py
import os


def find_backlight():
    return "/sys/class/backlight/backlight@0"


if __name__ == "__main__":
    print(find_backlight())
EOF

cat << 'EOF' > uconsole-sleep/usr/local/src/uconsole-sleep/find_drm_panel.py
import os

def find_drm_panel():
    DRM_PATH = "/sys/class/drm"

    for panel in os.listdir(DRM_PATH):
        panel_path = os.path.join(DRM_PATH, panel)
        connector_id_path = os.path.join(panel_path, "connector_id")

        if os.path.isfile(connector_id_path):
            with open(connector_id_path, "r") as f:
                connector_id = f.read().strip()

            if connector_id == "48":
                return panel_path

    return ""

if __name__ == "__main__":
    print(find_drm_panel())
EOF

cat << 'EOF' > uconsole-sleep/usr/local/src/uconsole-sleep/find_framebuffer.py
import os


def find_framebuffer():
    return "/sys/class/graphics/fb0"


if __name__ == "__main__":
    print(find_framebuffer())
EOF

cat << 'EOF' > uconsole-sleep/usr/local/src/uconsole-sleep/find_internal_kb.py
import os


def find_internal_kb(ids=["feed:0000", "1eaf:0003"]):
    usb_device_path = ""

    for device in os.listdir("/sys/bus/usb/devices/"):
        device_path = os.path.join("/sys/bus/usb/devices", device)
        vendor_path = os.path.join(device_path, "idVendor")
        product_path = os.path.join(device_path, "idProduct")

        if os.path.isfile(vendor_path) and os.path.isfile(product_path):
            with open(vendor_path, "r") as f:
                vid = f.read().strip()

            with open(product_path, "r") as f:
                pid = f.read().strip()

            if f"{vid}:{pid}" in ids:
                usb_device_path = device_path
                break

    return usb_device_path


if __name__ == "__main__":
    print(find_internal_kb())
EOF

cat << 'EOF' > uconsole-sleep/usr/local/src/uconsole-sleep/sleep_display_control.py
import os
import uinput
from find_drm_panel import find_drm_panel
from find_framebuffer import find_framebuffer
from find_backlight import find_backlight


drm_panel_path = find_drm_panel()
framebuffer_path = find_framebuffer()
backlight_path = find_backlight()

if not drm_panel_path:
    raise Exception("there's no matched drm panel")

if not framebuffer_path:
    raise Exception("there's no matched framebuffer")

if not backlight_path:
    raise Exception("there's no matched backlight")

uinput_path = "/dev/uinput"
if not os.path.exists(uinput_path):
    raise FileNotFoundError(f"{file_path} 파일이 존재하지 않습니다.")

uinput_device = uinput.Device([uinput.KEY_SLEEP, uinput.KEY_WAKEUP])

status_path = os.path.join(backlight_path, "bl_power")

def toggle_display():
    global drm_panel_path
    global framebuffer_path
    global backlight_path
    global uinput_device
    global status_path

    try:
        with open(status_path, "r") as f:
            screen_state = f.read().strip()

        if screen_state == "4":
            #on
            with open(os.path.join(framebuffer_path, "blank"), "w") as f:
                f.write("0")
            with open(os.path.join(backlight_path, "bl_power"), "w") as f:
                f.write("0")
            with open(os.path.join(drm_panel_path, "status"), "w") as f:
                f.write("detect")
            uinput_device.emit_click(uinput.KEY_WAKEUP)
        else:
            #off
            with open(os.path.join(drm_panel_path, "status"), "w") as f:
                f.write("off")
            with open(os.path.join(framebuffer_path, "blank"), "w") as f:
                f.write("1")
            with open(os.path.join(backlight_path, "bl_power"), "w") as f:
                f.write("4")

        print(f"panel status: {screen_state} to {'0' if screen_state == '4' else '4'}")

    except Exception as e:
        print(f"error occured: {e}")


if __name__ == "__main__":
    toggle_display()
EOF

cat << 'EOF' > uconsole-sleep/usr/local/src/uconsole-sleep/sleep_remap_powerkey.py
import struct
import os
import fcntl
import select
import uinput
import threading
from time import time

from sleep_display_control import toggle_display


EVENT_DEVICE = "/dev/input/event0"
KEY_POWER = 116
HOLD_TRIGGER_SEC = 0.7


def timer_input_power_task(device):
    device.emit(uinput.KEY_POWER, 1)
    device.emit(uinput.KEY_POWER, 0)


with open(EVENT_DEVICE, "rb") as f:
    fcntl.ioctl(f, 0x40044590, 1)

    epoll = select.epoll()
    epoll.register(f.fileno(), select.EPOLLIN)

    uinput_device = uinput.Device([uinput.KEY_POWER])

    try:
        last_key_down_timestamp = 0
        input_power_timer = None

        while True:
            events = epoll.poll()
            current_time = time()
            for fileno, event in events:
                if fileno == f.fileno():
                    event_data = f.read(24)
                    if not event_data:
                        break

                    sec, usec, event_type, code, value = struct.unpack("qqHHi", event_data)

                    if event_type == 1 and code == KEY_POWER:
                        if value == 1:
                            print(f"SRP: power key down input detected.")
                            last_key_down_timestamp = current_time
                            input_power_timer = threading.Timer(HOLD_TRIGGER_SEC, timer_input_power_task, args=(uinput_device,))
                            input_power_timer.start()
                        else:
                            print(f"SRP: power key up input detected.")
                            if input_power_timer != None and (current_time - last_key_down_timestamp) < HOLD_TRIGGER_SEC:
                                input_power_timer.cancel()
                                toggle_display()

    finally:
        epoll.unregister(f.fileno())
        epoll.close()
EOF

cat << 'EOF' > uconsole-sleep/usr/local/src/uconsole-sleep/sleep_power_control.py
import os
import time
from inotify_simple import INotify, flags
#from find_drm_panel import find_drm_panel
from find_backlight import find_backlight
from find_internal_kb import find_internal_kb


def control_by_state(state):
    global kb_device_path
    global kb_device_id
    global usb_driver_path
    global cpu_policy_path

    if state:
        with open(os.path.join(cpu_policy_path, "scaling_max_freq"), "w") as f:
            f.write(default_cpu_freq_max)
        print(f"cpu freq max: {default_cpu_freq_max}")

        with open(os.path.join(usb_driver_path, "bind"), "w") as f:
            f.write(kb_device_id)
        with open(os.path.join(kb_device_path, "power/control"), "w") as f:
            f.write("on")
        print("kb power state: bind")
    else:
        with open(os.path.join(kb_device_path, "power/control"), "w") as f:
            f.write("auto")
        with open(os.path.join(usb_driver_path, "unbind"), "w") as f:
            f.write(kb_device_id)
        print("kb power state: unbind")

        with open(os.path.join(cpu_policy_path, "scaling_max_freq"), "w") as f:
            f.write(default_cpu_freq_min)
        print(f"cpu freq max: {default_cpu_freq_min}")


backlight_path = find_backlight()
#drm_panel_path = find_drm_panel()
kb_device_path = find_internal_kb()
kb_device_id = os.path.basename(kb_device_path)
usb_driver_path = "/sys/bus/usb/drivers/usb"
cpu_policy_path = "/sys/devices/system/cpu/cpufreq/policy0"

if not backlight_path:
    raise Exception("there's no matched backlight")

#if not drm_panel_path:
#    raise Exception("there's no matched drm panel")

if not kb_device_path:
    raise Exception("there's no matched kb")

with open(os.path.join(kb_device_path, "power/autosuspend_delay_ms"), "w") as f:
    f.write("0")
    print(f"{kb_device_path}/power/autosuspend_delay_ms = 0")

with open(os.path.join(cpu_policy_path, "cpuinfo_max_freq"), "r") as f:
    default_cpu_freq_max = f.read().strip()
    print(f"default_cpu_freq_max: {default_cpu_freq_max}")

with open(os.path.join(cpu_policy_path, "cpuinfo_min_freq"), "r") as f:
    default_cpu_freq_min = f.read().strip()
    print(f"default_cpu_freq_min: {default_cpu_freq_min}")

backlight_bl_path = os.path.join(backlight_path, "bl_power")
with open(backlight_bl_path, "r") as f:
    screen_state = f.read().strip()

#drm_enabled_path = os.path.join(drm_panel_path, "enabled")
#with open(drm_enabled_path, "r") as f:
#    screen_state = f.read().strip()

try:
    control_by_state(screen_state != "4")
#    control_by_state(screen_state != "disabled")
except Exception as e:
    print(f"Error occurred: {e}, on init. ignored")

inotify = INotify()
watch_flags = flags.MODIFY
inotify.add_watch(backlight_bl_path, watch_flags)

print(f"Monitoring {backlight_bl_path} for changes...")

last_screen_state = ""
while True:
    try:
        events = inotify.read(1000)

        event_occured = False
        for event in events:
            event_occured = True

        with open(backlight_bl_path, "r") as f:
            screen_state = f.read().strip()
        event_occured = screen_state != last_screen_state
        last_screen_state = screen_state

        if not event_occured:
            continue

        control_by_state(screen_state != "4")

    except Exception as e:
        print(f"Error occurred: {e}")

EOF


cat << 'EOF' > uconsole-sleep/etc/systemd/system/sleep-power-control.service
[Unit]
Description=Sleep Power Control Based on Display and Sleep State
After=basic.target

[Service]
ExecStart=/usr/local/bin/sleep_power_control
Restart=always
User=root
Group=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=basic.target
EOF

cat << 'EOF' > uconsole-sleep/etc/systemd/system/sleep-remap-powerkey.service
[Unit]
Description=Sleep Remap PowerKey
After=basic.target

[Service]
ExecStartPre=/sbin/modprobe uinput
ExecStart=/usr/local/bin/sleep_remap_powerkey
Restart=always
User=root
Group=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=basic.target
EOF

cat << 'EOF' > uconsole-sleep/DEBIAN/control
Package: uconsole-sleep
Version: ENV_VERSION
Maintainer: paragonnov (github.com/qkdxorjs1002)
Original-Maintainer: paragonnov (github.com/qkdxorjs1002)
Architecture: all
Description: uConsole Sleep control scripts.
 Source-Path: /usr/local/src/uconsole-sleep
 Source-Site: https://github.com/qkdxorjs1002/uConsole-sleep
EOF

sed -i "s|ENV_VERSION|$ENV_VERSION|g" uconsole-sleep/DEBIAN/control

cat << 'EOF' > uconsole-sleep/DEBIAN/postinst
#!/bin/bash

systemctl daemon-reload

systemctl enable sleep-power-control.service
systemctl enable sleep-remap-powerkey.service

systemctl start sleep-power-control.service
systemctl start sleep-remap-powerkey.service
EOF

cat << 'EOF' > uconsole-sleep/DEBIAN/prerm
#!/bin/bash

systemctl stop sleep-power-control.service
systemctl stop sleep-remap-powerkey.service

systemctl disable sleep-power-control.service
systemctl disable sleep-remap-powerkey.service
EOF

cat << 'EOF' > uconsole-sleep/DEBIAN/postrm
#!/bin/bash

systemctl daemon-reload
EOF


cd uconsole-sleep
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --no-cache-dir pyinstaller
python3 -m pip install --no-cache-dir "inotify-simple>=1.3.0"
python3 -m pip install --no-cache-dir "python-uinput>=1.0.0"

#pyinstaller -F --distpath usr/local/bin/ usr/local/src/uconsole-sleep/find_backlight.py
#pyinstaller -F --distpath usr/local/bin/ usr/local/src/uconsole-sleep/find_drm_panel.py
#pyinstaller -F --distpath usr/local/bin/ usr/local/src/uconsole-sleep/find_framebuffer.py
#pyinstaller -F --distpath usr/local/bin/ usr/local/src/uconsole-sleep/find_internal_kb.py
#pyinstaller -F --hidden-import=_libsuinput --distpath usr/local/bin/ usr/local/src/uconsole-sleep/sleep_display_control.py
pyinstaller -F --distpath usr/local/bin/ usr/local/src/uconsole-sleep/sleep_power_control.py
pyinstaller -F --hidden-import=_libsuinput --distpath usr/local/bin/ usr/local/src/uconsole-sleep/sleep_remap_powerkey.py

chmod +x usr/local/bin/*
chmod +x DEBIAN/*

rm -rf usr/local/src/uconsole-sleep/*.py
rm -rf ./*.spec
rm -rf ./build
rm -rf ./.venv
cd ..

dpkg-deb --build uconsole-sleep


rm -rf uconsole-sleep
