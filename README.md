# SignalStrengthPainter

SwiftUI iOS app that "paints" a 2D walk path and colors each segment by measured network latency.

## Included Features

- Motion tracking with `CMPedometer` and `CMMotionManager` (`yaw` heading) to convert walking into `(x,y)` points.
- Network diagnostic engine probing `8.8.8.8:53` every 500ms.
- Real-time `Canvas` trail rendering:
  - Green: `< 50ms`
  - Yellow: `50ms - 150ms`
  - Red: `> 150ms` or timeout
- Consumer-friendly controls:
  - `Start Walk` calibrates origin at `(0,0)`
  - `Reset` clears the map
  - Legend labels for signal quality use-cases

## Files

- `SignalStrengthPainterApp.swift`: App entry point
- `ContentView.swift`: Main UI
- `SignalCanvasView.swift`: Efficient drawing layer
- `SignalMapViewModel.swift`: ObservableObject bridge for motion + network
- `LatencyProbe.swift`: Lightweight latency probe
- `SignalTrailModels.swift`: Data/quality models
- `Info.plist`: Motion + local network privacy descriptions

## Open and run (Xcode project included)

1. Open `SignalStrengthPainter.xcodeproj` in Xcode (double-click or **File → Open**).
2. Select the **SignalStrengthPainter** scheme and your iPhone or a simulator.
3. In **Signing & Capabilities**, choose your **Team** so the app can install on device (bundle ID is `com.example.SignalStrengthPainter`; change it in the target’s **General** tab if you prefer).
4. Build and run (**⌘R**). For motion and pedometer, use a **physical iPhone**; the simulator has limited motion support.

### Manual setup (only if you are not using the bundled `.xcodeproj`)

1. Create a new iOS App project named `SignalStrengthPainter` (SwiftUI lifecycle).
2. Replace generated Swift files with the contents of `SignalStrengthPainter/`.
3. Point **Info.plist** to `SignalStrengthPainter/Info.plist` or merge the privacy keys into your plist.
# SignalStrengthPainter
