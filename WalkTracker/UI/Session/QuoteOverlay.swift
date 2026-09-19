import SwiftUI

/// La frase motivacional del arranque, **encima de una sesión que ya está corriendo** (2.2,
/// CAP-6). El cronómetro cuenta y el podómetro entrega por debajo: este overlay no bloquea
/// nada, solo tapa.
///
/// Se va sola a los 3 s o con un **tap en cualquier punto**; no hay botón de cerrar (UX del
/// épico). Quien gobierna las dos salidas es `SessionStore.dismissQuote()`: esta vista no
/// escribe estado (sección 6 del gate).
///
/// **Colores del sistema.** Ni el fondo acento a pantalla completa de la v3 —derogado— ni
/// nada cableado: el fondo es material del sistema y el vocabulario (espaciado, radio,
/// relleno) sale de `UI/Style/DesignTokens.swift` (sección 12 del gate).
///
/// **Accesibilidad.** VoiceOver lo lee como contenido modal (`.isModal`, que además saca de
/// la ruta lo que hay debajo) y la frase es su único elemento. Quien lo presenta anuncia solo
/// una **señal corta** de que ha aparecido: la frase entera la lee el foco del modal, y
/// anunciarla además la diría dos veces seguidas. Con Dynamic Type grande el contenido se
/// desplaza en vertical en lugar de recortarse, también con la frase más larga del banco. La
/// entrada y la salida las anima quien lo presenta, que respeta Reduce Motion.
struct QuoteOverlay: View {

    /// El texto de la frase. Es dato de `quotes.json`, no una cadena localizable.
    let text: String
    /// El tap: la misma intención que el vencimiento de los 3 s.
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.l) {
                    Image(systemName: "figure.walk.motion")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text(verbatim: text)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        // Nunca se encoge ni se recorta: con el texto al máximo, se desplaza.
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Toca para continuar", comment: "Pie del overlay de la frase motivacional, al iniciar una caminata: dice cómo se quita antes de que se vaya sola a los 3 s.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .padding(LayoutMetrics.margin)
                // El `ScrollView` se queda el toque que cae sobre su contenido, que es justo el
                // centro de la pantalla y la parte más obvia donde tocar. Sin esto, "un tap en
                // cualquier punto" no incluiría la propia frase.
                .contentShape(.rect)
                .onTapGesture(perform: onDismiss)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // Y el resto del overlay —el material de alrededor— también: "en cualquier punto".
        .contentShape(.rect)
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityHint(Text("Toca para continuar con la caminata, que ya está en curso.", comment: "Pista de VoiceOver del overlay de la frase motivacional: cómo se descarta y que la caminata no está esperando."))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.default, onDismiss)
    }
}
