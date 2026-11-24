import SwiftUI

@main
struct ParkingBLEProbeApp: App {
    @StateObject private var ble = BLEManager.shared
    @StateObject private var api = APIClient.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .environmentObject(api)
        }
        .onChange(of: scenePhase) { newPhase in
            ble.recordScenePhase(newPhase)
        }
    }
}
