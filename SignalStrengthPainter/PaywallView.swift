import SwiftUI

struct PaywallView: View {
    @Binding var isPresented: Bool
    var onPurchase: (() -> Void)?
    @Environment(\.theme) private var theme
    @State private var selectedPlan: Plan = .monthly
    @State private var currentPage = 0

    private let pageCount = 3

    enum Plan {
        case monthly, lifetime
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            theme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroPreview
                        .frame(height: 280)
                        .clipped()

                    VStack(spacing: 22) {
                        titleSection
                        featureIcon
                        tagline
                        pageDots
                        pricingCards
                        buyButton
                        bottomLinks
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
            }

            closeButton
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
    }

    // MARK: - Hero preview

    private var heroPreview: some View {
        Canvas { context, size in
            drawMiniFloorPlan(context: context, size: size)
            drawHeatBlobs(context: context, size: size)
            drawSignalNodes(context: context, size: size)
            drawConnectionLines(context: context, size: size)
        }
        .overlay(
            LinearGradient(
                colors: [.clear, .clear, theme.background.opacity(0.85), theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func drawMiniFloorPlan(context: GraphicsContext, size: CGSize) {
        let bg = Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
        }
        context.fill(bg, with: .color(Color(red: 0.06, green: 0.06, blue: 0.08)))

        var ctx = context
        ctx.opacity = 0.18
        let gridSpacing: CGFloat = 28
        let cols = Int(size.width / gridSpacing) + 1
        let rows = Int(size.height / gridSpacing) + 1
        for col in 0...cols {
            let x = CGFloat(col) * gridSpacing
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(.gray), lineWidth: 0.5)
        }
        for row in 0...rows {
            let y = CGFloat(row) * gridSpacing
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(.gray), lineWidth: 0.5)
        }

        var walls = context
        walls.opacity = 0.35
        let wallColor = Color(red: 0.9, green: 0.85, blue: 0.6)
        let rooms: [(CGRect, String)] = [
            (CGRect(x: 20, y: 30, width: 140, height: 110), "KITCHEN"),
            (CGRect(x: 180, y: 30, width: 160, height: 110), "LIVING"),
            (CGRect(x: 20, y: 155, width: 160, height: 100), "BEDROOM"),
            (CGRect(x: 200, y: 155, width: 140, height: 100), "OFFICE"),
        ]
        for (rect, label) in rooms {
            let roomPath = Path(rect)
            walls.stroke(roomPath, with: .color(wallColor), lineWidth: 1.5)

            let labelPoint = CGPoint(x: rect.midX - 20, y: rect.minY + 14)
            walls.draw(
                Text(label).font(.system(size: 8, weight: .medium)).foregroundColor(wallColor),
                at: labelPoint,
                anchor: .topLeading
            )
        }
    }

    private func drawHeatBlobs(context: GraphicsContext, size: CGSize) {
        let blobs: [(CGPoint, CGFloat, Color)] = [
            (CGPoint(x: 90, y: 85), 80, Color(red: 0.2, green: 0.85, blue: 0.4)),
            (CGPoint(x: 260, y: 85), 70, Color(red: 0.3, green: 0.75, blue: 0.95)),
            (CGPoint(x: 100, y: 200), 65, Color(red: 0.95, green: 0.75, blue: 0.2)),
            (CGPoint(x: 270, y: 200), 60, Color(red: 0.95, green: 0.35, blue: 0.3)),
            (CGPoint(x: 180, y: 140), 50, Color(red: 0.5, green: 0.9, blue: 0.5)),
        ]
        for (center, radius, color) in blobs {
            let blobRect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let gradient = Gradient(colors: [color.opacity(0.55), color.opacity(0.12), .clear])
            context.fill(
                Path(ellipseIn: blobRect),
                with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
            )
        }
    }

    private func drawSignalNodes(context: GraphicsContext, size: CGSize) {
        let nodes: [CGPoint] = [
            CGPoint(x: 90, y: 85),
            CGPoint(x: 260, y: 85),
            CGPoint(x: 100, y: 200),
            CGPoint(x: 270, y: 200),
            CGPoint(x: 180, y: 140),
            CGPoint(x: 50, y: 145),
            CGPoint(x: 320, y: 140),
        ]
        for node in nodes {
            let outerR: CGFloat = 8
            let innerR: CGFloat = 4
            context.fill(
                Path(ellipseIn: CGRect(x: node.x - outerR, y: node.y - outerR, width: outerR * 2, height: outerR * 2)),
                with: .color(Color.blue.opacity(0.4))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: node.x - innerR, y: node.y - innerR, width: innerR * 2, height: innerR * 2)),
                with: .color(Color.blue)
            )
        }
    }

    private func drawConnectionLines(context: GraphicsContext, size: CGSize) {
        let connections: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 90, y: 85), CGPoint(x: 180, y: 140)),
            (CGPoint(x: 260, y: 85), CGPoint(x: 180, y: 140)),
            (CGPoint(x: 100, y: 200), CGPoint(x: 180, y: 140)),
            (CGPoint(x: 270, y: 200), CGPoint(x: 180, y: 140)),
            (CGPoint(x: 50, y: 145), CGPoint(x: 100, y: 200)),
            (CGPoint(x: 320, y: 140), CGPoint(x: 270, y: 200)),
            (CGPoint(x: 90, y: 85), CGPoint(x: 50, y: 145)),
            (CGPoint(x: 260, y: 85), CGPoint(x: 320, y: 140)),
        ]
        var ctx = context
        ctx.opacity = 0.35
        for (a, b) in connections {
            var line = Path()
            line.move(to: a)
            line.addLine(to: b)
            ctx.stroke(line, with: .color(.blue), lineWidth: 1.2)
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        HStack(spacing: 0) {
            Text("Unlock Wi-Fi Buddy ")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Text("Pro")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.blue)
        }
    }

    // MARK: - Feature icon

    private var featureIcon: some View {
        AppLogoView(size: 100)
            .padding(.vertical, 4)
    }

    // MARK: - Tagline

    private var tagline: some View {
        Text("Visualize your Wi-Fi coverage &\noptimize your network setup")
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(theme.secondaryText)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
    }

    // MARK: - Page dots

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                if index == currentPage {
                    Capsule()
                        .fill(.blue)
                        .frame(width: 20, height: 8)
                } else {
                    Circle()
                        .fill(theme.tertiaryText)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }

    // MARK: - Pricing cards

    private var pricingCards: some View {
        VStack(spacing: 12) {
            pricingOption(
                plan: .monthly,
                title: "Monthly",
                subtitle: "Billed every month",
                price: "$1.99",
                badge: nil,
                crossedOutPrice: nil
            )

            pricingOption(
                plan: .lifetime,
                title: "Lifetime",
                subtitle: "Pay once, use forever",
                price: "$9.99",
                badge: "Best Deal",
                crossedOutPrice: "$19.99"
            )
        }
        .padding(.top, 8)
    }

    private func pricingOption(
        plan: Plan,
        title: String,
        subtitle: String,
        price: String,
        badge: String?,
        crossedOutPrice: String?
    ) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = plan
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : theme.tertiaryText, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 14, height: 14)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.primaryText)

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.tertiaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 6) {
                        if let crossedOutPrice {
                            Text(crossedOutPrice)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(theme.tertiaryText)
                                .strikethrough(true, color: theme.tertiaryText)
                        }

                        Text(price)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? theme.subtle : theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.blue : theme.cardStroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Buy button

    private var buyButton: some View {
        Button {
            onPurchase?()
            isPresented = false
        } label: {
            Text("Buy Now")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.buttonText)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.top, 8)
    }

    // MARK: - Bottom links

    private var bottomLinks: some View {
        HStack(spacing: 32) {
            Button("Restore purchase") {
                // StoreKit restore will go here
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.blue)

            Button("Not now") {
                isPresented = false
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.tertiaryText)
        }
        .padding(.top, 4)
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 30, height: 30)
                .background(theme.subtle)
                .clipShape(Circle())
        }
    }
}

#Preview {
    PaywallView(isPresented: .constant(true))
        .withAppTheme()
}
