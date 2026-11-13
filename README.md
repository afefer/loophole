# Pi-hole Switcher

A macOS menu bar app that turns Pi-hole blocking on and off — indefinitely or for a set interval (30 seconds, 5 minutes, 15 minutes, 1 hour, or any number of minutes).

It also shows Pi-hole's status (query rate, load, memory) and the last 24 hours' query totals, links to the admin page, shows the time left on a pause in the menu bar, and supports global keyboard shortcuts (set them in Settings).

Requires macOS 15+ and Pi-hole v6+ (it uses the v6 REST API).

## Install

```sh
./scripts/build-app.sh --install   # builds, copies to /Applications, launches
```

Without `--install` the app is left in `dist/`.

Click the shield in the menu bar, choose **Settings…**, and enter your Pi-hole's address (e.g. `http://pi.hole` or `https://192.168.1.2`) and password. An app password (Pi-hole → Settings → Web interface / API) is recommended, and required if you use two-factor login. The password is stored in your login keychain.

## Development

```sh
swift build
swift test
swift scripts/make-icon.swift      # regenerate Support/AppIcon.icns from Support/pi-hole.svg
```

The Pi-hole logo is a trademark of Pi-hole LLC; the icon file comes from [Dashboard Icons](https://dashboardicons.com/icons/pi-hole).
