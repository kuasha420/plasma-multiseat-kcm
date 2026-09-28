# Plasma Multiseat Manager (`kcm_multiseat`)

A native **KDE Plasma 6 System Settings** module for monitoring, inspecting, and managing hardware-isolated Linux multiseat workstations.

Built with **C++20**, **KDE Frameworks 6 (KF6)**, **Qt6**, and **Kirigami**.

---

## Features

* **Native System Settings Integration**: Appears directly in `systemsettings` under the **Hardware** category.
* **Real-Time Seat Monitoring**: Tracks all active systemd seats (`seat0`, `seat1`, etc.) and their current login states.
* **GPU & Display Allocation**: Shows assigned graphics cards (dGPU vs. iGPU), driver status (`amdgpu`), DRM card nodes, and connected monitor resolutions & refresh rates.
* **USB Topology & Input Mapping**: Displays physical port allocations (e.g. CPU-direct ports vs. Chipset USB Hubs) and attached HID peripherals (keyboards, mice, wireless combo receivers).
* **Audio Routing Overview**: Displays digital HDMI/DP and analog audio sinks mapped to each workstation.
* **Udev Rule Inspector**: Live view of persistent hardware assignment rules in `/etc/udev/rules.d/72-seat-*.rules`.
* **Plasma Login Manager Supervisor**: Included bidirectional background supervisor daemon (`scripts/multiseat-supervisor.sh`) that automates multi-seat login greeter sequencing on KDE Plasma 6 Wayland without requiring SDDM.

---

## Reference Setup Case Study

This module and documentation were created and tested on a production dual-station workstation:

* **CPU**: AMD Ryzen 7 7700 (8-Core / 16-Thread)
* **Motherboard**: MSI PRO B650-S WIFI
* **Seat 0 (Primary / Power User)**:
  * GPU: Sapphire AMD Radeon RX 9060 XT (dGPU / `drm:card1`)
  * Display: Xiaomi Mi Monitor (2560×1440 @ 144Hz via dGPU HDMI)
  * USB: AMD CPU-Direct USB 3.2 Ports (Red ports) -> Rapoo Gaming Keyboard + Instant Gaming Mouse
  * User: `psl` (Wayland session)
* **Seat 1 (Secondary / Productivity Station)**:
  * GPU: AMD Raphael RDNA2 iGPU (Ryzen 7 7700 / `drm:card0`)
  * Display: Xiaomi Mi Monitor (2560×1440 @ 100Hz via Motherboard HDMI)
  * USB: ASMedia ASM1074 USB 3.0 Hub (All 4 Rear Blue Ports) -> HS6209 2.4G Wireless Receiver (Hotpluggable)
  * User: `lsp` (Wayland session)

For full architectural details, see the [Modern Linux Multiseat Guide](docs/multiseat-guide.md).

---

## Installation & Build

### Requirements
* KDE Plasma 6.0+
* KDE Frameworks 6 (`kcmutils`, `kcoreaddons`, `ki18n`, `kirigami`)
* Qt 6.6+ (`Core`, `Gui`, `Quick`, `DBus`)
* CMake 3.20+ and Extra CMake Modules (`extra-cmake-modules`)

### Building from Source

```bash
# Clone the repository
git clone https://github.com/<your-username>/plasma-multiseat-kcm.git
cd plasma-multiseat-kcm

# Configure build
cmake -B build -S . -DCMAKE_INSTALL_PREFIX=/usr

# Compile
cmake --build build

# Install (requires root)
sudo cmake --install build

# Update KDE configuration cache
kbuildsycoca6
```

### Testing Standalone
You can launch the module directly without opening full System Settings:
```bash
kcmshell6 kcm_multiseat
```

---

## Plasma Login Manager Supervisor

When running KDE Plasma 6's native `plasma-login-manager` on Wayland, concurrent multi-seat greeters collide at early boot due to a single-UID `systemd --user` constraint.

We provide a lightweight, zero-dependency supervisor daemon that automatically serializes greeter activations over D-Bus as seats log in.

To install and activate the supervisor:
```bash
./scripts/install-supervisor.sh
```

To view its live operation:
```bash
journalctl -u multiseat-supervisor.service -f
```

For the full architectural analysis and our draft upstream bug report for KDE developers, see [`docs/upstream-issue-draft.md`](docs/upstream-issue-draft.md).

---

## License

GPL-2.0-or-later. See [LICENSE](LICENSE) for details.
