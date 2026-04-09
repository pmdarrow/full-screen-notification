import SwiftUI

struct GradientBackground: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: [
                Color(red: 0.15, green: 0.05, blue: 0.25),  // dark purple
                Color(red: 0.20, green: 0.10, blue: 0.30),  // purple
                Color(red: 0.25, green: 0.15, blue: 0.35),  // light purple

                Color(red: 0.12, green: 0.10, blue: 0.20),  // dark mid
                Color(red: 0.20, green: 0.18, blue: 0.25),  // mid
                Color(red: 0.15, green: 0.20, blue: 0.25),  // teal-ish

                Color(red: 0.15, green: 0.20, blue: 0.10),  // dark green
                Color(red: 0.25, green: 0.30, blue: 0.12),  // olive green
                Color(red: 0.20, green: 0.25, blue: 0.10),  // green
            ]
        )
        .drawingGroup()
        .ignoresSafeArea()
    }
}
