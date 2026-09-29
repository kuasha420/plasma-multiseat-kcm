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

### Step 4: Display Manager Integration (Plasma Login Manager)
In KDE Plasma 6, **Plasma Login Manager (`plasma-login-manager`)** launches greeter sessions managed under `systemd --user` for the system user `plasmalogin` (UID 959). 

#### The Boot Race Condition
Because `systemd --user` runs a single user manager per UID, running multiple concurrent greeters under the same UID creates a compositor socket and D-Bus name collision at early boot (`BusName=org.kde.KWin`, `$XDG_RUNTIME_DIR/wayland-0`). 

At boot time, discrete GPUs (dGPU) and integrated GPUs (iGPU) initialize in parallel. Whichever GPU initializes first wins the race and claims `plasma-login-kwin_wayland.service`; the losing seat's greeter helper enters a stalled `ppoll` wait state, leaving its monitor blank.

#### The Solution: Bidirectional Multiseat Supervisor
To resolve this without requiring SDDM, we provide the **Multiseat Supervisor Daemon** ([`scripts/multiseat-supervisor.sh`](../scripts/multiseat-supervisor.sh)):
1. Symmetrically monitors `systemd-logind` session states in both directions (`seat0 -> seat1` and `seat1 -> seat0`).
2. Whichever seat logs in first (or autologs in) transitions to that user's personal session (`user@<uid>.service`), completely freeing `user@959.service`.
3. Within 2 seconds, the supervisor detects the active user session on the winning seat, terminates the stalled session on the waiting seat, and triggers `org.freedesktop.DisplayManager.Seat.SwitchToGreeter` over system D-Bus.
4. The waiting seat immediately lights up with its login screen, allowing the second user to authenticate.

#### Installation
Run the included installer script:
```bash
./scripts/install-supervisor.sh
```
This installs `/usr/local/bin/multiseat-supervisor` and enables `/etc/systemd/system/multiseat-supervisor.service`.

For full details on the upstream architecture and proposed fixes, see [Upstream Issue Draft](upstream-issue.md).

---

## 5. Maintenance & Quick Reset

### Check Seat & Supervisor Status
```bash
# List all active seats
loginctl list-seats

# Inspect devices attached to seat1
loginctl seat-status seat1

# View active user sessions
loginctl list-sessions

# Check supervisor daemon status and logs
systemctl status multiseat-supervisor.service
journalctl -u multiseat-supervisor.service -t multiseat-supervisor -f
```

### Emergency Reset / Revert to Single-Seat
If you ever want to reset back to a standard unified dual-monitor desktop:
```bash
sudo loginctl flush-devices
sudo udevadm trigger
```
This wipes all custom seat rules and immediately merges all displays and USB ports back to `seat0`.

---

## 6. Workstation Recovery & Reseeding (`multiseat-ctl`)

When operating a multi-user, multi-GPU workstation, occasional hardware or compositor issues can occur on one seat (e.g. sudden USB peripheral dropout, monitor blackout / DPMS sleep, or frozen compositor). 

The included utility **`multiseat-ctl`** (also accessible directly from the KDE System Settings module on both seats) enables a user at the healthy workstation to diagnose and repair the troubled workstation without rebooting the system or affecting the healthy seat.

### Three-Tier Escalation Architecture

| Level | Flag | Impact on User Apps | Target Problem & Mechanism |
|---|---|---|---|
| **Tier 1: Graceful** | `--level graceful` | **Zero** (Apps keep running) | **USB dropout, display blackout, or DPMS stall.** Re-probes DRM connectors to force AMDGPU monitor wakeup, triggers udev subsystem events (`input`, `hid`, `drm`), and automatically re-binds missing USB devices without terminating the user session. |
| **Tier 2: Session** | `--level session` | **Kills apps on target seat only** | **Frozen desktop session or stalled greeter.** Terminates stuck sessions specifically on the target seat (`loginctl terminate-session`), refreshes hardware udev maps, and signals `SwitchToGreeter` over D-Bus to respawn a clean login screen. |
| **Tier 3: Hard Reseed** | `--level hard` | **Full hardware reset of target seat** | **Dead USB hub chip, kernel controller lockup, or hard lockout.** Terminates all sessions on the target seat, physically power-cycles the assigned USB controller/hub (via `xhci_hcd` driver `unbind` $\rightarrow$ `bind`), resets the DRM card node, re-seeds udev rules, and respawns the greeter. |

### CLI Usage

```bash
# Check full system status, assigned DRM cards, and USB topology
multiseat-ctl status

# Non-destructive soft refresh on seat1 (wakes display & recovers dropped USB)
multiseat-ctl recover seat1

# Restart stuck session or login screen on seat1
multiseat-ctl recover seat1 --level session

# Full hardware power-cycle and reseed of seat1 (alias: multiseat-ctl reseed seat1)
multiseat-ctl recover seat1 --level hard

# Recover seat0 from seat1
multiseat-ctl recover seat0 --level graceful

# Dry run simulation
multiseat-ctl recover seat1 --level hard --dry-run
```

### Graphical Integration (System Settings)

Each seat card in **KDE System Settings $\rightarrow$ Multiseat** includes dedicated one-click repair buttons (**Soft Refresh**, **Restart Session**, **Hard Reseed**) with real-time feedback and execution indicators. Users on either seat can repair the other seat instantly.


