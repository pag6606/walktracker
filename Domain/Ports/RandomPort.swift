import Foundation

/// Azar del sistema (CAP-6) — AD-3, AD-10.
///
/// El dominio no llama a un generador aleatorio, igual que no llama a `Date()`: sin este
/// puerto, `MotivationEngine` sería invectorizable y "20 caminatas sin repetir frase" no se
/// podría probar. Es el motivo por el que AD-10 lo incluye en el conjunto cerrado de 11.
///
/// **Firma mínima a propósito.** Una sola operación —elegir una posición— cubre toda
/// elección aleatoria sobre una colección, que es lo único que el dominio necesita. Un doble
/// determinista se escribe en tres líneas y fija la selección de un test entero.
public protocol RandomPort: Sendable {

    /// Un índice uniforme en `0..<count`, o `nil` si `count` no es positivo.
    ///
    /// Quien llama trata el `nil` como "no hay nada que elegir": nunca fuerza un índice.
    func index(below count: Int) -> Int?
}
