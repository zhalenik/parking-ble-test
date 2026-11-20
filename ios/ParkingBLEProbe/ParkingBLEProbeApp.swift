import SwiftUI

@main
struct ParkingBLEProbeApp: App {
    @StateObject private var ble = BLEManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
        }
        .onChange(of: scenePhase) { newPhase in
            ble.recordScenePhase(newPhase)
        }
    }
}
