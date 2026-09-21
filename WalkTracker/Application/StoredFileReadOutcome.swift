import Domain
import Foundation

/// Cómo fue la última lectura del fichero que posee un store, y por tanto **si hay algo en disco
/// que una escritura destruiría** (B-1, hallazgo D1 de la retro del Epic 2).
///
/// **Son tres casos, no uno.** Los tres acaban con valores usables en memoria —perder los datos
/// no puede impedir caminar—, pero colapsarlos fue la causa raíz de la pérdida de los ajustes: la
/// primera escritura no tenía cómo saber que estaba escribiendo encima de algo que seguía entero
/// en disco.
///
/// Lo estrenó `SettingsStore.ReadOutcome` en B-1 y la 5.1 lo saca aquí para que `HistoryStore` y
/// `AchievementsStore` no vuelvan a razonarlo cada uno por su cuenta. `SettingsStore` conserva de
/// momento su tipo anidado: converger los tres es parte de B-10 y está en `deferred-work.md`.
enum StoredFileReadOutcome: Equatable {

    /// Había fichero y se leyó entero: lo que hay en memoria viene de él.
    case loaded
    /// El fichero no existe todavía (primera instalación). **No hay nada que perder.**
    case absent
    /// Hay algo y no se pudo interpretar: un fallo del sistema de ficheros, un esquema del
    /// futuro o un ilegible ya apartado. Lo que hay en memoria **no representa lo que hay en
    /// disco**.
    case unreadable(StorageError)

    /// Se puede escribir sin destruir nada: o se leyó lo que había, o no había nada.
    ///
    /// "Sin fichero" tiene que dejar escribir, o la primera instalación no guardaría nunca.
    var allowsWriting: Bool {
        switch self {
        case .loaded, .absent: true
        case .unreadable: false
        }
    }

    /// Hay algo en disco que esta ejecución no ha podido leer.
    ///
    /// Es lo que dispara el **aviso visible** del historial: a diferencia de los ajustes, que se
    /// rehacen, lo que hay en `sessions.json` no se puede reconstruir, y perderlo en silencio es
    /// la peor de las salidas posibles (decisión de Paul, 2026-09-21).
    var isUnreadable: Bool { !allowsWriting }
}
