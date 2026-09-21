import Foundation

/// Los instantes de `sessions.json` y `achievements.json`, en **ISO-8601** (contrato de datos,
/// 5.1).
///
/// **Por qué no son milisegundos.** `activeSession.json` los guarda en milisegundos enteros
/// porque ese es el contrato del snapshot de la v3 (domain-model.md §8), y eso no cambia. Los
/// ficheros nuevos son del contrato de datos del historial, que fija ISO-8601. Las dos
/// serializaciones **conviven en el mismo directorio y no se mezclan**: cada adapter conoce la
/// suya y ninguna clave se llama igual (`startedAtMs` frente a `startedAt`).
///
/// **Se escribe con milisegundos y se lee con y sin ellos.** Escribir la fracción hace el viaje
/// de ida y vuelta estable hasta el milisegundo, que es exactamente la precisión que el snapshot
/// ya tenía; aceptar la forma sin fracción deja leer un fichero escrito a mano o por otra
/// herramienta sin apartarlo por una coma.
///
/// `Date.ISO8601FormatStyle` y no `ISO8601DateFormatter` a propósito: es un tipo de valor
/// `Sendable`, así que puede ser una constante estática compartida bajo concurrencia estricta
/// (AD-12); el formateador de clase habría obligado a construir uno por llamada o a esconder un
/// `nonisolated(unsafe)`. La zona es **UTC** en los dos sentidos: un instante no tiene zona, y
/// escribir la del dispositivo haría que el mismo registro se serializara distinto en cada viaje.
enum ISO8601Timestamp {

    /// Lo que se escribe: `2026-09-21T10:30:00.000Z`.
    private static let withFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    /// Lo que además se acepta al leer: `2026-09-21T10:30:00Z`.
    private static let wholeSeconds = Date.ISO8601FormatStyle()

    static func text(_ instant: Date) -> String {
        withFractionalSeconds.format(instant)
    }

    /// El instante de `text`, o `nil` si no es ISO-8601 en ninguna de las dos formas.
    static func instant(_ text: String) -> Date? {
        if let instant = try? withFractionalSeconds.parse(text) { return instant }
        return try? wholeSeconds.parse(text)
    }
}
