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
    var isThinking: Bool = false

    static func == (lhs: AssistantMessage, rhs: AssistantMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Knowledge Base

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
        ),
        AssistantQA(
            question: "Why is my Wi-Fi slower than what I pay for?",
            keywords: ["slower", "plan", "paying", "pay", "isp", "promised", "advertised", "subscription", "mbps", "gigabit", "gbps"],
            answer: """
ISP plans advertise wired speeds — what you see over Wi-Fi is almost always lower. Here's why, and what to check:

• Wi-Fi overhead eats 20–40% of raw speed, even with a strong signal.
• Test with a device plugged directly into the router via Ethernet — that tells you what your ISP is actually delivering.
• If wired speed is close to your plan but Wi-Fi is far below it, the router or signal is the bottleneck, not the ISP.
• Older phones and laptops (Wi-Fi 4 / 802.11n) max out around 100 Mbps no matter how fast your plan is.
• Run the speed test in the Speed tab a few times across the day — if wired speed is consistently much lower than advertised, call your ISP.
""",
            category: "Speed"
        ),
        AssistantQA(
            question: "Is Wi-Fi 6 or Wi-Fi 7 worth upgrading to?",
            keywords: ["wifi6", "wifi7", "wi-fi6", "wi-fi7", "upgrade", "upgrading", "new", "router", "worth", "802.11ax", "802.11be", "generation"],
            answer: """
Whether an upgrade helps depends on your devices:

• Wi-Fi 6 (802.11ax) — great if you have 15+ connected devices, a busy smart home, or a recent phone/laptop. Handles crowded networks much better than Wi-Fi 5.
• Wi-Fi 6E — adds the 6 GHz band. Nice if your gear supports it (iPhone 15 Pro+, recent Androids, newer MacBooks), but useless if it doesn't.
• Wi-Fi 7 (802.11be) — still early. Real-world gains are modest unless you have Wi-Fi 7 client devices, which are rare.

If your current router is 5+ years old and you have fast internet (500 Mbps+), a Wi-Fi 6 or 6E router is usually a clear win. Otherwise, placement and mesh upgrades matter more than the Wi-Fi generation.
""",
            category: "Setup"
        ),
        AssistantQA(
            question: "Why won't my device connect to Wi-Fi?",
            keywords: ["wont", "cant", "can't", "won't", "connect", "connecting", "join", "joining", "refuses", "stuck", "authenticating", "incorrect"],
            answer: """
If a device refuses to join, try these in order:

• Double-check the password — case matters, and 0 vs O / 1 vs l trip people up.
• On the device, "forget this network," then re-enter the password fresh.
• Reboot just that device — toggle airplane mode on iPhone/Android, or restart the laptop.
• Reboot the router (unplug 60 seconds).
• Move closer to the router — weak signal can show up as "incorrect password."
• Check if other devices can connect. If none can, the router's Wi-Fi radio may have crashed.
• Some routers have a device limit or MAC filter — log into the admin page to check.
""",
            category: "Reliability"
        ),
        AssistantQA(
            question: "Can my neighbors use my Wi-Fi?",
            keywords: ["neighbor", "neighbors", "neighbour", "stranger", "someone", "else", "leeching", "freeloading", "stealing", "using"],
            answer: """
If your Wi-Fi has a strong password (WPA2 or WPA3), neighbors can't just hop on. But let's make sure:

• Wi-Fi security: should be WPA2 or WPA3 — never "Open." Check in your router's admin page.
• Password strength: long and random is better than clever. 12+ characters.
• Change it if you ever shared it with someone and don't want them connected anymore.
• Open the Devices tab — anything on your network you don't recognize? Start by unplugging or turning off your own devices one at a time; anything left is worth investigating.

If you ever find an unknown device and can't identify it, change your Wi-Fi password — every device will need to reconnect with the new one.
""",
            category: "Security"
        ),
        AssistantQA(
            question: "What's the difference between a modem and a router?",
            keywords: ["modem", "router", "difference", "between", "vs", "versus", "gateway", "combo", "separate"],
            answer: """
They do different jobs, even when they're in the same box:

• Modem — translates your ISP's signal (coax, fiber, DSL) into regular internet. One cable in, one cable out. No Wi-Fi.
• Router — takes the modem's internet and shares it with your devices, does Wi-Fi, assigns addresses, handles the firewall.
• Gateway / combo unit — one device that does both. Common with rentals from the ISP.

Separate units usually beat the combo box because you can upgrade the router independently. If your ISP rents you a combo for $10–15/month, buying your own modem + router often pays for itself within a year.
""",
            category: "Setup"
        ),
        AssistantQA(
            question: "How do I make video calls less choppy?",
            keywords: ["zoom", "teams", "facetime", "meet", "webex", "call", "video", "choppy", "freezing", "frozen", "quality", "meeting", "glitching"],
            answer: """
Video calls need stable upload, low latency, and no competing traffic. Try:

• Get close to the router, on 5 GHz. Weak signal kills video calls first.
• If your setup is permanent (home office), plug into Ethernet — even $20 worth of cable changes everything.
• Pause cloud backups (iCloud, Dropbox, OneDrive) during important meetings.
• Turn off other devices that might be streaming 4K or downloading.
• Close browser tabs you aren't using — some (video sites, social media feeds) quietly pull a lot of bandwidth.
• Check the Speed tab — you want at least 3–5 Mbps upload and ping under 60 ms for smooth HD video calls.
""",
            category: "Streaming"
        ),
        AssistantQA(
            question: "Should I change my DNS to Google or Cloudflare?",
            keywords: ["dns", "cloudflare", "google", "1.1.1.1", "8.8.8.8", "change", "server", "opendns", "faster"],
            answer: """
Changing DNS can help in a few specific ways:

• Speed — public DNS like Cloudflare (1.1.1.1) or Google (8.8.8.8) is often faster than your ISP's, especially when your ISP's is overloaded.
• Privacy — Cloudflare and Quad9 don't log browsing the way some ISP DNS does.
• Reliability — public DNS rarely goes down; ISP DNS occasionally does.

Set it once on the router and every device on your Wi-Fi uses it. Or set it per-device if you only want it on your phone/laptop.

Realistically, the speed boost is usually tens of milliseconds, not a game-changer. But privacy-wise, it's a nice free win.
""",
            category: "Setup"
        ),
        AssistantQA(
            question: "How do I set up parental controls?",
            keywords: ["parental", "kids", "children", "block", "blocking", "filter", "filtering", "schedule", "bedtime", "limit", "limits", "content"],
            answer: """
You've got a few layers to work with:

• Router-level controls — most modern routers (Eero, Nest, Orbi, ASUS, TP-Link) have built-in parental controls in their app. You can pause Wi-Fi per device, set bedtimes, and filter categories.
• DNS filtering — switching to OpenDNS FamilyShield (208.67.222.123) or Cloudflare Families (1.1.1.3) blocks adult and malicious sites network-wide.
• Device-level — iOS Screen Time and Google Family Link give you app limits, downtime, and site filters that follow the device off Wi-Fi too.

Best setup is usually router-level bedtime/pause + on-device Screen Time. The combo is tough to bypass.
""",
            category: "Security"
        ),
        AssistantQA(
            question: "Do smart home devices make my Wi-Fi slow?",
            keywords: ["smart", "iot", "home", "bulbs", "plugs", "camera", "cameras", "alexa", "echo", "many", "too", "devices", "overload"],
            answer: """
Individually, no. As a pile, sometimes yes:

• Most smart plugs, bulbs, and sensors use tiny amounts of bandwidth — they just sit idle.
• The real cost is connection count. Older routers start struggling above ~20–30 simultaneous clients.
• Smart cameras are the exception — 1080p cameras streaming to the cloud can use 1–2 Mbps each, 24/7.
• Many IoT devices only speak 2.4 GHz, which crowds that band fast.
• Check the Devices tab — if you have 30+ IoT gadgets, a mesh system or Wi-Fi 6 router will handle them far better than a 5-year-old single unit.

Bonus: put IoT stuff on a guest network so a hacked smart bulb can't reach your laptop.
""",
            category: "Security"
        ),
        AssistantQA(
            question: "Why is my Wi-Fi fine in some rooms but not others?",
            keywords: ["rooms", "room", "corners", "upstairs", "downstairs", "basement", "garage", "outside", "backyard", "deadzone", "dead", "weak"],
            answer: """
That's classic signal drop — Wi-Fi doesn't pass through materials evenly:

• Concrete, brick, and stone walls block a lot of signal.
• Metal (filing cabinets, fridges, mirrors) reflects it.
• Floors with rebar or radiant heating kill vertical coverage.
• Water (aquariums, water heaters) absorbs 2.4 GHz.

What to do:

• Move the router more centrally, higher up, and out of enclosures.
• Run the Survey tab — it literally shows you where your weak spots are on a floor plan.
• If a dead zone persists after good placement, a mesh node (or a second router in access-point mode) in that area fixes it.
• One far corner only? A single extender may do, but expect it to feel slower.
""",
            category: "Coverage"
        ),
        AssistantQA(
            question: "Should I use a VPN on my home Wi-Fi?",
            keywords: ["vpn", "privacy", "private", "tunnel", "encrypt", "encryption", "nordvpn", "expressvpn", "proton", "hide"],
            answer: """
On your own home Wi-Fi, a VPN is usually optional — your traffic is already encrypted between you and the router, and between your device and any HTTPS site. What a VPN changes:

• Hides your traffic from your ISP. Useful if you don't want them logging what you browse.
• Masks your IP from the sites you visit.
• Lets you pretend to be in another country for streaming.

What it costs:

• Most VPNs noticeably slow down your connection (especially upload).
• Ping goes up — bad for gaming and video calls.
• Some services (banking, streaming) block known VPN IPs.

On public Wi-Fi (cafés, airports), a VPN is more useful. At home, it's a privacy choice, not a security must.
""",
            category: "Security"
        ),
        AssistantQA(
            question: "Should I hide my Wi-Fi network name?",
            keywords: ["hide", "hidden", "ssid", "broadcast", "invisible", "stealth", "name"],
            answer: """
Short answer: don't bother. "Hiding" the SSID (turning off broadcast) feels like a security win, but it isn't:

• Anyone with a free Wi-Fi scanning app can still see hidden networks — they just don't show the name.
• Your phone has to shout the hidden name everywhere it goes looking for it, which is actually worse for privacy.
• Some devices (printers, smart gadgets) have trouble joining hidden networks.

Real security comes from: a strong password, WPA2/WPA3 encryption, updated firmware, and turning off WPS. Those protect you. Hiding the name doesn't.
""",
            category: "Security"
        ),
        AssistantQA(
            question: "How do I port forward for a game or server?",
            keywords: ["port", "forward", "forwarding", "nat", "open", "host", "server", "minecraft", "strict", "moderate"],
            answer: """
Port forwarding lets incoming connections reach a specific device on your network. Rough steps:

• Give the device a static local IP (in the router's DHCP reservation page), so the forwarding rule keeps pointing at the right machine.
• In the router admin page, find "Port Forwarding" (sometimes under "NAT" or "Firewall").
• Add a rule: external port(s) → internal IP → internal port(s) → protocol (TCP, UDP, or both).
• Save, then test with a tool like canyouseeme.org or the game's own network test.

Safer alternatives:

• UPnP — many games/apps open ports automatically. Works if enabled on the router.
• For game consoles showing "strict NAT," enabling UPnP usually fixes it without manual port forwarding.
• Only forward what you need — every open port is exposed to the internet.
""",
            category: "Setup"
        ),
        AssistantQA(
            question: "What do download and upload speeds actually mean?",
            keywords: ["download", "upload", "speed", "mbps", "bandwidth", "definition", "meaning", "explain", "what", "difference"],
            answer: """
Download is data coming to you (streaming, loading web pages, game downloads). Upload is data leaving you (sending email, uploading photos, video calls, live streaming).

Rough numbers that matter:

• 25 Mbps download — enough for one 4K stream or a household of basic browsing.
• 100+ Mbps download — comfortable for multiple 4K streams and busy households.
• 5 Mbps upload — enough for HD video calls.
• 25+ Mbps upload — helpful if you stream, upload big files, or have cloud backups.

Speeds are in megabits per second (Mbps). File sizes are in megabytes (MB). 1 MB = 8 Mb, so a 100 Mbps connection downloads roughly 12 MB per second, not 100.
""",
            category: "Speed"
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

    static let thinkingPhrases: [String] = [
        "Crunching the bytes",
        "Sniffing the packets",
        "Tuning my antenna",
        "Scanning the spectrum",
        "Decoding the signal",
        "Checking the airwaves",
        "Measuring the throughput",
        "Consulting the router",
        "Polling the access points",
        "Diagnosing the network",
        "Booting up my brain",
        "Recalibrating my dish",
        "Listening to the SSIDs",
        "Squinting at the waveform"
    ]

    static func randomThinkingPhrase() -> String {
        thinkingPhrases.randomElement() ?? "Thinking"
    }
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
            KlausMascotView(size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Klaus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text("Your Wi-Fi Buddy sidekick")
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
                    if message.isThinking {
                        ThinkingBubble(phrase: message.text)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(theme.cardFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(theme.cardStroke, lineWidth: 1)
                                    )
                            )
                    } else {
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
                    }
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
                .frame(width: 34, height: 34)
                .overlay(
                    Circle().stroke(Color.blue.opacity(0.22), lineWidth: 1)
                )
            KlausMascotView(size: 30)
                .offset(y: 1)
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
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
            TextField("Ask Klaus about your Wi-Fi...", text: $inputText, axis: .vertical)
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

        let thinkingMessage = AssistantMessage(
            role: .assistant,
            text: WiFiAssistantEngine.randomThinkingPhrase(),
            relatedQuestions: [],
            isThinking: true
        )
        let thinkingID = thinkingMessage.id
        messages.append(thinkingMessage)

        let delay = Double.random(in: 1.4...2.2)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            let reply: AssistantMessage
            if let match = WiFiAssistantEngine.findBestAnswer(for: cleaned) {
                let follow = WiFiAssistantEngine.relatedQuestions(for: match)
                reply = AssistantMessage(role: .assistant, text: match.answer, relatedQuestions: follow)
            } else {
                let suggestions = WiFiAssistantEngine.fallbackSuggestions()
                reply = AssistantMessage(
                    role: .assistant,
                    text: "Hmm, my little antenna didn't quite pick that one up. Here's what I *definitely* know about — tap a question to pick my brain.",
                    relatedQuestions: suggestions
                )
            }

            if let idx = messages.firstIndex(where: { $0.id == thinkingID }) {
                messages[idx] = reply
            } else {
                messages.append(reply)
            }
        }
    }

    private func seedGreetingIfNeeded() {
        guard messages.isEmpty else { return }
        messages.append(
            AssistantMessage(
                role: .assistant,
                text: "Beep boop — hi there! I'm Klaus, your Wi-Fi Buddy. I live in your router's packets and I know *way* too much about Wi-Fi. Tap a question below or ask me anything.",
                relatedQuestions: WiFiAssistantEngine.starterQuestions
            )
        )
    }
}

// MARK: - Thinking Bubble

private struct ThinkingBubble: View {
    @Environment(\.theme) private var theme

    let phrase: String

    @State private var dotPhase: Int = 0

    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            Text(phrase)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Text(dotString)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 18, alignment: .leading)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(timer) { _ in
            dotPhase = (dotPhase + 1) % 4
        }
        .accessibilityLabel("\(phrase)…")
    }

    private var dotString: String {
        String(repeating: ".", count: dotPhase)
    }
}

#Preview {
    WiFiAssistantView()
        .withAppTheme()
}
