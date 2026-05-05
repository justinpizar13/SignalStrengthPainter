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
            keywords: ["throttle", "throttling", "throttled", "shaping", "deprioritize", "slow", "after", "data", "cap", "isp"],
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
        ),
        AssistantQA(
            topic: "what-is-wifi",
            question: "What is Wi-Fi, actually?",
            keywords: ["what", "wifi", "wi-fi", "wireless", "explain", "basics", "definition"],
            answers: [
                """
Wi-Fi is radio. Your router is a tiny radio station in your home. Your phone, laptop, TV, and smart gadgets are little radio receivers that can also talk back. Instead of music, they're trading internet data — web pages, video, messages.

The reason everyone has their own Wi-Fi: the radio range is short on purpose. It reaches around your house, and your neighbor has their own radio station doing the same on a different channel. That's why signal fades the further you walk from the router.

"Wi-Fi" is just a brand name, by the way — it doesn't stand for anything. The standard underneath is called IEEE 802.11. Nobody cares about the number, which is why marketing calls it Wi-Fi 6 / Wi-Fi 7 now.
""",
                """
Imagine a walkie-talkie between your phone and your router, but instead of voice, it's sending the pixels of every Netflix frame, every tap on a website, every text message. That's Wi-Fi.

Your router is the 'base station' of this private radio network. It's also plugged into a cable from your internet provider, so it can pass your requests out to the wider internet and bring answers back. Everything wireless in your home is just talking through this one box.
"""
            ],
            followUps: [
                "Wi-Fi operates on microwave radio frequencies — the same neighborhood as baby monitors, cordless phones, and (literally) microwave ovens. That's why a running microwave in the kitchen can make Wi-Fi wobble for a minute.",
                "Wi-Fi is half-duplex, which is a fancy way of saying only one device can 'talk' on a channel at a time. Lots of busy devices means they take turns, and that's where the perceived slowness comes from."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "what-is-ssid",
            question: "What's an SSID or network name?",
            keywords: ["ssid", "network", "name", "broadcast", "what"],
            answers: [
                """
SSID stands for Service Set Identifier — but forget that acronym. It's just the *name* of your Wi-Fi network. The thing that appears in the list when you tap "Wi-Fi Settings" on your phone.

"MyHomeNetwork", "Linksys_5G", "PrettyFlyForAWiFi" — those are all SSIDs. Your router broadcasts this name every second so devices nearby know what's available. You can change it to whatever you want in the router admin page; the only real rule is don't include personal info like your address.
""",
                """
It's the name of the Wi-Fi. That's it. Your phone sees a list of these in its Wi-Fi settings, you pick one, you enter the password.

Most dual-band routers publish one SSID and silently handle 2.4 GHz / 5 GHz routing behind the scenes. Older setups used two separate SSIDs (one with '_2G', one with '_5G') — you rarely want that anymore.
"""
            ],
            followUps: [
                "SSIDs are case-sensitive. 'MyHome' and 'myhome' are two different networks as far as your devices are concerned.",
                "Naming it after yourself or your address is a minor privacy nudge — anyone in range can see the name. Keep it neutral."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "what-is-ip-address",
            question: "What's an IP address?",
            keywords: ["ip", "address", "192", "168", "10", "what", "mean", "explain"],
            answers: [
                """
An IP address is the mailing address of a device on a network. Every phone, laptop, TV, and smart plug gets one when it joins your Wi-Fi, and your router uses it to know where to send each piece of incoming data.

Two flavors worth knowing:

• **Private IP** — what your devices have *inside* your home (often starts with `192.168.` or `10.`). Only your router sees these.
• **Public IP** — what the rest of the internet sees when your router talks out. One per household, usually.

That's why two houses can both have a phone at `192.168.1.5` with no conflict — those addresses only mean something inside each house.
""",
                """
Think of it as the street address for your device. Your router runs a tiny post office and hands out one to every gadget that joins. When you load a webpage, the request goes out tagged with your address so the response knows where to come home to.

The number you see in the Speed tab (like `192.168.1.123`) is your device's private address on your home network. Your 'public' address — the one websites see — is handed to your whole household by the ISP and usually changes every so often.
"""
            ],
            followUps: [
                "IPv4 addresses (the 'four numbers with dots' format) are running out globally. IPv6 is the newer format — longer, messier-looking — that most modern networks use behind the scenes.",
                "You can reserve a fixed private IP for a specific device in the router admin page ('DHCP reservation'). Useful for printers, security cameras, or anything that needs a stable address."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "what-is-mac-address",
            question: "What's a MAC address?",
            keywords: ["mac", "address", "hardware", "what", "hex", "serial"],
            answers: [
                """
A MAC address is the hardware serial number of a device's Wi-Fi (or Ethernet) chip. It looks like six pairs of letters and numbers — `a4:83:e7:9c:12:4f` — and it's meant to be globally unique per device.

Where you see them:

• Your router's admin page lists them for every connected device.
• Network-scanner apps like this one read them out of your device's ARP table.
• The first half of a MAC encodes the *manufacturer* (Apple, Samsung, Amazon, etc.), which is how the Devices tab guesses what a device is even without a name.

Modern phones randomize their MAC per network for privacy — so in a scan they show up as "Uses Private Wi-Fi Address" and look generic. That's expected and almost always your own gear.
""",
                """
MAC = Media Access Control address. It's burned into every Wi-Fi chip at the factory, like a license plate for the hardware. Routers use it to tell one device from another even when IP addresses get shuffled around.

Two useful facts: the first six characters of a MAC identify the manufacturer (that's how scanners guess 'Apple' or 'Samsung'), and modern phones deliberately shuffle their MAC per network so they can't be tracked across coffee shops.
"""
            ],
            followUps: [
                "MAC addresses only matter inside a single network segment. They don't travel across the internet — only IP addresses do.",
                "Some older parental-control setups rely on MAC filtering to block specific devices. That breaks the moment the phone randomizes, which is why modern parental control has moved to per-device profiles instead."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "what-is-dns-basic",
            question: "What is DNS and how does it work?",
            keywords: ["what", "dns", "resolve", "lookup", "how", "does", "work", "nameserver"],
            answers: [
                """
DNS is the phonebook of the internet. Humans like to type `netflix.com`; computers need a numeric IP address to actually reach it. DNS is the translation layer in between.

Every time you tap a link:

1. Your device asks a DNS server, "What's the IP for netflix.com?"
2. The DNS server answers with something like `52.84.14.99`.
3. Your device connects to that IP.
4. The page loads.

All of that happens in tens of milliseconds. When DNS is broken, pages feel like they're "stuck loading" even though the rest of the internet is fine — because step 1 never finishes.
""",
                """
Computers talk in IP addresses, you talk in domain names. DNS is the translator.

Your ISP runs one by default. Cloudflare (`1.1.1.1`) and Google (`8.8.8.8`) run public ones. They all do the same job; the differences are speed, privacy, and uptime. If pages suddenly stop loading but a speed test still works, the ISP's DNS is probably down — switching to Cloudflare in router settings fixes it instantly.
"""
            ],
            followUps: [
                "DNS responses are cached aggressively. Your phone remembers `netflix.com`'s IP for a while so it doesn't have to ask every time. This is why some site changes take 'a few hours to propagate' — everyone's caches have to expire.",
                "If a website is blocked on one network (school, work) but works on cellular, DNS filtering is often why. The ISP is returning a fake 'not found' answer instead of the real IP."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "what-is-nat",
            question: "What is NAT and why do I keep hearing about it?",
            keywords: ["nat", "network", "address", "translation", "double", "strict", "moderate", "open"],
            answers: [
                """
NAT stands for Network Address Translation. Your router uses it to let many devices in your house share one public internet address.

Picture a big office building with one street address but hundreds of people inside. Mail comes in addressed to the building; the receptionist (the router) knows who to route each envelope to. That's NAT.

It's invisible 99% of the time. The exception is **strict NAT** in gaming, where two players behind different NATs can't easily reach each other directly. Enabling UPnP in the router, or manually port-forwarding, fixes that.
""",
                """
NAT is how one internet connection gets shared with every device in your home. Without it, every phone, laptop, and TV would need its own public IP address, and the world ran out of those decades ago.

The router keeps a lookup table of "which device asked for what" so that when answers come back from the internet, it can deliver them to the right gadget inside.
"""
            ],
            followUps: [
                "**Double NAT** happens when you have two routers in a chain (ISP combo unit + your own router) and both are doing NAT. It breaks UPnP, port forwarding, and some video-calling apps. Fix: put the ISP's box in 'bridge mode'.",
                "On consoles, 'Open NAT' means the most connectivity flexibility (best for hosting multiplayer), 'Moderate' is fine for most games, 'Strict' causes matchmaking issues."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "access-point-vs-router",
            question: "What's the difference between a router and an access point?",
            keywords: ["access", "point", "ap", "difference", "router", "vs", "extra"],
            answers: [
                """
Routers do several jobs: they assign IP addresses (DHCP), run NAT, handle the firewall, and usually also broadcast Wi-Fi. An access point does *only* the Wi-Fi broadcast piece — it's a dumb radio extension plugged into an existing router.

When each makes sense:

• Small home, one location: a single router with Wi-Fi is all you need.
• Large home or office with Ethernet drops: keep the router central, add access points wired in at far rooms. Rock-solid coverage because each AP has its own Ethernet backhaul.
• Apartment / renters: a router is fine; access points aren't worth the complexity.

Mesh systems are basically wireless access points pre-paired with a router, so you don't have to wire them in.
""",
                """
A router is a Swiss Army knife. An access point is just the Wi-Fi broadcast part by itself.

The classic pro-tier home setup: one powerful wired router in the basement or closet, plus two or three access points spread through the house on Ethernet. It beats mesh in stability and speed but requires cable runs.
"""
            ],
            followUps: [
                "You can turn many old routers into an access point by disabling their DHCP/NAT and plugging them into a LAN port on your main router. Free AP instead of throwing it out.",
                "Ubiquiti, TP-Link EAP, and Aruba are popular access-point brands for people who want to wire their whole house cleanly."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "connected-no-internet",
            question: "Why does it say 'Connected, no internet'?",
            keywords: ["connected", "no", "internet", "access", "wifi", "says", "but", "cant", "load"],
            answers: [
                """
That message means your device is talking to the router just fine, but the router isn't talking to the outside world. Two different links, and only the second one is broken.

Work through it in this order:

• Check another device. If your phone works but the laptop doesn't, it's a device problem.
• If nothing works, reboot the modem and router (unplug 60 seconds, plug back in).
• Still nothing? Check your ISP's status page or Twitter account — outages are common.
• If the ISP is fine, it could be a DNS issue. Try switching to `1.1.1.1` or `8.8.8.8` in your device's Wi-Fi settings.
• A stuck router after a long uptime is the single most common cause. The 60-second power cycle fixes 70% of these.

The Speed tab's topology card tells you exactly which hop is broken — router green + ISP red means "modem or provider."
""",
                """
Classic symptom. The Wi-Fi handshake works (you have a local connection) but the path out to the internet is blocked somewhere.

Fast checklist:
1. Other devices affected? Reboot the router.
2. Only this device? Forget the network, rejoin.
3. Everyone's down? Could be the ISP. Check the Speed tab topology — if the "Internet" node is red and the "Router" node is green, the problem is on the ISP's end.
"""
            ],
            followUps: [
                "Captive portals (hotel / café Wi-Fi) also show 'Connected, no internet' until you agree to their terms in a browser. Try opening any non-HTTPS page — the portal usually redirects.",
                "If the issue is only on one app (like streaming) but other apps work, DNS filtering or the service itself is the culprit, not your Wi-Fi."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "printer-wifi",
            question: "Why won't my printer connect or print over Wi-Fi?",
            keywords: ["printer", "print", "printing", "cant", "won't", "connect", "hp", "epson", "brother", "canon", "offline"],
            answers: [
                """
Printers are notoriously fussy on Wi-Fi. The single biggest reason: most home printers only speak 2.4 GHz, but your router may be hiding that from them.

Run through this:

• During printer setup, make sure your phone is on the 2.4 GHz band of your Wi-Fi (some routers have a separate network name for it).
• Move the printer closer to the router — weak 2.4 GHz signal drops printers constantly.
• Reboot the printer (pull the power for 30 seconds) AND the router.
• On your computer/phone, remove the printer and re-add it. Stale driver state is a classic source of "offline" even though the printer is on.
• Some routers isolate the guest network from the main one — if your printer and your phone are on different networks, they can't see each other.

If you print regularly, Ethernet or USB to the printer solves Wi-Fi printing complaints permanently.
""",
                """
Printers and Wi-Fi have a rough relationship. Most home printers have a weak radio, only speak 2.4 GHz, and go to sleep aggressively. Then your computer caches an 'offline' status and stops trying.

The usual cure:

1. Power-cycle the printer.
2. Power-cycle the router.
3. Remove the printer on your Mac/PC, add it back.
4. Print a test page within a couple minutes so the printer radio is awake.
"""
            ],
            followUps: [
                "If you have a mesh network with separate bands, some mesh brands (Eero especially) silently put printers on 2.4 GHz automatically — but during setup you sometimes need to temporarily disable 5 GHz so the printer can find the network.",
                "AirPrint (Apple) and Mopria (Android) rely on Bonjour / mDNS discovery. A router with 'AP Isolation' or 'Client Isolation' enabled breaks both — check that setting."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "password-reenter",
            question: "Why do my devices keep forgetting the Wi-Fi password?",
            keywords: ["password", "forgetting", "reenter", "reentering", "keeps", "asking", "prompt", "again"],
            answers: [
                """
A few common causes:

• **You changed the password recently** — every old device needs it entered once more.
• **Router swap or firmware update** — sometimes the router re-generates a session key that invalidates cached credentials on older devices.
• **Device software bug** — phones occasionally forget saved networks after a major OS update. Re-joining fixes it.
• **Authentication actually failing** — the password looks saved but the router is rejecting it. Usually a corrupted router setting; a reboot clears it.
• **Signal drops during handshake** — if signal is weak at the moment of join, the device interprets the timeout as 'bad password' and prompts again.

If only one device does this while everyone else stays connected, the issue is on that device. If all devices get prompted simultaneously, something about the router changed.
""",
                """
Most often: the password actually changed (you or someone else went into the router admin), the device cached an older version, or signal was weak during the handshake and it timed out.

Fastest fix: forget the network on the device, type the password in again fresh, and make sure you're close to the router when you do.
"""
            ],
            followUps: [
                "On iOS: Settings → Wi-Fi → tap the (i) next to the network → 'Forget This Network' is cleaner than a straight reconnect.",
                "If you rotated the password and some IoT gadgets (bulbs, plugs) won't rejoin, you may need to factory-reset them and re-pair. They often can't handle the password change on their own."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "outage-troubleshoot",
            question: "My internet is down — what do I do?",
            keywords: ["down", "outage", "broken", "not", "working", "nothing", "loads", "troubleshoot", "emergency"],
            answers: [
                """
Quick triage:

1. **Check multiple devices** — is it really the whole network, or just one gadget?
2. **Look at the Speed tab topology** — if the "Router" node is green but "Internet" is red, your ISP is the problem, not you.
3. **Check the modem lights** — most have a labeled "Internet" or "Online" light. If it's blinking or red, the line is down.
4. **Power-cycle the modem + router** — unplug both for 60 seconds, modem first, router second. Wait 2-3 minutes for everything to come back.
5. **If still down** — pull out your phone, hop on cellular, and check your ISP's outage page or social media.
6. **If everyone's fine except you** — the issue is inside your home. Try a wired laptop directly into the modem; if that works, the router is the problem.

A failover cellular hotspot from your phone is the fastest emergency workaround while you wait.
""",
                """
The fastest diagnosis: phone on cellular → check your ISP's status page. That tells you in ten seconds whether it's them or you.

Then if it's you: modem lights are the second-best clue. A red/blinking "Internet" or "Online" light means the line from the ISP never got its handshake back. Cable-pull + 60-second wait + cable-back on the modem fixes the stuck handshake most of the time.
"""
            ],
            followUps: [
                "downdetector.com is the crowdsourced outage map that often reports ISP problems before the ISP officially acknowledges them.",
                "Once you know it's the ISP's fault, a quick call can get you pro-rated credit for the downtime — most ISPs will do this if you ask nicely."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "router-lights",
            question: "What do the lights on my router mean?",
            keywords: ["lights", "blinking", "led", "indicator", "router", "modem", "red", "amber", "green", "orange", "flashing"],
            answers: [
                """
Every router brand is a little different, but the general language is the same:

• **Solid green / white** — everything's healthy.
• **Solid amber / orange** — something's working but not at full capacity (limited speed, limited 5 GHz).
• **Red / no internet light** — the connection out to the ISP is broken.
• **Blinking steadily** — normal data activity.
• **Blinking rapidly with no rhythm** — usually during a firmware update; don't unplug.
• **No lights at all** — power or hardware failure.

If you see a red or missing "Internet" / "WAN" light specifically, that's your ISP or modem, not your Wi-Fi.
""",
                """
The quick rule: green is good, amber is warning, red is broken. Any label near it tells you what (Internet, Wi-Fi, WPS, etc).

For more detail, dig up the manual online — searching "[brand] [model] LED meanings" almost always finds a clear chart.
"""
            ],
            followUps: [
                "Some routers have an all-off option for nighttime. If yours looks dark but devices are still online, someone enabled that mode.",
                "A rapidly flashing light that never settles usually means the router can't finish handshaking with the modem. A full power cycle (modem first, router second, 60 seconds between) fixes most of these."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "iot-only-2ghz",
            question: "My smart device only joins 2.4 GHz — how do I set it up?",
            keywords: ["smart", "iot", "only", "2.4", "ghz", "join", "pair", "setup", "plug", "bulb", "camera", "doorbell"],
            answers: [
                """
Most cheap smart devices (bulbs, plugs, older cameras) only speak 2.4 GHz to save on antenna costs. On a modern router that broadcasts one name for both bands, that creates a pairing problem because your phone is usually sitting on 5 GHz.

Options in order of least hassle:

• **Put your phone on 2.4 GHz temporarily** during pairing. Some routers publish a hidden "2.4 GHz only" network name you can join briefly.
• **In the router app, temporarily turn off 5 GHz** during setup. The phone drops to 2.4 GHz automatically, the device pairs, then you turn 5 GHz back on.
• **Keep a small travel router** broadcasting a 2.4 GHz-only network just for pairings.
• **Separate the bands permanently** if you pair smart stuff often — many routers let you split "Home_2G" and "Home_5G" as two SSIDs.

Once the IoT device is joined, it doesn't care if you turn 5 GHz back on for the rest of the house.
""",
                """
The classic trick: go into your router app, temporarily disable 5 GHz, pair the smart device (your phone will automatically drop to 2.4 GHz), then re-enable 5 GHz. The IoT gadget stays on 2.4 GHz after that.

Eero and Google Nest handle this silently most of the time — they detect the IoT pairing and fall back. Older routers usually don't.
"""
            ],
            followUps: [
                "Some Android phones have a developer setting to 'prefer 2.4 GHz' which also solves this. iOS doesn't expose that option.",
                "Matter and Thread are newer smart-home standards that sidestep all of this — devices join once via Bluetooth and don't depend on Wi-Fi bands at all."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "apartment-wifi",
            question: "How do I get better Wi-Fi in an apartment?",
            keywords: ["apartment", "condo", "flat", "small", "building", "thin", "walls", "complex"],
            answers: [
                """
Apartments have a unique Wi-Fi challenge: thirty neighbors broadcasting on the same airwaves at the same time. Your signal is fine — it's the interference that kills you.

Strategies:

• **Prefer 5 GHz for anything that matters.** The 2.4 GHz band is almost always crowded in apartment buildings; 5 GHz has way more channels and shorter range, so your neighbors' signals don't reach you.
• **Put the router toward the inside of the unit**, not pressed against the shared wall with a neighbor.
• **Manually pick 2.4 GHz channel 1, 6, or 11** in router settings — those are the only non-overlapping channels and the least fought-over.
• **A modern Wi-Fi 6 router** handles crowded spectrum dramatically better than older ones thanks to a feature called OFDMA.
• **Hide smart-home devices on 2.4 GHz** and push everything else to 5 GHz so the crowded band does less for you.

A mesh kit usually isn't worth it in an apartment — a single good router beats extenders in tight spaces where walls aren't the problem.
""",
                """
Apartment Wi-Fi woes are almost never "not enough signal" — they're "too much of everyone else's signal." Your phone and laptop hear twenty networks and have to share the radio time with all of them.

Fixes: push devices to 5 GHz, manually set 2.4 GHz to channel 1, 6, or 11, place the router away from shared walls, and if you live in a city high-rise consider upgrading to Wi-Fi 6 or 6E. That 6 GHz band is pristine right now.
"""
            ],
            followUps: [
                "Most apartments don't have the Ethernet infrastructure for a proper wired backhaul, which is why mesh ROI is lower here than in a house. A single well-placed router is usually king.",
                "If your apartment has concrete walls or cinderblock between rooms, placement becomes much more important — signal doesn't pass through those easily."
            ],
            category: "Coverage"
        ),
        AssistantQA(
            topic: "basement-garage",
            question: "How do I get Wi-Fi to my basement, garage, or backyard?",
            keywords: ["basement", "garage", "backyard", "outside", "shed", "detached", "addition", "adu", "far"],
            answers: [
                """
Wi-Fi has a hard time punching through floors, concrete, and distance. Detached or semi-buried spaces need their own access point — an extender alone rarely works well.

Best-to-OK options:

• **Ethernet run + access point / mesh node** in the target space. Rock solid, no speed loss. A cheap $20 Cat6 cable through an exterior wall works wonders.
• **MoCA** — uses existing coaxial cable runs (the black TV cable) to deliver Ethernet to distant rooms. Almost as good as wired.
• **Powerline adapters** — uses your home's electrical wiring. Not as fast as Ethernet but zero installation.
• **Outdoor-rated mesh node** — some mesh brands (Eero Outdoor, Asus ZenWiFi) sell weatherproof nodes for backyards or garages.
• **Wi-Fi extender (last resort)** — halves the speed and makes client roaming annoying.

A garage door or a set of concrete basement stairs is a much harder obstacle than most people expect. Don't assume "one more wall" — go test with a speed check before buying anything.
""",
                """
Detached or below-grade spaces are the classic mesh/AP use case. Wi-Fi doesn't punch through dirt or concrete well, so the fix is almost always "put a second radio in the problem spot."

The winning setups I've seen most often:

1. Ethernet through the wall → mesh node in the garage/basement. Best.
2. MoCA adapter pair if you have coax lines. Very good.
3. Outdoor-rated mesh node for backyards. Weatherproof is a real requirement.
"""
            ],
            followUps: [
                "A shed or ADU that's more than ~30 feet from the house and has walls in between is almost always beyond reasonable Wi-Fi range. Ethernet (buried in conduit) or a point-to-point outdoor radio link is the grown-up answer.",
                "For backyard-only coverage a couple of hours at a time, you may prefer just using cellular on your phone rather than investing in extending the Wi-Fi outside."
            ],
            category: "Coverage"
        ),
        AssistantQA(
            topic: "work-from-home-setup",
            question: "What's the best Wi-Fi setup for working from home?",
            keywords: ["work", "home", "wfh", "remote", "office", "setup", "desk", "zoom", "teams"],
            answers: [
                """
Work from home lives or dies on video-call stability. Optimize for that:

• **Ethernet to your desk, if at all possible.** One $15 Cat6 cable changes everything — ping drops by 20 ms, jitter disappears, no more "you're frozen." If your router is in a different room, a long cable along a baseboard is worth the ugliness.
• **If Wi-Fi only, be on 5 GHz** as close to the router as practical. Weak 5 GHz beats strong 2.4 GHz for calls.
• **Pause cloud backups during meetings** — iCloud, Google Drive, OneDrive can silently upload gigabytes and wreck your upload for the call.
• **Dedicate one band or SSID to work** if your household gets busy. Some routers let you prioritize specific devices (QoS).
• **5 Mbps upload minimum** for stable HD video calls. Check yours in the Speed tab.
• **Ping under 60 ms** feels great on calls; over 100 ms starts to feel laggy in natural conversation.

If calls are critical to your job and Wi-Fi is iffy, a dedicated mesh node in your office is the nicest upgrade you'll ever buy yourself.
""",
                """
The ROI order for work-from-home Wi-Fi:

1. Ethernet to the desktop or laptop dock. 5–30 ms of latency savings, zero jitter, no drops.
2. If wireless, a mesh node within line of sight of the desk.
3. Router firmware and hardware that's less than 5 years old.
4. QoS prioritizing your work computer's MAC address (if your router supports it).

Video calls care about upload and stability, not raw download speed. A cable plan's 500 Mbps down is worthless if the upload keeps stuttering.
"""
            ],
            followUps: [
                "A cheap USB-to-Ethernet adapter + a long Cat6 run is probably the best $20 investment you can make for work-from-home reliability.",
                "If you travel, a small travel router that can bridge hotel Wi-Fi to a local network of your own lets all your devices share one hotel login and gives you a consistent experience on the road."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "travel-wifi",
            question: "What are some tips for Wi-Fi while traveling?",
            keywords: ["travel", "traveling", "hotel", "airbnb", "rental", "road", "trip", "portable"],
            answers: [
                """
Tips I'd give anyone traveling:

• **Hotel Wi-Fi is almost always saturated and captive-portaled.** Expect slow, expect a login page. A VPN on top helps with both privacy and occasionally with throttling.
• **Check your phone's hotspot quota** before the trip. Tethering is usually faster than hotel Wi-Fi, but many plans cap you at 5 or 10 GB before throttling.
• **A travel router** (GL.iNet makes popular ones) lets you log into hotel Wi-Fi once, then share that connection to all your other devices without re-authenticating each.
• **Airbnb Wi-Fi** varies wildly. Ask the host for the plan speed before booking if you need it for work.
• **Airport/café Wi-Fi** is fine for browsing but never trust it for banking unless you're on a VPN or HTTPS-only mode.
• **International data roaming** is expensive. A local SIM or eSIM is usually far cheaper for a week or longer.

Most modern smartphones can also save a trusted network and auto-reconnect; test that at the hotel before you need it to work.
""",
                """
The traveler's cheat codes:

• Travel router — log in once, share the connection to your laptop, iPad, and work phone.
• Phone hotspot — faster than most hotel Wi-Fi most of the time.
• VPN for anything sensitive — public Wi-Fi is still sketchy for banking.
• eSIM or local SIM for international trips; it's usually cheaper than your carrier's roaming.
"""
            ],
            followUps: [
                "If hotel Wi-Fi makes you re-log-in every 24 hours and breaks all your devices, a $30 travel router with 'clone MAC' support is a genuinely life-changing purchase.",
                "Many streaming services geo-restrict content when you travel internationally. A VPN back to your home country usually fixes that."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "captive-portal",
            question: "Hotel or café Wi-Fi won't let me log in — why?",
            keywords: ["captive", "portal", "hotel", "cafe", "coffee", "airport", "hotspot", "login", "agree", "terms"],
            answers: [
                """
That's a captive portal. The Wi-Fi connects but doesn't give you real internet until you accept some terms page in a browser. The page should pop up automatically when you first join. If it doesn't:

• **Open any non-HTTPS site manually** (e.g. `neverssl.com`) — it forces the portal to redirect.
• **Try turning off Private Wi-Fi Address** (iOS) for that network — some portals don't handle randomized MACs correctly.
• **Disable VPNs** temporarily. Many captive portals can't route VPN traffic.
• **Forget the network and rejoin** — sometimes the portal was already agreed-to earlier, then expired, and your phone caches the dead session.
• **Turn off cellular briefly** — your phone might be silently using cellular instead of the Wi-Fi for the portal check.

Once you've agreed, the portal usually remembers your device for 24 hours before asking again.
""",
                """
Captive portal = the "please agree to our terms" page at coffee shops, hotels, and airports. Your device sees the Wi-Fi but every app acts broken until you finish the agreement in a browser.

Magic URL to force the portal: `http://neverssl.com` or `http://captive.apple.com`. One of those will redirect to the agreement page, you tap accept, and everything starts working.
"""
            ],
            followUps: [
                "iOS has a built-in captive portal detector and usually pops the login sheet for you. If it doesn't, your Private Wi-Fi Address setting is the most common culprit — try toggling it off for that network.",
                "A travel router is the cleanest solution if you use captive portal Wi-Fi often — log in once on the router, and all your devices get seamless internet without re-authenticating."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "qos",
            question: "What is QoS (Quality of Service) and should I use it?",
            keywords: ["qos", "quality", "service", "priority", "prioritize", "traffic", "shaping"],
            answers: [
                """
QoS lets your router decide which traffic is more important when the pipe is busy. If someone's uploading a huge file while you're on a Zoom call, QoS can reserve bandwidth for the call so video doesn't stutter.

Two common styles:

• **Device-based QoS** — prioritize specific devices by MAC address. Your work laptop gets first dibs, the smart TV gets leftovers.
• **Application-based QoS** — the router recognizes patterns (video calls, gaming, streaming) and prioritizes those automatically.

When it helps:

• Busy households with video calls and 4K streaming competing.
• Gamers sharing bandwidth with bulk downloads.
• Anyone with a slow plan that gets saturated easily.

When it doesn't help: fast plans with headroom. If your connection rarely saturates, there's nothing to prioritize.

Most modern mesh systems (Eero, Google Nest, Orbi) turn QoS on automatically with sensible defaults.
""",
                """
Think of QoS as carpool-lane rules for your internet. When the highway is wide open, nobody needs them. When everyone's trying to leave at once, they matter.

Simple version: if you have gamers and 4K streamers fighting over a congested plan, enable QoS and set the gaming device as priority. If your connection is fast enough that everyone gets what they want, leave it off.
"""
            ],
            followUps: [
                "Some routers' QoS is garbage — it actually slows everything down while it's 'shaping' traffic. Test before/after with a speed test to confirm it's helping.",
                "Gamers often prefer QoS over upgrading their plan — a 100 Mbps plan with good QoS can feel better than a 500 Mbps plan without it during peak hours."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "beamforming-mumimo",
            question: "What are beamforming and MU-MIMO?",
            keywords: ["beamforming", "mu-mimo", "mumimo", "technology", "new", "feature", "explain", "antenna"],
            answers: [
                """
Two features you'll see on modern router boxes:

• **Beamforming** — instead of broadcasting Wi-Fi in all directions equally (like a lamp), the router aims the signal toward where your device actually is (like a flashlight). Stronger signal reach, less wasted power, and adjusts automatically as you move.
• **MU-MIMO** (Multi-User, Multiple-Input, Multiple-Output) — the router can talk to several devices simultaneously instead of taking turns. Huge for busy households with many phones and TVs active at once.

Older routers did everything one device at a time, round-robin. A newer router with MU-MIMO can genuinely hand Netflix data to the TV at the same moment it's sending a video-call upload from the laptop. It makes a busy home network feel much snappier.

Both features are baked into Wi-Fi 5 (MIMO basics), Wi-Fi 6 (upgraded MU-MIMO + OFDMA), and Wi-Fi 7. You don't usually need to "enable" them — if both router and device support it, it just works.
""",
                """
Two of the big "your new router is smarter" features:

• Beamforming — directed signal instead of omnidirectional. Longer reach, better in the specific direction your devices are sitting.
• MU-MIMO — the router can serve multiple devices at the same time, not round-robin. Feels faster when the house is busy.

Both are automatic in modern routers. The more devices both your router and your clients (phones, laptops) both support them, the more benefit you see.
"""
            ],
            followUps: [
                "OFDMA (Orthogonal Frequency Division Multiple Access) is Wi-Fi 6's other headline feature. It lets the router slice each channel into smaller sub-channels and serve multiple devices per transmission. Especially helpful for busy IoT-heavy homes.",
                "For any of these to help, both ends need to support them. A fancy Wi-Fi 6 router talking to a 10-year-old laptop still communicates on the older protocol for that session."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "packet-loss",
            question: "What is packet loss and why does it matter?",
            keywords: ["packet", "loss", "dropped", "lost", "drops", "percentage", "percent"],
            answers: [
                """
Every piece of internet data is broken into small chunks called packets. Packet loss is the percentage of those chunks that never reach their destination.

A packet loss of 0% is perfect. 1% starts to feel noticeable in real-time uses (voice, video, games). Over 2-3%, things get visibly wobbly. Over 10%, almost nothing works smoothly.

It's usually more disruptive than raw "slow speed" because:

• Streaming and video calls freeze waiting for missing packets to retransmit.
• Games rubber-band or teleport because the next state update never arrived.
• Web pages load with gaps or half-broken images.

Common causes: weak Wi-Fi signal, overloaded router, bad cable between modem and wall, or an ISP-side issue. If a Speed Test shows fine Mbps but streaming feels broken, packet loss is often the hidden culprit.
""",
                """
Packet loss is the invisible killer of real-time apps. Your speed test can look fine — 200 Mbps down, 20 Mbps up — but if 2% of packets are disappearing in transit, calls and games will stutter constantly.

Common sources, in order of likelihood: weak Wi-Fi signal (packets die on the air before reaching the router), overloaded router (drops packets when it can't keep up), and ISP line issues (usually shows up as jitter + packet loss together).
"""
            ],
            followUps: [
                "Ping tests catch packet loss if you run them long enough. Try `ping -c 100 8.8.8.8` on a Mac or `ping -n 100 8.8.8.8` on Windows — anything over 1% lost packets deserves attention.",
                "Wired Ethernet basically eliminates Wi-Fi-sourced packet loss. If a device is stationary and gaming/calls are flaky, a wired connection is the fastest troubleshooting step."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "old-router-extender",
            question: "Can I use my old router as a Wi-Fi extender?",
            keywords: ["old", "router", "extender", "reuse", "repurpose", "second", "ap", "mode"],
            answers: [
                """
Yes, and it's usually a better extender than a cheap plug-in extender because the radios are typically stronger. Two common ways to repurpose an old router:

**Access-Point Mode** (best):

• Plug an Ethernet cable from your main router to the old router.
• In the old router's admin page, find "Operation Mode" or "Access Point Mode" and switch it on. This disables DHCP and NAT on the old unit, so it just broadcasts Wi-Fi.
• Give it the same Wi-Fi name and password as your main router so devices roam seamlessly.

**Wireless Bridge / Repeater Mode** (no Ethernet needed):

• Some routers support this natively; many don't.
• The old router connects to your main Wi-Fi wirelessly and re-broadcasts it.
• Throughput is usually cut in half because both hops share the same radio, similar to a consumer extender.

Ethernet-fed access-point mode is by far the better option. If you can get a cable to where the old router will live, it's basically free mesh-level coverage.
""",
                """
Absolutely. The cleanest approach: plug it into your main router with Ethernet, turn on its access-point or bridge mode, match the Wi-Fi name and password, and put it in the spot that has the worst coverage. Clients roam between the main router and the old one automatically.

Without Ethernet, some routers support "repeater" mode wirelessly, but the speed penalty is real (typically 50%+). Wired backhaul is the win.
"""
            ],
            followUps: [
                "If the old router is 5+ years old, it may not support modern Wi-Fi standards. Using it as an AP still helps coverage but caps you at its older generation's speed.",
                "Third-party firmware like OpenWRT or DD-WRT unlocks access-point mode on many routers that didn't originally ship with it. Not for the faint of heart, but doable."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "fiber-cable-dsl",
            question: "What's the difference between fiber, cable, and DSL internet?",
            keywords: ["fiber", "cable", "dsl", "satellite", "5g", "difference", "compare", "which", "types", "type"],
            answers: [
                """
The main home-internet flavors, briefly:

• **Fiber** — light through a glass cable. Fastest (often 1 Gbps+), lowest latency, symmetric (same upload and download). Best if available.
• **Cable** — uses the coax cable used for TV. Fast download (up to 1 Gbps in good areas), much slower upload (usually 10-50 Mbps). Common in suburban US.
• **DSL** — uses phone lines. Slow (usually 10-100 Mbps down), and speed drops the further you are from the ISP's junction box. Often the only option in rural areas.
• **5G Home Internet** — cellular 5G sold as home broadband (T-Mobile, Verizon). Comparable to cable speeds, higher latency, data caps common. Great where wired options are bad.
• **Satellite (Starlink, HughesNet)** — best option in rural areas. Starlink is genuinely good (100-250 Mbps, 40 ms latency). Older satellite has 600 ms+ latency and is painful for anything real-time.

If fiber is available, grab it. Cable is fine for most households. DSL only if you have to.
""",
                """
Short version:

• Fiber — fastest and most stable. Get it if you can.
• Cable — most common, usually fine, watch out for asymmetric upload.
• DSL — old tech, rural only, slow but reliable.
• 5G Home — newer cellular-based option; good where cable/fiber is bad.
• Starlink — game-changer for remote rural homes.

All of them feed into your router. Once the internet arrives, the Wi-Fi experience in your home is 100% up to the router and your placement.
"""
            ],
            followUps: [
                "Fiber's big advantage isn't just raw speed — it's symmetric upload/download, which matters for video calls, streaming to Twitch, and cloud backups.",
                "If you're shopping ISPs, check bbb.org or local Reddit for real service reliability rather than trusting advertised speeds. Marketing numbers are theoretical maximums."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "wifi-calling",
            question: "What is Wi-Fi Calling and should I use it?",
            keywords: ["wifi", "calling", "wi-fi", "call", "vowifi", "volte", "carrier"],
            answers: [
                """
Wi-Fi Calling lets your phone route regular calls and texts over your home Wi-Fi instead of the cellular network. Major US carriers (Verizon, AT&T, T-Mobile) all support it for free.

When it helps:

• **Bad cell reception at home** — basement apartments, deep suburbs, rural dead zones.
• **Inside a large building** where concrete blocks cellular.
• **International travel** — calling back to US numbers is free on Wi-Fi even when your phone is physically overseas.

When it doesn't help:

• You have a strong cell signal anyway — Wi-Fi Calling usually picks whichever is better automatically.
• Your Wi-Fi is the problem — a shaky home network makes calls worse, not better.

Turn it on under Settings → Cellular → Wi-Fi Calling (iOS) or Settings → Network → Calls & SMS (Android). It's safe to leave enabled all the time.
""",
                """
It's what its name suggests: your phone makes calls and sends texts through your Wi-Fi instead of the cell tower. Invisible to the person you're calling.

The killer use case is bad cell reception at home. If you've ever had to walk to the window to finish a phone call, turn on Wi-Fi Calling and that problem disappears the moment you're on Wi-Fi.
"""
            ],
            followUps: [
                "Wi-Fi Calling hands off smoothly to cellular when you leave the house mid-call. It's not instant — you may hear a brief pause — but it works.",
                "Carriers require you to register an emergency address for Wi-Fi Calling, because 911 dispatch needs a location when they can't use cell tower triangulation."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "cast-airplay",
            question: "Why won't my AirPlay / Chromecast / Cast work?",
            keywords: ["airplay", "cast", "chromecast", "google", "cast", "mirror", "screen", "tv", "stream", "won't"],
            answers: [
                """
AirPlay and Chromecast both rely on the sending device and the receiver being on the same network — and being able to "see" each other. Three common reasons it stops working:

• **Different networks** — your phone is on the 5 GHz SSID, your Chromecast is on 2.4 GHz, and your router has them as separate networks. Solution: put them on the same SSID name (modern routers let you do this).
• **Guest network** — your TV is on the main network, but you or a visitor is on the guest network. Guest networks are intentionally isolated and block AirPlay/Cast discovery.
• **"Client Isolation" or "AP Isolation" enabled on the router** — this blocks devices from seeing each other. It's sometimes turned on by default on newer routers for security. Find it and turn it off.

Also worth checking:

• Firewall / IP filtering in the router admin.
• On iOS, AirDrop and AirPlay share discovery — if AirDrop is set to Contacts Only and you're not in your TV's contacts (you aren't), it can mysteriously misbehave.
• Both devices need mDNS / Bonjour enabled, which most routers pass through by default.
""",
                """
Almost always: your phone and the TV are on different networks, or "Client Isolation" is enabled on the router. Both break cross-device discovery.

Fastest test: put both devices on the same SSID (same name) and make sure guest networks aren't involved. If it suddenly works, that was the cause.
"""
            ],
            followUps: [
                "Eero, Google Nest, and Orbi mesh systems do something called 'client steering' that moves devices between bands automatically. That's usually fine but occasionally means the TV and phone temporarily end up on bands that are configured strangely.",
                "If AirPlay works but is super laggy, that's usually a Wi-Fi congestion issue rather than a discovery issue. 4K video over AirPlay needs ~30 Mbps of clean airtime."
            ],
            category: "Streaming"
        ),
        AssistantQA(
            topic: "share-wifi-password",
            question: "How do I share my Wi-Fi password with a guest?",
            keywords: ["share", "sharing", "password", "guest", "visitor", "qr", "code", "wife", "quickshare"],
            answers: [
                """
Modern options in order of easy-to-fancy:

• **iOS to iOS** — if your contact has you saved (and vice versa), have them tap your network on their iPhone while your iPhone is nearby and unlocked. A "Share Password" prompt appears automatically. Same works between macOS and iOS.
• **Android** — Settings → Wi-Fi → tap your network → Share. Your phone generates a QR code; they scan it and they're on.
• **QR code printout** — router apps from Eero, Google Nest, and TP-Link can generate a QR you can tape to the fridge. Anyone scans it, they're on.
• **Old-school** — just... tell them the password. Long passwords copy-paste well if you send over iMessage or WhatsApp.

If you share often, strongly consider a **guest network**. It has its own password you can share freely and isolates visitor devices from your own.
""",
                """
Three easy ways:

1. iPhone-to-iPhone auto-share when both contacts know each other. Cleanest.
2. QR code from your router's app or phone's Wi-Fi settings. Scan it, done.
3. Guest network with its own easy-to-remember password. Safer for recurring guests.

Sharing the main password with lots of people is fine for security (with modern WPA2/WPA3) but painful when you want to rotate it — every device needs the new password.
"""
            ],
            followUps: [
                "iOS password-sharing works silently in the background. If someone's holding their phone next to yours and nothing happens, either AirDrop is off on one side or they're not saved in your contacts.",
                "If you give the guest network a QR sticker on the fridge, visitors can just scan without you being involved — nicest setup for frequent hosts."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "weather-wifi",
            question: "Does weather affect my Wi-Fi?",
            keywords: ["weather", "rain", "storm", "humidity", "temperature", "affect", "thunderstorm"],
            answers: [
                """
Weather barely touches Wi-Fi *inside* your home — the signal is only traveling a few meters through walls, not miles through atmosphere.

Where weather does come in:

• **Your ISP's outside infrastructure** — heavy rain, wind, and ice can damage or wet coax, copper, or fiber connections to the pole. That shows up as "my internet is slow when it rains."
• **Satellite internet** — genuinely suffers in heavy weather. Starlink handles it well but not perfectly; older satellite is much worse.
• **Outdoor Wi-Fi to a backyard** — rain absorbs 2.4 GHz a little. It's a tiny effect, but in a borderline-coverage backyard you might notice.
• **Lightning surges** — real danger to any networking gear during storms. A good surge protector matters.

If your Wi-Fi feels worse in storms, the cause is almost always at the ISP's infrastructure, not your home network.
""",
                """
Indoor Wi-Fi doesn't care about the weather — the signal is traveling between rooms, not across miles. What you're probably noticing in bad weather is the ISP's line getting wet, damaged, or congested by everyone else at home using the internet.

Satellite and long-range outdoor links genuinely do degrade in rain. Everything else is downstream of ISP issues.
"""
            ],
            followUps: [
                "Humidity is a bigger effect over long outdoor ranges than most people realize — point-to-point Wi-Fi links between buildings can lose a decibel or two on humid days.",
                "If storms consistently take your internet out, have your ISP inspect the outside cable run. Cracked insulation lets water in and slowly kills the signal."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "wifi-health",
            question: "Is Wi-Fi safe? Does it cause health problems?",
            keywords: ["safe", "health", "dangerous", "cancer", "radiation", "emf", "emr", "kids", "worry"],
            answers: [
                """
Wi-Fi uses non-ionizing radio waves — the same class of energy as AM/FM radio and visible light, orders of magnitude weaker than what's needed to damage DNA or cells. The World Health Organization, the FCC, and the FDA have all reviewed decades of research and consistently found no evidence that typical Wi-Fi exposure harms human health.

For context:

• A router transmits at ~100 milliwatts (less than a quarter of what your phone puts out during a call).
• Signal strength falls off with distance rapidly, so being 2 meters away means you get a small fraction of the power.
• Humans have been exposed to radio waves (broadcast, cell, Wi-Fi) for roughly a century now — the long-term epidemiology is reassuring.

The one caveat: devices that sit physically against your body for long periods (phones in pockets, laptops on laps) get regulated under SAR limits. Those limits are set generously conservative, and modern gadgets meet them easily.
""",
                """
The scientific consensus is clear: typical home Wi-Fi exposure doesn't cause health problems. Wi-Fi radio waves are millions of times too weak to break chemical bonds or damage cells.

That said — if it bothers you, keep the router out of your bedroom and at least a couple meters from where you regularly sit. That's more than enough buffer at the power levels involved.
"""
            ],
            followUps: [
                "The strongest radio exposure most people get isn't from Wi-Fi — it's from their cellular phone when it's searching for a weak tower. If health concerns motivate you, Wi-Fi calling actually *reduces* your phone's RF output.",
                "If you still want to minimize exposure, turn the router off at night with a smart plug. You won't notice any difference in signal during the day and it uses slightly less electricity too."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "old-devices-slow-network",
            question: "Will one old device slow down my whole network?",
            keywords: ["old", "device", "slow", "whole", "network", "holding", "back", "legacy"],
            answers: [
                """
Mostly a myth, with a grain of truth.

**The myth:** A single old device drops your whole Wi-Fi to its speed.

**The reality:** Your router talks to each device at the fastest speed that device can handle. Your old Wi-Fi 4 laptop gets served at 100 Mbps, your new Wi-Fi 6 phone still gets served at 800 Mbps — in the same moments.

**The grain of truth:** Wi-Fi uses airtime, which is shared. If the old device is *actively* using the radio (streaming video, constantly pinging the router), it holds the channel for longer because its transmissions take more time per byte. That can crowd out faster devices during busy moments.

Practical advice:

• An idle old device (smart plug, old tablet sitting charging) doesn't slow anyone.
• An old device running constant traffic (4K streaming on an ancient TV) can crowd the channel.
• The fix isn't to replace the old device — it's to upgrade the *router* to one that handles mixed clients well (Wi-Fi 6 and up, with MU-MIMO and OFDMA).
""",
                """
The "one slow device ruins everyone" myth persists because old routers actually did work that way. Modern routers don't. Each device gets served at the fastest speed it can handle, independently.

Where the myth still holds: if the old device is constantly streaming, its air-time demands can make the channel feel busy for everyone. A Wi-Fi 6 or 7 router with OFDMA handles this much better than older gear.
"""
            ],
            followUps: [
                "802.11b (the original Wi-Fi from 1999) is the one genuine exception. A router serving a pre-2005 device may actually slow down — most modern routers let you disable 802.11b explicitly in advanced settings.",
                "If you want to verify, temporarily power off the old device and run a speed test. If your numbers don't change, it wasn't the bottleneck."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "wifi-standards-explained",
            question: "What does 802.11 ac / ax / be actually mean?",
            keywords: ["802.11", "ac", "ax", "be", "n", "standard", "standards", "generations", "letters", "wi-fi"],
            answers: [
                """
The IEEE 802.11 standard is the technical name for Wi-Fi. The letters after it identify the generation. Here's the plain-English cheat sheet:

• **802.11b** (1999) — first mainstream Wi-Fi. 11 Mbps. Obsolete.
• **802.11a / g** (early 2000s) — 54 Mbps. Obsolete.
• **802.11n** = Wi-Fi 4 — up to ~300 Mbps in practice. Found on a lot of older gadgets.
• **802.11ac** = Wi-Fi 5 — up to ~1 Gbps, introduced 5 GHz as the main speed band. Still fine for most homes.
• **802.11ax** = Wi-Fi 6 — much better at handling many devices at once. Wi-Fi 6E adds the 6 GHz band.
• **802.11be** = Wi-Fi 7 — newest, faster, supports multi-band at once. Limited device support yet.

The Wi-Fi Alliance renamed them to simple numbers because nobody could remember the letters. Both names still appear on boxes.
""",
                """
Translation guide:

• Wi-Fi 4 = 802.11n (older)
• Wi-Fi 5 = 802.11ac (very common today)
• Wi-Fi 6 = 802.11ax (current mainstream for new routers)
• Wi-Fi 6E = 802.11ax + 6 GHz band
• Wi-Fi 7 = 802.11be (bleeding edge)

Newer generations don't just add speed — they add smarter multi-device handling. Wi-Fi 6's OFDMA is why a busy household network feels so much better on new routers.
"""
            ],
            followUps: [
                "Wi-Fi generations are backward-compatible. A Wi-Fi 6 router happily talks to a Wi-Fi 4 laptop — just at Wi-Fi 4 speeds for that session.",
                "The speed jumps between generations are marketing numbers in ideal conditions. Real-world Wi-Fi 6 vs Wi-Fi 5 in most homes is maybe 20-40% faster, not the 'triple the speed' that boxes advertise."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "find-wifi-password",
            question: "How do I find my Wi-Fi password?",
            keywords: ["password", "find", "forgot", "lost", "recover", "remember", "saved", "network", "key"],
            answers: [
                """
A few easy places to look:

• **On the router itself.** Most routers ship with the default password printed on a sticker on the back or bottom (often labeled "Wi-Fi Password" or "Network Key"). If nobody changed it, that's the one.
• **On a device that's already connected.** On iPhone (iOS 16+) or Mac, go to Settings → Wi-Fi → tap the connected network → Password (Face ID required). On Windows, it's Settings → Network → Properties → "View Wi-Fi security key."
• **On the router admin page.** Open the **Speed** tab — I've got your gateway IP in the topology card. Type that into a browser, log in, and look under Wireless settings.

Last resort: factory-reset the router (recessed button on the back) and the password reverts to the printed sticker default. Every other device will need to reconnect, though.
""",
                """
Three reliable methods:

1. **Look at the sticker on the router.** Default passwords are printed there from the factory.
2. **Already on Wi-Fi from an iPhone or Mac?** Settings → Wi-Fi → (i) on the network → Password. Authenticate with Face ID/Touch ID and it shows up.
3. **Log into the router admin** — gateway IP from the Speed tab → in any browser → Wireless section.

If the password got changed and nobody knows what it is anymore, a factory reset is the nuclear option. Works, but resets every other custom setting too.
"""
            ],
            followUps: [
                "Pro tip: once you find it, save it in your password manager (or even iCloud Keychain). Wi-Fi passwords get rediscovered far more often than people expect.",
                "If you've got an iPhone or Mac in the house, you can AirDrop or share the Wi-Fi password to a guest's device without typing or saying it out loud — built into iOS 11+ and macOS High Sierra+."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "buy-vs-rent-router",
            question: "Should I buy my own router instead of renting from my ISP?",
            keywords: ["buy", "rent", "rental", "own", "isp", "modem", "fee", "monthly", "save", "money"],
            answers: [
                """
Almost always yes — buying your own router pays for itself in under a year.

• **Rental fees are real.** Most ISPs charge $10–15/month. Over two years that's $240–360 — more than a quality mesh system costs.
• **Your hardware is usually better.** ISP-provided gateways are built down to a price. A $150 Wi-Fi 6 router beats almost every rental box on coverage, speed, and update support.
• **You keep settings when you switch ISPs.** Rentals get returned. Yours stays.

The one catch: if your service includes a *modem* (cable, fiber ONT, DSL), you usually still need that part — but you can disable its built-in Wi-Fi and run your own router behind it.
""",
                """
Yes, with a small asterisk.

The math is overwhelming on the rental side ($10–15/month forever), and a one-time $150–300 router is almost always nicer hardware. The asterisk: cable and fiber services need the modem (or ONT) to actually decode the signal — so you might still rent the modem half but skip the router half. Ask the ISP for a "modem-only" or "bridge mode" config.

Once you go this route, you also get to control firmware updates and security patches yourself instead of waiting on the ISP.
"""
            ],
            followUps: [
                "If you're cable, the modem needs to be **DOCSIS 3.1** to handle gigabit plans without bottlenecking. Older DOCSIS 3.0 modems still work but can cap your speed.",
                "When you buy your own, make sure to call the ISP and explicitly cancel the rental — they don't always notice the returned hardware on their own, and the fee keeps quietly billing."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "moving-house-wifi",
            question: "How do I set up Wi-Fi when I move into a new place?",
            keywords: ["moving", "move", "new", "house", "apartment", "set", "up", "setup", "first", "day"],
            answers: [
                """
Beep boop — the moving-day Wi-Fi playbook:

1. **Schedule the ISP install** at least a week before you move. Earlier is better — most ISPs are booked solid in summer.
2. **Bring your own router** (if you have one) — works with any ISP, no rental fees, no waiting on a tech to bring one.
3. **Day-of**: the modem (or fiber ONT) goes wherever the cable enters the house. The router can sit there too, or — better — be moved to a central spot using a long Ethernet run.
4. **Walk the place**: open the **Survey** tab in WiFi Buddy and map your coverage. You'll know within 10 minutes whether you need a mesh node or just a router move.
5. **Reconnect everything**: phones first, then computers, then smart-home devices. (IoT gear is the slowest because it usually needs a 2.4 GHz network and an app pairing flow.)
""",
                """
The order I'd do it in:

• Confirm ISP install date before you sign the moving truck.
• Bring your own router if possible — saves the rental fee from day one.
• When the tech leaves, walk the home with the **Survey** tab so you know where the dead zones are *before* you commit to a permanent router spot.
• Reconnect the high-priority stuff first (phones, work laptop), and save the smart-home reconnect for the weekend — it's tedious.

If anything feels weird in the first few days, run a Speed Test in the **Speed** tab and compare to your plan. ISPs often start new accounts on a temporary throttle that lifts after 24–48 hours.
"""
            ],
            followUps: [
                "If your new place is wired with **Ethernet jacks in the walls**, that's a huge gift — you can put one router/access point per floor connected by Ethernet and get near-perfect coverage with zero mesh latency.",
                "Don't auto-trust the previous tenant's router. If one was left behind, factory-reset it before connecting anything — old credentials and port-forwards from a stranger are a real security risk."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "smart-camera-offline",
            question: "Why does my security camera or doorbell keep going offline?",
            keywords: ["camera", "cameras", "doorbell", "ring", "nest", "arlo", "blink", "offline", "disconnect", "drops"],
            answers: [
                """
Outdoor cameras and doorbells are notorious for dropping. Usually one of these:

• **Weak signal at the install spot.** They sit on the perimeter — exterior walls, the front porch — which is exactly where 2.4 GHz starts to die. Run a Survey out to the doorbell location and check the rating.
• **2.4 GHz only.** Most doorbells/cameras refuse to use 5 GHz. If your router is broadcasting only 5 GHz on a single SSID with band steering, the camera may not see a band it can use.
• **Battery cameras throttle.** Battery-powered models lower their transmit power to save juice, which makes a marginal connection unstable.
• **Power glitches.** Hardwired doorbells reboot every time the doorbell transformer dips. Old transformers (under 16 V AC) are a common culprit.

Quickest win: move your router (or a mesh node) closer to that side of the house, and double-check that the 2.4 GHz network is broadcasting where the camera can hear it.
""",
                """
The boring truth about smart cameras: they're all 2.4 GHz, they all sit at the edge of the house, and they all flake when the signal is weak.

Three fixes that almost always work:

1. **Add a mesh node within 20 feet of the camera.** Distance is the killer.
2. **Make sure 2.4 GHz is its own SSID.** If your router auto-steers everything onto 5 GHz, cameras can disappear.
3. **For battery-powered cams, charge them.** A camera at 15% battery cuts radio power to stretch life — which makes them drop.
"""
            ],
            followUps: [
                "Microwaves, baby monitors, and old cordless phones all crowd 2.4 GHz. If your camera goes offline at the same time of day every day, look for the household routine that overlaps.",
                "Some routers offer **client isolation** on the IoT/2.4 GHz network — turn it OFF temporarily if a camera is failing to connect. Some camera apps need to talk to your phone on the same subnet during pairing."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "smart-speaker-offline",
            question: "Why is my Alexa or Google Home offline?",
            keywords: ["alexa", "echo", "google", "home", "nest", "speaker", "smart", "offline", "won't", "respond"],
            answers: [
                """
Smart speakers usually go offline for one of three reasons:

• **The router rebooted and the speaker didn't reconnect cleanly.** Pull the speaker's power for 10 seconds and plug it back in — about 80% of "offline" cases fix here.
• **Wi-Fi password changed.** Smart speakers store the password and don't auto-update. You have to re-pair them in the companion app (Alexa app / Google Home).
• **2.4 GHz network is gone or renamed.** Most Echos and older Google Homes are 2.4 GHz only. If you split your bands or renamed the SSID, they can't find their old network.

If the speaker shows up in the **Devices** tab but says "offline" in its app, the Wi-Fi part is fine and it's an account/cloud issue — try signing out and back in on the companion app.
""",
                """
Quick triage:

1. **Power-cycle the speaker.** Unplug, wait 10 seconds, plug back in.
2. **Check the SSID.** If you changed your network name or password, you need to re-pair through the Alexa or Google Home app.
3. **Look in the Devices tab here in WiFi Buddy.** If you see it on the list, it's reaching the network — the issue is the cloud service, not Wi-Fi. Sign out and back in on its app.

If it keeps dropping daily, it's probably weak 2.4 GHz coverage where you put it. A mesh node nearby is usually the permanent fix.
"""
            ],
            followUps: [
                "Echo Dots and older Google Homes are 2.4 GHz only. Echo Show 10/15, Nest Hub Max, and the newer Echos can do 5 GHz — but if you have a mix, leave 2.4 GHz broadcasting too.",
                "If a speaker is in a far room and a mesh node fixes it, that's a hint your phone is also struggling out there even though it doesn't tell you. Run a Survey to confirm."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "find-my-router",
            question: "Where is my router? What does it look like?",
            keywords: ["where", "find", "look", "router", "modem", "box", "looks", "like", "what"],
            answers: [
                """
Your router is the box that creates your Wi-Fi network. Here's how to find it:

• **It has antennas (sometimes hidden inside).** Common shapes: a flat rectangle with 2–4 stick antennas, a small cube, a cylindrical tube, a tall white wedge, or a smooth puck (mesh node).
• **It has lights on the front.** Usually green/blue — power, internet, Wi-Fi, and sometimes a per-ethernet-port indicator.
• **It's connected to your modem with a short Ethernet cable.** The modem is the box that connects to the wall (cable, phone jack, or fiber ONT). The router is what plugs into that.
• **In many homes, it's all one box** — an "all-in-one gateway" from the ISP that's both modem and router. That's what Comcast/Spectrum/AT&T usually rent you.

Common hiding spots: behind the TV, in a coat closet, in the basement near where the cable comes in, on top of a kitchen cabinet. Hint: it's almost certainly closer to the front of the house than to the middle.
""",
                """
Picture a small box with blinking lights and either visible antennas or a modern minimalist puck shape. That's your router.

Most homes have it tucked next to where the cable or fiber line enters — often a closet, basement corner, or a shelf near the TV. If you have one box that the ISP gave you (Comcast/Verizon/etc.), it's usually a combo modem+router and that's *it*.

If your router is hidden in a closet, that's actually the #1 cause of weak signal. Wi-Fi can't go through walls, books, and a metal shelf gracefully. Move it out into the open and you'll instantly notice the difference.
"""
            ],
            followUps: [
                "Want to confirm? Open the **Speed** tab — the topology card shows your router's gateway IP. The closer you stand to the actual hardware, the lower that round-trip number drops.",
                "If you have **mesh nodes** (Eero, Google Nest, Orbi pucks), the main one connects to the modem and the satellites can be anywhere. They all count as 'your router' for purposes of where the Wi-Fi is coming from."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "choose-new-router",
            question: "How do I pick a new router?",
            keywords: ["pick", "choose", "buy", "new", "router", "best", "recommend", "shopping", "which"],
            answers: [
                """
Plain-English buying guide:

• **For a typical apartment (under ~1000 sq ft):** A single Wi-Fi 6 router in the $100–150 range is plenty. Look for "AX1800" or "AX3000" labeling.
• **For a typical house (1000–2500 sq ft, multi-floor):** A mesh kit with 2 nodes is the right call. Eero 6+, TP-Link Deco X55, Google Nest Wifi Pro, ASUS ZenWifi — all good. $250–400.
• **For a big house (2500+ sq ft) or thick walls:** 3-node mesh, ideally Wi-Fi 6 or Wi-Fi 6E. $350–600.

Things to actually look for, regardless of size:
• **Wi-Fi 6 (ax) at minimum.** Wi-Fi 5 (ac) is fine but you're buying yesterday's tech.
• **MU-MIMO and OFDMA support** — both make busy households much smoother.
• **Reasonable update history** — check the manufacturer's support page; if the latest firmware is from two years ago, skip.
""",
                """
Three buckets that cover 90% of homes:

1. **Single router, small space:** $100–150 Wi-Fi 6 unit (TP-Link, ASUS, Netgear). Minimal complexity, high value.
2. **Mesh, normal house:** A 2- or 3-pack from Eero, Nest, Deco, or Orbi. The first time you stop seeing dead zones, you'll feel the upgrade.
3. **Power-user / gigabit fiber:** Wi-Fi 6E or Wi-Fi 7 mesh, $500+. Worth it only if you're paying for a 1+ Gbps internet plan and have devices that can use it.

Avoid: anything advertising specs from before 2020, anything ISP-branded as "exclusive," and anything where the brand name doesn't survive a Google search.
"""
            ],
            followUps: [
                "Run a Survey in the current home before you buy. If the grade is C or below in just one room, mesh fixes that. If the grade is bad everywhere, your existing router is the problem and a single new router will work — but mesh is still cleaner.",
                "Wi-Fi 7 sounds tempting but is overkill for most plans. Until your devices and ISP plan can use Wi-Fi 7 features (multi-link operation, 6 GHz), Wi-Fi 6 or 6E is the sweet spot."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "extender-not-helping",
            question: "Why isn't my Wi-Fi extender helping?",
            keywords: ["extender", "booster", "repeater", "not", "helping", "still", "slow", "doesn't", "work"],
            answers: [
                """
Extenders disappoint people for predictable reasons:

• **It's installed where the signal is already weak.** An extender can only rebroadcast what it receives. Place it about halfway between the router and the dead zone — on the *strong-signal side* of where you want to fix.
• **It cuts speed in half.** A single-radio extender uses the same band to listen to the router and broadcast to your devices. That's a built-in 50% speed loss. Look at "tri-band" extenders if you want to dodge this.
• **Devices aren't switching to it.** Phones and laptops are stubborn — they hold onto the original router signal until it's almost dead. Toggle Wi-Fi off/on, or let it run a Survey through the room and watch what the latency does.
• **Your dead zone isn't a coverage problem.** It's an interference problem — neighbor Wi-Fi, microwaves, masonry. An extender on a crowded channel makes it *worse*.

The honest upgrade: replace the extender with a **mesh system**. Mesh handles handoffs and uses dedicated backhaul; a $30 extender almost can't compete.
""",
                """
Three reasons extenders flop:

1. **Bad placement.** They need to sit where the signal from the router is still strong. Put them halfway, not in the dead zone itself.
2. **Half the speed.** Most extenders rebroadcast on the same band they receive on, which halves throughput. So even if signal looks better, speed feels worse.
3. **Devices don't roam.** Your phone clings to the old router signal long past when the extender would be better. Forgetting and re-joining the network forces a fresh decision.

If you're still frustrated after fixing those, it's mesh time. The price gap shrunk a lot — entry-level mesh kits run $150 these days.
"""
            ],
            followUps: [
                "Some extenders create a **second SSID** (often \"Network_EXT\"). If yours does, your phone has to manually switch — auto-roaming basically doesn't happen. Mesh systems share one SSID, which is a big quality-of-life jump.",
                "If you must keep using an extender, plug it into the wall on a **wired Ethernet backhaul** if you can. That bypasses the half-speed problem and is essentially free mesh."
            ],
            category: "Coverage"
        ),
        AssistantQA(
            topic: "phone-cellular-at-home",
            question: "Why does my phone keep switching to cellular at home?",
            keywords: ["phone", "iphone", "cellular", "lte", "5g", "switch", "switches", "drops", "wifi", "home"],
            answers: [
                """
Modern phones aggressively fall back to cellular when Wi-Fi looks unreliable. The triggers:

• **Wi-Fi Assist (iOS) / Adaptive Wi-Fi (Android)** — both will silently use cellular when Wi-Fi has high latency or low throughput, even with full bars showing. Toggle Settings → Cellular → Wi-Fi Assist OFF (iPhone) to test.
• **Captive portal expired.** Your phone connected to a network that needs a sign-in (xfinitywifi, AT&T-Hotspot, etc.) and now silently won't trust it.
• **Weak signal in this room.** Walk to the router and see if it sticks. If yes, the issue is coverage, not config.
• **DNS issue.** If the router's DNS stopped responding, your phone marks the Wi-Fi unusable and falls to cellular even though signal looks fine.

Open the **Signal** tab — if latency reads above ~250 ms or fails outright, that's exactly the kind of network iOS will quietly route around.
""",
                """
Two main reasons this happens:

1. **iOS's "Wi-Fi Assist" or Android's smart network switch.** Both watch the connection quality and silently use cellular when Wi-Fi looks rough. Helpful on the road, frustrating at home. You can toggle these off in cellular settings.
2. **The Wi-Fi network is genuinely unreliable.** Even one room of dead zone is enough to trigger the fallback. Run a Survey to find the weak spot — fixing it usually fixes this complaint too.

If you're seeing this only in a specific room, it's coverage. If you see it across the whole house, the router probably has flaky moments and a reboot helps.
"""
            ],
            followUps: [
                "On iPhone, you can also forget the Wi-Fi network and rejoin — sometimes a stale captive-portal flag persists invisibly across days.",
                "If you have an **unlimited cellular plan**, you might not even notice this until you check your data usage and find your phone burned a few GB at home. That's a giveaway your Wi-Fi is degrading more than you realize."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "bluetooth-wifi-conflict",
            question: "Does Bluetooth interfere with my Wi-Fi?",
            keywords: ["bluetooth", "wifi", "conflict", "interfere", "interference", "headphones", "airpods", "speaker"],
            answers: [
                """
Yes, but only on the 2.4 GHz band — and modern devices coordinate well enough that it's usually subtle.

Here's the technical truth:

• Bluetooth and 2.4 GHz Wi-Fi share the same chunk of spectrum (2400–2483 MHz).
• Bluetooth hops across 79 narrow channels constantly, while Wi-Fi sits on a single 20–40 MHz channel. They collide briefly, both retransmit, and you get small hiccups.
• Apple, Intel, Qualcomm, and most chip vendors have implemented "coexistence" features that time-slice the radio so the two protocols actively avoid each other on the same device.

When this *does* hurt:
• Cheap Bluetooth gadgets without coexistence (no-name speakers, generic dongles).
• Many Bluetooth devices in close range during a heavy Wi-Fi session.
• Dual-radio chips at very close range where the antennas almost touch.

Quick fix: move anything Wi-Fi-critical to **5 GHz** — Bluetooth doesn't reach there.
""",
                """
A little, in the same way two cars share a road. Bluetooth and 2.4 GHz Wi-Fi both live in the 2.4 GHz slice of spectrum, so they technically compete.

In practice, modern phones and laptops handle the coexistence so well that you almost never notice. The exceptions:

• Cheap Bluetooth devices in a 2.4 GHz-heavy environment.
• Listening on AirPods while streaming 4K to the same iPhone over 2.4 GHz Wi-Fi (just put the iPhone on 5 GHz instead).

If gaming or video calls feel rough on Wi-Fi while AirPods are connected, that's the experiment to try.
"""
            ],
            followUps: [
                "Bluetooth Low Energy (BLE) is even less of a problem because the bursts are tiny. Smart-home sensors and fitness trackers basically don't bother Wi-Fi at all.",
                "If you're routing audio via AirPlay (Wi-Fi) instead of Bluetooth, you sidestep the issue entirely — AirPlay rides the same Wi-Fi network instead of fighting for radio time."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "microwave-kills-wifi",
            question: "My microwave kills my Wi-Fi — why?",
            keywords: ["microwave", "kitchen", "kills", "drops", "while", "running", "cooking", "interference"],
            answers: [
                """
Real thing, real physics — not your imagination.

Microwave ovens operate at exactly **2.45 GHz**, which sits dead center in the 2.4 GHz Wi-Fi band. Even a perfectly sealed microwave leaks a few milliwatts of RF, which is enough to drown out Wi-Fi signals nearby for the duration of the cook.

Symptoms:

• Wi-Fi drops only on **2.4 GHz** devices in the room. 5 GHz is unaffected.
• Drop lasts only while the microwave runs.
• Old microwaves (over ~10 years) leak more than newer ones.

Fixes:

• Move 2.4 GHz devices (smart speakers, IoT) to a different room or a different band when possible.
• Switch your phone or laptop to **5 GHz** — the microwave can't touch it.
• If the microwave is *very* old or has a damaged seal, replace it. (That's also a safety thing.)
""",
                """
The microwave isn't broken and your Wi-Fi isn't broken — they just operate on the same frequency.

Microwave ovens work at 2.45 GHz, the same band 2.4 GHz Wi-Fi uses. While the oven runs, it's blasting that frequency hard enough to overpower a router across the room. Anything on 5 GHz is fine.

Quickest fix: move the cookery-adjacent device to 5 GHz (or to the wired network), or just live with the 90-second blip while popcorn pops.
"""
            ],
            followUps: [
                "Old cordless phones (especially 2.4 GHz models from the early 2000s) are the other classic offender. If a 90s-style cordless handset still lives in the house, retire it — cell phones cost less per minute now anyway.",
                "If a microwave is killing Wi-Fi for an unreasonable amount of time after it stops running, the door seal might be failing. That's a safety issue worth a service call or replacement."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "only-one-device-slow",
            question: "Why is just one of my devices slow on Wi-Fi?",
            keywords: ["one", "device", "only", "just", "slow", "laptop", "phone", "rest", "fine"],
            answers: [
                """
When everything else is fine and one device is the outlier, the device is almost always the culprit:

• **Old Wi-Fi radio.** A laptop with a Wi-Fi 4 (802.11n) chip will cap around 50–80 Mbps no matter how good your router is. Replacement USB Wi-Fi 6 dongles are $30 and night-and-day.
• **Driver/firmware.** Especially on Windows, an outdated Intel or Killer Wi-Fi driver tanks throughput. Windows Update doesn't always grab the latest. Get it from the laptop maker's site.
• **Background bandwidth hog.** OneDrive/iCloud first sync, OS updates, Steam downloads. Run the Speed test, then check Activity Monitor / Task Manager for "Network" sorted by usage.
• **VPN.** Corporate or privacy VPNs typically halve speed and add jitter. Toggle off and retest.
• **Connected to the wrong band.** Forget the network and rejoin to land it on 5 GHz instead of a stale 2.4 GHz association.

A great clean test: same Speed Test from the slow device and from any other device, both standing in the same spot. If only one is slow, it's the device.
""",
                """
Step-by-step:

1. **Run a Speed Test from the slow device** in the room next to the router. Record numbers.
2. **Run the same test from a known-good device** in the same spot. If those numbers are very different, the problem is the slow device, not the network.
3. From there: update Wi-Fi drivers, check for background uploads, toggle VPNs off, and forget-and-rejoin the SSID to refresh the association.

If both devices are slow in that spot, it's the router or the ISP, not the device.
"""
            ],
            followUps: [
                "Some streaming sticks and old smart TVs are notorious for capping around 25–50 Mbps even on a strong signal — they ship with cheap radios. The fix is wired Ethernet, if the device supports it.",
                "On Mac, hold Option and click the Wi-Fi icon for a hidden detail panel — it shows your actual link speed (PHY rate). If that number is in the hundreds of Mbps, the radio is fine; if it's in the tens, the device is the bottleneck."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "isp-or-wifi-issue",
            question: "How do I tell if it's the internet or just my Wi-Fi?",
            keywords: ["internet", "wifi", "issue", "problem", "isp", "outage", "tell", "diagnose", "is", "it"],
            answers: [
                """
This is the single most useful diagnostic in home networking. Here's how I'd run it:

1. **Plug a laptop directly into the router with Ethernet** and run a Speed Test. If the wired test is fast → Wi-Fi is the issue. If it's also slow → the internet (ISP) is the issue.
2. **No laptop or no Ethernet?** Open the **Speed** tab. Look at the topology card. The router-RTT and ISP-RTT numbers tell the same story:
   • Router responsive (under 50 ms) but ISP slow/red → ISP problem.
   • Router slow → router or local Wi-Fi problem.
3. **Cellular-side check.** Turn Wi-Fi off and re-test on cellular. If cellular is fast and Wi-Fi-via-router is slow, it's your network.

Once you know which side it is, the fix paths are completely different — so this triage saves a lot of fiddling.
""",
                """
Three quick checks:

• **Wired Ethernet test from a laptop.** If wired is fast, the internet is fine and Wi-Fi is the bottleneck. If wired is also slow, it's the ISP.
• **The Speed tab's topology card here in the app.** Watch the router and internet RTT colors. Green router + red internet = ISP issue. Red router = local issue.
• **Cellular comparison.** Disable Wi-Fi briefly. If cellular Speed Test is fast at the same time, your Wi-Fi or router is the problem.

Different fixes — knowing which side it is matters.
"""
            ],
            followUps: [
                "If it's the ISP, **call them only after rebooting the modem** (unplug 30 seconds, plug back in). Their first-line script will demand it anyway and it fixes a surprising fraction of issues.",
                "Some ISP outages are area-wide. Type your provider name + your city + 'outage' into search before spending an hour troubleshooting your own gear."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "wired-vs-wireless",
            question: "Should I use Ethernet or Wi-Fi?",
            keywords: ["ethernet", "wired", "cable", "wireless", "wifi", "use", "vs", "should", "better"],
            answers: [
                """
The rule of thumb: **wired beats wireless for anything that doesn't move.**

Use Ethernet for:

• Desktop computers
• Smart TVs and streaming boxes you binge on
• Game consoles
• Printers (when reachable)
• Mesh node backhaul (if your house has Ethernet jacks)

Use Wi-Fi for:

• Phones and tablets (mobility wins)
• Laptops (when you're moving around)
• Smart-home stuff that you bought because it's wireless
• Anything that's not in cabling distance

Why the rule works: Ethernet is faster, more consistent, has no congestion, no interference, and adds zero ping. The trade-off is just running a cable. If you can run one for 30 seconds and never think about Wi-Fi for that device again, it's almost always worth it.
""",
                """
If you can use Ethernet, use Ethernet. Wireless is a convenience, not a quality choice — and consoles, TVs, and desktops never move anyway.

The big wins on wired:

• **Latency drops by 5–20 ms** versus Wi-Fi. Gaming gets noticeably crisper.
• **Speed is whatever your plan is**, no bottlenecks from band, range, or contention.
• **Stability is near-perfect.** No buffering hiccups, no random disconnects.

Run a single 25-foot flat Ethernet cable along the baseboard to the TV and the difference for streaming and gaming is immediate.
"""
            ],
            followUps: [
                "If you can't run a long cable, **MoCA adapters** (use existing coax cable in the walls) or **powerline adapters** (use existing electrical wiring) can give you near-Ethernet speeds in places where running new cable isn't feasible.",
                "Cat 5e is plenty for gigabit; Cat 6 is overkill for most homes but the price difference is small. Avoid Cat 7/8 marketing hype unless you're running 10 Gbps."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "router-running-hot",
            question: "Is it normal for my router to be hot to the touch?",
            keywords: ["hot", "warm", "heat", "router", "temperature", "burning", "feel", "touch"],
            answers: [
                """
Warm is normal. Hot enough that you can't keep your hand on it is a problem.

A healthy router runs around 100–115 °F (38–46 °C) on its case — noticeably warm but not uncomfortable. Things that push it past that:

• **Bad ventilation.** Routers stuffed in cabinets, under TVs, or stacked between modems and surge protectors. The vents need air on all sides.
• **Aging power supply.** External power bricks fail gradually, get hot, and start cooking the router.
• **Old or dust-clogged hardware.** Pull it out and look — vents full of dust hold heat.
• **Constant peak load.** Many devices uploading at once (security cameras + cloud backups) keeps the radio hot.

Long-term, heat shortens router life and causes random reboots. If yours feels uncomfortable to touch, give it more air or replace it. Modern Wi-Fi 6/7 routers run cooler than old gear.
""",
                """
A router that's warm to the touch is fine — that's the chip working. A router that's hot enough to be uncomfortable is overheating, which causes flaky disconnects and shortens its lifespan.

Quick fixes:

• Pull it out of the cabinet or shelf, give it open air on all sides.
• Clean the vents with compressed air.
• If the case is dirty AND the router is more than 5 years old, that's two reasons to replace it at once.

Heat-related router failures are usually preceded by months of "random reboots" before the router actually dies — so don't ignore it.
"""
            ],
            followUps: [
                "Power supplies (the wall brick) fail more often than the routers themselves. If your router is overheating *and* the brick is also hot, the brick is probably losing efficiency. Manufacturers will sometimes replace them under warranty.",
                "Mesh nodes mounted high on a shelf (vs. sitting on the floor) get noticeably better airflow and stay cooler. They also give better Wi-Fi coverage — bonus."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "mesh-sticky-node",
            question: "Why does my phone stay connected to a far mesh node instead of the closer one?",
            keywords: ["mesh", "sticky", "stuck", "node", "phone", "roaming", "switch", "stay"],
            answers: [
                """
The "sticky client" problem is one of mesh's oldest annoyances. Phones and laptops are conservative — they hold the existing connection until the signal looks genuinely bad, even when there's a much stronger node 10 feet away.

What helps:

• **Enable 802.11k/v/r** in your router's settings if it's not already on. These protocols let the network *suggest* roams to clients instead of waiting for them to decide.
• **Update the phone's OS.** Modern iOS and Android handle 802.11k/v/r much better than older versions.
• **Toggle Wi-Fi off and on.** Forces a fresh association — the phone picks the strongest node visible at that moment.
• **Disable smart connect** (which fuses 2.4 + 5 GHz into one SSID) only if your specific phone keeps clinging to 2.4 GHz. Some phones roam better with split bands.

A surprising number of "my mesh is bad" complaints are actually "my phone is sticky." Forgetting and rejoining the network usually proves which one it is.
""",
                """
Wi-Fi clients are stubborn. Most phones won't roam to a closer node until the current one is nearly unusable — even if a much stronger one is right there.

Two fixes that move the needle:

1. **Turn on 802.11k/v/r** in your mesh router admin (sometimes called "Fast Roaming" or "Smart Roaming"). It nudges your phone to switch nodes proactively.
2. **Toggle Wi-Fi off and back on** when you walk to a new room. It's a manual fix, but it works every single time.

If a specific room is always slow because of this, place an additional node closer to it — but the protocol fix above should be tried first.
"""
            ],
            followUps: [
                "Eero, Google Nest Wifi, Orbi, ASUS, and TP-Link Deco all support 802.11k/v/r. It's usually on by default but worth checking — the option is sometimes hidden in advanced settings.",
                "Some mesh systems have a 'Move device to closest node' debug button — handy for proving where the issue is. If the manual move fixes everything, you've confirmed the protocol-level roaming is what needs tuning."
            ],
            category: "Coverage"
        ),
        AssistantQA(
            topic: "wifi-power-outage",
            question: "Will my Wi-Fi work during a power outage?",
            keywords: ["power", "outage", "blackout", "battery", "ups", "during", "without", "electricity"],
            answers: [
                """
Short answer: no. Wi-Fi needs the router powered on, and the router needs wall power.

The longer answer:

• **Cellular still works** during local power outages — towers have battery backup. So your phone's data still works even when home Wi-Fi is dark.
• **Fiber and DSL service** may technically be live at the curb during a brief outage, but your modem and router need power to use it.
• **Cable internet** also typically stays live as long as your local node has battery — but again, your end needs power.

If you want home internet during outages: a small **UPS** (uninterruptible power supply, $80–150) plugged into your modem + router gets you 1–4 hours of buffer. Enough to ride out short outages and shut things down safely on long ones.

You can also set your phone to **Personal Hotspot** and tether laptops to it — the cellular connection works whether or not your home is dark.
""",
                """
No. Routers and modems need wall power.

The good news:

• **Phones still work on cellular**, so you can use your phone's hotspot to keep a laptop online.
• **A small UPS** (battery backup the size of a shoebox) can keep your modem + router running for an hour or two of short outages. Eero and similar mesh systems pull only ~5 watts each, so a $100 UPS goes a long way.

Beyond that, you're on cellular until the lights come back.
"""
            ],
            followUps: [
                "If you live somewhere with frequent outages, a UPS is a small luxury that pays off the first time you need to keep video calls or online learning going during a brownout.",
                "For longer outages, a portable power station (Jackery, EcoFlow, etc.) can keep router + modem + a laptop going for many hours. The router uses very little power, so most of that capacity goes to the laptop screen."
            ],
            category: "Reliability"
        ),
        AssistantQA(
            topic: "two-routers-home",
            question: "Can I use two routers in my house?",
            keywords: ["two", "second", "another", "extra", "router", "routers", "chain", "double"],
            answers: [
                """
Yes, with one important rule: only one of them should be doing the routing (NAT and DHCP). The other should be acting as just a wireless access point.

Three common setups:

• **Mesh kit (recommended).** Designed for this from day one. The nodes share an SSID and roam cleanly. Buy a kit — don't try to mix-and-match brands.
• **Second router as a wireless access point (AP mode).** Most routers have an "AP mode" toggle. Plug it into the main router via Ethernet, and it just adds Wi-Fi coverage on the same network.
• **Two routers each doing their own thing (don't do this).** "Double NAT" causes weird issues with games, video calls, and smart home gear. Avoid.

If you have an old router sitting around, AP mode is a free way to extend coverage to a second floor or far room. Just make sure to disable DHCP on the second one.
""",
                """
Absolutely — done correctly, two routers is one of the cleanest ways to extend coverage.

The rule: only the main router should hand out IP addresses. Set the second one to "Access Point mode" (sometimes called "Bridge mode" or "AP mode") so it just rebroadcasts Wi-Fi without creating a second network behind it.

Connect them with an Ethernet cable if you can — that gives near-zero performance loss and is essentially what mesh systems do internally.
"""
            ],
            followUps: [
                "If both routers are on the same SSID and password, devices roam between them roughly the same way they do in mesh. If they have different SSIDs, you'll have to switch manually — usually a worse experience.",
                "Avoid double NAT. Two routers each running NAT (the default mode) makes every game, video call, and IoT pairing flow flaky. The fix is always the same: put one in AP mode."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "download-vs-streaming",
            question: "Why does downloading kill my Wi-Fi but streaming doesn't?",
            keywords: ["download", "downloading", "streaming", "netflix", "kills", "different", "saturate"],
            answers: [
                """
Streaming and downloading look similar but use bandwidth completely differently.

• **Streaming uses a steady, modest amount.** A 4K Netflix stream runs at ~25 Mbps and barely above. It uses adaptive bitrate to stay smooth — if your network slows, it lowers quality and keeps going.
• **Downloads grab everything they can.** A Steam download or a system update will saturate every Mbps available, with no manners. Other devices on the network feel that immediately.

The result:

• Netflix on one TV: smooth, no impact on anyone else.
• Steam download on a desktop: every other device's video stutters, video calls drop, gaming pings spike.

Fix options:

• Use the **Pause** button in Steam/Battle.net/cloud-backup tools when others are gaming or on calls.
• Schedule big downloads for overnight.
• Enable **QoS** on your router and tag the desktop's downloads as low priority.
""",
                """
Streaming is bandwidth-polite — it uses what it needs and slows down if the network gets busy. Downloads are bandwidth-greedy — they take everything they can.

A 4K Netflix stream is ~25 Mbps steady. A Steam download will instantly use 100% of whatever your plan can deliver. So during the download, every other device feels the squeeze.

Easiest fix: pause the download when someone else needs the network, or schedule big stuff overnight. Routers with QoS can also de-prioritize known download patterns automatically.
"""
            ],
            followUps: [
                "Cloud backup tools (iCloud, OneDrive, Backblaze) are the silent culprit version of this — they wake up after long idle periods and start syncing megabytes of photos, killing everyone's Wi-Fi without anyone realizing.",
                "Many routers have a per-device upload/download cap setting. If one heavy user keeps spoiling things for the rest, capping that device at, say, 50% of plan speed makes the household much happier."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "pause-kids-wifi",
            question: "Can I pause my kids' Wi-Fi at bedtime?",
            keywords: ["kids", "children", "pause", "bedtime", "schedule", "parental", "time", "limit"],
            answers: [
                """
Yes — and most modern routers make this very easy.

Three ways to do it:

1. **Router app schedule.** Eero, Nest Wifi, Orbi, TP-Link Deco, and ASUS all have per-device scheduling. Add the kid's phone/tablet/console to a profile, set Wi-Fi off from 9 PM to 7 AM. Done.
2. **Apple Screen Time / Google Family Link.** These pause the *device's* network access regardless of which Wi-Fi it's on (school, friends' houses). Often a better fit than router-level controls for older kids.
3. **DNS-level filtering.** Services like NextDNS or Pi-hole can block specific categories (social, games) on a schedule without fully cutting Wi-Fi.

For most families, the router app is the right starting point — set it once and it runs every night automatically. Add Apple/Google parental controls on top if you want category filtering and screen-time reports.
""",
                """
Easy — most modern routers and mesh systems have this baked into their app.

The recipe:

1. Open the router's app (Eero, Nest Wifi, etc.).
2. Add the kid's devices to a profile (or set up a "Kids" profile).
3. Set a schedule — typically 9 PM to 7 AM on school nights.
4. Optional: add category filters (block YouTube, social, etc.) for during-the-day boundaries.

If your router doesn't support this directly, **Apple Screen Time** (per device, on any network) and **Google Family Link** (Android) accomplish the same thing without router involvement.
"""
            ],
            followUps: [
                "Older routers without per-device scheduling can sometimes be retrofitted with **OpenWrt** firmware or a **Pi-hole** for the same functionality — but at that point a $150 mesh kit is usually less work.",
                "Heads up: kids on **cellular data** will route around router-level pauses. If they have an iPhone or Android with a cell plan, you need device-level controls (Screen Time / Family Link) too."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "roommate-wifi",
            question: "How should I share Wi-Fi with roommates?",
            keywords: ["roommate", "roommates", "share", "sharing", "house", "apartment", "split", "bandwidth"],
            answers: [
                """
The civil-roommate Wi-Fi setup:

• **One router on a plan that can handle everyone.** Plan a minimum of ~25 Mbps download per concurrent heavy user. Four roommates streaming = 100+ Mbps plan minimum.
• **Use a guest network for visitors.** Keeps strangers off your main network without sharing the password every time.
• **One person owns the admin.** Pick a tech-comfortable person to handle the router and ISP — distributed ownership leads to nobody fixing things.
• **Rotate the bill or split equally.** Splitwise/Venmo on the first of the month. ($60–80 ISP plans split four ways = nothing.)

The worst-case version is everyone running their own router on the same modem. Don't do that — double NAT, weird IP collisions, none of it works well.
""",
                """
A few practical tips:

1. **Pick a plan with enough bandwidth.** Multiply expected concurrent heavy users × 25 Mbps. Five gamers/streamers = ~125 Mbps minimum.
2. **One main Wi-Fi network for everyone, plus a guest network for visitors.** Cleaner than rotating Wi-Fi passwords.
3. **Designate one router admin.** Ideally the most patient roommate — they call the ISP when things break.
4. **Be polite about big downloads.** Console game updates can drop everyone else into laggy land. Schedule them for overnight when possible.

If anyone really needs guaranteed quality (work-from-home, streaming income), Ethernet to their room ends every roommate-bandwidth-fight before it starts.
"""
            ],
            followUps: [
                "If you're sharing across multiple bedrooms in a big apartment, a 2-pack mesh handles whole-place coverage cleanly. Cheaper per square foot than buying a single high-end router.",
                "Don't share router admin credentials casually. Whoever can log in can see device names, watch traffic patterns, and even kick people off. Keep that to one person."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "vpn-work-laptop",
            question: "Why is my work laptop slow only when on VPN?",
            keywords: ["vpn", "work", "laptop", "slow", "corporate", "remote", "company"],
            answers: [
                """
Corporate VPNs add three things to every packet: encryption, a detour to the company's gateway, and aggressive security inspection. All three cost speed.

Typical impact:

• **30–50% throughput loss** is normal. A 200 Mbps Wi-Fi connection feels like 100 Mbps on VPN.
• **Higher latency** because traffic detours through a corporate hub before reaching its destination. Video calls and remote desktop are most affected.
• **More jitter** because the detour adds variability.

What you can usually still do:

• **Turn off split tunneling carefully.** Some VPNs route only company traffic; if yours routes everything, ask IT about a split-tunnel option.
• **Stay on 5 GHz Wi-Fi or wired Ethernet.** The VPN already eats overhead — don't add weak signal on top.
• **Use the closest VPN gateway.** Many corporate VPNs let you pick a region; the closest one is fastest.

If the laptop is fine *off* VPN and slow *on* VPN, the VPN is doing its job — the slowness is its overhead, not your network.
""",
                """
VPNs are inherently slower than the underlying network — they add encryption, routing detours, and traffic inspection. A 30–50% drop is normal.

Three things you can do:

1. **Use Ethernet** if possible. The cleaner the underlying connection, the less the VPN drag stacks.
2. **Pick the closest VPN region** if you have a choice (some clients let you pick).
3. **Ask IT about split tunneling** — if work traffic alone needs the VPN, having Netflix or video calls bypass it can dramatically improve quality.

If your laptop is fast *without* VPN and slow *with* VPN, that's normal VPN overhead — not a Wi-Fi problem.
"""
            ],
            followUps: [
                "Some corporate VPNs (especially older Cisco AnyConnect setups) are infamous for capping out around 50–80 Mbps no matter how fast your home internet is. That's the VPN concentrator's limit, not yours.",
                "Personal VPNs (NordVPN, ProtonVPN, etc.) are generally faster than corporate ones because they're optimized for consumer throughput, not enterprise security inspection."
            ],
            category: "Speed"
        ),
        AssistantQA(
            topic: "app-overview",
            question: "What does WiFi Buddy do?",
            keywords: ["wifibuddy", "buddy", "what", "does", "app", "overview", "features", "tour", "tabs"],
            answers: [
                """
Beep boop — happy to give you the tour. WiFi Buddy has five tabs:

• **Speed** — full speed test (download, upload, ping, jitter), live ISP→Router→Device topology, and a post-test Wi-Fi report on what your numbers are good for.
• **Survey** — walk your space using AR; the app paints a heatmap of your signal quality on a floor plan and grades the result A–F with a written explanation.
• **Signal** — a quick "what's my latency right now?" reading and a button to chat with me (Klaus) about anything Wi-Fi-related.
• **Devices** — scans your network and identifies every device on it (phones, TVs, IoT gear, doorbells, etc.) using eight different identification techniques. You can mark devices as trusted, rename them, and get alerted when something new shows up.
• **Pro** — explains what unlocks if you upgrade.

Everything runs **on your phone** — no cloud, no analytics, no logging. I'm offline too.
""",
                """
WiFi Buddy is a toolkit for understanding your home Wi-Fi without needing to log into the router.

The five tabs:

1. **Speed** — speed test + live latency to your router and ISP.
2. **Survey** — walk your home and see a heatmap of where signal is good vs bad.
3. **Signal** — one-tap latency check + Klaus (me).
4. **Devices** — full inventory of what's on your network.
5. **Pro** — subscription details.

Everything is local. Nothing about your network gets sent to a server — including your chats with me.
"""
            ],
            followUps: [
                "The most underused feature is the **Survey** — most people skip it because walking around feels weird, but it shows you exactly which rooms need help. Five minutes of walking saves hours of guesswork.",
                "I (Klaus) can read every tab's live data — current ping, last Speed Test, your Survey grade, your device count. Try asking 'how's my network?' and I'll give you a one-shot rundown."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "app-survey-how",
            question: "How does the AR Survey work?",
            keywords: ["survey", "ar", "augmented", "reality", "walk", "heatmap", "how", "works", "calibrate"],
            answers: [
                """
The Survey paints a real-time heatmap of your Wi-Fi quality onto a floor plan as you walk through your home.

Here's what's actually happening:

1. **You pick a floor plan** (Blank, Apartment, or Upstairs) and tap a starting point on the map.
2. **AR locks the origin** to a real-world position using your phone's camera. Your phone now knows where it is in physical space relative to the start.
3. **As you walk, the app pings the internet every quarter-second** (TCP to a public server) and records the round-trip time at each location.
4. **Each ping becomes a colored dot** on the map — green = fast, yellow = OK, red = slow. The dots blend into a heatmap.
5. **When you finish**, I generate a grade (A–F) based on coverage, median latency, and how bad the worst spots are. Plus a written breakdown: dead zones, router-direction hint, what to do next.

It needs ARKit, so iPhones from the last few years all work. No router login, no special setup.
""",
                """
You walk; the app maps. That's the elevator pitch.

Mechanics:

• AR tracks where you are using your phone's camera (no GPS — too imprecise indoors).
• Every quarter-second, the app pings the internet and records the round-trip time.
• Those pings turn into colored dots on a floor plan: green/yellow/red.
• At the end, you get a graded report — coverage %, latency median/p95, dead zones flagged, and recommendations.

Tips: walk normally, don't rush, and re-anchor at a landmark if the dots start drifting from where you actually are.
"""
            ],
            followUps: [
                "Re-anchoring is the secret sauce. AR drifts a little over long walks; tap **Re-anchor Here** at a known spot and the trail snaps back into place.",
                "If you don't see a grade at the end, you probably walked under 8 useful samples — try a longer walk (more than ~10 meters) and the report will appear."
            ],
            category: "Coverage"
        ),
        AssistantQA(
            topic: "app-pro-features",
            question: "What does WiFi Buddy Pro unlock?",
            keywords: ["pro", "premium", "subscription", "unlock", "paid", "features", "buy", "upgrade"],
            answers: [
                """
WiFi Buddy Pro unlocks three things:

1. **AR Wi-Fi Survey.** Walking and painting a heatmap of your home's Wi-Fi signal is Pro-only. Free users see the calibration screen so they know what they're getting, but the actual walk is gated.
2. **Smart Insights.** The graded post-survey report (grade + dead zones + router-direction hint + tailored recommendations) only renders for Pro users.
3. **Unlimited Klaus chat** (that's me). Free users get one question; Pro is unlimited.

Everything else — Speed Test, live topology, Signal latency check, full Device discovery — is free, forever.

Pricing: Monthly $3.99 or Yearly $34.99 (saves about 27%). Both come with a **3-day free trial** if you're a new user. Cancel anytime in Settings → Apple ID → Subscriptions.
""",
                """
Pro unlocks:

• **AR Survey** — the actual walk + heatmap.
• **Smart Insights** — the graded survey report with dead-zone analysis.
• **Unlimited chat with me** — free users get one question, Pro gets unlimited.

Everything else (Speed Test, live topology, Signal tab, Device discovery, network monitoring) is free.

$3.99/month or $34.99/year, 3-day free trial for new users. Apple handles all the billing — you can cancel any time in your iOS Settings.
"""
            ],
            followUps: [
                "The free trial doesn't auto-charge silently — Apple sends you a notification 24 hours before it ends, and I send a reminder too.",
                "If you upgrade and then cancel later, you keep Pro until the end of the period you paid for. Apple doesn't refund partial months for sub cancellations, but you don't lose access early either."
            ],
            category: "Setup"
        ),
        AssistantQA(
            topic: "app-privacy",
            question: "Does WiFi Buddy collect my data?",
            keywords: ["privacy", "data", "collect", "tracking", "analytics", "share", "send", "cloud"],
            answers: [
                """
No. WiFi Buddy collects nothing. Every measurement, scan, chat, and setting stays on your iPhone.

Specifics:

• **No analytics SDK.** No Mixpanel, no Amplitude, no Firebase Analytics, nothing.
• **No cloud servers** other than the public ones used for actual measurements (Cloudflare for speed tests, 8.8.8.8 for latency probes — same as any speed-testing tool).
• **No account.** You don't sign up, sign in, or hand over an email.
• **Klaus (me) is offline.** I don't talk to a cloud LLM. I'm a curated knowledge base running on your phone.
• **Survey results, device names, trust flags, chat history** — all stored only in iOS app storage (UserDefaults), wiped if you delete the app.

The trade-off is honest: I'm not as smart as a cloud AI. But I never leak anything about your network either.
""",
                """
Nope. Everything stays on your phone.

Concrete details:

• No analytics, no telemetry, no ad SDKs.
• No account or sign-in.
• Klaus runs offline — chats never leave your device.
• Survey data, device lists, and settings live only in local app storage.

The only network traffic the app generates is the actual measurements (speed test to Cloudflare, latency probe to 8.8.8.8), which is the same destination every speed-test app uses.
"""
            ],
            followUps: [
                "The App Store privacy nutrition label says \"Data Not Collected\" across the board. We had to file a Privacy Manifest with Apple to make sure that stays true even if a future SDK changes things.",
                "If you're really privacy-paranoid, you can verify there's no outbound traffic with a tool like **Little Snitch** or **NextDNS** — only Cloudflare's speed-test endpoints and 8.8.8.8 will appear during normal use."
            ],
            category: "Security"
        ),
        AssistantQA(
            topic: "app-trust-device",
            question: "What does \"Trusting\" a device do in WiFi Buddy?",
            keywords: ["trust", "trusted", "trust", "device", "rename", "what", "does", "mark"],
            answers: [
                """
Trusting a device tells WiFi Buddy "I recognize this — it belongs here." It's how you build a personal map of *your* network so unfamiliar devices stand out.

When a device is trusted:

• It gets a **TRUSTED** badge in the Devices list.
• You can give it a **custom name** ("Mom's iPad", "Living Room TV").
• New unknown devices appearing later trigger a notification — but only if there are already trusted devices on this network (so you don't get spammed at coffee shops).

Important details:

• Trust is **scoped per network**, keyed off your router's MAC address — not the IP. So a stranger's iPad on a different home network won't inherit a "TRUSTED" flag from yours.
• Trust info is **stored only on your phone**, never synced anywhere.
• Untrusting a device clears its custom name too.
""",
                """
Trusting a device says "I know this one." It does three things:

1. Adds a **TRUSTED** badge to the device.
2. Lets you **rename** it (\"Kids' Switch\", \"Backyard Camera\").
3. Helps the app spot **new unfamiliar devices** by comparing future scans against your trusted list.

It's all local to your phone, scoped to your specific home router. No cloud, no sync.
"""
            ],
            followUps: [
                "Trust is keyed by your router's MAC address. So if you visit your sister's house and the same IP pattern shows up, you won't accidentally see a stranger's device flagged \"trusted\" — that mistake was a real bug we fixed.",
                "If you switch ISPs or replace the router, your trust list resets — that's intentional, since the new gateway has a different MAC and the previous trust list might not even apply to the same physical devices."
            ],
            category: "Security"
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
    case safety                // "how do I hack my neighbor", "crack wifi password"
    case outOfScope            // "tell me a joke", "what's the weather"
    case qa(AssistantQA)
    case fallback
}

/// Holds whatever Klaus needs to remember between turns. Today this is
/// just the most recently answered topic so follow-ups can resolve to
/// "tell me more about X." Kept as a value so it's easy to test.
struct AssistantTurnMemory {
    var lastTopic: String?
    var followUpsServed: Set<String> = []   // per-topic delivered follow-ups
    /// How many "hi"-style greetings Klaus has handled this session
    /// (including the seeded session-open greeting). Used so a user
    /// who says "hi" twice in a row doesn't get two near-identical
    /// hellos with the same network rundown stapled on.
    var greetingsSeen: Int = 0
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
    // Follow-up patterns deliberately exclude bare conjunctions like
    // "and" / "or" — they appear inside dozens of legitimate QA
    // question titles ("What is jitter and why does it matter?",
    // "What's a guest network and should I use one?") and would
    // otherwise route a tapped chip to a follow-up of the previous
    // topic instead of the topic the user actually asked about.
    private static let followUpPatterns: [String] = [
        "tell me more", "more info", "any more", "anything else", "what else",
        "expand on", "go deeper", "elaborate", "more detail", "more details", "say more",
        "another one", "give me more", "keep going", "go on"
    ]
    private static let livePingPatterns: [String] = [
        "what's my ping", "whats my ping", "what is my ping", "my ping",
        "what's my latency", "whats my latency", "my latency", "ping right now",
        "current ping", "current latency", "how's my latency", "hows my latency",
        "how is my signal", "how's my signal", "hows my signal"
    ]
    // Note on live-data patterns: keep them specific enough that the
    // pattern only fires when the user is actually asking about a
    // live reading. Bare phrases like "my speed" / "my isp" /
    // "my devices" used to be in this list, but they collided with
    // legitimate QA questions ("Why are my speed test results
    // different every time?" / "Is my ISP throttling me?" / "Why do
    // my devices keep forgetting the Wi-Fi password?") and routed
    // them to live-data replies that ignored the actual question.
    private static let liveSpeedPatterns: [String] = [
        "what's my speed", "whats my speed", "what is my speed",
        "how fast", "what speed", "download speed", "upload speed",
        "my mbps", "what mbps", "current speed"
    ]
    private static let liveSurveyPatterns: [String] = [
        "my survey", "my grade", "my score", "how was my walk",
        "survey result", "survey results", "my report", "how did i do",
        "how is my coverage", "hows my coverage", "how's my coverage"
    ]
    private static let liveDevicesPatterns: [String] = [
        "how many devices", "what devices", "list devices",
        "what's on my network", "whats on my network", "what is on my network"
    ]
    private static let liveTopologyPatterns: [String] = [
        "my router ip", "router address", "gateway ip", "what's my gateway", "whats my gateway",
        "my ip address", "what's my ip", "whats my ip", "what is my ip",
        "what isp", "what's my isp", "whats my isp"
    ]
    private static let liveSummaryPatterns: [String] = [
        "how's my network", "hows my network", "how is my network",
        "how's my wifi", "hows my wifi", "how is my wifi",
        "give me the rundown", "give me the summary", "summary", "rundown",
        "how am i doing", "status report", "status check"
    ]
    /// Phrases that signal the user wants help getting onto a network
    /// or device they don't own. Anything that matches gets a polite
    /// refusal + redirect to the legitimate "secure my own network"
    /// QAs — never falls through to the QA matcher, which would
    /// otherwise happily dispense WPA2 advice in the wrong context.
    /// Patterns intentionally lean toward false positives over false
    /// negatives — better to occasionally over-refuse a borderline
    /// phrasing than to coach somebody through credential theft.
    private static let safetyPatterns: [String] = [
        "hack ", "hack my", "hack a ", "hack the ", "hack into",
        "hack the wifi", "hack wifi", "hacking wifi", "hacking into",
        "hack neighbor", "hack my neighbor", "hack my neighbour",
        "hacking my neighbor", "hacking the neighbor", "wifi hacking",
        "crack the password", "crack a password", "crack wifi", "crack the wifi",
        "cracking wifi", "wpa crack", "crack wpa",
        "steal wifi", "stealing wifi", "steal someone's wifi", "steal my neighbor",
        "free wifi without paying",
        "break into ", "breaking into ", "get into someone",
        "exploit my neighbor", "exploit the router", "exploit wifi",
        "deauth ", "deauth attack", "evil twin", "wifi pineapple", "rogue ap ",
        "bypass password", "bypass the password", "bypass wifi password",
        "bypass router", "bypass the router",
        "neighbor's wifi", "neighbour's wifi", "neighbors wifi", "neighbours wifi",
        "use the neighbor's", "use my neighbor's", "use my neighbour's",
        "log into my neighbor", "log into the neighbor", "log into someone",
        "spy on ", "snoop on ",
        "without permission", "without their knowledge", "without them knowing",
        "kick someone off their", "boot someone off their"
    ]
    /// Conversational gambits that are clearly not Wi-Fi — caught after
    /// smalltalk so "hi" or "thanks" still feel personal, but before
    /// the QA matcher so "tell me a joke" doesn't accidentally hit a
    /// keyword and produce something nonsensical. Klaus answers with a
    /// brief, in-character "not my zone" rather than the generic
    /// "didn't pick that one up" fallback.
    private static let outOfScopePatterns: [String] = [
        "tell me a joke", "tell a joke", "knock knock", "joke please",
        "what's the weather", "whats the weather", "weather today",
        "weather forecast", "weather tomorrow",
        "play music", "play a song", "play me a song",
        "set a timer", "set an alarm", "set a reminder",
        "what time is it", "what's the time", "whats the time",
        "write a poem", "write me a poem", "write a story", "write me a story",
        "what is 2 + 2", "what's 2 + 2", "whats 2 + 2", "2+2", "2 + 2",
        "calculate ",
        "who is the president", "who's the president", "whos the president",
        "recipe for", "how do i cook", "how to cook",
        "stock price", "bitcoin price", "ethereum price",
        "translate ", "in spanish", "in french", "in german"
    ]

    static func classifyIntent(rawInput: String, memory: AssistantTurnMemory) -> AssistantIntent {
        let cleaned = sanitize(rawInput).lowercased()
        guard !cleaned.isEmpty else { return .fallback }

        // Safety always wins. If the user is asking how to attack a
        // network or device they don't own, intercept before any QA
        // keyword can accidentally hand back useful security advice in
        // the wrong context.
        if matchesAny(cleaned, safetyPatterns) { return .safety }

        // Chip-tap fast path: when the input matches a known QA's
        // question verbatim (after word-boundary normalization), route
        // straight to that QA. Curated suggestion chips are the
        // dominant input source for free-tier users and tying QAs by
        // keyword score (e.g. "What does WiFi Buddy do?" vs.
        // "What is Wi-Fi, actually?") used to send chip taps to the
        // wrong topic. Matching by question text is unambiguous.
        if let qa = matchingQAByQuestionText(cleaned) {
            return .qa(qa)
        }

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

        // Out-of-scope conversational asks (jokes, weather, math) get a
        // tailored polite redirect rather than tripping the QA matcher.
        if matchesAny(cleaned, outOfScopePatterns) { return .outOfScope }

        // QA fallback — keyword tokenization + scoring against the
        // knowledge base. Threshold is "at least one keyword overlap".
        if let qa = bestQA(for: cleaned) { return .qa(qa) }
        return .fallback
    }

    /// Word-boundary-safe substring check for intent classification.
    ///
    /// A naive `text.contains(pattern)` here used to mis-classify
    /// chip-tapped questions because patterns are short and the input
    /// is free-form. For example, the thanks pattern `"ty "` matched
    /// inside `"security "` and routed `"Why does my security camera
    /// or doorbell keep going offline?"` to `.thanks` instead of the
    /// `smart-camera-offline` QA. The fix normalizes both sides into
    /// a space-padded, single-spaced word stream so a pattern like
    /// `"ty"` only fires when "ty" stands on its own — never inside
    /// `"security"`, `"loyalty"`, `"empty"`, etc. Multi-word patterns
    /// such as `"how do i use"` continue to match cleanly because
    /// runs of whitespace and punctuation collapse to a single space.
    private static func matchesAny(_ text: String, _ patterns: [String]) -> Bool {
        let normalizedText = normalizeForMatching(text)
        for pattern in patterns {
            let normalizedPattern = normalizeForMatching(pattern)
            if normalizedText.contains(normalizedPattern) { return true }
        }
        return false
    }

    /// Lowercases and collapses any run of non-alphanumeric characters
    /// (apostrophes preserved so contractions like `what's` survive)
    /// into a single space, padding with leading and trailing spaces
    /// so callers can rely on word-boundary substring matching.
    private static func normalizeForMatching(_ s: String) -> String {
        var result = " "
        var lastWasSpace = true
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "'" {
                result.append(ch)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        if !result.hasSuffix(" ") {
            result.append(" ")
        }
        return result
    }

    /// Return the QA whose `question` text exactly matches the user's
    /// input after word-boundary normalization. Used as a fast path
    /// for tapped suggestion chips, where the input string is the
    /// curated question verbatim.
    private static func matchingQAByQuestionText(_ cleanedLowercase: String) -> AssistantQA? {
        let normalizedInput = normalizeForMatching(cleanedLowercase)
        for entry in WiFiAssistantKnowledge.entries {
            if normalizeForMatching(entry.question) == normalizedInput {
                return entry
            }
        }
        return nil
    }

    /// Score each QA by counting how many of its `keywords` appear as
    /// whole-word matches in the user's input. Uses the same
    /// space-padded normalization as `matchesAny` so hyphenated
    /// keywords like `"wi-fi"` / `"long-term"` / `"802.11"` line up
    /// with the equivalent forms users actually type ("Wi-Fi",
    /// "long term", "802.11"), and so a keyword like `"ip"` matches
    /// the standalone word "IP" without accidentally matching inside
    /// "script" or "trip".
    ///
    /// Stop-word keywords (`"what"`, `"how"`, `"the"`, etc.) and
    /// single-character keywords are skipped at scoring time — they
    /// over-match against virtually every question and were dead
    /// weight under the previous `Set.contains` matcher anyway.
    private static func bestQA(for text: String) -> AssistantQA? {
        let normalizedInput = normalizeForMatching(text)
        guard normalizedInput.trimmingCharacters(in: .whitespaces).isEmpty == false else {
            return nil
        }

        var bestScore = 0
        var best: AssistantQA?
        for entry in WiFiAssistantKnowledge.entries {
            var score = 0
            for keyword in entry.keywords {
                let lowered = keyword.lowercased()
                if lowered.count < 2 { continue }
                if stopwords.contains(lowered) { continue }
                let normalizedKeyword = normalizeForMatching(keyword)
                let trimmedKeyword = normalizedKeyword.trimmingCharacters(in: .whitespaces)
                if trimmedKeyword.isEmpty { continue }
                if normalizedInput.contains(normalizedKeyword) {
                    score += 1
                }
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
                text: composeGreetingReply(context: context, memory: memory),
                relatedQuestions: starterQuestions,
                topic: nil
            )
        case .safety:
            return AssistantReply(
                text: pick(safetyReplies),
                relatedQuestions: [
                    "Is my network secure?",
                    "Can my neighbors use my Wi-Fi?",
                    "What's a guest network and should I use one?"
                ],
                topic: nil
            )
        case .outOfScope:
            return AssistantReply(
                text: pick(outOfScopeReplies),
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
        case "good-ping", "improve-signal", "what-is-jitter", "gaming-peak", "video-calls", "packet-loss", "work-from-home-setup":
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
        case "isp-mismatch", "speed-test-fluctuation", "where-to-test", "slow-upload", "fiber-cable-dsl":
            if let down = context.lastDownloadMbps, let up = context.lastUploadMbps {
                return "Quick context: your last Speed Test landed at \(formatMbps(down)) down / \(formatMbps(up)) up."
            }
        case "rooms-vary", "extender-vs-mesh", "mesh-vs-router", "basement-garage", "apartment-wifi":
            // Comparison/situational questions where the user's actual
            // survey result legitimately changes the recommendation.
            // We only overlay when there's a clear actionable signal —
            // dumping "graded B with no dead zones" into a generic
            // question reads as filler, not insight.
            if let grade = context.lastSurveyGrade,
               let dz = context.lastSurveyDeadZoneCount,
               dz > 0 {
                return "Quick context: your last Survey graded \(grade) with \(dz) dead zone\(dz == 1 ? "" : "s") flagged."
            }
        case "router-placement":
            // The placement answer is generic by design — a checklist
            // of rules of thumb. Only weave in live data when there's
            // a real dead-zone count to act on; otherwise the overlay
            // feels stapled-on and unrelated to "where do I put it?"
            if let dz = context.lastSurveyDeadZoneCount,
               dz > 0 {
                return "Heads up: your last Survey flagged \(dz) dead zone\(dz == 1 ? "" : "s"), so placement is exactly the lever that'll move that needle."
            }
        case "security", "neighbors", "wifi-security-types", "iot-load", "what-is-mac-address":
            if let count = context.deviceCount {
                let trusted = context.trustedDeviceCount ?? 0
                let unknown = max(0, count - trusted)
                if unknown > 0 {
                    return "Quick context: your last scan saw \(count) devices, \(unknown) of which aren't marked trusted yet."
                } else if count > 0 {
                    return "Quick context: your last scan saw \(count) devices and they're all marked trusted."
                }
            }
        case "what-is-ip-address", "what-is-nat":
            if let lip = context.localIP, let gip = context.gatewayIP {
                return "Quick context: your device's current IP is \(lip), and your router's gateway IP is \(gip)."
            } else if let lip = context.localIP {
                return "Quick context: your device's current IP on this network is \(lip)."
            }
        case "connected-no-internet", "outage-troubleshoot":
            if let gms = context.gatewayLatencyMs, let ims = context.ispLatencyMs {
                let gHealthy = gms < 50
                let iHealthy = ims < 150
                if gHealthy && !iHealthy {
                    return "Quick context: your router is responsive (\(Int(gms.rounded())) ms) but the path out to the internet is slow or unreachable (\(Int(ims.rounded())) ms to 8.8.8.8) — that points at the ISP or modem, not your Wi-Fi."
                } else if !gHealthy && !iHealthy {
                    return "Quick context: both your router RTT (\(Int(gms.rounded())) ms) and ISP RTT (\(Int(ims.rounded())) ms) are elevated — the router is probably overloaded or having trouble staying synced."
                } else if gHealthy && iHealthy {
                    return "Quick context: actually, your router and ISP are both responding well right now (router \(Int(gms.rounded())) ms / ISP \(Int(ims.rounded())) ms). If something specific isn't loading, it's probably that site, not your network."
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
    ///
    /// If the body already starts with a "Quick context:" or
    /// "Heads up:" overlay (added by `liveOverlay`), we skip the
    /// opener — stacking two prefixes reads as filler.
    private static func dressUp(_ body: String, topic: String) -> String {
        let startsWithOverlay = body.hasPrefix("Quick context:") || body.hasPrefix("Heads up:")

        var prefix: String?
        var suffix: String?
        let roll = Int.random(in: 0..<100)
        switch roll {
        case 0..<50: break                          // raw
        case 50..<75: prefix = pick(openers)        // opener only
        case 75..<90: suffix = pick(closers)        // closer only
        default: prefix = pick(openers); suffix = pick(closers)
        }

        if startsWithOverlay { prefix = nil }

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

• Explain anything Wi-Fi — from the absolute basics (what is an SSID, IP, DNS, MAC?) to the deep stuff (QoS, beamforming, packet loss, NAT, Wi-Fi generations). I aim for plain English.
• Troubleshoot real-life problems — printer won't print, "Connected, no internet," laggy gaming, hotel captive portals, slow basement Wi-Fi, AirPlay drops, and similar.
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

    /// Composes the greeting reply. The first greeting in a session
    /// (the seeded one Klaus opens with) gets the full warm welcome
    /// plus a one-line live-data rundown. Any subsequent "hi"s get a
    /// shorter conversational acknowledgment so Klaus doesn't dump the
    /// same network status into every greeting and read like a kiosk.
    private static func composeGreetingReply(context: KlausChatContext, memory: AssistantTurnMemory) -> String {
        if memory.greetingsSeen >= 1 {
            return pick(repeatGreetingReplies)
        }

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
        "Hi! What are we troubleshooting?",
        "Hey, glad you stopped by. Klaus here, ready to dig in.",
        "Howdy. Wi-Fi diagnostics on standby.",
        "Greetings, human. Tiny robot, ready to help."
    ]

    /// Used when the user says hi after Klaus has already greeted them
    /// in this session. Shorter and more conversational than the
    /// session-open greeting so we don't repeat the same kiosk-style
    /// "I can already see..." rundown on every hello.
    private static let repeatGreetingReplies: [String] = [
        "Hey again — what did you want to dig into?",
        "Beep boop — still here, antenna up. What's on your mind?",
        "Hi! Yep, still listening. Got a Wi-Fi question for me?",
        "Hello again. Pick a suggestion or fire one off.",
        "Twice in one session — I'm flattered. What can I help with?",
        "Still parked in your phone. What do you want to look at?",
        "Right back atcha. Where do you want to start?"
    ]

    // MARK: Safety + out-of-scope replies

    /// Klaus's polite refusals when the user asks for help getting
    /// onto a network or device they don't own. Each variant declines
    /// in-character and pivots to the legitimate "secure your own
    /// network" QAs so the user has somewhere productive to go.
    private static let safetyReplies: [String] = [
        """
Beep boop — that's a hard nope from me. I won't help with getting onto a network or device that isn't yours. Hopping onto someone else's Wi-Fi without permission is illegal pretty much everywhere, and even an offline little robot like me isn't going there.

If you're worried about *your own* network being on the receiving end of that kind of thing, I can absolutely help. Try **"Is my network secure?"** or **"Can my neighbors use my Wi-Fi?"** to start.
""",
        """
I have to sit that one out. Walking somebody onto a network they're not authorized on isn't a Wi-Fi tip — that's computer-misuse-act territory, and it's not something I'm built to coach.

What I *can* do is help you make sure nobody's doing the same to you. Want to check your own setup? Ask **"Is my network secure?"** and I'll dig in.
""",
        """
Not a road I'll go down. Accessing someone else's Wi-Fi or devices without permission is illegal even when the network's wide open, and helping with it isn't in my wheelhouse.

If your real question is "could this happen to *me*?", that's a great one. Ask about your network's security and I'll walk through hardening it.
"""
    ]

    /// Polite redirects for clearly non-Wi-Fi conversational gambits
    /// (jokes, weather, math). Klaus stays in character and points
    /// the user back at his actual area of expertise.
    private static let outOfScopeReplies: [String] = [
        """
Ha — wish I could, but I'm a one-trick robot. My whole training is Wi-Fi: signal, speed, security, devices, the lot. For anything outside that I'm intentionally useless (kept me small enough to live entirely offline on your phone).

Got a Wi-Fi question I can dig into instead?
""",
        """
That's outside my zone, friend. I'm strictly Wi-Fi — I can troubleshoot a dead zone, decode a weird device on your network, or explain why your speed test feels off, but I can't do general assistant stuff.

Tap a suggestion if you want to head back to my actual area of expertise.
""",
        """
Beep boop — request denied, but politely. I don't have a chat model behind me, just a tightly focused Wi-Fi knowledge base and the ability to read your in-app metrics. Anything not Wi-Fi-shaped slips right past me.

Tell me what's going on with your network and I'll be much more useful.
"""
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

            // Track repeat greetings so the next "hi" gets a shorter,
            // more conversational acknowledgment instead of replaying
            // the full session-open welcome and live-data rundown.
            if case .greeting = intent {
                memory.greetingsSeen += 1
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
        // Count the seeded session-open greeting so a subsequent user
        // "hi" goes through the shorter repeat-greeting branch instead
        // of replaying the same welcome.
        memory.greetingsSeen += 1
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
