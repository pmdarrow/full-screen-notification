# FullScreenNotification

A macOS menu bar app that monitors your Google Calendar and displays full-screen notifications for upcoming events.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## Features

- **Full-screen alerts** — immersive overlay notification with event details and a countdown timer
- **Google Calendar integration** — connects via OAuth 2.0, polls for events every 30 seconds
- **Configurable timing** — trigger notifications 1–15 minutes before events
- **Video call quick-join** — detects Google Meet links and opens them in one click
- **Menu bar UI** — lightweight, runs without a dock icon

## Setup

### Prerequisites

- macOS 15 (Sequoia) or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- A Google Cloud project with the [Calendar API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com) enabled

### Google OAuth credentials

1. Go to the [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Create an **OAuth 2.0 Client ID** (choose iOS/macOS as the application type)
3. Note your client ID — it looks like `123456789-abcdef.apps.googleusercontent.com`

### Build

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/full-screen-notification.git
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
        GOOGLE_REDIRECT_SCHEME: com.googleusercontent.apps.YOUR_CLIENT_ID
```

Then generate the Xcode project and build:

```bash
xcodegen

# Build from the command line
xcodebuild -project FullScreenNotification.xcodeproj -scheme FullScreenNotification build

# Run
open ~/Library/Developer/Xcode/DerivedData/FullScreenNotification-*/Build/Products/Debug/FullScreenNotification.app

# Or open in Xcode and hit Cmd+R
open FullScreenNotification.xcodeproj
```

## License

MIT
