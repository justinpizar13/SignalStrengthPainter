import SwiftUI
import Combine

// MARK: - Klaus Context (live data Klaus can speak about)

/// A snapshot of everything Klaus knows about the user's current network
/// state. Producers across the app — `NetworkTopologyMonitor`,
/// `SpeedTestManager`, `NetworkScanner`, the Signal-tab probe, the Survey
/// insights view — push the latest values into `KlausContextHub.shared`,
/// and Klaus reads from there when crafting replies. None of this is
/// persisted to disk; the snapshot lives in memory and resets per
/// process, mirroring the rest of the app's privacy posture (no analytics,
/// no logged history).
///
/// Every field is optional. Klaus's reply templates check for presence
/// before quoting a number, and gracefully fall back to telling the user
/// where in the app to generate the missing reading (e.g. "run a Speed
/// Test and I'll be able to tell you").
struct KlausChatContext {
    // Connection medium reported by `NetworkInterfaceMonitor`. Used so
    // Klaus can frame answers correctly on cellular ("you're on
    // Cellular, so the Wi-Fi-specific advice doesn't apply yet").
    var connectionStatus: NetworkInterfaceMonitor.Status = .unknown

    // Signal tab — last LatencyProbe reading.
    var signalLatencyMs: Double?
    var signalLatencyAt: Date?

    // Topology card — gateway + ISP latency, local network identity.
    var localIP: String?
    var gatewayIP: String?
    var gatewayLatencyMs: Double?
    var ispLatencyMs: Double?
    var topologyUpdatedAt: Date?

    // Speed test — most recent completed run.
    var lastDownloadMbps: Double?
    var lastUploadMbps: Double?
    var lastSpeedPingMs: Double?
    var lastSpeedJitterMs: Double?
    var lastSpeedTestAt: Date?
    var ispOrganization: String?
    var serverColo: String?
    var serverCity: String?
    var distanceMiles: Double?
    var isLikelySuboptimalRoute: Bool = false

    // Survey insights — most recent generated report.
    var lastSurveyGrade: String?
    var lastSurveyHeadline: String?
    var lastSurveyMedianMs: Double?
    var lastSurveyP95Ms: Double?
    var lastSurveyJitterMs: Double?
    var lastSurveyDeadZoneCount: Int?
    var lastSurveyDistanceMeters: Double?
    var lastSurveyExcellentPct: Double?
    var lastSurveyPoorPct: Double?
    var lastSurveyAt: Date?

    // Devices tab — most recent scan results.
    var deviceCount: Int?
    var trustedDeviceCount: Int?
    var unknownDeviceCount: Int?
    var randomizedMacCount: Int?
    var lastScanAt: Date?

    /// Quality bucket for `signalLatencyMs`. Used inside templated
    /// replies so the prose can switch tone ("solid", "fine but
    /// noticeable", "rough").
    enum LatencyBand {
        case excellent  // < 30 ms
        case good       // 30–60 ms
        case fair       // 60–120 ms
        case poor       // 120–250 ms
        case awful      // > 250 ms
    }

    static func band(for ms: Double) -> LatencyBand {
        switch ms {
        case ..<30: return .excellent
        case ..<60: return .good
        case ..<120: return .fair
        case ..<250: return .poor
        default: return .awful
        }
    }

    /// Anything to say at all? Used to gate "give me the rundown"
    /// queries — without any populated field, Klaus doesn't pretend.
    var hasAnyLiveData: Bool {
        signalLatencyMs != nil
            || ispLatencyMs != nil
            || gatewayLatencyMs != nil
            || lastDownloadMbps != nil
            || lastSurveyGrade != nil
            || deviceCount != nil
    }
}

/// Process-wide hub Klaus reads from. Producers across the app push live
/// network state in via `update`, Klaus's intent engine pulls the
/// snapshot when composing a reply.
///
/// `@MainActor` because every producer (topology, speed test, scanner,
/// signal tab) already runs on the main actor, and every consumer
/// (Klaus chat) is a SwiftUI view. Marking this here keeps the producer
/// call sites straightforward — no `Task { @MainActor in … }` hops at
/// hundreds of update points.
@MainActor
final class KlausContextHub: ObservableObject {
    static let shared = KlausContextHub()

    @Published private(set) var snapshot = KlausChatContext()

    private var interfaceObservation: AnyCancellable?

    private init() {
        snapshot.connectionStatus = NetworkInterfaceMonitor.shared.status
        interfaceObservation = NetworkInterfaceMonitor.shared.$status
            .removeDuplicates()
            .sink { [weak self] status in
                Task { @MainActor in
                    self?.snapshot.connectionStatus = status
                }
            }
    }

    /// Mutate the stored snapshot. Producers describe what changed via
    /// the closure; observers re-render. Cheap to call repeatedly.
    func update(_ mutate: (inout KlausChatContext) -> Void) {
        mutate(&snapshot)
    }
}

// MARK: - Knowledge Base Models

/// A single curated topic Klaus can hold a conversation around. Every
/// answer variant is a complete reply on its own; the engine picks one
/// at random per turn so the same question doesn't always read the same
/// way. `followUps` are short "tell me more" extensions Klaus can offer
/// when the user asks for depth on the same topic.
struct AssistantQA: Identifiable {
    let id = UUID()
    /// Stable string key for follow-up tracking and live-data
    /// cross-references. Keep these unique within `WiFiAssistantKnowledge`.
    let topic: String
    let question: String
    let keywords: [String]
    /// One or more answer variants. The engine picks one at random per
    /// turn. Each variant is a complete answer — they don't share state.
    let answers: [String]
    /// Optional "tell me more" extensions. The engine returns one of
    /// these when the user follows up on the same topic ("any more?",
    /// "tell me more", "what else").
    let followUps: [String]
    let category: String
}

// MARK: - Knowledge Base

/// Curated Q&A library Klaus draws from. Topics cover the seven
/// categories visible in the suggested-question chips: Coverage,
/// Reliability, Setup, Streaming, Security, Speed, Gaming. Each topic
/// has multiple answer variants so back-to-back asks of the same
/// question read differently. Keep keywords lowercase; the matcher
/// lowercases user input before scoring.
enum WiFiAssistantKnowledge {
    static let entries: [AssistantQA] = [
        AssistantQA(
            topic: "improve-signal",
            question: "How can I make my Wi-Fi signal better?",
            keywords: ["improve", "better", "stronger", "boost", "weak", "signal", "wifi", "wireless", "stronger", "boost"],
            answers: [
                """
The biggest wins for a stronger signal:

• Move the router into a central, open spot — not in a closet, not behind the TV.
• Get it off the floor. Waist height or higher works far better.
• Switch nearby devices to 5 GHz — it's faster and less crowded.
• Reboot the router every few weeks to clear up flaky state.
• Walk a Survey to see exactly where the dead zones are.
""",
                """
A few moves that almost always help:

• Put the router in the middle of the area you actually use.
• Anything metal, masonry, or wet (aquariums, water heaters) absorbs signal — keep them out of the line.
• On 5 GHz for anything that needs speed; 2.4 GHz for far-away IoT.
• If walls are stealing the signal, a mesh node beats wishful thinking.

Open the Survey tab and walk the rooms — I'll show you exactly where the signal drops.
""",
                """
Honestly, signal trouble is almost always one of three things: bad router placement, an overcrowded 2.4 GHz band, or aging hardware. In that order.

Start with placement: central, elevated, out in the open. Then push devices that can handle it onto 5 GHz. If it's still rough, the router is probably the bottleneck.
"""
            ],
            followUps: [
                "Beep boop — extra credit: Wi-Fi radiates outward in a sphere from the antenna. Putting the router in the corner of your home wastes half the coverage on the neighbor's yard.",
                "If you can't move the router, try at least rotating it 90°. Most consumer routers have directional antennas, and a quarter turn can shift coverage into a different room.",
                "Quick sanity check: how old is the router? Anything over five years old struggles with modern device counts even if signal looks fine."
            ],
            category: "Coverage"
        ),
        AssistantQA(
            topic: "gaming-peak",
            question: "Why is my gaming slow at certain times of day?",
            keywords: ["gaming", "game", "lag", "laggy", "peak", "evening", "night", "hours", "times", "congestion"],
            answers: [
                """
Evenings — roughly 7 to 11 PM — are peak internet hours. Everyone in your neighborhood is streaming, gaming, and video-calling at once, so your ISP's shared lines get congested.

What helps:

• Plug your console or PC into Ethernet. Cuts ping dramatically.
• If you must use Wi-Fi, stay on 5 GHz, not 2.4.
• Pause cloud backups and uploads during matches.
• Check the Devices tab — a streaming device hogging bandwidth wrecks ping for everyone.
""",
                """
Classic neighborhood congestion. Your ISP's last-mile capacity is shared, and prime time gets crushed.

Quick wins: wired Ethernet, 5 GHz when wireless is the only option, and quitting anything that's uploading in the background. If it's still bad night after night, the plan in your area might genuinely be oversubscribed and worth a call to the ISP.
"""
            ],
            followUps: [
                "Pro tip: open the Speed tab around 8 PM and again at 6 AM. If your evening download is half the morning number, that's congestion, not your Wi-Fi.",
                "Game-specific: most competitive shooters care about ping more than throughput. Even on a 'slow' plan you can game well if latency stays under 60 ms."
            ],
            category: "Gaming"
        ),
        AssistantQA(
            topic: "disconnects",
            question: "Why does my Wi-Fi keep disconnecting?",
            keywords: ["disconnect", "disconnects", "disconnecting", "dropping", "drops", "drop", "keeps", "losing", "connection", "cutting", "unstable", "flaky"],
            answers: [
                """
Random drops usually trace back to one of these:

• Overheating router — if it's hot to the touch, give it airflow or replace it.
• Outdated firmware — log into the router admin page and update.
• Channel interference from neighbors — try channels 1, 6, or 11 on 2.4 GHz.
• Too many connected devices — older routers choke around 20+ active clients.
• A dying router. Most consumer units last 3 to 5 years.

Start simple: power-cycle for 60 seconds.
""",
                """
First thing I'd check: heat. A router that's warm to the touch is one that's about to misbehave. Move it out of any enclosure, get airflow around it.

Second: firmware. Most of these dropouts are bugs that the manufacturer has already fixed in a firmware update sitting on the admin page.

Third: age. If the router is north of five years and you have 20+ devices, the box itself is the bottleneck.
"""
            ],
            followUps: [
                "If a single device drops while everything else stays connected, the issue is on that device — toggle airplane mode or 'forget this network' and re-join.",
                "Routers near baby monitors, microwaves, or older cordless phones get slammed on 2.4 GHz. Check what's within 6 feet."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "router-placement",
            question: "Where should I place my router?",
            keywords: ["place", "placement", "position", "where", "put", "location", "router", "central", "centrally", "spot"],
            answers: [
                """
Router placement rules of thumb:

• Central to the area you use most.
• Elevated. On a shelf, not the floor.
• Out in the open. Not inside a cabinet, not behind the TV.
• Away from microwaves, cordless phones, and baby monitors.
• Away from big metal objects and thick masonry.

Walk a Survey after you move it — I'll show you whether it actually helped.
""",
                """
Wi-Fi radiates outward from the antennas, so the placement game is "geometric center of where I want signal" not "wherever the cable comes out of the wall." A long Cat6 cable is your friend.

Key avoids: floors, closets, cabinets, anywhere boxed in. Anything wet — aquariums, water heaters — absorbs 2.4 GHz like a sponge.
"""
            ],
            followUps: [
                "Two-story home? The router's job is easier from the upstairs ceiling than the downstairs floor — signal cones outward and downward better than upward.",
                "Got concrete or brick interior walls? Even great placement won't beat them. That's the case for a mesh node, not a more powerful router."
            ],
            category: "Coverage"
        ),
        AssistantQA(
            topic: "bands",
            question: "Should I use 2.4 GHz or 5 GHz?",
            keywords: ["2", "5", "ghz", "band", "frequency", "dual", "which", "2.4"],
            answers: [
                """
Quick answer:

• 5 GHz — faster, less crowded, shorter range. Best for devices within ~25 ft of the router and anything that needs speed (streaming, gaming, video calls).
• 2.4 GHz — slower, longer range, better at getting through walls. Best for far-away devices and simple smart-home gadgets.

If your router supports it, leave both bands on the same network name and let the router handle band steering. Manually splitting them is more headache than it's worth.
""",
                """
Think of it like radio stations. 5 GHz is the empty premium station — fast but only reaches the next room. 2.4 GHz is crowded AM — slower, but reaches the basement.

Modern phones, laptops, and TVs prefer 5 GHz when they're close. Smart bulbs and old Echo Dots are stuck on 2.4 GHz. Most modern routers handle the routing for you under one SSID.
"""
            ],
            followUps: [
                "If you have Wi-Fi 6E or Wi-Fi 7 gear, there's a third band — 6 GHz — that's even faster and even less crowded than 5 GHz.",
                "On 2.4 GHz, only channels 1, 6, and 11 don't overlap. If your router auto-picked channel 4, it's interfering with both 1 and 6."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "buffering",
            question: "Why is my streaming buffering?",
            keywords: ["stream", "streaming", "buffer", "buffering", "netflix", "youtube", "video", "4k", "hd", "pausing", "loading"],
            answers: [
                """
Buffering almost always means not enough bandwidth is reaching the streaming device. Run through this:

• How many devices are using the network right now? Every active stream competes.
• Is the streaming device on 5 GHz and close to the router?
• Speed Test from the Speed tab — 4K wants ~25 Mbps, HD wants ~5 Mbps.
• Restart the streaming device and the router.
• For a TV that doesn't move, plug in Ethernet. No more buffering.
""",
                """
A few specific culprits I'd check, in order:

1. Your speed in the room with the TV. Run a speed test there, not by the router.
2. Whether the TV is actually on 5 GHz. Many smart TVs default to 2.4 GHz forever.
3. Whether someone else is uploading or downloading something heavy. Cloud backups are sneaky.
4. Whether the streaming app itself is having trouble — try a different one.
"""
            ],
            followUps: [
                "Netflix in particular drops to a lower resolution when bandwidth dips and only re-checks every few minutes. Pause for 10 seconds and resume to force a fresh handshake.",
                "If your TV supports it, plug Ethernet directly into the back. A $10 cable solves more buffering than any router upgrade I've seen."
            ],
            category: "Streaming"
        ),
        AssistantQA(
            topic: "security",
            question: "Is my network secure?",
            keywords: ["secure", "security", "safe", "hacked", "hacker", "intruder", "strangers", "password", "protect"],
            answers: [
                """
Good home Wi-Fi security comes down to a few basics:

• WPA3, or WPA2 if your router doesn't support 3. Never "Open" or WEP.
• Strong, unique Wi-Fi password. 12+ characters, not "password123".
• Change the router admin login from the default (admin/admin).
• Keep the router firmware updated.
• Turn off WPS — it's a well-known weak spot.

Pop into the Devices tab. Anything you don't recognize? Time to investigate or rotate the password.
""",
                """
The honest answer: most home networks are 'secure enough' the moment you have a long WPA2/WPA3 password and you've changed the admin login. The remaining attack surface is firmware bugs, which is why I keep harping on updates.

Two extra moves: turn off WPS, and put your IoT devices on a guest network so a compromised smart bulb can't reach your laptop.
"""
            ],
            followUps: [
                "Want a litmus test? Open the Devices tab and try to identify every device. Anything you can't account for after powering down your own gear is worth a closer look.",
                "WPA3 is meaningfully better than WPA2 against offline cracking — if your router supports it, flip the switch."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "good-ping",
            question: "What's a good ping for gaming?",
            keywords: ["ping", "latency", "good", "ms", "milliseconds", "fps", "shooter", "competitive"],
            answers: [
                """
Rough ping guidelines for online gaming:

• Under 30 ms — excellent. Competitive shooters feel responsive.
• 30–60 ms — great. You won't notice it for most games.
• 60–100 ms — playable but you'll feel it in fast-paced games.
• 100–150 ms — noticeable lag, especially in competitive matches.
• Over 150 ms — rough. Expect frustration.

The Signal tab measures live latency. If it's always high on Wi-Fi, a wired connection usually shaves 10–30 ms.
""",
                """
The honest gaming-ping thresholds: under 50 ms feels great, 50–100 is fine for most games, 100+ starts to hurt. Anything past 150 in a competitive shooter and you'll lose gunfights you should have won.

Wi-Fi adds 5–15 ms of overhead by itself, so if you're stuck on Wi-Fi, getting closer to the router and onto 5 GHz is your biggest lever.
"""
            ],
            followUps: [
                "Jitter matters more than people realize. A steady 80 ms feels better than a 30 ms average that spikes to 200.",
                "Most game servers are regional. If you're playing a friend across the country, your ping floor is set by the speed of light, not your Wi-Fi."
            ],
            category: "Gaming"
        ),
        AssistantQA(
            topic: "slow-upload",
            question: "Why is my upload so slow?",
            keywords: ["upload", "uploading", "slow", "asymmetric", "zoom", "twitch", "asymmetrical"],
            answers: [
                """
Slow uploads are usually a plan issue, not a Wi-Fi issue. Most home plans (especially cable) are asymmetric — lots of download, much less upload.

Things to try:

• Speed Test from the Speed tab — compare upload to what your ISP promised.
• Close cloud backups (iCloud, Drive, OneDrive) during important calls.
• If you stream or upload a lot, ask the ISP about fiber. Fiber plans are usually symmetric.
• On Wi-Fi, stay on 5 GHz close to the router — weak signal kills upload first.
""",
                """
Cable plans typically give you 10x more download than upload. Fiber plans usually give you the same in both directions. So if your downloads are blazing but Zoom is freezing, the plan itself is asymmetric — not your Wi-Fi.

That said, weak signal kills upload before it kills download because the device has to fight to get its packets back to the router. Get closer or jump to 5 GHz.
"""
            ],
            followUps: [
                "Upload becomes the bottleneck for video calls, online backups, livestreaming, and uploading to cloud photo apps. Download barely matters for those.",
                "Some ISPs throttle upload after a certain monthly cap. If your upload speed cratered after a heavy month, that might be why."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "extender-vs-mesh",
            question: "Do I need a Wi-Fi extender or a mesh system?",
            keywords: ["extender", "repeater", "mesh", "booster", "range", "coverage", "deadzone", "dead", "zone", "zones", "big", "house"],
            answers: [
                """
Quick breakdown:

• Wi-Fi extender — cheap, plugs into an outlet, rebroadcasts your signal. Often halves the speed of anything connected through it. Fine for one far-away corner.
• Mesh system — multiple nodes that act as one seamless network. Devices roam automatically. More expensive but dramatically better for full-house coverage.

More than one or two dead zones? Skip the extender, go mesh. The Survey tab can show you exactly where coverage drops off.
""",
                """
Honest take: extenders are a band-aid, mesh is a fix. An extender will work for one trouble corner, but the moment you have two or three weak spots you're better off replacing the router with a mesh kit.

Mesh nodes talk to each other on a dedicated 'backhaul' band, so they don't halve your speed the way a basic extender does.
"""
            ],
            followUps: [
                "If you go mesh, three nodes covers most homes up to ~3000 sqft. Two nodes is enough for a typical apartment.",
                "Powerline adapters are an underrated middle option — they push internet through your home's electrical wiring. Not as fast as Ethernet but doesn't share Wi-Fi airtime."
            ],
            category: "Coverage"
        ),
        AssistantQA(
            topic: "restart-router",
            question: "How often should I restart my router?",
            keywords: ["restart", "reboot", "reset", "power", "cycle", "often", "how", "frequency"],
            answers: [
                """
Rebooting clears out memory leaks, stuck DHCP leases, and overheating. Good rhythm:

• Every 1–2 weeks as preventive maintenance.
• Any time speeds suddenly drop.
• After any firmware update.

How to do it right: unplug the router (and modem if separate) for a full 60 seconds, plug back in, wait 2–3 minutes for everything to come up.

Don't confuse this with a factory reset — you only want the power cycle.
""",
                """
Once every couple weeks is plenty. Some people swear by nightly reboots; that's overkill but harmless. The main thing is the 60-second unplug — turning it off and back on too quickly doesn't actually flush anything.

If you're rebooting more than once a week to keep things working, the router is dying. Time for new hardware.
"""
            ],
            followUps: [
                "Some routers have a 'scheduled reboot' option in the admin page. Set it for 4 AM and forget about it.",
                "If a reboot fixes things only briefly, that's a memory leak — almost always solved by a firmware update or a new router."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "isp-mismatch",
            question: "Why is my Wi-Fi slower than what I pay for?",
            keywords: ["slower", "plan", "paying", "pay", "isp", "promised", "advertised", "subscription", "mbps", "gigabit", "gbps"],
            answers: [
                """
ISP plans advertise wired speeds — Wi-Fi is almost always lower. Here's the rundown:

• Wi-Fi overhead eats 20–40% of raw speed even with a strong signal.
• Test with a device plugged directly into the router via Ethernet — that tells you what the ISP is actually delivering.
• Wired close to the plan, Wi-Fi far below? The router or signal is the bottleneck, not the ISP.
• Older devices (Wi-Fi 4 / 802.11n) max out around 100 Mbps no matter how fast your plan is.

Run the Speed Test a few times across the day. If wired is consistently far below advertised, call the ISP.
""",
                """
The thing nobody tells you when you sign up: 'gigabit' is a wired number. Realistic Wi-Fi will be 60–80% of that on a great router, less on cheaper hardware.

Test method: plug a laptop directly into the router with Ethernet, run a Speed Test. That's the honest ISP number. Compare it to the plan you bought.
"""
            ],
            followUps: [
                "If your plan is over 500 Mbps, you genuinely need a Wi-Fi 6 router to see the benefit on wireless. Wi-Fi 5 is the bottleneck above that.",
                "ISP speed dipping at peak hours is normal. ISP speed dipping all day, every day, is a service problem worth a call."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "wifi-generations",
            question: "Is Wi-Fi 6 or Wi-Fi 7 worth upgrading to?",
            keywords: ["wifi6", "wifi7", "wi-fi6", "wi-fi7", "upgrade", "upgrading", "new", "router", "worth", "802", "generation"],
            answers: [
                """
Whether an upgrade helps depends on your devices:

• Wi-Fi 6 (802.11ax) — great if you have 15+ devices, a busy smart home, or a recent phone/laptop.
• Wi-Fi 6E — adds the 6 GHz band. Nice if your gear supports it, useless if it doesn't.
• Wi-Fi 7 (802.11be) — still early. Real gains are modest unless your client devices are also Wi-Fi 7.

Router five-plus years old + plan over 500 Mbps + recent phone/laptop? Wi-Fi 6 or 6E is a clear win. Otherwise placement and mesh matter more than the generation.
""",
                """
Honest answer: most people will see a bigger improvement from better placement or going mesh than from buying a Wi-Fi 7 router. The newer standards mainly help busy networks — lots of devices, lots of simultaneous activity.

If you're still on a router from 2018 and your phone is recent, go Wi-Fi 6/6E. If you bought a Wi-Fi 6 router last year, don't bother with 7 yet.
"""
            ],
            followUps: [
                "Wi-Fi 6 isn't just faster — it's better at handling many devices at once thanks to OFDMA. That matters more in a busy household than the raw speed bump.",
                "Wi-Fi 6E's 6 GHz band is the cleanest spectrum available right now. If you can use it, do."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "wont-connect",
            question: "Why won't my device connect to Wi-Fi?",
            keywords: ["wont", "cant", "can't", "won't", "connect", "connecting", "join", "joining", "refuses", "stuck", "authenticating", "incorrect"],
            answers: [
                """
If a device refuses to join, run through these in order:

• Double-check the password — case matters. 0 vs O / 1 vs l trips people up.
• On the device, "forget this network" then re-enter the password fresh.
• Reboot just the device — airplane mode toggle on phones, full restart on laptops.
• Reboot the router (60-second unplug).
• Move closer — weak signal often shows up as "incorrect password."
• Check if other devices can connect. None can? The router's Wi-Fi radio may have crashed.
• Some routers have a device-count limit or MAC filter — log into admin to check.
""",
                """
Almost always one of three things: typo in the password, the device cached a stale password, or the router needs a power-cycle.

Forget the network on the device, reboot the router, re-enter the password fresh. That fixes 90% of these.
"""
            ],
            followUps: [
                "If the device sees the network but won't authenticate, that's a password issue. If the device doesn't see the network at all, that's a band/channel issue or the router itself.",
                "Some IoT devices only join 2.4 GHz. If your router has band steering and the smart plug refuses to pair, temporarily disable 5 GHz during setup."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "neighbors",
            question: "Can my neighbors use my Wi-Fi?",
            keywords: ["neighbor", "neighbors", "neighbour", "stranger", "someone", "else", "leeching", "freeloading", "stealing", "using"],
            answers: [
                """
If your Wi-Fi has a strong WPA2 or WPA3 password, neighbors can't just hop on. But let's verify:

• Wi-Fi security: should be WPA2 or WPA3. Never "Open."
• Password strength: long and random beats clever. 12+ characters.
• Change the password if you ever shared it and don't want them connected anymore.
• Open the Devices tab — see anything you don't recognize? Power down your gear one at a time; whatever's left is worth investigating.

Find an unknown device you can't account for? Rotate the password. Every device of yours will need the new one.
""",
                """
The short version: with a strong WPA2 password, no, they can't. With a default-weak password or "Open" Wi-Fi, absolutely yes.

The Devices tab is your audit. Walk through it and identify every device. The unknowns are usually a randomized-MAC iPhone or a smart bulb you forgot about — but if you genuinely can't place it, rotate the password.
"""
            ],
            followUps: [
                "Many phones and laptops use a randomized 'Private' MAC address on each network for privacy — they can look unfamiliar in a scan but they're almost always your own devices.",
                "If you're really paranoid, most routers can show you the connection log. You'll see every device that's authenticated, with timestamps."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "modem-vs-router",
            question: "What's the difference between a modem and a router?",
            keywords: ["modem", "difference", "between", "vs", "versus", "gateway", "combo", "separate"],
            answers: [
                """
They do different jobs, even when they're in the same box:

• Modem — translates the ISP's signal (coax, fiber, DSL) into regular internet. One cable in, one cable out. No Wi-Fi.
• Router — takes the modem's internet, shares it with your devices, runs Wi-Fi, assigns addresses, handles the firewall.
• Gateway / combo — one device that does both. Common with rentals from the ISP.

Separate units beat the combo box because you can upgrade the router independently. If your ISP rents you a combo for $10–15/month, buying your own often pays for itself in a year.
""",
                """
Modem talks to the outside world. Router talks to your devices. Combos do both in one box but are usually compromised on the router side — middling Wi-Fi, no settings to tinker with, no upgrades.

If you can swap to your own router, you'll get better Wi-Fi and stop paying the rental fee.
"""
            ],
            followUps: [
                "When you swap, put the ISP combo unit into 'bridge mode' so it stops doing routing. Otherwise you have two routers fighting each other ('double NAT').",
                "Fiber installs sometimes don't have a separate modem — the optical network terminal (ONT) on the wall does that job, and you just plug your router into it."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "video-calls",
            question: "How do I make video calls less choppy?",
            keywords: ["zoom", "teams", "facetime", "meet", "webex", "call", "video", "choppy", "freezing", "frozen", "quality", "meeting", "glitching"],
            answers: [
                """
Video calls need stable upload, low latency, and no competing traffic. Try:

• Get close to the router on 5 GHz. Weak signal kills video calls first.
• Permanent setup? Plug into Ethernet. Even $20 of cable changes everything.
• Pause cloud backups during important meetings.
• Turn off other devices that might be streaming or downloading.
• Close unused browser tabs — some quietly pull a lot of bandwidth.
• You want at least 3–5 Mbps upload and ping under 60 ms for smooth HD calls.
""",
                """
Order of impact: Ethernet > great 5 GHz signal > pausing background uploads > closing tabs.

Video calls are uniquely sensitive because they care about both bandwidth and latency in both directions, simultaneously. Anything wobbly on the network shows up immediately.
"""
            ],
            followUps: [
                "If only one app stutters, it might be the app's servers, not your network. Test by switching from Zoom to FaceTime to Meet — same problem on all three is your end, only on one is theirs.",
                "Bluetooth headphones can also stutter for completely different reasons (interference with 2.4 GHz). If audio drops but video looks fine, try a wired headset."
            ],
            category: "Streaming"
        ),
        AssistantQA(
            topic: "dns",
            question: "Should I change my DNS to Google or Cloudflare?",
            keywords: ["dns", "cloudflare", "1.1.1.1", "8.8.8.8", "opendns", "quad9", "resolver"],
            answers: [
                """
Changing DNS can help in a few specific ways:

• Speed — Cloudflare (1.1.1.1) or Google (8.8.8.8) is often faster than your ISP's, especially when the ISP's is overloaded.
• Privacy — Cloudflare and Quad9 don't log browsing the way some ISPs do.
• Reliability — public DNS rarely goes down; ISP DNS occasionally does.

Set it once on the router and every device on your Wi-Fi uses it. Or set it per-device if you only want it on your phone or laptop.

Realistically the speed boost is tens of milliseconds, not a game-changer. Privacy-wise, it's a free win.
""",
                """
DNS is the phonebook for the internet. Switching from your ISP's phonebook to Cloudflare's is mostly a privacy decision; you stop your ISP from logging every domain you visit.

Speed-wise, it's usually a wash. The exception is some ISPs whose DNS is genuinely slow or overloaded — there, switching feels meaningfully snappier.
"""
            ],
            followUps: [
                "Quad9 (9.9.9.9) is the privacy/security pick — it actively blocks known-malicious domains.",
                "If you want family-safe DNS that blocks adult content network-wide, Cloudflare Families (1.1.1.3) or OpenDNS FamilyShield (208.67.222.123) are the easiest options."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "parental-controls",
            question: "How do I set up parental controls?",
            keywords: ["parental", "kids", "children", "block", "blocking", "filter", "filtering", "schedule", "bedtime", "limit", "limits", "content"],
            answers: [
                """
You've got three layers to work with:

• Router-level — most modern routers (Eero, Nest, Orbi, ASUS, TP-Link) have parental controls in their app. Pause Wi-Fi per device, set bedtimes, filter categories.
• DNS filtering — switch to OpenDNS FamilyShield (208.67.222.123) or Cloudflare Families (1.1.1.3) to block adult and malicious sites network-wide.
• Device-level — iOS Screen Time and Google Family Link give you app limits, downtime, and site filters that follow the device off Wi-Fi.

Best setup is usually router-level bedtime/pause + on-device Screen Time. The combo is tough to bypass.
""",
                """
Layer them. Don't rely on just one — kids will find the gap.

Router pause is the easiest "off button" for the whole device. DNS filtering catches adult sites everywhere. Screen Time / Family Link handle apps and time limits.
"""
            ],
            followUps: [
                "If a kid's phone is on cellular too, router-only controls won't reach it. Device-level Screen Time is the only thing that follows the phone everywhere.",
                "Eero and Nest both have particularly good parental control apps if you're shopping for a router and these features matter to you."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "iot-load",
            question: "Do smart home devices make my Wi-Fi slow?",
            keywords: ["smart", "iot", "home", "bulbs", "plugs", "camera", "cameras", "alexa", "echo", "many", "too", "devices", "overload", "smarthome"],
            answers: [
                """
Individually, no. As a pile, sometimes yes:

• Most smart plugs, bulbs, and sensors use tiny amounts of bandwidth — they sit idle most of the time.
• The real cost is connection count. Older routers struggle past ~20–30 simultaneous clients.
• Smart cameras are the exception — 1080p streaming to the cloud uses 1–2 Mbps each, 24/7.
• Many IoT devices only speak 2.4 GHz, which crowds that band fast.
• Devices tab will show you the total. 30+ IoT? A mesh system or Wi-Fi 6 router will handle them far better than a 5-year-old single unit.

Bonus: put IoT stuff on a guest network so a hacked smart bulb can't reach your laptop.
""",
                """
Cameras are the big-bandwidth offender. Twenty smart bulbs combined use less than one Ring doorbell.

The bigger issue with a lot of IoT is the connection count, not the bandwidth. Older routers were never designed for 40+ simultaneous clients.
"""
            ],
            followUps: [
                "Wi-Fi 6 was designed for households like this. It uses OFDMA to talk to many quiet devices at once instead of one at a time.",
                "If you're seeing your camera drop and reconnect constantly, the camera's signal is weak. A mesh node nearby usually fixes it."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "rooms-vary",
            question: "Why is my Wi-Fi fine in some rooms but not others?",
            keywords: ["rooms", "room", "corners", "upstairs", "downstairs", "basement", "garage", "outside", "backyard", "deadzone", "dead", "weak"],
            answers: [
                """
Classic signal drop. Wi-Fi doesn't pass through materials evenly:

• Concrete, brick, and stone walls block a lot of signal.
• Metal (filing cabinets, fridges, mirrors) reflects it.
• Floors with rebar or radiant heating kill vertical coverage.
• Water — aquariums, water heaters — absorbs 2.4 GHz hard.

What to do:

• Move the router more centrally, higher, out of enclosures.
• Run the Survey tab — it shows you exactly where the weak spots are on a floor plan.
• If a dead zone persists after good placement, a mesh node in that area fixes it.
• One far corner only? A single extender may do, but expect it to feel slower.
""",
                """
Wi-Fi cones outward from the router, and every wall, floor, and big metal object eats into that cone. The further and more obstructed a room is, the worse it gets.

Survey the space (Survey tab). I'll mark exactly which rooms are good, fair, and dead. Then we can talk fixes that target the actual problem zones instead of guessing.
"""
            ],
            followUps: [
                "Brick chimneys, kitchen appliances, and tile-on-concrete bathrooms are the three biggest signal killers in most homes I've seen.",
                "If the dead zone is a single far corner with no walls in the way — that's just distance. Mesh node, period."
            ],
            category: "Coverage"
        ),
        AssistantQA(
            topic: "vpn",
            question: "Should I use a VPN on my home Wi-Fi?",
            keywords: ["vpn", "tunnel", "encrypt", "encryption", "nordvpn", "expressvpn", "proton", "hide", "anonymity"],
            answers: [
                """
On your own home Wi-Fi, a VPN is usually optional. Your traffic is already encrypted between you and the router, and between your device and any HTTPS site. What a VPN changes:

• Hides your traffic from your ISP. Useful if you don't want them logging.
• Masks your IP from the sites you visit.
• Lets you pretend to be in another country for streaming.

What it costs:

• Most VPNs noticeably slow down your connection (especially upload).
• Ping goes up — bad for gaming and video calls.
• Some banks and streaming services block known VPN IPs.

On public Wi-Fi (cafés, airports), a VPN is more useful. At home, it's a privacy choice, not a security must.
""",
                """
Real talk: at home, the security argument for a VPN is weak — HTTPS already encrypts almost everything, and your ISP is the only one snooping anyway. The privacy argument is real if you don't trust your ISP with your browsing history.

If you do run one, get one with WireGuard support. The ping/speed cost is way smaller than legacy VPN protocols.
"""
            ],
            followUps: [
                "Free VPNs are almost always worse for privacy than your ISP — they need to make money somehow, and that 'somehow' is usually selling your data.",
                "A VPN doesn't help with malware, phishing, or weak passwords. It changes who sees your traffic in transit, nothing more."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "hidden-ssid",
            question: "Should I hide my Wi-Fi network name?",
            keywords: ["hide", "hidden", "ssid", "broadcast", "invisible", "stealth", "name"],
            answers: [
                """
Short answer: don't bother. "Hiding" the SSID feels like a security win, but it isn't:

• Anyone with a free Wi-Fi scanning app can still see hidden networks — they just don't show the name.
• Your phone has to shout the hidden name everywhere it goes, which is actually worse for privacy.
• Some devices (printers, smart gadgets) struggle to join hidden networks.

Real security comes from a strong password, WPA2/WPA3, updated firmware, and turning off WPS. Those protect you. Hiding the name doesn't.
""",
                """
Security through obscurity that doesn't actually obscure anything. Skip it.

Spend the same five minutes turning off WPS, updating firmware, and rotating to a longer password — those moves actually matter.
"""
            ],
            followUps: [
                "Naming your SSID something fun ('PrettyFlyForAWiFi') is fine and doesn't affect security one way or the other.",
                "Just don't put your address or unit number in the SSID. That's the only naming choice that's actually a security issue."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "port-forwarding",
            question: "How do I port forward for a game or server?",
            keywords: ["port", "forward", "forwarding", "nat", "open", "host", "minecraft", "strict", "moderate"],
            answers: [
                """
Port forwarding lets incoming connections reach a specific device on your network. Rough steps:

• Give the device a static local IP (DHCP reservation in the router admin) so the rule keeps pointing at the right machine.
• In the router admin page, find "Port Forwarding" (sometimes under "NAT" or "Firewall").
• Add a rule: external port(s) → internal IP → internal port(s) → protocol (TCP, UDP, or both).
• Save, then test with canyouseeme.org or the game's own network test.

Safer alternatives:

• UPnP — many games/apps open ports automatically.
• For consoles showing "strict NAT," enabling UPnP usually fixes it without manual port forwarding.
• Only forward what you need. Every open port is exposed to the internet.
""",
                """
The two-step shortcut for most people: enable UPnP in the router, restart the device having NAT issues. That covers most consoles and games.

Manual port forwarding is for when UPnP isn't enough or isn't trusted (some routers have buggy UPnP). The recipe: reserve the device's IP, open the right ports for that IP, test from outside the network.
"""
            ],
            followUps: [
                "If you're hosting a game server long-term, point a dynamic-DNS hostname at your home IP so friends don't have to memorize it.",
                "Never forward port 22, 80, 443, or 3389 to a home device unless you really know what you're doing — those are heavily scanned by attackers."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "speed-units",
            question: "What do download and upload speeds actually mean?",
            keywords: ["download", "upload", "speed", "mbps", "bandwidth", "definition", "meaning", "explain", "what"],
            answers: [
                """
Download is data coming to you (streaming, web pages, game downloads). Upload is data leaving you (sending email, posting photos, video calls, livestreaming).

Rough numbers that matter:

• 25 Mbps download — enough for one 4K stream or a household of basic browsing.
• 100+ Mbps download — comfortable for multiple 4K streams and busy households.
• 5 Mbps upload — enough for HD video calls.
• 25+ Mbps upload — helpful if you stream, upload big files, or have cloud backups.

Speeds are in megabits per second (Mbps). File sizes are in megabytes (MB). 1 MB = 8 Mb, so a 100 Mbps connection downloads roughly 12 MB per second, not 100.
""",
                """
The bit-vs-byte gotcha trips up almost everyone. ISPs sell speeds in megabits (Mbps). Files are sized in megabytes (MB). One byte is eight bits. So divide your Mbps by 8 to estimate real-world MB/s.

A 1000 Mbps "gigabit" plan downloads roughly 125 MB per second of file. Not 1000.
"""
            ],
            followUps: [
                "1080p Netflix wants ~5 Mbps. 4K Netflix wants ~25. 8K wants ~100. Most households never need more than a 300 Mbps plan no matter what marketing tells them.",
                "Latency (ping) is independent of speed. You can have a 1 Gbps plan with terrible latency and a 50 Mbps plan that feels snappy."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "guest-network",
            question: "What's a guest network and should I use one?",
            keywords: ["guest", "visitor", "friends", "separate", "isolation"],
            answers: [
                """
A guest network is a second Wi-Fi name your router broadcasts that's isolated from your main one. Devices on the guest network can reach the internet but can't talk to your phones, laptops, printers, or smart-home gear.

You should use one if:

• Friends or family visit and want Wi-Fi — keeps their (possibly infected) devices away from yours.
• You have lots of cheap smart-home gadgets — put them on the guest network so a compromised bulb can't pivot to your laptop.
• You run a small business from home — keep customers off your work devices.

Almost every router from the last 10 years supports it.
""",
                """
Two great use cases: visitors and IoT. The visitor one is obvious — give them internet without giving them access to your stuff. The IoT one is underused — most cheap smart bulbs and plugs have terrible security, and an isolated guest network keeps them sandboxed.

It's usually a five-minute setup in the router admin page.
"""
            ],
            followUps: [
                "Some routers also have an 'IoT network' option that's similar to guest but tuned for 2.4-GHz-only devices. Same idea, slightly cleaner.",
                "Give the guest network a different password and rotate it occasionally. It's the one you'll share most often."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "mesh-vs-router",
            question: "Should I get one big router or a mesh kit?",
            keywords: ["mesh", "vs", "single", "router", "big", "powerful", "antennas"],
            answers: [
                """
The instinct is "more antennas = more better." It's actually the opposite for a lot of homes.

• Single router with many antennas — works great in a one-room apartment. Doesn't fix walls or distance.
• Mesh kit — multiple nodes spread around the home. Way better at coverage, since every weak spot gets its own access point nearby.

If your home has more than a couple problem rooms, mesh wins by a mile. If you're in a small apartment, save the money and get one good single router.
""",
                """
A bigger antenna doesn't push through walls any better. Once you've got a brick wall or a long hallway, no amount of "Wi-Fi 6 with 8 streams" beats just having a second access point on the other side.

That's mesh's whole pitch. For most homes over ~1500 sqft, mesh is the right answer.
"""
            ],
            followUps: [
                "Wired backhaul is the cheat code for mesh. If you can run Ethernet between mesh nodes, throughput at far nodes is way higher.",
                "Eero, TP-Link Deco, and Asus ZenWiFi are the popular kits right now. All three are fine — just pick one with the coverage rating that matches your sqft."
            ],
            category: "Coverage"
        ),
        AssistantQA(
            topic: "ethernet",
            question: "Should I run Ethernet for some devices?",
            keywords: ["ethernet", "wired", "cable", "rj45", "lan", "cat6", "cat5", "plug"],
            answers: [
                """
For anything that doesn't move, yes. Ethernet beats Wi-Fi at literally every metric: lower latency, higher throughput, fewer drops, no airtime contention.

Best candidates:

• Desktop PC / gaming console — ping drops by 10–30 ms.
• Smart TV — no more buffering.
• Home office — rock-steady video calls.
• Mesh node — wired backhaul transforms the kit.

A $15 Cat6 cable to a stationary device is the highest-ROI Wi-Fi upgrade most people can make.
""",
                """
The unsexy answer that consistently wins: pull a cable. Wi-Fi is a workaround for not having one. Anything bolted in place benefits from Ethernet.
"""
            ],
            followUps: [
                "If running cable through walls is a nightmare, MoCA (Ethernet over coax) and powerline adapters are decent alternatives. Faster than Wi-Fi at long distances, slower than real Cat6.",
                "Use Cat6 or better. Cat5e works at gigabit but you may as well buy the slightly newer cable for the same price."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "channel-interference",
            question: "How do I check Wi-Fi channel interference?",
            keywords: ["channel", "channels", "interference", "neighbor", "crowded", "overlap"],
            answers: [
                """
Most consumer routers default to 'Auto' for channel selection but get it wrong frequently — they pick a channel that was clear at boot and never re-check.

What to do:

• In the router admin, manually set 2.4 GHz to channel 1, 6, or 11. Nothing else. Those are the only non-overlapping channels.
• On 5 GHz, just leave it on Auto with a wider 80 MHz channel width — there's so much spectrum that interference is rarely the issue there.
• If 2.4 GHz feels crowded no matter what, that's apartment life. The fix is to push everything that can handle it onto 5 GHz.
""",
                """
Apartment buildings are the worst offenders — twenty Wi-Fi networks fighting over the same 2.4 GHz channels. There's no winning that fight; the answer is to use 5 GHz, which has way more channels and shorter range so interference is rarer.

If you must stay on 2.4, channels 1, 6, or 11 are the only ones that don't bleed into each other.
"""
            ],
            followUps: [
                "Bluetooth, baby monitors, microwaves, and old cordless phones all jam 2.4 GHz too. Sometimes the interferer isn't another Wi-Fi network at all.",
                "Some Wi-Fi 6 routers handle interference much better via 'BSS coloring,' which lets nearby networks share the same channel without stepping on each other."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "smart-tv-slow",
            question: "Why is my smart TV slower than my phone on the same Wi-Fi?",
            keywords: ["smart", "tv", "television", "slower", "phone", "compared"],
            answers: [
                """
Three usual suspects:

• The TV's Wi-Fi chip is older than your phone's. Many TVs ship with a Wi-Fi 4 / 802.11n radio that caps around 100 Mbps regardless of plan.
• The TV is on 2.4 GHz when it should be on 5 GHz. Some TVs hide this in deep settings.
• The TV is far from the router. Phones get used closer-up; TVs sit in fixed corners.

Easy fix when possible: plug Ethernet into the TV. That sidesteps all three.
""",
                """
TVs lag behind phones on Wi-Fi quality by about a generation. That's why phones often feel snappier in the same room — even if the apps are similar.

If your TV has an Ethernet port and you can get a cable to it, do that. It's the single best smart-TV upgrade.
"""
            ],
            followUps: [
                "If the streaming app itself feels slow loading the home screen, that's the TV's CPU, not the network. A $50 streaming stick (Apple TV, Fire TV, Roku) often outperforms a 5-year-old smart TV's built-in apps.",
                "Older Roku and Fire TV sticks have weak antennas. Upgrading to a more recent stick can meaningfully improve streaming on the same network."
            ],
            category: "Streaming"
        ),
        AssistantQA(
            topic: "router-admin",
            question: "How do I log into my router admin page?",
            keywords: ["admin", "login", "password", "settings", "configure", "192.168", "page"],
            answers: [
                """
The router admin page lives at the gateway IP of your network. Most often:

• 192.168.1.1
• 192.168.0.1
• 10.0.0.1

Type that into a browser, log in with the username/password on the sticker on the bottom of the router (or whatever you set when you first installed it).

If you don't know the gateway, the Speed tab shows your current router's IP at the top of the topology card. Use that.
""",
                """
Type your router's IP into a browser. Don't know it? Open the Speed tab — the topology card shows it at the top.

Login is on a sticker on the underside of the router. If you've never changed it, change it now while you're in there.
"""
            ],
            followUps: [
                "If the sticker login doesn't work, someone (you, probably, at some point) changed the password. A factory reset (hold the recessed reset button 10 seconds) is the only way back in — but it wipes all settings.",
                "Newer routers (Eero, Nest, etc.) don't have a web admin page — they only configure through their phone app."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "iphone-private-mac",
            question: "What is 'Private Wi-Fi Address' on my iPhone?",
            keywords: ["private", "address", "randomized", "mac", "iphone", "android", "tracking"],
            answers: [
                """
Modern iPhones, iPads, recent Androids, recent macOS, and Windows 11 use a random MAC address per Wi-Fi network. It's a privacy feature — networks can't track you across locations using your hardware fingerprint.

You'll see it in iOS Settings → Wi-Fi → (your network) → Private Wi-Fi Address.

The downside: in a network scan, every Apple device looks 'unknown' because the manufacturer can't be looked up from a random MAC. That's normal. The Devices tab labels these as "Uses Private Wi-Fi Address" so you know it's not a stranger.
""",
                """
It's a privacy thing, on by default since iOS 14 / Android 10. Each Wi-Fi network sees your phone with a different fake MAC. Networks can't track you between coffee shops.

In a scan, those devices look manufacturer-less. Almost always your own phones.
"""
            ],
            followUps: [
                "You can turn it off per-network on iOS if you really need a stable MAC for parental controls or a captive portal. Settings → Wi-Fi → tap the network → toggle off.",
                "Smart bulbs, plugs, and old TVs don't randomize. Their hardware MAC is exactly the same every time."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "5g-vs-wifi",
            question: "Should I use 5G cellular instead of my home Wi-Fi?",
            keywords: ["5g", "cellular", "lte", "instead", "hotspot", "tether", "fallback"],
            answers: [
                """
For most homes, no — Wi-Fi over a fiber/cable plan beats 5G in price-per-GB and in stable latency. But there are real cases for 5G home internet:

• Rural — when wired internet is DSL-only, 5G can be far faster.
• Renters / temporary housing — no install fees, no lock-in.
• Backup — keep a 5G hotspot for outages on your main ISP.

The catch: 5G plans throttle after a data cap, and 5G upload is usually weaker than fiber upload. Don't expect to host a server on it.
""",
                """
5G home internet is a legitimate alternative to cable in some markets — especially T-Mobile and Verizon. Comparable download speeds, fewer install hassles, no annual contract.

Latency is the trade-off. 5G ping floors are higher and more variable than wired connections. Gamers and competitive video callers will notice.
"""
            ],
            followUps: [
                "Many phones can act as a Wi-Fi hotspot for your laptop in a pinch. Useful when home Wi-Fi goes down — though watch your phone plan's hotspot quota.",
                "If your main internet drops constantly, a separate 5G modem with auto-failover is much nicer than tethering manually."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "isp-throttling",
            question: "Is my ISP throttling me?",
            keywords: ["throttle", "throttling", "shaping", "deprioritize", "slow", "after", "data", "cap"],
            answers: [
                """
A few signs that point to throttling vs a normal slowdown:

• Speed Tests look fine, but specific apps (streaming, gaming, video calls) feel slow.
• Speeds drop sharply after a certain monthly data total.
• A VPN suddenly makes things faster — that's the smoking gun, since the ISP can't see what's inside the tunnel to slow it down.
• Your plan documentation mentions "after X GB, speeds may be reduced."

If you suspect it, run Speed Tests at a few different times of day, with and without a VPN. If the with-VPN number is consistently higher, that's selective throttling.
""",
                """
The classic test: if a VPN actively makes you faster on a specific service, your ISP is throttling that service. Real network slowdowns hit the VPN traffic too.

Read your plan's fine print. 'Unlimited' often means 'unlimited at low priority once you cross 1.2 TB.'
"""
            ],
            followUps: [
                "Mobile carriers throttle video to 480p on cheaper plans by default. There's usually a setting to turn that off if you want full-quality streaming.",
                "Net-neutrality rules vary by country. In the US, ISPs are technically allowed to throttle as long as they disclose it."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "old-router",
            question: "How long should a router last?",
            keywords: ["old", "age", "replace", "lifespan", "years", "ancient", "outdated"],
            answers: [
                """
Plan on 3 to 5 years for a consumer router. After that, you're running into:

• No more firmware updates, including security patches.
• A Wi-Fi standard older than your devices.
• Capacitors and antenna gain quietly degrading.

If your router is 5+ years old and you've been compensating with reboots or extenders, replacing it usually fixes more than the upgrade itself promises.
""",
                """
Five years is the rule of thumb. Past that, the chips on the board are aging, the manufacturer probably stopped pushing security updates, and the Wi-Fi generation is two behind your phone.

If yours is older than that and the household has changed (more devices, faster internet plan, more 4K streaming), the router is almost certainly the bottleneck.
"""
            ],
            followUps: [
                "Manufacturer firmware-update support is usually 3–5 years. Check the manufacturer's site for your exact model — if updates stopped two years ago, it's a security risk on top of being slow.",
                "ISP-rented routers tend to be older and weaker than what you can buy yourself. Returning the rental and buying your own is almost always a win."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "open-wifi",
            question: "Is using public Wi-Fi safe?",
            keywords: ["public", "cafe", "coffee", "airport", "hotel", "starbucks", "open", "free"],
            answers: [
                """
Modern public Wi-Fi is safer than its reputation, but a few rules still help:

• Stick to HTTPS sites. Almost everything is HTTPS now, and that means your traffic is encrypted even on open Wi-Fi.
• Avoid logging into anything sensitive (banking, work email) on networks you don't know — not because of magic packet sniffing, but because of fake captive portals and lookalike SSIDs.
• A reputable VPN is genuinely useful here. It hides your traffic from the network operator entirely.
• Disable file sharing and AirDrop in 'Everyone' mode while you're on it.

The old 'someone could steal your password from a coffee shop' threat is mostly obsolete. The newer threat is fake networks and phishing pop-ups.
""",
                """
The threat model has shifted. In 2010 you were worried about packet sniffing on open networks. In 2026 almost everything is HTTPS, so the network operator can't see what's inside your traffic.

The real risk is fake networks ('Coffee_Free_WiFi') that route you through a malicious portal. Verify the SSID with the staff before joining, and ignore login pop-ups that look off.
"""
            ],
            followUps: [
                "If you do use public Wi-Fi a lot, enable the 'Limit IP Address Tracking' setting on iOS and the equivalent privacy options on other devices.",
                "Tethering off your phone is almost always safer than joining an unknown public network."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "what-is-jitter",
            question: "What is jitter and why does it matter?",
            keywords: ["jitter", "variance", "consistent", "stable", "varying"],
            answers: [
                """
Jitter is the variation in your latency between consecutive measurements. If your ping fluctuates wildly between 20 ms and 120 ms, your jitter is high — even though the average looks fine.

Why it matters:

• Voice calls and gaming need consistency more than they need a low average.
• 80 ms of steady ping feels better than a 30 ms average that spikes to 200.
• High jitter is usually a Wi-Fi issue (signal strength dipping) or a congested link.

The Speed Test surfaces jitter alongside ping for exactly this reason. Anything under 5 ms is excellent. Over 20 ms tends to be felt.
""",
                """
Jitter is the unsteadiness of your ping. A connection with a 40 ms average ping and 5 ms jitter feels rock-solid. The same average with 50 ms jitter feels broken.

It usually points to weak Wi-Fi signal, a contended channel, or a congested ISP link.
"""
            ],
            followUps: [
                "Buffering, audio glitches, and rubber-banding in games are jitter symptoms more often than they're outright bandwidth symptoms.",
                "A wired connection drops jitter dramatically. That's a big part of why Ethernet feels qualitatively better than fast Wi-Fi for gaming."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "wifi-security-types",
            question: "What's the difference between WEP, WPA, WPA2, and WPA3?",
            keywords: ["wep", "wpa", "wpa2", "wpa3", "encryption", "protocol", "type"],
            answers: [
                """
Wi-Fi security protocols, oldest to newest:

• WEP — broken since 2001. Don't use it.
• WPA — also obsolete, vulnerable to known attacks.
• WPA2 — the standard for 15+ years. Still strong with a long password.
• WPA3 — current best. Resistant to offline password guessing.

If your router supports WPA3, use it. Otherwise WPA2-PSK (AES) is fine. Anything older than WPA2 should be considered "open" — the encryption no longer protects you.
""",
                """
WPA2 with a strong password is still safe. WPA3 is better. Anything older is a security hole.

Most routers default to "WPA2 / WPA3 mixed" mode now, which is the right setting — it lets older devices join with WPA2 while newer ones get WPA3.
"""
            ],
            followUps: [
                "Some old smart-home devices only speak WPA2-PSK or even WPA. If you can't get them off WPA, put them on a separate guest network so they don't drag down your main one's security.",
                "WPA3 specifically protects against offline brute-force attacks where someone captures your handshake and tries passwords later. WPA2 is theoretically vulnerable to that."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "speed-test-fluctuation",
            question: "Why are my speed test results different every time?",
            keywords: ["speed", "test", "different", "varies", "fluctuates", "inconsistent", "sometimes", "results"],
            answers: [
                """
Speed tests measure many things at once, and any of them can vary:

• Server load — even Cloudflare POPs see uneven load minute-to-minute.
• Your Wi-Fi signal — moving 6 feet can change the result.
• Other devices on your network — every active stream eats from the same pipe.
• ISP-level congestion — neighborhood usage cycles through the day.

The Speed tab tries to mitigate this with multiple parallel streams and a fixed test window. But for the most accurate reading, plug a laptop directly into the router via Ethernet and run the test 3–4 times.
""",
                """
Variance is normal. A single test is a snapshot, not gospel. Run two or three back to back and look at the median — that's your real number.

If the variance is huge (e.g., 50 Mbps once and 500 the next), something on your network or your ISP is wobbly.
"""
            ],
            followUps: [
                "Run a Speed Test before you start a game session and another at the same time tomorrow. Big differences across days at the same hour usually means ISP problems.",
                "The Server Selection step in the Speed tab tells you which Cloudflare POP you're hitting. If it's far away, you can sometimes get better numbers by manually choosing a closer one in another tool."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "where-to-test",
            question: "Where in my home should I test Wi-Fi speed?",
            keywords: ["where", "test", "location", "spot", "best", "where", "should"],
            answers: [
                """
Test in the rooms where you actually use it. Speed near the router tells you what your plan delivers; speed in the bedroom tells you what your Wi-Fi delivers there.

A good routine:

• Test next to the router (this is your ceiling).
• Test in your most-used room (this is what you actually feel).
• Test in your worst spot (this defines whether you need a mesh).
• Better still — walk a Survey to map every room at once.
""",
                """
Don't test in one place. Test in every place you actually use Wi-Fi, including the rooms you suspect are bad. The differences tell you whether you have a plan problem (everywhere is slow) or a coverage problem (only some rooms are slow).

The Survey tab does this all at once on a floor plan, which is way faster than running individual tests.
"""
            ],
            followUps: [
                "If wired speed at the router is fine but Wi-Fi anywhere else is slow, the router is the limit. If wired is also slow, the ISP is the limit.",
                "For laptops, run the test plugged in if you can. Battery saver mode can throttle the Wi-Fi radio."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "wifi-vs-cellular",
            question: "When does my phone switch from Wi-Fi to cellular?",
            keywords: ["switch", "cellular", "automatic", "wifi", "assist", "lte"],
            answers: [
                """
Both iOS and Android have logic to bail out of bad Wi-Fi onto cellular automatically. iOS calls it 'Wi-Fi Assist'; Android has similar settings under 'Mobile data always on.'

It usually fires when:

• Wi-Fi signal drops below a threshold.
• Specific apps fail to reach a server even though Wi-Fi shows connected.
• You're on a captive-portal network you haven't logged into.

The downside: if it fires on a busy plan, your data usage spikes. The upside: you stop seeing 'Wi-Fi connected, no internet' lockups.
""",
                """
iOS Wi-Fi Assist and Android's equivalent are why your phone sometimes says it's on Wi-Fi but is actually using LTE. Helpful in dead zones, painful for data plans.

You can turn it off in Settings if data caps are a concern.
"""
            ],
            followUps: [
                "On iOS, Settings → Cellular → scroll all the way down → 'Wi-Fi Assist'. There's also a per-app data toggle if a specific app keeps eating cellular.",
                "If your phone keeps switching to cellular even at home, that's a sign your Wi-Fi has a dead zone in the spot you sit most often."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "tip-prevention",
            question: "How do I keep my Wi-Fi healthy long-term?",
            keywords: ["healthy", "maintain", "maintenance", "longterm", "long-term", "keep", "keeping"],
            answers: [
                """
A boring routine that prevents 90% of problems:

• Reboot the router every couple of weeks.
• Apply firmware updates as soon as they show up in the admin app.
• Re-survey the space if you rearrange a room or change router placement.
• Audit the Devices tab once a month — anything new and unidentifiable should be looked at.
• Replace the router every 3–5 years; don't wait for it to fail.

That's it. Wi-Fi isn't supposed to be exciting.
""",
                """
Treat it like the smoke alarm in your house: set a reminder, do a basic check every few weeks, replace the hardware every few years. Boring, predictable, never an emergency.

Most "my Wi-Fi is suddenly broken" calls trace back to skipping one of those steps for two years.
"""
            ],
            followUps: [
                "I can ping you with re-survey reminders at 30, 90, and 180 days after every survey you complete. That's already on if you've granted notification permissions.",
                "Keep the router cool. A bookshelf above eye level, away from sunlight, is ideal. The hotter it runs, the shorter its life."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "what-is-bandwidth",
            question: "What's the difference between bandwidth and speed?",
            keywords: ["bandwidth", "throughput", "capacity", "vs", "explain", "speed"],
            answers: [
                """
Bandwidth is the size of the pipe; speed is how much actually flows through it.

Your plan promises a maximum bandwidth — say, 500 Mbps. The speed you actually get depends on the device, the Wi-Fi signal, the server you're talking to, and how many other things are using the same pipe.

People use 'speed' and 'bandwidth' interchangeably in casual conversation, and that's fine. Just remember: more bandwidth doesn't help if the bottleneck is somewhere else (Wi-Fi, server, distance).
""",
                """
Bandwidth = capacity. Speed = current observed throughput. They're related but not the same.

If you're getting 80 Mbps on a 500 Mbps plan, paying for more bandwidth won't change anything — something else in the chain is the actual ceiling.
"""
            ],
            followUps: [
                "The 'last mile' (your house to the local node) is usually the bottleneck on cable plans. Once your traffic gets to the node, the rest of the internet is huge.",
                "Latency and bandwidth are independent. A high-bandwidth/high-latency satellite link feels different from a low-bandwidth/low-latency fiber link."
            ],
            category: "Speed"
        )
    ]

    /// Lookup by topic key — used by the engine when serving follow-ups
    /// against the most recently discussed topic.
    static let byTopic: [String: AssistantQA] = {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.topic, $0) })
    }()
}

// MARK: - Intent

/// What the user appears to be doing in this turn. Drives the reply
/// composition path. Anything that isn't recognized as a higher-level
/// intent falls through to QA matching, then to a fallback.
enum AssistantIntent {
    case greeting
    case thanks
    case bye
    case identity              // "who are you", "are you AI"
    case capabilities          // "what can you do", "help"
    case mood                  // "how are you", insults, compliments
    case livePing              // "what's my ping/latency now"
    case liveSpeed             // "what's my speed/download"
    case liveSurvey            // "how's my survey", "what's my grade"
    case liveDevices           // "how many devices"
    case liveTopology          // "what's my router IP", "where's my gateway"
    case liveSummary           // "give me the rundown", "how's my network"
    case followUp              // "tell me more", "what else"
    case qa(AssistantQA)
    case fallback
}

/// Holds whatever Klaus needs to remember between turns. Today this is
/// just the most recently answered topic so follow-ups can resolve to
/// "tell me more about X." Kept as a value so it's easy to test.
struct AssistantTurnMemory {
    var lastTopic: String?
    var followUpsServed: Set<String> = []   // per-topic delivered follow-ups
}

// MARK: - Engine

/// The core reasoning surface for Klaus's chat. Everything is pure
/// functions over the knowledge base + a `KlausChatContext` snapshot —
/// no LLM, no network, no persisted state. The engine is intentionally
/// plain Swift so chat behavior is debuggable, deterministic for any
/// fixed RNG, and fast enough to feel instant.
enum WiFiAssistantEngine {
    private static let maxInputLength = 400

    private static let stopwords: Set<String> = [
        "the", "is", "a", "an", "to", "of", "and", "or", "for", "on", "in", "at", "by",
        "it", "i", "my", "me", "we", "our", "you", "your", "this", "that", "these", "those",
        "do", "does", "did", "be", "been", "being", "was", "were", "am", "are", "have",
        "has", "had", "can", "could", "should", "would", "will", "shall", "may", "might",
        "there", "so", "if", "but", "not", "no", "as", "just", "too", "really",
        "any", "some", "much", "many", "very", "with", "from", "about", "okay",
        "ok", "please", "thanks", "thank"
    ]

    // MARK: Sanitize / tokenize

    static func sanitize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
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

    // MARK: Intent classification

    /// Pattern groups for non-QA intents. Matched against the lowercased
    /// raw string (with light normalization). Keyword search is
    /// substring-based so "hi klaus" and "hi, klaus!" both register.
    private static let greetingPatterns: [String] = [
        "hello", "hi ", "hi.", "hi!", "hi,", "hey", "yo ", "yo!", "yo.", "howdy",
        "good morning", "good afternoon", "good evening", "sup ", "sup!", "what's up", "whats up"
    ]
    private static let byePatterns: [String] = [
        "bye", "goodbye", "see ya", "see you", "later", "cya"
    ]
    private static let thanksPatterns: [String] = [
        "thanks", "thank you", "thx", "ty ", "ty.", "ty!", "appreciate", "cheers"
    ]
    private static let identityPatterns: [String] = [
        "who are you", "what are you", "are you ai", "are you an ai", "are you a bot",
        "are you a person", "are you human", "are you real", "your name", "tell me about yourself",
        "what's your name", "whats your name"
    ]
    private static let capabilityPatterns: [String] = [
        "what can you do", "help me", "help ", "help.", "help?", "help!",
        "how do you work", "how do i use", "what should i ask", "give me ideas",
        "what do you know"
    ]
    private static let moodPatterns: [String] = [
        "how are you", "you ok", "you alright", "are you good",
        "you suck", "you're dumb", "youre dumb", "you're stupid", "youre stupid", "i hate you",
        "you're awesome", "youre awesome", "you're great", "youre great", "you rock", "good bot",
        "bad bot", "love you", "you're cool", "youre cool"
    ]
    private static let followUpPatterns: [String] = [
        "tell me more", "more info", "any more", "anything else", "what else",
        "expand on", "go deeper", "elaborate", "more detail", "more details", "say more",
        "another one", "give me more", "and"
    ]
    private static let livePingPatterns: [String] = [
        "what's my ping", "whats my ping", "what is my ping", "my ping",
        "what's my latency", "whats my latency", "my latency", "ping right now",
        "current ping", "current latency", "how's my latency", "hows my latency",
        "how is my signal", "how's my signal", "hows my signal"
    ]
    private static let liveSpeedPatterns: [String] = [
        "what's my speed", "whats my speed", "what is my speed", "my speed",
        "how fast", "what speed", "download speed", "upload speed",
        "my mbps", "what mbps", "current speed"
    ]
    private static let liveSurveyPatterns: [String] = [
        "my survey", "my grade", "my score", "how was my walk",
        "survey result", "survey results", "my report", "how did i do",
        "how is my coverage", "hows my coverage", "how's my coverage"
    ]
    private static let liveDevicesPatterns: [String] = [
        "how many devices", "what devices", "list devices", "my devices",
        "what's on my network", "whats on my network", "what is on my network"
    ]
    private static let liveTopologyPatterns: [String] = [
        "my router ip", "router address", "gateway ip", "what's my gateway", "whats my gateway",
        "my ip address", "what's my ip", "whats my ip", "what is my ip", "my isp",
        "what isp", "what's my isp", "whats my isp"
    ]
    private static let liveSummaryPatterns: [String] = [
        "how's my network", "hows my network", "how is my network",
        "how's my wifi", "hows my wifi", "how is my wifi",
        "give me the rundown", "give me the summary", "summary", "rundown",
        "how am i doing", "status report", "status check"
    ]

    static func classifyIntent(rawInput: String, memory: AssistantTurnMemory) -> AssistantIntent {
        let cleaned = sanitize(rawInput).lowercased()
        guard !cleaned.isEmpty else { return .fallback }

        // Match the most specific intents first. Live queries beat
        // smalltalk so "what's my ping?" doesn't get caught by greeting
        // matchers; smalltalk beats QA so "hi" doesn't match a keyword.
        if matchesAny(cleaned, livePingPatterns) { return .livePing }
        if matchesAny(cleaned, liveSpeedPatterns) { return .liveSpeed }
        if matchesAny(cleaned, liveSurveyPatterns) { return .liveSurvey }
        if matchesAny(cleaned, liveDevicesPatterns) { return .liveDevices }
        if matchesAny(cleaned, liveTopologyPatterns) { return .liveTopology }
        if matchesAny(cleaned, liveSummaryPatterns) { return .liveSummary }

        // Follow-up only counts when there's a topic to follow up on.
        if memory.lastTopic != nil, matchesAny(cleaned, followUpPatterns) {
            return .followUp
        }

        if matchesAny(cleaned, identityPatterns) { return .identity }
        if matchesAny(cleaned, capabilityPatterns) { return .capabilities }
        if matchesAny(cleaned, moodPatterns) { return .mood }
        if matchesAny(cleaned, byePatterns) { return .bye }
        if matchesAny(cleaned, thanksPatterns) { return .thanks }
        if matchesAny(cleaned, greetingPatterns) || cleaned == "hi" || cleaned == "hey" {
            return .greeting
        }

        // QA fallback — keyword tokenization + scoring against the
        // knowledge base. Threshold is "at least one keyword overlap".
        if let qa = bestQA(for: cleaned) { return .qa(qa) }
        return .fallback
    }

    private static func matchesAny(_ text: String, _ patterns: [String]) -> Bool {
        for pattern in patterns where text.contains(pattern) { return true }
        return false
    }

    private static func bestQA(for text: String) -> AssistantQA? {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return nil }

        var bestScore = 0
        var best: AssistantQA?
        for entry in WiFiAssistantKnowledge.entries {
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

    // MARK: Reply composition

    struct AssistantReply {
        let text: String
        let relatedQuestions: [String]
        let topic: String?
    }

    static func reply(
        for intent: AssistantIntent,
        context: KlausChatContext,
        memory: AssistantTurnMemory
    ) -> AssistantReply {
        switch intent {
        case .greeting:
            return AssistantReply(
                text: composeGreetingReply(context: context),
                relatedQuestions: starterQuestions,
                topic: nil
            )
        case .thanks:
            return AssistantReply(
                text: pick(thanksReplies),
                relatedQuestions: starterQuestions.shuffled().prefix(3).map { $0 },
                topic: nil
            )
        case .bye:
            return AssistantReply(
                text: pick(byeReplies),
                relatedQuestions: [],
                topic: nil
            )
        case .identity:
            return AssistantReply(
                text: pick(identityReplies),
                relatedQuestions: ["What can you help me with?", "How's my network?", "How can I make my Wi-Fi signal better?"],
                topic: nil
            )
        case .capabilities:
            return AssistantReply(
                text: capabilitiesReply(context: context),
                relatedQuestions: starterQuestions,
                topic: nil
            )
        case .mood:
            return AssistantReply(
                text: pick(moodReplies),
                relatedQuestions: ["How's my network?", "How can I make my Wi-Fi signal better?"],
                topic: nil
            )
        case .livePing:
            return AssistantReply(
                text: livePingReply(context: context),
                relatedQuestions: ["What's a good ping for gaming?", "What is jitter and why does it matter?", "How can I make my Wi-Fi signal better?"],
                topic: "live-ping"
            )
        case .liveSpeed:
            return AssistantReply(
                text: liveSpeedReply(context: context),
                relatedQuestions: ["Why is my Wi-Fi slower than what I pay for?", "Why are my speed test results different every time?", "Where in my home should I test Wi-Fi speed?"],
                topic: "live-speed"
            )
        case .liveSurvey:
            return AssistantReply(
                text: liveSurveyReply(context: context),
                relatedQuestions: ["Do I need a Wi-Fi extender or a mesh system?", "Where should I place my router?", "Why is my Wi-Fi fine in some rooms but not others?"],
                topic: "live-survey"
            )
        case .liveDevices:
            return AssistantReply(
                text: liveDevicesReply(context: context),
                relatedQuestions: ["Is my network secure?", "What's a guest network and should I use one?", "Can my neighbors use my Wi-Fi?"],
                topic: "live-devices"
            )
        case .liveTopology:
            return AssistantReply(
                text: liveTopologyReply(context: context),
                relatedQuestions: ["How do I log into my router admin page?", "What's the difference between a modem and a router?"],
                topic: "live-topology"
            )
        case .liveSummary:
            return AssistantReply(
                text: liveSummaryReply(context: context),
                relatedQuestions: starterQuestions,
                topic: "live-summary"
            )
        case .followUp:
            return followUpReply(memory: memory)
        case .qa(let qa):
            return composeQAReply(qa: qa, context: context)
        case .fallback:
            return AssistantReply(
                text: pick(fallbackReplies),
                relatedQuestions: fallbackSuggestions(),
                topic: nil
            )
        }
    }

    // MARK: QA composition

    /// Picks an answer variant, optionally wraps it in a Klaus-voice
    /// opener / closer, and weaves in a one-line live-context hint when
    /// the topic has obvious overlap with current network state.
    private static func composeQAReply(qa: AssistantQA, context: KlausChatContext) -> AssistantReply {
        var body = pick(qa.answers)

        // Live-context overlay — for topics where the user's actual
        // numbers add a useful "and by the way" line. Klaus keeps these
        // short so they never displace the curated answer.
        if let overlay = liveOverlay(for: qa.topic, context: context) {
            body = "\(overlay)\n\n\(body)"
        }

        let dressed = dressUp(body, topic: qa.topic)
        return AssistantReply(
            text: dressed,
            relatedQuestions: relatedQuestions(for: qa),
            topic: qa.topic
        )
    }

    private static func relatedQuestions(for answered: AssistantQA, count: Int = 3) -> [String] {
        let pool = WiFiAssistantKnowledge.entries.filter { $0.id != answered.id }
        let sameCategory = pool.filter { $0.category == answered.category }.shuffled()
        let otherCategory = pool.filter { $0.category != answered.category }.shuffled()
        let ordered = sameCategory + otherCategory
        return Array(ordered.prefix(count)).map { $0.question }
    }

    // MARK: Live overlay (one-line hint that prefixes a topic answer)

    private static func liveOverlay(for topic: String, context: KlausChatContext) -> String? {
        switch topic {
        case "good-ping", "improve-signal", "what-is-jitter", "gaming-peak", "video-calls":
            if let ms = context.signalLatencyMs {
                let band = KlausChatContext.band(for: ms)
                let phrase: String
                switch band {
                case .excellent: phrase = "your latest ping reading was \(Int(ms.rounded())) ms — that's excellent"
                case .good: phrase = "your latest ping reading was \(Int(ms.rounded())) ms — solid territory"
                case .fair: phrase = "your latest ping reading was \(Int(ms.rounded())) ms — fine, but you'd feel improvement"
                case .poor: phrase = "your latest ping reading was \(Int(ms.rounded())) ms — that's into the laggy zone"
                case .awful: phrase = "your latest ping reading was \(Int(ms.rounded())) ms — that's rough; the advice below should help a lot"
                }
                return "Quick context: \(phrase)."
            }
        case "isp-mismatch", "speed-test-fluctuation", "where-to-test", "slow-upload":
            if let down = context.lastDownloadMbps, let up = context.lastUploadMbps {
                return "Quick context: your last Speed Test landed at \(formatMbps(down)) down / \(formatMbps(up)) up."
            }
        case "rooms-vary", "extender-vs-mesh", "mesh-vs-router", "router-placement":
            if let grade = context.lastSurveyGrade, let dz = context.lastSurveyDeadZoneCount {
                if dz > 0 {
                    return "Quick context: your last Survey graded \(grade) with \(dz) dead zone\(dz == 1 ? "" : "s") flagged."
                } else {
                    return "Quick context: your last Survey graded \(grade) with no dead zones — nice baseline."
                }
            }
        case "security", "neighbors", "wifi-security-types", "iot-load":
            if let count = context.deviceCount {
                let trusted = context.trustedDeviceCount ?? 0
                let unknown = max(0, count - trusted)
                if unknown > 0 {
                    return "Quick context: your last scan saw \(count) devices, \(unknown) of which aren't marked trusted yet."
                } else if count > 0 {
                    return "Quick context: your last scan saw \(count) devices and they're all marked trusted."
                }
            }
        default:
            return nil
        }
        return nil
    }

    // MARK: Voice modulation

    /// Wraps an answer body in a Klaus-flavored opener and/or closer,
    /// each rolled independently. The roll keeps short answers from
    /// getting fluffed up too much — we keep raw answers ~50% of the
    /// time, prefix only ~25%, suffix only ~15%, both ~10%.
    private static func dressUp(_ body: String, topic: String) -> String {
        var prefix: String?
        var suffix: String?
        let roll = Int.random(in: 0..<100)
        switch roll {
        case 0..<50: break                          // raw
        case 50..<75: prefix = pick(openers)        // opener only
        case 75..<90: suffix = pick(closers)        // closer only
        default: prefix = pick(openers); suffix = pick(closers)
        }

        var out = body
        if let p = prefix { out = "\(p)\n\n\(out)" }
        if let s = suffix { out = "\(out)\n\n\(s)" }
        return out
    }

    private static let openers: [String] = [
        "Beep boop — packet inspection complete.",
        "Antenna engaged. Here's what I'd try:",
        "OK let me unpack this one.",
        "Honestly? Here's the deal:",
        "Quick scan of the airwaves says:",
        "Good question. Pulling from my mental knowledge base…",
        "Spinning up the diagnostic dish.",
        "Buckle in — Klaus mode: activated.",
        "Let me give it to you straight:",
        "I get this one a lot. Here's what works:"
    ]

    private static let closers: [String] = [
        "Need me to dig deeper on any of those?",
        "Beep boop — let me know if you want more.",
        "Tap any of the suggestions to keep going.",
        "Want me to walk through any of that?",
        "Anything else I can poke at for you?",
        "I've got more if you want it — just say the word."
    ]

    // MARK: Smalltalk replies

    private static let identityReplies: [String] = [
        """
Beep boop — I'm Klaus, your WiFi Buddy. I live in your router's packets and I know *way* too much about Wi-Fi for someone with a pixel-art body. I can't make calls or browse the internet, but I can break down anything Wi-Fi-related, look at your live network state, and walk you through fixes.
""",
        """
Klaus, at your service. I'm a pixel-art robot built into WiFi Buddy. I run entirely on your phone — no cloud calls, no logging — and I can see the same speed/signal/survey/device data you can. Pretty much my whole personality is helping you make sense of all that.
""",
        """
I'm Klaus. I'm an offline assistant — no LLM, no servers, just curated knowledge and the ability to read your in-app metrics. Less impressive than ChatGPT, but I won't ever leak your data to a cloud, and I actually know the app you're using.
"""
    ]

    private static let thanksReplies: [String] = [
        "You're welcome — beep boop, mission accomplished.",
        "Anytime. Happy to help.",
        "Glad it landed. Tap a suggestion if you want to keep going.",
        "Nice. If anything else comes up, just ask.",
        "Beep boop — that's what I'm here for."
    ]

    private static let byeReplies: [String] = [
        "Catch you later. I'll be here when the network acts up.",
        "Bye for now. May your packets flow swiftly.",
        "Powering down my little antenna. See you next time.",
        "Take care. Run a Survey if anything starts feeling weird."
    ]

    private static let moodReplies: [String] = [
        "Beep boop — circuits humming, antenna calibrated. How can I help?",
        "Operating well within tolerances. What's on your mind?",
        "Doing fine — the only thing I get tired of is bad Wi-Fi advice. What can I help with?",
        "I'm a little robot in your phone — I'm always ready. What do you want to look at?",
        "Honestly? Same as always. Ready to dig into your network."
    ]

    private static let fallbackReplies: [String] = [
        """
Hmm, my little antenna didn't quite pick that one up. Try one of the suggested questions, or rephrase — I'm best with topics like signal strength, speed, security, gaming, streaming, or anything device-related.
""",
        """
That one slipped past my packet inspector. I'm offline, so I can only riff on Wi-Fi topics in my knowledge base — but there's a lot of ground covered there. Tap a suggestion to keep going.
""",
        """
Couldn't decode that — my training is strictly Wi-Fi diagnostics. If you give me something more specific (signal, speed, security, devices, gaming, streaming), I can usually take it from there.
"""
    ]

    private static func capabilitiesReply(context: KlausChatContext) -> String {
        let liveBits = liveSummarySnippets(context: context)
        let livePart: String
        if liveBits.isEmpty {
            livePart = ""
        } else {
            livePart = "\n\nI can already see: \(liveBits.joined(separator: "; ")).\n"
        }
        return """
Here's roughly what I can do:

• Explain Wi-Fi topics — placement, bands, security, gaming, streaming, IoT, modems, mesh, troubleshooting.
• Read your live in-app data — current ping, last Speed Test, your most recent Survey, the device list — and tell you what those numbers mean.
• Suggest fixes that target the *actual* issues I can see, not generic ones.\(livePart)
Tap any of the suggested questions or just type something — I'll do my best.
"""
    }

    // MARK: Live-data replies

    static func livePingReply(context: KlausChatContext) -> String {
        if let ms = context.signalLatencyMs {
            let intMs = Int(ms.rounded())
            let band = KlausChatContext.band(for: ms)
            switch band {
            case .excellent:
                return "Your latest signal latency was **\(intMs) ms** — that's excellent. Anything under 30 ms is gold-tier for video calls and competitive gaming."
            case .good:
                return "Your latest signal latency was **\(intMs) ms** — solid. You're in the comfortable zone for streaming, gaming, and calls."
            case .fair:
                return "Your latest signal latency was **\(intMs) ms** — fine for most things, but you'd notice the difference if it were closer to 30 ms. Getting nearer the router or jumping to 5 GHz usually shaves real numbers off."
            case .poor:
                return "Your latest signal latency was **\(intMs) ms** — that's into laggy territory. Likely culprits: weak signal, congested 2.4 GHz, or an overloaded router. Want a Wi-Fi-improvement walkthrough?"
            case .awful:
                return "Your latest signal latency was **\(intMs) ms** — rough. Either the signal is very weak in this spot, the router is overloaded, or there's an outage on the way. Try moving closer to the router and re-running the test."
            }
        }
        if context.connectionStatus == .cellular {
            return "You're on Cellular right now, so there's no Wi-Fi ping to read. Switch to Wi-Fi and tap **Refresh Signal** in the Signal tab — once I see a number I'll break it down."
        }
        if context.connectionStatus == .offline {
            return "Looks like you're offline at the moment — I can't read a ping until the network is back."
        }
        return "I haven't seen a fresh ping yet. Hop over to the **Signal** tab and tap **Refresh Signal** — once I have a reading I can tell you exactly what it means."
    }

    static func liveSpeedReply(context: KlausChatContext) -> String {
        guard let down = context.lastDownloadMbps, let up = context.lastUploadMbps else {
            return "I don't have a Speed Test result on file yet. Hop into the **Speed** tab and tap **Run Test** — once it finishes, I can compare it to your plan and call out anything weird."
        }
        var lines: [String] = ["Your last Speed Test:"]
        lines.append("• **Download:** \(formatMbps(down)) Mbps")
        lines.append("• **Upload:** \(formatMbps(up)) Mbps")
        if let p = context.lastSpeedPingMs {
            lines.append("• **Ping:** \(Int(p.rounded())) ms")
        }
        if let j = context.lastSpeedJitterMs {
            lines.append("• **Jitter:** \(formatJitter(j)) ms")
        }
        if let server = context.serverColo, let city = context.serverCity {
            lines.append("• **Server:** Cloudflare \(server) · \(city)")
        }
        if context.isLikelySuboptimalRoute {
            lines.append("\nFair warning: that server is unusually far away for your location, which can drag down the numbers. Real internet might be a bit better than this reading suggests.")
        }
        if down >= 200 {
            lines.append("\nThat download speed is more than enough for 4K streaming on multiple devices and any kind of cloud gaming.")
        } else if down >= 50 {
            lines.append("\nThat's comfortable for HD streaming, video calls, and most gaming.")
        } else if down >= 10 {
            lines.append("\nUsable for HD streaming and basic browsing, but you'd feel any household contention.")
        } else {
            lines.append("\nThat's on the slow side. Worth checking whether the test ran on Wi-Fi or wired — if Wi-Fi, run again next to the router.")
        }
        if up < 5 {
            lines.append("Heads up: upload under 5 Mbps will choke video calls. If yours is genuinely that low, it's a plan-level issue, not Wi-Fi.")
        }
        return lines.joined(separator: "\n")
    }

    static func liveSurveyReply(context: KlausChatContext) -> String {
        guard let grade = context.lastSurveyGrade else {
            return "I don't have a Survey on file yet. Open the **Survey** tab, walk a calibration loop, and finish the survey — I'll grade it and break down dead zones, latency, and what to do next."
        }
        var lines: [String] = ["Your last Survey graded **\(grade)**."]
        if let head = context.lastSurveyHeadline {
            lines.append(head + ".")
        }
        if let median = context.lastSurveyMedianMs {
            lines.append("Median latency across the walk was **\(Int(median.rounded())) ms**.")
        }
        if let dz = context.lastSurveyDeadZoneCount, dz > 0 {
            lines.append("I flagged **\(dz) dead zone\(dz == 1 ? "" : "s")** during the walk.")
        } else if context.lastSurveyDeadZoneCount == 0 {
            lines.append("No dead zones flagged — coverage was continuous.")
        }
        if let dist = context.lastSurveyDistanceMeters {
            lines.append("You walked roughly **\(Int(dist.rounded())) m** of the space.")
        }
        switch grade {
        case "A": lines.append("\nThat's a strong baseline — placement, signal, and latency are all in good shape.")
        case "B": lines.append("\nMostly healthy with a couple of weak spots. Small placement tweaks could push this to an A.")
        case "C": lines.append("\nMixed coverage. A repositioning or a mesh node would have a meaningful effect here.")
        case "D": lines.append("\nA large part of this space is struggling — almost certainly time for mesh or moving the router closer.")
        case "F": lines.append("\nNot much of this space is usable as-is. A mesh node or a much closer router placement is the move.")
        default: break
        }
        return lines.joined(separator: " ")
    }

    static func liveDevicesReply(context: KlausChatContext) -> String {
        guard let count = context.deviceCount else {
            return "I don't have a fresh device scan on file. Open the **Devices** tab and tap **Scan** — I'll tell you exactly what's on your network."
        }
        let trusted = context.trustedDeviceCount ?? 0
        let unknown = max(0, count - trusted)
        let randomized = context.randomizedMacCount ?? 0
        var lines: [String] = ["I see **\(count)** device\(count == 1 ? "" : "s") on your network from your last scan."]
        if trusted > 0 {
            lines.append("**\(trusted)** of those are marked trusted.")
        }
        if unknown > 0 {
            lines.append("**\(unknown)** \(unknown == 1 ? "isn't" : "aren't") marked trusted yet — worth a quick look in the Devices tab to see if you recognize them.")
        }
        if randomized > 0 {
            lines.append("**\(randomized)** \(randomized == 1 ? "uses" : "use") a Private (randomized) MAC — almost always your own iPhones, iPads, or Macs.")
        }
        if count > 25 {
            lines.append("\nThat's a lot of clients. If your router is older than ~5 years, it's almost certainly the bottleneck for a network this busy — Wi-Fi 6 mesh handles 30+ devices much more cleanly.")
        }
        return lines.joined(separator: " ")
    }

    static func liveTopologyReply(context: KlausChatContext) -> String {
        var bits: [String] = []
        if let lip = context.localIP {
            bits.append("• **Your device IP:** \(lip)")
        }
        if let gip = context.gatewayIP {
            bits.append("• **Router (gateway) IP:** \(gip)")
        }
        if let gms = context.gatewayLatencyMs {
            bits.append("• **Router RTT:** \(Int(gms.rounded())) ms")
        }
        if let ims = context.ispLatencyMs {
            bits.append("• **Internet RTT (8.8.8.8):** \(Int(ims.rounded())) ms")
        }
        if let isp = context.ispOrganization {
            bits.append("• **ISP:** \(isp)")
        }
        if bits.isEmpty {
            return "I haven't seen a topology refresh yet — open the **Speed** tab and let it sit a moment. It'll publish your gateway and ISP info and I can read it from there."
        }
        return ([
            "Here's where you sit on the network right now:"
        ] + bits + [
            "",
            "If you want to log into the router admin page, just type your gateway IP into a browser. Your phone won't bookmark it for you, but I can save you the trouble of digging through the topology card."
        ]).joined(separator: "\n")
    }

    static func liveSummaryReply(context: KlausChatContext) -> String {
        var bits = liveSummarySnippets(context: context)
        if bits.isEmpty {
            return """
I don't have any live readings to summarize yet. Once you do any of these I'll be able to tell you how things are stacking up:

• Tap **Refresh Signal** in the Signal tab.
• Run a **Speed Test** in the Speed tab.
• Walk a **Survey** in the Survey tab.
• Run a **Scan** in the Devices tab.
"""
        }
        // Pretty up grammar — first letter cap, sentence-style joining.
        if !bits.isEmpty {
            bits[0] = capitalizeFirst(bits[0])
        }
        return "Beep boop — quick rundown of your network:\n\n" + bits.map { "• \($0)" }.joined(separator: "\n")
    }

    /// Building blocks for the network "rundown" reply. Returned as
    /// short clauses so the caller can join them into bullet points or
    /// inline prose.
    private static func liveSummarySnippets(context: KlausChatContext) -> [String] {
        var bits: [String] = []
        switch context.connectionStatus {
        case .wifi: bits.append("you're on **Wi-Fi**")
        case .cellular: bits.append("you're on **Cellular** — the Wi-Fi advice in here doesn't apply")
        case .wired: bits.append("you're on a **wired** connection — about as good as it gets")
        case .offline: bits.append("you're currently **offline**")
        case .unknown: break
        }
        if let ms = context.signalLatencyMs {
            let band = KlausChatContext.band(for: ms)
            let label: String
            switch band {
            case .excellent: label = "excellent"
            case .good: label = "solid"
            case .fair: label = "fair"
            case .poor: label = "laggy"
            case .awful: label = "rough"
            }
            bits.append("signal latency is **\(Int(ms.rounded())) ms** (\(label))")
        }
        if let down = context.lastDownloadMbps, let up = context.lastUploadMbps {
            bits.append("last Speed Test was **\(formatMbps(down)) down / \(formatMbps(up)) up**")
        }
        if let grade = context.lastSurveyGrade {
            if let dz = context.lastSurveyDeadZoneCount, dz > 0 {
                bits.append("last Survey graded **\(grade)** with **\(dz)** dead zone\(dz == 1 ? "" : "s")")
            } else {
                bits.append("last Survey graded **\(grade)** with **no dead zones**")
            }
        }
        if let count = context.deviceCount {
            let trusted = context.trustedDeviceCount ?? 0
            let unknown = max(0, count - trusted)
            if unknown > 0 {
                bits.append("**\(count)** devices on the network (**\(unknown)** not marked trusted)")
            } else {
                bits.append("**\(count)** devices on the network, all trusted")
            }
        }
        return bits
    }

    // MARK: Follow-up

    private static func followUpReply(memory: AssistantTurnMemory) -> AssistantReply {
        guard let topic = memory.lastTopic, let qa = WiFiAssistantKnowledge.byTopic[topic] else {
            return AssistantReply(
                text: "Tell me what you'd like more on — pick one of the suggestions or ask another question and I'll dig in.",
                relatedQuestions: starterQuestions,
                topic: nil
            )
        }
        // Find a follow-up we haven't served on this topic yet, falling
        // back to a fresh full-answer variant if all the canned
        // follow-ups have been used.
        let unused = qa.followUps.filter { !memory.followUpsServed.contains($0) }
        let body: String
        if let next = unused.randomElement() {
            body = next
        } else if let extra = qa.answers.shuffled().first {
            body = "Here's another angle on the same question:\n\n\(extra)"
        } else {
            body = "I've covered the main points on that one — want to pick a new topic?"
        }
        return AssistantReply(
            text: body,
            relatedQuestions: relatedQuestions(for: qa),
            topic: qa.topic
        )
    }

    // MARK: Greetings + starters

    private static func composeGreetingReply(context: KlausChatContext) -> String {
        let bits = liveSummarySnippets(context: context)
        let head = pick(greetingHeads)
        if bits.isEmpty {
            return "\(head) Tap a suggestion below or ask me anything Wi-Fi-related."
        }
        return "\(head)\n\nI can already see: \(bits.joined(separator: "; ")). Want me to expand on any of that?"
    }

    private static let greetingHeads: [String] = [
        "Beep boop — hi! Klaus here.",
        "Hey there. Antenna up, ready to help.",
        "Hi! Packet-sniffer warmed up.",
        "Hello — Klaus reporting in.",
        "Hi! What are we troubleshooting?"
    ]

    static let starterQuestions: [String] = [
        "How's my network?",
        "What's my ping right now?",
        "How can I make my Wi-Fi signal better?",
        "Is my network secure?"
    ]

    static func fallbackSuggestions(count: Int = 4) -> [String] {
        Array(WiFiAssistantKnowledge.entries.shuffled().prefix(count)).map { $0.question }
    }

    // MARK: Thinking phrases

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
        "Squinting at the waveform",
        "Pinging the gateway",
        "Reading the ARP table",
        "Counting the hops",
        "Triangulating the dead zone",
        "Decompressing my thoughts",
        "Rebooting a few neurons",
        "Asking the router nicely",
        "Catching a few stray packets",
        "Inspecting the handshake",
        "Aligning my parabolic dish",
        "Warming up the diagnostic dish",
        "Indexing my Wi-Fi notebook",
        "Cross-checking the OUI table",
        "Watching the latency curve",
        "Following the breadcrumb trail"
    ]

    static func randomThinkingPhrase() -> String {
        thinkingPhrases.randomElement() ?? "Thinking"
    }

    // MARK: Helpers

    private static func pick<T>(_ items: [T]) -> T {
        items.randomElement()!
    }

    private static func formatMbps(_ value: Double) -> String {
        if value >= 100 { return String(Int(value.rounded())) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    private static func formatJitter(_ value: Double) -> String {
        if value >= 10 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }

    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
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
    /// Stable topic key set on the assistant's message when the engine
    /// resolved a topic (QA / live). Used by the chat view to update
    /// `AssistantTurnMemory.lastTopic` so follow-ups know what the user
    /// last asked about.
    var topic: String? = nil

    static func == (lhs: AssistantMessage, rhs: AssistantMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Chat View

struct WiFiAssistantView: View {
    /// StoreKit-backed Pro entitlement source. Free users get exactly
    /// one question answered *for the lifetime of the install*; after
    /// that the input bar is replaced with a Pro upsell CTA. Gating is
    /// always re-evaluated against `store.isProUser` (derived from
    /// `Transaction.currentEntitlements` in `ProStore`) rather than a
    /// cached flag, so if the user buys Pro mid-chat the chat unlocks
    /// immediately without a view rebuild.
    @ObservedObject var store: ProStore
    @ObservedObject private var contextHub = KlausContextHub.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    /// Free-tier cap: number of user messages allowed before the Pro
    /// paywall takes over the input bar. Changing this value is the
    /// single place to tune the free trial for Klaus.
    private static let freeMessageLimit = 1

    /// UserDefaults key backing the persisted free-question counter.
    /// The counter must outlive the sheet — if it lived in `@State`,
    /// dismissing the assistant and re-presenting it would construct
    /// a fresh view with `userMessagesSent = 0`, letting a free user
    /// bypass the paywall just by closing and re-opening the chat.
    /// `@AppStorage` anchors the count to the install so the cap
    /// actually gates.
    private static let freeMessagesSentKey = "klaus.freeMessagesSent"

    @State private var messages: [AssistantMessage] = []
    @State private var inputText: String = ""
    @AppStorage(WiFiAssistantView.freeMessagesSentKey) private var userMessagesSent: Int = 0
    @State private var showPaywall: Bool = false
    @State private var memory = AssistantTurnMemory()
    @FocusState private var inputFocused: Bool

    /// Free users are out of messages when they've sent their cap of
    /// non-Pro questions. Pro users are never locked out.
    private var isLockedForFreeUser: Bool {
        !store.isProUser && userMessagesSent >= Self.freeMessageLimit
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(theme.divider)
            messageList
            if isLockedForFreeUser {
                proUpsellBar
            } else {
                inputBar
            }
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear(perform: seedGreetingIfNeeded)
        .sheet(isPresented: $showPaywall) {
            PaywallView(store: store, isPresented: $showPaywall)
                .withAppTheme()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            KlausMascotView(size: 44, mode: .portrait)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Klaus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text("Your WiFi Buddy sidekick")
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
                        assistantBubble(text: message.text)
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

    /// Renders the assistant's reply with light Markdown support so
    /// `**bold**` segments inside live-data answers come through as
    /// emphasis. Falls back to plain text if `AttributedString` parsing
    /// fails for any reason.
    private func assistantBubble(text: String) -> some View {
        let display: AttributedString = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        return Text(display)
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

    private var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 34, height: 34)
                .overlay(
                    Circle().stroke(Color.blue.opacity(0.22), lineWidth: 1)
                )
            KlausMascotView(size: 34, mode: .portrait)
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

    // MARK: Pro upsell bar

    /// Replaces the input bar once a free user has used their one free
    /// question. Explains the limit and opens the paywall sheet. The
    /// lock-out survives dismissing and re-opening the assistant sheet
    /// because `userMessagesSent` is persisted via `@AppStorage` (see
    /// the property declaration for why that persistence matters).
    /// If the user purchases Pro from the paywall sheet,
    /// `store.isProUser` flips to `true`, `isLockedForFreeUser`
    /// becomes `false`, and the regular input bar swaps back in on
    /// the next render — no need to dismiss and reopen the chat.
    private var proUpsellBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.blue)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("You've used your free question")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("Get WiFi Buddy Pro to keep chatting with Klaus as much as you want.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Unlock Unlimited Chat")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(theme.buttonText)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            theme.background
                .overlay(
                    Rectangle()
                        .fill(theme.divider)
                        .frame(height: 0.5),
                    alignment: .top
                )
        )
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
        // Gate the send at the edge, not inside the engine. This runs
        // for both tapped chips and typed input, so a free user can't
        // sneak past the cap by tapping a suggested question.
        guard !isLockedForFreeUser else {
            showPaywall = true
            return
        }

        let cleaned = WiFiAssistantEngine.sanitize(rawText)
        guard !cleaned.isEmpty else { return }

        messages.append(
            AssistantMessage(role: .user, text: cleaned, relatedQuestions: [])
        )

        // Count only accepted, non-empty user submissions against the
        // free cap — sanitization rejecting an empty/whitespace input
        // shouldn't eat the user's one free message. The counter is
        // persisted via `@AppStorage`, so this increment outlives the
        // current sheet presentation; a free user can't reset it just
        // by closing and reopening Klaus.
        if !store.isProUser {
            userMessagesSent += 1
        }

        // Snapshot the current memory so the intent classifier sees a
        // stable view of "what was the last topic?" while the reply
        // composes. Klaus replies before we apply the new topic, so the
        // engine doesn't accidentally treat a fresh question as a
        // follow-up to itself.
        let memorySnapshot = memory

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

            let intent = WiFiAssistantEngine.classifyIntent(
                rawInput: cleaned,
                memory: memorySnapshot
            )
            let reply = WiFiAssistantEngine.reply(
                for: intent,
                context: contextHub.snapshot,
                memory: memorySnapshot
            )

            // Update follow-up memory after the reply is composed.
            if case .followUp = intent {
                // Keep `lastTopic` pointed at the same topic. Track
                // which follow-up text was used so the next "tell me
                // more" rotates a different phrase.
                if let topic = memorySnapshot.lastTopic,
                   let qa = WiFiAssistantKnowledge.byTopic[topic] {
                    let served = qa.followUps.first { reply.text.contains($0) }
                    if let served {
                        memory.followUpsServed.insert(served)
                    }
                }
            } else if let topic = reply.topic {
                memory.lastTopic = topic
                memory.followUpsServed = []
            } else {
                // Smalltalk / fallback don't change the last topic; we
                // still let the user "tell me more" about whatever they
                // were last on.
            }

            let newMessage = AssistantMessage(
                role: .assistant,
                text: reply.text,
                relatedQuestions: reply.relatedQuestions,
                isThinking: false,
                topic: reply.topic
            )

            if let idx = messages.firstIndex(where: { $0.id == thinkingID }) {
                messages[idx] = newMessage
            } else {
                messages.append(newMessage)
            }
        }
    }

    private func seedGreetingIfNeeded() {
        guard messages.isEmpty else { return }
        let greeting = WiFiAssistantEngine.reply(
            for: .greeting,
            context: contextHub.snapshot,
            memory: memory
        )
        messages.append(
            AssistantMessage(
                role: .assistant,
                text: greeting.text,
                relatedQuestions: greeting.relatedQuestions,
                isThinking: false,
                topic: greeting.topic
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
    WiFiAssistantView(store: ProStore())
        .withAppTheme()
}
