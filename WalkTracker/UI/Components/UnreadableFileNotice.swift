import SwiftUI

/// El aviso de que un fichero del sandbox **existe y esta ejecución no ha podido leerlo** (B-1,
/// 5.1).
///
/// **Lo comparten dos pantallas y por eso vive aquí.** Inicio lo pinta para `sessions.json` (5.1)
/// y Logros para `achievements.json` (3.3): el mismo tratamiento visual con dos textos distintos.
/// Estaba escrito entero dentro de `HomeView` y copiarlo en la segunda pantalla habría dejado dos
/// sitios que se pueden arreglar por separado, que es la lección que la 3.2 dejó escrita al
/// extraer `AchievementsStore.upsert(_:into:)`.
///
/// **Los textos entran como `Text`, no como `LocalizedStringKey`.** Así cada pantalla conserva su
/// `comment:` en el String Catalog: con una clave, el literal se extraería aquí sin comentario y
/// el traductor se quedaría sin saber de qué fichero habla.
///
/// **Sin botón, a propósito.** No hay nada que Paul pueda hacer desde aquí, y un "Aceptar" solo
/// serviría para que el aviso dejara de estar sin que el problema deje de estar.
struct UnreadableFileNotice: View {

    /// Qué no se pudo leer, en una línea.
    let title: Text
    /// Qué **no** ha pasado —no se ha borrado nada— y qué se puede seguir haciendo. Las dos cosas
    /// importan: el aviso informa, no bloquea.
    let message: Text

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                title
                    .font(.subheadline.weight(.semibold))
                message
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Colors.error)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Surface.cardPaddingHorizontal)
        .padding(.vertical, Surface.cardPaddingVertical)
        .background(Colors.error.opacity(Surface.noticeTintOpacity), in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }
}
