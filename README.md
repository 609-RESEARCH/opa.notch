<p align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="opa.notch app icon">
</p>

<h1 align="center">opa.notch</h1>

<p align="center">Your day and your reminders, living in the MacBook notch.</p>

<p align="center">
  <a href="../../releases/latest/download/opa.notch.dmg"><b>Download for macOS</b></a>
</p>

<p align="center">
  <img src="assets/screenshot-open.png" alt="The open notch: the meeting in progress with a progress bar and Join button, later events, and four reminders due today with one overdue">
</p>

- **Closed:** a countdown to your current or next meeting, and how many reminders are due today.
- **Open** (hover or <kbd>⌃⌥N</kbd>): today's meetings with one-click **Join**, and your reminders to check off, reschedule or prioritise.
- **Quick add** (<kbd>⌃⌥R</kbd>): type `Send invoice friday 10am` and it lands in Apple Reminders, due Friday at 10:00.

<p align="center">
  <img src="assets/screenshot-closed.png" alt="The closed notch: a meeting countdown around the camera and the reminders count in a detached pill beside it">
</p>

Everything syncs through Apple Calendar and Reminders. opa.notch stores no data of its own.

## Install

1. Download [opa.notch.dmg](../../releases/latest/download/opa.notch.dmg) and drag the app into Applications (macOS 14+).
2. On first launch, approve it in **System Settings → Privacy & Security → Open Anyway**. It isn't notarized yet.
3. Hover over the notch and click **Allow Access** for Calendar and Reminders.

## Build

Open `OpaNotch.xcodeproj` in Xcode 26 and run the **OpaNotch** scheme. To package a release, run `scripts/build-release.sh`. It writes `dist/opa.notch.dmg` to attach to a GitHub release.

## License

GPL-3.0. See `LICENSE` and `THIRD_PARTY_LICENSES`.

---

<p align="center">
  DESIGNED, CRAFTED<br>AND ENGINEERED BY
</p>
<p align="center">
  <a href="https://609-research.github.io">
    <img src="assets/609-research-logo.png" width="180" alt="609 Research">
  </a>
</p>
