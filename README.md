# uConsole-sleep

### NOTE: Rotation Fix

This is a relatively quick and hacky way of fixing the display being rotated wrong upon wake. Basically, this version sets the rotation and kills any display setting windows. Are there better ways? Sure. Do I want to spend any time on this? No. Otherwise this works identically to the original. This is based on the v1.3 of the original.

### uConsole Sleep service package

This service is built on Ubuntu 22.04 and Python.

It detects power key events to turn the screen on and off. Initially, I used a polling loop for event detection, but to reduce CPU load, I switched to using epoll.

Whenever the screen turns off for any reason (e.g., screensaver, desktop lock, sleep mode), 
the service detects the screen-off state and lowers the CPU’s maximum frequency to the minimum while also turning off the built-in keyboard’s power and wakeup trigger.

(I also tried changing the CPU governor to `powersave`, but I noticed a slight delay when switching.)

Similarly, I initially used a polling loop to detect screen-off events, but to reduce CPU load, I switched to using inotify.

The service consists of two background processes:

* **sleep-remap-powerkey**
`/usr/local/bin/sleep_remap_powerkey`
Detects power key events and controls the screen power.
* **sleep-power-control**
`/usr/local/bin/sleep_power_control`
Manages power-saving operations based on screen status.

**More Details**
[on forum.clockworkpi.com](https://forum.clockworkpi.com/t/uconsole-sleep-v1-2/15612?u=paragonnov)


<a href="https://www.buymeacoffee.com/paragonnov" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-red.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
