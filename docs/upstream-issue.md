# Multiseat: Concurrent Wayland greeters collide under singleton plasmalogin systemd --user session

### Summary
In a multiseat environment managed by `systemd-logind` (e.g. `seat0` with a dedicated GPU and `seat1` with an integrated GPU), `plasma-login-manager` attempts to spawn Wayland greeters on each seat concurrently at system startup.

Because `plasma-login-manager` runs greeters inside `systemd --user` under a single shared system user (`plasmalogin`, UID 959), only one seat can successfully initialize `plasma-login-kwin_wayland.service` and `plasma-login-wayland.target`. The secondary seat suffers a compositor collision, its helper stalls in a `ppoll` wait state, and its monitor remains completely blank.

---

### System Environment
* **OS**: Arch Linux
* **KDE Plasma**: 6.7.5
* **KDE Frameworks**: 6.x
* **Display Manager**: `plasma-login-manager` 6.7.5-1 (`plasmalogin.service`)
* **Kernel**: Linux 6.x (`amdgpu` driver)
* **Hardware Architecture**:
  * **Seat 0**: Dedicated GPU (AMD Radeon RX 9060 XT / `drm:card1`), CPU-direct USB ports
  * **Seat 1**: Integrated GPU (AMD Raphael RDNA2 / `drm:card0`), Chipset USB hub

---

### Steps to Reproduce
1. Configure a standard dual-seat setup via `loginctl attach seat1 <drm-device-path>` and assign corresponding USB input devices.
2. Enable `plasmalogin.service`.
3. Reboot the system.
4. Observe the displays at the login screen.

**Expected Result**: Both monitors light up with their respective `plasma-login-greeter` instances, allowing users at either physical seat to log in independently.

**Actual Result**: Only one monitor displays the login screen (whichever GPU won the kernel DRM initialization race). The second monitor remains completely black with no active compositor.

---

### Relevant Journal Logs

At boot, the daemon creates displays on both seats:
```
plasmalogin[13402]: Adding new display... Using VT -1
plasmalogin[13402]: Adding new display... Using VT 1
plasmalogin[13402]: Display server started.
plasmalogin-helper[13412]: Starting Wayland user session: "/usr/share/plasmalogin/scripts/wayland-session" "/usr/bin/startplasma-login-wayland"
plasmalogin-helper[13413]: Starting Wayland user session: "/usr/share/plasmalogin/scripts/wayland-session" "/usr/bin/startplasma-login-wayland"
plasmalogin[13402]: Greeter session started successfully
plasmalogin[13402]: Greeter session started successfully
plasmalogin[13402]: Message received from greeter: Connect
```
*(Notice that only one `Connect` message is received; the second greeter never establishes a connection).*

When a user logs into the winning seat:
```
plasmalogin[13402]: Session started true
plasmalogin[13402]: Greeter stopping...
plasmalogin[13402]: Auth: plasmalogin-helper exited with 255
plasmalogin[13402]: Greeter stopped. PLASMALOGIN::Auth::HelperExitStatus(255)
```
The teardown of the winning seat's greeter shuts down `plasma-login-wayland.target` on `user@959.service`, which terminates or crashes the stalled helper on the second seat, leaving the second monitor blank.

---

### Diagnostic Observations

1. **Singleton `systemd --user` Manager**:
   `plasma-login-manager` runs greeters under a fixed system user (`plasmalogin`, UID 959). Systemd only ever spawns a single user manager instance (`user@959.service`) per UID.

2. **Static Non-Templated Target and Units**:
   The session units (`plasma-login-wayland.target`, `plasma-login-kwin_wayland.service`, `plasma-login.service`) are non-templated. When both seats launch at boot:
   * Both `plasmalogin-helper` processes invoke `startplasma-login-wayland`, which requests `plasma-login-wayland.target`.
   * Systemd user manager cannot start a second concurrent instance of the same target.

3. **Compositor Resource Conflicts**:
   * `plasma-login-kwin_wayland.service` specifies `BusName=org.kde.KWin`. Two KWin instances cannot own this D-Bus name concurrently on the same user session bus.
   * Both KWin instances attempt to bind `$XDG_RUNTIME_DIR/wayland-0` inside `/run/user/959`.

---

### Current External Workaround (For Context)

We currently work around this by running a background supervisor script that serializes greeter activations over D-Bus:
1. One seat claims the initial greeter at boot while the second waits.
2. Once the first user logs in, that seat transitions to their own personal session (`user@<uid>.service`), freeing `user@959.service`.
3. The supervisor detects the active user session, cleans up the stalled session on the waiting seat via `loginctl terminate-session`, and calls:
   `qdbus6 --system org.freedesktop.DisplayManager /org/freedesktop/DisplayManager/SeatX org.freedesktop.DisplayManager.Seat.SwitchToGreeter`
4. The second seat's greeter then initializes cleanly and lights up.
