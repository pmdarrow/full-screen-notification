import Foundation

enum DateFormatting {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    static func formatTime(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    static func formatTimeRange(start: Date, end: Date) -> String {
        "\(timeFormatter.string(from: start)) \u{2013} \(timeFormatter.string(from: end))"
    }

    static func formatRelativeTime(from now: Date, to target: Date) -> String {
        let interval = target.timeIntervalSince(now)

        if interval <= 0 {
            let elapsed = abs(interval)
            if elapsed < 60 {
                return "Started just now"
            } else {
                let minutes = Int(elapsed / 60)
                return "Started \(minutes) minute\(minutes == 1 ? "" : "s") ago"
            }
        }

        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            if minutes > 0 {
                return "The event will start in \(hours)h \(minutes)m"
            }
            return "The event will start in \(hours) hour\(hours == 1 ? "" : "s")"
        }

        if minutes > 0 {
            return "The event will start in \(minutes) minute\(minutes == 1 ? "" : "s")"
        }

        return "The event will start in less than a minute"
    }
}
