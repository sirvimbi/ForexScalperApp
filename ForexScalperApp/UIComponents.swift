import SwiftUI

// MARK: - Design System
extension Color {
    static let bgPrimary    = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let bgSecondary  = Color(red: 0.08, green: 0.10, blue: 0.14)
    static let bgCard       = Color(red: 0.10, green: 0.13, blue: 0.18)
    static let bgCardHover  = Color(red: 0.13, green: 0.16, blue: 0.22)
    static let accentCyan   = Color(red: 0.00, green: 0.85, blue: 0.95)
    static let accentGold   = Color(red: 1.00, green: 0.78, blue: 0.20)
    static let accentGreen  = Color(red: 0.18, green: 0.95, blue: 0.58)
    static let accentRed    = Color(red: 1.00, green: 0.28, blue: 0.38)
    static let accentPurple = Color(red: 0.60, green: 0.35, blue: 1.00)
    static let borderSubtle = Color.white.opacity(0.07)
    static let borderActive = Color(red: 0.00, green: 0.85, blue: 0.95).opacity(0.4)
    
    static let textPrimary  = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textMuted    = Color.white.opacity(0.30)
}

// MARK: - View Modifiers
struct TableHeaderModifier: ViewModifier {
    let width: CGFloat
    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.textMuted)
            .frame(width: width, alignment: .leading)
    }
}

extension View {
    func tableHeader(width: CGFloat) -> some View {
        modifier(TableHeaderModifier(width: width))
    }
}

// MARK: - Reusable Components
struct GlowText: View {
    let text: String
    let color: Color
    let font: Font
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .shadow(color: color.opacity(0.8), radius: 6, x: 0, y: 0)
            .shadow(color: color.opacity(0.4), radius: 14, x: 0, y: 0)
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    var borderColor: Color = Color.borderSubtle
    
    init(borderColor: Color = Color.borderSubtle, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.borderColor = borderColor
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
    }
}

struct PulsingDot: View {
    @State private var pulse = false
    var color: Color = .accentGreen
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 14, height: 14)
                .scaleEffect(pulse ? 1.6 : 1.0)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear { pulse = true }
    }
}

struct TagBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(4)
    }
}

struct BarIndicator: View {
    let value: Double
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.6), color],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
                    .shadow(color: color.opacity(0.6), radius: 4)
            }
        }
        .frame(height: 4)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    var accentColor: Color = .accentCyan
    var icon: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.7))
                }
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textMuted)
                    .tracking(1.2)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .shadow(color: accentColor.opacity(0.5), radius: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 100)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
