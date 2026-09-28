# The Modern Linux Multiseat Guide (Systemd + Wayland)

A complete guide to configuring a high-performance, dual-station, hardware-isolated Linux workstation using **systemd-logind**, **DRM / KMS**, and **Wayland**.

---

## 1. Introduction: The Evolution of Linux Multiseat

In the legacy Xorg era (circa 2019 and earlier), configuring multiseat was notoriously difficult:
* Required crafting complex, brittle `xorg.conf` files with manual PCI `BusID` specifications.
* Needed `Option "AutoAddDevices" "false"` and manually hardcoded `/dev/input/event*` devices.
* Fighting the display manager to manage multiple X servers across virtual terminals often broke VT switching or kernel modesetting.
* GPU driver mismatches frequently crashed the compositor or broke 3D hardware acceleration.

### How Modern Linux Solved It
With **systemd-logind** and the modern **Direct Rendering Manager (DRM)** subsystem:
1. **DRM Card Granularity**: Each graphics card node (`/dev/dri/cardX`) can act as a `[MASTER]` of a seat.
2. **Clean Hardware Isolation**: Wayland compositors (such as KDE's KWin) run directly on their assigned DRM master node with exclusive hardware acceleration.
3. **Cascading USB Rules**: Systemd's seat engine automatically passes seat assignments from parent USB hubs/ports down to child devices via `IMPORT{parent}="ID_SEAT"`.
4. **Zero Xorg Hacks**: No config files, no hardcoded `/dev/input` links, and full hotplugging support out of the box.

---

## 2. Hardware Architecture & Golden Rules

### Rule 1: Use Two Independent Physical GPUs (dGPU + iGPU)
While running two monitors off a single dedicated GPU works well for an extended desktop, **a single DRM card node cannot be cleanly split across two independent systemd seats**. 

Modern desktop processors (such as AMD Ryzen 7000/9000 series with AM5 RDNA2 graphics, or Intel Core with UHD/Iris Xe graphics) feature capable integrated GPUs. 
* **Seat 0 (Primary / Power User)**: Dedicated GPU (e.g. AMD Radeon RX 9060 XT) driving high-refresh 1440p/4K gaming or 3D rendering.
* **Seat 1 (Secondary / Productivity)**: Motherboard integrated GPU driving 1440p desktop, web browsing, coding, and 4K media playback with hardware video decode (AV1/VP9).

### Rule 2: Open-Source Unified Kernel Drivers
When possible, pair an AMD dGPU with an AMD iGPU (or Intel dGPU with Intel iGPU). Both GPUs utilize the exact same in-tree kernel driver (`amdgpu`) and Mesa Gallium/RADV drivers. This completely eliminates kernel module conflicts, EGL/GBM mismatches, or proprietary driver crashes.

### Rule 3: Understand Your Motherboard USB Topology
Modern motherboards feature multiple independent USB controllers:
* **Direct CPU root hubs**: Usually wired to specific high-speed rear ports (often colored Red, 10Gbps).
* **Chipset root hubs**: Wire to auxiliary ports, internal headers, and onboard USB hub chips (often colored Blue, 5Gbps).
* **Onboard Hub Chips (e.g. ASMedia ASM1074)**: Many motherboards group 4 rear ports onto an internal hub chip. Assigning this single hub to `seat1` instantly provisions all 4 physical ports for hotplugging!

---

## 3. Reference Case Study: AM5 Ryzen 7 7700 + RX 9060 XT

This setup documents the live reference configuration running on an **MSI PRO B650-S WIFI**:

```
[ PC Hardware: AMD Ryzen 7 7700 + MSI PRO B650-S WIFI ]
 │
 ├── SEAT 0 (Primary Station — User: psl)
 │    ├── GPU: Sapphire AMD Radeon RX 9060 XT (0000:03:00.0 / drm:card1)
 │    ├── Display: Xiaomi Mi Monitor (2560x1440 @ 144Hz via dGPU HDMI-A-1)
 │    ├── USB Ports: Direct AMD CPU xHCI (Rear RED USB 3.2 Ports)
 │    ├── Peripherals: Rapoo Gaming Keyboard + INSTANT USB Gaming Mouse
 │    └── Audio: Navi 48 HDMI/DP Digital Audio (Monitor 1) + Realtek ALC897 Analog
 │
 └── SEAT 1 (Secondary Station — User: lsp)
      ├── GPU: AMD Raphael RDNA2 iGPU (0000:12:00.0 / drm:card0)
      ├── Display: Xiaomi Mi Monitor (2560x1440 @ 100Hz via Motherboard HDMI-A-3)
      ├── USB Ports: ASMedia ASM1074 USB 3.0 Hub (All 4 Rear BLUE USB Ports)
      ├── Peripherals: HS6209 2.4G Wireless Keyboard & Mouse Combo (Hotpluggable)
      └── Audio: Radeon High Definition HDMI Digital Audio (Monitor 2)
```

---

## 4. Step-by-Step Implementation

### Step 1: Cable Routing
1. Keep **Monitor 1** plugged into the dedicated GPU.
2. Plug **Monitor 2** directly into the **Motherboard HDMI or DisplayPort**.
3. Plug User 1's peripherals into the designated **RED USB ports**.
4. Plug User 2's peripherals (or USB hub) into the designated **BLUE USB ports**.

### Step 2: Identify Device Hardware Paths
Query `loginctl` and `udevadm`:
```bash
# Find DRM cards
ls -l /sys/class/drm/card*

# Find the USB hub / port path for Seat 1
udevadm info /sys/bus/usb/devices/1-5 | grep ID_PATH
```

### Step 3: Attach Hardware to `seat1`
Run `loginctl attach`:
```bash
# 1. Attach the iGPU as the display master for seat1
sudo loginctl attach seat1 /sys/devices/pci0000:00/0000:00:08.1/0000:12:00.0/drm/card0

# 2. Attach the ASMedia 4-port USB hub to seat1
sudo loginctl attach seat1 /sys/devices/pci0000:00/0000:00:02.1/0000:05:00.0/0000:06:0c.0/0000:10:00.0/usb1/1-5
```

This generates persistent udev rules in `/etc/udev/rules.d/`:
* `72-seat-drm-pci-0000_12_00_0.rules`:
  ```udev
  TAG=="seat", ENV{ID_FOR_SEAT}=="drm-pci-0000_12_00_0", ENV{ID_SEAT}="seat1"
  ```
* `72-seat-usb-pci-0000_10_00_0-usb-0_5.rules`:
  ```udev
  TAG=="seat", ENV{ID_FOR_SEAT}=="usb-pci-0000_10_00_0-usb-0_5", ENV{ID_SEAT}="seat1"
  ```

Apply the new rules immediately:
```bash
sudo udevadm trigger
```

### Step 4: Display Manager Integration
Modern display managers like **Plasma Login Manager (`plasma-login-manager`)**, **GDM**, and **SDDM** automatically monitor logind D-Bus signals. The instant `seat1` is created, the display manager spawns a native Wayland login greeter on Monitor 2.

---

## 5. Maintenance & Quick Reset

### Check Seat Status
```bash
# List all active seats
loginctl list-seats

# Inspect devices attached to seat1
loginctl seat-status seat1

# View active user sessions
loginctl list-sessions
```

### Emergency Reset / Revert to Single-Seat
If you ever want to reset back to a standard unified dual-monitor desktop:
```bash
sudo loginctl flush-devices
sudo udevadm trigger
```
This wipes all custom seat rules and immediately merges all displays and USB ports back to `seat0`.
