import SwiftUI

// MARK: - Knowledge Base Model

struct AssistantQA: Identifiable {
    let id = UUID()
    let question: String
    let keywords: [String]
    let answer: String
    let category: String
}

// MARK: - Message Model

struct AssistantMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let relatedQuestions: [String]

    static func == (lhs: AssistantMessage, rhs: AssistantMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Canned Knowledge Base

enum WiFiAssistantKnowledge {
    static let entries: [AssistantQA] = [
        AssistantQA(
            question: "How can I make my Wi-Fi signal better?",
            keywords: ["improve", "better", "stronger", "boost", "weak", "signal", "wifi", "wireless", "slow", "speed"],
            answer: """
Here are the biggest wins for a stronger Wi-Fi signal:

• Move closer to the router — walls, floors, and metal appliances cut signal fast.
• Put the router in a central, open spot (not a closet, not behind the TV).
• Keep it off the floor — waist height or higher works best.
• Switch to the 5 GHz band for nearby devices (faster, less crowded).
• Reboot the router every few weeks to clear up flaky state.

Tap the Survey tab to walk your space and see exactly where the dead zones are.
""",
            category: "Coverage"
        ),
        AssistantQA(
            question: "Why is my gaming slow at certain times of day?",
            keywords: ["gaming", "game", "lag", "laggy", "slow", "peak", "evening", "night", "hours", "times", "day", "congestion"],
            answer: """
Evenings (roughly 7–11 PM) are peak internet hours — everyone in your neighborhood is streaming, gaming, and video-calling at once, so your ISP's shared lines get congested.

A few things that help:

• Use a wired Ethernet cable for your console or PC — cuts ping dramatically.
• If you must use Wi-Fi, connect on 5 GHz, not 2.4 GHz.
• Close background uploads (cloud backups, video calls) during matches.
• Check the Devices tab — a streaming device hogging bandwidth can ruin your ping.
• If it's consistently bad at peak hours, your ISP's plan may be oversubscribed in your area.
""",
            category: "Gaming"
        ),
        AssistantQA(
            question: "Why does my Wi-Fi keep disconnecting?",
            keywords: ["disconnect", "disconnects", "disconnecting", "dropping", "drops", "drop", "keeps", "losing", "connection", "cutting", "unstable"],
            answer: """
Random disconnects usually come down to one of these:

• Overheating router — if it's hot to the touch, give it airflow or replace it.
• Outdated firmware — log into your router's admin page and update it.
• Channel interference from neighbors — try changing the Wi-Fi channel (1, 6, or 11 on 2.4 GHz).
• Too many devices — older routers choke above ~20 active clients.
• A failing router — most consumer routers last 3–5 years.

Start with a simple power-cycle: unplug the router for 60 seconds, then plug it back in.
""",
            category: "Reliability"
        ),
        AssistantQA(
            question: "Where should I place my router?",
            keywords: ["place", "placement", "position", "where", "put", "location", "router", "central", "centrally"],
            answer: """
Router placement rules of thumb:

• Central to the area you use most — Wi-Fi radiates in all directions.
• Elevated — on a shelf, not on the floor.
• Out in the open — not inside a cabinet or behind the TV.
• Away from microwaves, cordless phones, and baby monitors (they share the 2.4 GHz band).
• Away from big metal objects and thick masonry walls.

Run the Survey in the Survey tab after moving the router to confirm coverage improved.
""",
            category: "Coverage"
        ),
        AssistantQA(
            question: "Should I use 2.4 GHz or 5 GHz?",
            keywords: ["2.4", "5", "ghz", "band", "frequency", "dual", "which"],
            answer: """
Quick answer:

• 5 GHz — faster, less crowded, shorter range. Best for devices within ~25 ft of the router, and for anything that needs speed (streaming, gaming, video calls).
• 2.4 GHz — slower, more range, better at getting through walls. Best for far-away devices and simple smart-home gadgets.

Most modern routers advertise both bands under the same network name and let devices auto-pick. If you have the option, let the router handle it ("band steering") rather than manually splitting them.
""",
            category: "Setup"
        ),
        AssistantQA(
            question: "Why is my streaming buffering?",
            keywords: ["stream", "streaming", "buffer", "buffering", "netflix", "youtube", "video", "4k", "hd", "pausing"],
            answer: """
Buffering almost always means not enough bandwidth is reaching the streaming device. Check:

• How many devices are using the network? Every active stream/download competes.
• Is the streaming device on 5 GHz and close to the router?
• Run a speed test in the Speed tab — 4K needs ~25 Mbps, HD needs ~5 Mbps.
• Restart the streaming device and the router.
• For a TV that stays in one spot, plug in Ethernet if you can — no more buffering.
""",
            category: "Streaming"
        ),
        AssistantQA(
            question: "Is my network secure?",
            keywords: ["secure", "security", "safe", "hacked", "hacker", "intruder", "strangers", "password", "protect"],
            answer: """
Good home Wi-Fi security comes down to a few basics:

• Use WPA3 (or WPA2 if that's all your router supports) — never "Open" or WEP.
• Set a strong, unique Wi-Fi password (12+ characters, not "password123").
• Change the router admin login from the default (admin/admin).
• Keep router firmware updated.
• Turn off WPS — it's a well-known weak spot.

Head over to the Devices tab to see every device on your network. Any you don't recognize? Investigate or change your Wi-Fi password and reconnect your own devices.
""",
            category: "Security"
        ),
        AssistantQA(
            question: "What's a good ping for gaming?",
            keywords: ["ping", "latency", "good", "ms", "milliseconds", "fps", "shooter", "competitive"],
            answer: """
Rough ping guidelines for online gaming:

• Under 30 ms — excellent. Competitive shooters feel responsive.
• 30–60 ms — great. You won't notice it for most games.
• 60–100 ms — playable but you'll feel it in fast-paced games.
• 100–150 ms — noticeable lag, especially in competitive matches.
• Over 150 ms — rough. Expect frustration.

The Signal tab shows your current latency. If it's always high on Wi-Fi, a wired connection usually cuts ping by 10–30 ms.
""",
            category: "Gaming"
        ),
        AssistantQA(
            question: "Why is my upload so slow?",
            keywords: ["upload", "uploading", "slow", "asymmetric", "zoom", "call", "video", "twitch"],
            answer: """
Slow uploads are usually a plan issue, not a Wi-Fi issue. Most home internet plans (especially cable) are "asymmetric" — lots of download speed, much less upload.

Things to try:

• Run the Speed tab's speed test — compare upload to what your ISP promised.
• Close background cloud backups (iCloud, Google Drive, OneDrive) during important calls.
• If you stream or upload a lot, ask your ISP about fiber plans — they usually offer symmetric speeds.
• On Wi-Fi, stay on 5 GHz and close to the router — weak signal kills upload first.
""",
            category: "Speed"
        ),
        AssistantQA(
            question: "Do I need a Wi-Fi extender or a mesh system?",
            keywords: ["extender", "repeater", "mesh", "booster", "range", "coverage", "deadzone", "dead", "zone", "zones", "big", "house"],
            answer: """
Extenders vs mesh — quick breakdown:

• Wi-Fi extender — cheap, plugs into an outlet, rebroadcasts your signal. Often halves the speed of anything connected through it, and you end up with a second network name to switch between. Fine for one far-away corner.
• Mesh system — multiple nodes that act as one seamless network. Your devices roam automatically. More expensive but dramatically better for full-house coverage.

If you have more than one or two dead zones, skip the extender and go mesh. The Survey tab can help you confirm where coverage actually drops off.
""",
            category: "Coverage"
        ),
        AssistantQA(
            question: "What's a guest network and should I use one?",
            keywords: ["guest", "visitor", "friends", "separate", "iot", "smart", "home", "isolation"],
            answer: """
A guest network is a second Wi-Fi name your router broadcasts that's isolated from your main network. Devices on the guest network can reach the internet but can't talk to your phones, laptops, printers, or smart home gear.

You should use one if:

• Friends or family visit and want Wi-Fi — keeps their (possibly infected) devices away from yours.
• You have lots of cheap smart-home gadgets — put them on the guest network so a compromised bulb can't pivot to your laptop.
• You run a small business from home — keep customers off your work devices.

Almost every router from the last 10 years supports it in the admin page.
""",
            category: "Security"
        ),
        AssistantQA(
            question: "How often should I restart my router?",
            keywords: ["restart", "reboot", "reset", "power", "cycle", "often", "how", "frequency"],
            answer: """
Rebooting the router clears out memory leaks, stuck DHCP leases, and overheating. A good rhythm:

• Every 1–2 weeks as preventive maintenance.
• Any time speeds suddenly drop or devices start disconnecting.
• After firmware updates.

How to do it right: unplug the router (and modem if separate) for a full 60 seconds, then plug them back in and wait 2–3 minutes for everything to come up.

Don't confuse this with a factory reset — you only want the power cycle. A factory reset wipes all your settings.
""",
            category: "Reliability"
        )
    ]
}

// MARK: - Matching Engine

enum WiFiAssistantEngine {
    private static let maxInputLength = 300

    private static let stopwords: Set<String> = [
        "the", "is", "a", "an", "to", "of", "and", "or", "for", "on", "in", "at", "by",
        "it", "i", "my", "me", "we", "our", "you", "your", "this", "that", "these", "those",
        "do", "does", "did", "be", "been", "being", "was", "were", "am", "are", "have",
        "has", "had", "can", "could", "should", "would", "will", "shall", "may", "might",
        "there", "so", "if", "but", "not", "no", "as", "just", "too", "really"
    ]

    static func sanitize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
        let rebuilt = String(String.UnicodeScalarView(stripped))
        if rebuilt.count > maxInputLength {
            return String(rebuilt.prefix(maxInputLength))
        }
        return rebuilt
    }

    static func tokenize(_ input: String) -> Set<String> {
        let lowered = input.lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        let raw = lowered.components(separatedBy: separators)
        var tokens: Set<String> = []
        for token in raw where !token.isEmpty && !stopwords.contains(token) {
            tokens.insert(token)
        }
        return tokens
    }

    static func findBestAnswer(for rawInput: String, in qa: [AssistantQA] = WiFiAssistantKnowledge.entries) -> AssistantQA? {
        let cleaned = sanitize(rawInput)
        guard !cleaned.isEmpty else { return nil }

        let tokens = tokenize(cleaned)
        guard !tokens.isEmpty else { return nil }

        var bestScore = 0
        var best: AssistantQA?
        for entry in qa {
            var score = 0
            for keyword in entry.keywords where tokens.contains(keyword) {
                score += 1
            }
            if score > bestScore {
                bestScore = score
                best = entry
            }
        }

        return bestScore >= 1 ? best : nil
    }

    static func relatedQuestions(for answered: AssistantQA, count: Int = 3) -> [String] {
        let pool = WiFiAssistantKnowledge.entries.filter { $0.id != answered.id }
        let sameCategory = pool.filter { $0.category == answered.category }
        let otherCategory = pool.filter { $0.category != answered.category }
        let ordered = sameCategory + otherCategory
        return Array(ordered.prefix(count)).map { $0.question }
    }

    static func fallbackSuggestions(count: Int = 4) -> [String] {
        Array(WiFiAssistantKnowledge.entries.shuffled().prefix(count)).map { $0.question }
    }

    static let starterQuestions: [String] = [
        "How can I make my Wi-Fi signal better?",
        "Why is my gaming slow at certain times of day?",
        "Why is my streaming buffering?",
        "Is my network secure?"
    ]
}

// MARK: - Chat View

struct WiFiAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var messages: [AssistantMessage] = []
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(theme.divider)
            messageList
            inputBar
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear(perform: seedGreetingIfNeeded)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AppLogoView(size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wi-Fi Buddy Assistant")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text("Canned answers for common Wi-Fi questions")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(theme.cardFill)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        messageBubble(for: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .onChange(of: messages) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(for message: AssistantMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.buttonText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    assistantAvatar
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(theme.cardFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(theme.cardStroke, lineWidth: 1)
                                )
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 20)
                }

                if !message.relatedQuestions.isEmpty {
                    suggestedChips(message.relatedQuestions)
                        .padding(.leading, 40)
                }
            }
        }
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 30, height: 30)
            Image(systemName: "wifi")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
        }
    }

    // MARK: Suggested chips

    private func suggestedChips(_ questions: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(questions, id: \.self) { question in
                    Button {
                        submit(question)
                    } label: {
                        Text(question)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(Color.blue.opacity(0.12))
                            )
                            .overlay(
                                Capsule().stroke(Color.blue.opacity(0.25), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your Wi-Fi...", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(theme.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(theme.cardStroke, lineWidth: 1)
                        )
                )
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(sendCurrentInput)

            Button(action: sendCurrentInput) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
            .disabled(trimmedInput.isEmpty)
            .opacity(trimmedInput.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.background)
    }

    // MARK: Logic

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendCurrentInput() {
        let text = trimmedInput
        guard !text.isEmpty else { return }
        inputText = ""
        submit(text)
    }

    private func submit(_ rawText: String) {
        let cleaned = WiFiAssistantEngine.sanitize(rawText)
        guard !cleaned.isEmpty else { return }

        messages.append(
            AssistantMessage(role: .user, text: cleaned, relatedQuestions: [])
        )

        if let match = WiFiAssistantEngine.findBestAnswer(for: cleaned) {
            let follow = WiFiAssistantEngine.relatedQuestions(for: match)
            messages.append(
                AssistantMessage(role: .assistant, text: match.answer, relatedQuestions: follow)
            )
        } else {
            let suggestions = WiFiAssistantEngine.fallbackSuggestions()
            messages.append(
                AssistantMessage(
                    role: .assistant,
                    text: "I'm not sure I caught that one. Here are some common questions I can help with — tap one to get a canned answer.",
                    relatedQuestions: suggestions
                )
            )
        }
    }

    private func seedGreetingIfNeeded() {
        guard messages.isEmpty else { return }
        messages.append(
            AssistantMessage(
                role: .assistant,
                text: "Hi! I'm your Wi-Fi Buddy assistant. Tap a question below or type your own — I've got canned tips for common home Wi-Fi issues.",
                relatedQuestions: WiFiAssistantEngine.starterQuestions
            )
        )
    }
}

#Preview {
    WiFiAssistantView()
        .withAppTheme()
}
