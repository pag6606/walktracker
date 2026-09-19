import Domain
import Foundation
import OSLog

/// Frase motivacional del arranque (2.2, CAP-6, AD-7): elegirla, adjuntarla a la sesión ya
/// abierta y gobernar su overlay.
///
/// **La sesión arranca primero y la frase va encima.** Cuando el overlay aparece, el
/// cronómetro ya cuenta y el podómetro ya está abierto. La frase nunca bloquea, retrasa ni
/// condiciona el arranque.
///
/// **Síncrona y local, a diferencia del clima.** Elegir una frase es leer un array y pedir un
/// número: no hay `Task`, ni topes, ni `FirstResult`. La maquinaria asíncrona de
/// `SessionStore+Weather.swift` está ahí porque la red puede no volver; aquí no hay red.
///
/// **Degrada en silencio hacia el usuario, nunca hacia el log.** Sin banco no hay frase y la
/// caminata sigue (decisión de Paul, a diferencia del catálogo de logros de AD-5); y si la
/// ventana de recientes llegara a excluir el banco entero, el fallback heredado —ignorar el
/// filtro— se registra con `log.info`: la promesa de "20 sin repetir" no puede romperse sin
/// que quede rastro.
///
/// Escribe `quote` (solo aquí y en el reset) y, al adjuntar, `session` y `metrics`.
extension SessionStore {

    /// Elige la frase de la sesión recién abierta, la adjunta al agregado, la registra en la
    /// ventana de recientes y enciende el overlay.
    ///
    /// Va **después** de `hasSession = true` —la sesión ya está presentada y contando— y
    /// **antes** de `persist()`, para que el `quoteId` entre en el primer snapshot: un
    /// force-quit temprano no puede dejar una sesión con frase mostrada y sin `quoteId`.
    ///
    /// No hace nada sin sesión, con una finalizada o con una que ya tiene frase: adjuntarla es
    /// del arranque, no de cada evento.
    func attachQuoteForNewSession() {
        guard var session, session.status != .finished, session.quoteId == nil else { return }
        guard let selection = MotivationEngine.selectQuote(
            from: quotes,
            recentQuoteIds: settings.recentQuoteIds,
            random: random
        ) else {
            // Dos causas muy distintas detrás del mismo `nil`, y solo una es un fallo: sin
            // banco la degradación es la esperada (decisión de Paul); un puerto de azar que no
            // devuelve índice sobre un banco que sí tiene frases está roto.
            if quotes.isEmpty {
                log.info("Sin frase motivacional: el banco está vacío")
            } else {
                log.error("Sin frase motivacional: el puerto de azar no devolvió un índice válido sobre un banco de \(self.quotes.quotes.count, privacy: .public) frases")
            }
            return
        }
        if selection.ignoredRecentWindow {
            // Los dos números, porque el diagnóstico es distinguir "la ventana se corrompe" de
            // "el banco encoge": el tamaño de la ventana está topado a 20 por construcción y
            // casi nunca dice nada por sí solo.
            log.info("Frase motivacional: las \(self.settings.recentQuoteIds.count, privacy: .public) recientes cubrían el banco entero (\(self.quotes.quotes.count, privacy: .public) frases); se ignora el filtro y se elige de todo")
        }
        do {
            try session.attachQuote(selection.quote.id)
        } catch {
            log.error("Frase rechazada en la frontera: \(String(describing: error), privacy: .public)")
            return
        }
        self.session = session
        metrics = session.metrics(at: clock.now)
        settings.recordShownQuote(id: selection.quote.id)
        quote = selection.quote
    }

    /// El overlay se va: un tap en cualquier punto, o los 3 s cumplidos. Son la misma
    /// intención y llegan las dos de la vista (sección 6 del gate: la vista no escribe estado).
    ///
    /// La sesión sigue exactamente igual por debajo —el `quoteId` ya está en el agregado y en
    /// el snapshot—: esto solo apaga la presentación.
    func dismissQuote() {
        quote = nil
    }
}
