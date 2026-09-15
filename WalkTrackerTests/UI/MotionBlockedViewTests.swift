import Foundation
import Testing
import UIKit

@testable import WalkTracker

@Suite("Pantalla bloqueante · abrir Ajustes")
struct MotionBlockedViewTests {

    /// La vista no puede usar UIKit (AD-10) y escribe la URL a mano: este test es lo que
    /// impide que una errata deje la única salida de la pantalla sin abrir Ajustes.
    @Test("La URL de Ajustes coincide con UIApplication.openSettingsURLString")
    @MainActor
    func settingsURLMatchesSDK() throws {
        let expected = try #require(URL(string: UIApplication.openSettingsURLString))
        #expect(MotionBlockedView.settingsURL == expected)
    }
}
