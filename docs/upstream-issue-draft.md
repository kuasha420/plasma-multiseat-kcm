# Upstream Issue Draft: KDE Plasma Login Manager

**Target Repository**: [invent.kde.org/plasma/plasma-login-manager](https://invent.kde.org/plasma/plasma-login-manager/-/issues)  
**Type**: Bug / Feature Request  
**Title**: Multiseat support: Greeter collision and lockup at boot due to singleton `systemd --user` session (`user@<uid>.service`)

---

## Description

### Summary
In a multiseat environment managed by `systemd-logind` (e.g. `seat0` and `seat1` with dedicated DRM master GPUs and USB controllers), `plasma-login-manager` attempts to spawn Wayland greeters on each seat concurrently at system startup.

Because `plasma-login-manager` runs greeters inside `systemd --user` under a single shared system user (`plasmalogin`, UID 959), only one seat can successfully initialize `plasma-login-kwin_wayland.service` and `plasma-login-wayland.target`. The second seat suffers a compositor socket collision, enters a stalled `ppoll` wait state, and its display remains completely black/blank.

---

### System Environment
* **OS**: Arch Linux
* **KDE Plasma**: 6.7.5
* **KDE Frameworks**: 6.x
* **Display Manager**: `plasma-login-manager` 6.7.5-1 (`plasmalogin.service`)
* **Kernel**: Linux 6.x (`amdgpu` driver)
* **Hardware Architecture**:
  * **Seat 0**: Discrete GPU (AMD Radeon RX 9060 XT / `drm:card1`), CPU-direct USB ports
  * **Seat 1**: Integrated GPU (AMD Raphael RDNA2 / `drm:card0`), Chipset USB hub

---

### Technical Root Cause

1. **Singleton `systemd --user` Manager**:
   `plasma-login-manager` runs greeters under a fixed system user (`plasmalogin`, UID 959). Systemd only ever spawns a single user manager instance (`user@959.service`) per UID.

2. **Static Non-Templated Target and Units**:
   The session targets and services are static:
   * `/usr/lib/systemd/user/plasma-login-wayland.target`
   * `/usr/lib/systemd/user/plasma-login-kwin_wayland.service`
   * `/usr/lib/systemd/user/plasma-login.service`
   
   When both seats start at boot:
   * `plasmalogin-helper` for `seat0` calls `startplasma-login-wayland` $\rightarrow$ requests `plasma-login-wayland.target`.
   * `plasmalogin-helper` for `seat1` calls `startplasma-login-wayland` $\rightarrow$ requests `plasma-login-wayland.target`.
   
   Because unit names are not templated (e.g., `@.service`), systemd treats the second activation request as a no-op or conflates it with the first.

3. **Compositor Resource Conflicts**:
   * `plasma-login-kwin_wayland.service` specifies `BusName=org.kde.KWin`. Two KWin instances cannot own this D-Bus name concurrently on the same user session bus.
   * Both KWin instances attempt to bind `$XDG_RUNTIME_DIR/wayland-0` inside `/run/user/959`.

4. **Teardown Cascade**:
   When a user logs in on the winning seat, their greeter shuts down. The teardown logic stops `plasma-login-wayland.target` on `user@959.service`, which immediately terminates or crashes the losing seat's helper (often with `HelperExitStatus(255)`), leaving the second seat permanently stalled or powered off.

---

### Steps to Reproduce
1. Configure a standard dual-seat setup via `loginctl attach seat1 <drm-device-path>` and assign corresponding USB input devices.
2. Enable `plasmalogin.service`.
3. Reboot the machine.
4. Observe the displays at the login screen.

**Expected Result**: Both monitors light up with their respective `plasma-login-greeter` instances, allowing users at either physical seat to log in independently.

**Actual Result**: Only one monitor displays the login screen (whichever GPU won the kernel DRM initialization race). The second monitor remains completely black with no active compositor.

---

### Production Workaround (Supervisor Daemon)

We resolved this issue in production by implementing a lightweight supervisor daemon that serializes greeter activations across seats via D-Bus:
1. Boot initiates; the winning seat displays its greeter while the losing seat waits.
2. When a user logs in on the winning seat, that seat switches to the user's personal session (`user@<user_uid>.service`), completely freeing `user@959.service`.
3. The supervisor detects the active user session, cleans up the stale session on the waiting seat via `loginctl terminate-session`, and invokes:
   ```bash
   qdbus6 --system org.freedesktop.DisplayManager /org/freedesktop/DisplayManager/SeatX org.freedesktop.DisplayManager.Seat.SwitchToGreeter
   ```
4. The second seat's greeter initializes cleanly and lights up within 1–2 seconds.

While effective, this requires sequential login (one user must log in before the second workstation displays a login prompt).

---

### Suggested Upstream Architectural Solutions

1. **Dynamic Templated Systemd Units**:
   Parameterize greeter targets and services by seat:
   * `plasma-login-wayland@%i.target`
   * `plasma-login-kwin_wayland@%i.service`
   Allowing distinct Wayland sockets (`wayland-%i`) and namespaced or isolated session bus scopes.

2. **Ephemeral / Per-Seat Greeter Users**:
   Instead of a static `plasmalogin` UID 959, run each seat's greeter under a dynamically isolated user (e.g. `plasmalogin-seat0`, `plasmalogin-seat1`, or dynamically allocated systemd users via `DynamicUser=yes`).

3. **In-Daemon Greeter Arbitration**:
   If multi-compositor concurrent greeters cannot be supported immediately, `plasmalogin` daemon should natively detect multiple seats, gracefully queue secondary seats, and automatically trigger `SwitchToGreeter` on remaining seats as soon as one seat authenticates.
