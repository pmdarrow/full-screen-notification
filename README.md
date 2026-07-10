# Full Screen Notification

A macOS menu bar app that monitors timed events on your primary Google Calendar and displays full-screen notifications before they begin.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## Overview

- **Full-screen alerts** — a frosted overlay with event details and a live countdown
- **Google Calendar integration** — read-only OAuth access via AppAuth with updates fetched every 30 seconds
- **Accurate timing** — schedules each known alert locally for its exact trigger time
- **Configurable timing** — trigger notifications 1, 2, 3, 5, 10, or 15 minutes before events
- **Video call quick-join** — detects links for Google Meet, Zoom, Microsoft Teams, Webex, and other common providers
- **Focused monitoring** — skips all-day and cancelled events
- **Native menu bar UI** — shows the next timed event and runs without a Dock icon

## Install

Run the installer directly from the repository:

```bash
curl -fsSL https://raw.githubusercontent.com/pmdarrow/full-screen-notification/main/scripts/install.sh | bash
```

The installer downloads the latest macOS release zip from
[GitHub Releases](https://github.com/pmdarrow/full-screen-notification/releases),
extracts `Full Screen Notification.app`, and copies it into the system-wide
Applications folder:

```
/Applications/Full Screen Notification.app
```

Because this is a system-wide install, macOS will ask for an administrator
password. The installer launches the app when it finishes; look for the bell in
the menu bar.

The app is ad-hoc signed, but it is not signed with an Apple Developer ID or
notarized as I'm not really interested in paying to be a part of the Apple
Developer Program. The installer removes the downloaded app's quarantine
attribute so it can run on macOS.

## Development

### Prerequisites

- macOS 15 (Sequoia) or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A Google Cloud project with the [Calendar API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com) enabled

### Google OAuth credentials

1. Go to the [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Configure the OAuth consent screen and add your Google account as a test user if the app is in testing mode
3. Create an **OAuth 2.0 Client ID** and choose **Desktop app** as the application type
4. Note your client ID — it looks like `123456789-abcdef.apps.googleusercontent.com`

The app uses AppAuth's authorization-code flow with PKCE and a temporary loopback
callback on `127.0.0.1`. A client secret and custom URL scheme are not required.
It requests the `calendar.readonly` scope, so it can read events but cannot
create, edit, or delete them.

### Building

```bash
# Clone the repo
git clone https://github.com/pmdarrow/full-screen-notification.git
cd full-screen-notification

# Create your local config
cp project.local.example.yml project.local.yml
```

Edit `project.local.yml` with your values:

```yaml
targets:
  FullScreenNotification:
    settings:
      base:
        DEVELOPMENT_TEAM: YOUR_TEAM_ID
        GOOGLE_CLIENT_ID: YOUR_CLIENT_ID.apps.googleusercontent.com
```

Then generate the Xcode project and build:

```bash
xcodegen

# Build from the command line
xcodebuild -project FullScreenNotification.xcodeproj -scheme FullScreenNotification build

# Run
open ~/Library/Developer/Xcode/DerivedData/FullScreenNotification-*/Build/Products/Debug/Full\ Screen\ Notification.app

# Or open in Xcode and hit Cmd+R
open FullScreenNotification.xcodeproj
```

### Creating a GitHub release

The release helper builds a universal Apple Silicon and Intel app, ad-hoc signs
it, packages it as `dist/full-screen-notification-<version>-macos.zip`, and
uploads it to a GitHub release tagged `v<version>`. Before releasing, update
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, then commit
and push that change.

```bash
bash scripts/create-github-release.sh
```

Use `--draft` to create a draft release first:

```bash
bash scripts/create-github-release.sh --draft
```

The script requires a clean working tree and a current branch that is pushed to
GitHub, so the release tag matches the packaged source. To test the universal
build and packaging without publishing a release:

```bash
bash scripts/create-github-release.sh --dry-run
```

## License

MIT
