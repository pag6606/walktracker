import Domain
import Foundation

/// Recalibración de la zancada (2.3, CAP-7): la intención de guardar lo que Paul teclea y el
/// resultado de haberlo intentado.
///
/// **La decisión vive aquí, no en la pantalla** (sección 6 del gate). La vista entrega el texto
/// crudo del campo y pinta `strideOutcome`; qué es un número, qué se rechaza, qué se guarda y
/// qué merece un aviso lo decide este fichero. Es lo que permite probar la historia entera sin
/// renderizar una vista, con A-4 todavía abierto.
///
/// **Cinco resultados, no dos.** Rechazado (no se persiste nada), guardado, guardado con aviso
/// —el rango humano 0,3–1,2 m **avisa y no bloquea**, porque es una regla de producto y no del
/// dominio, ver `AppSettings.humanStrideRangeM`—, vuelto al valor por defecto, y aplicado en
/// memoria pero **sin poder escribirse en disco**, que es lo único que no se puede contar como
/// "guardado" sin mentir.
///
/// Escribe `strideOutcome` (solo aquí) y, al aceptar, `settings` y `settings.json`.
extension SettingsStore {

    /// Lo que hay que contarle a Paul del último "Guardar" o "Usar el valor por defecto".
    ///
    /// No lleva el texto del mensaje: eso es de la capa que pinta, y meterlo aquí obligaría a
    /// `Application/` a conocer el String Catalog.
    enum StrideOutcome: Equatable {

        /// Guardada y dentro de lo humano: no hay nada que avisar.
        case saved
        /// Guardada, pero fuera de 0,3–1,2 m. **Se guardó igual**: es su app y su zancada.
        case savedOutsideHumanRange(Double)
        /// Se quitó el override: vuelve a mandar el default de `formulas.json`.
        case clearedToDefault
        /// El cambio vale para esta ejecución, pero **no quedó escrito**.
        ///
        /// Dos causas, un solo resultado, porque lo que Paul necesita saber es el mismo: el
        /// disco falló al escribir, o los ajustes que hay en disco no se pudieron leer y
        /// escribir encima los borraría (B-1). En los dos casos el valor vale para la siguiente
        /// caminata y no sobrevive a relanzar la app.
        ///
        /// No es `saved`: decir "la siguiente caminata la usará" es verdad, y decir "guardada"
        /// no, porque al relanzar la app el valor ya no estará. `save(applying:)` no propaga el
        /// error —la caminata no se para por un fallo de disco— pero sí lo devuelve, y aquí se
        /// cuenta.
        case notPersisted
        /// No se guardó nada y el fichero no cambió.
        case rejected(StrideRejection)

        /// El ajuste quedó escrito en `settings.json`, con aviso o sin él.
        var isSaved: Bool {
            switch self {
            case .saved, .savedOutsideHumanRange, .clearedToDefault: true
            case .notPersisted, .rejected: false
            }
        }
    }

    /// Por qué se rechazó. Son tres causas distintas porque merecen tres mensajes distintos:
    /// "eso no es un número", "eso no cabe" y "una zancada tiene que ser mayor que cero" no se
    /// corrigen igual.
    enum StrideRejection: Equatable {

        /// Campo vacío, `abc`, `,` suelta: no hay número que leer.
        case notANumber
        /// Son dígitos, pero tantos que desbordan (`inf`): un número que no cabe. Sin esta
        /// causa, 400 dígitos leían "la zancada tiene que ser mayor que cero", que manda a
        /// corregir lo que no está mal.
        case tooLarge
        /// Hay número y cabe, pero el dominio lo rechaza: ≤ 0 (`Session.validateStride`).
        case notPositive
    }

    /// "Guardar" en Ajustes: parsea el texto, lo valida en la frontera y, si pasa, lo persiste.
    ///
    /// **Un valor inválido no toca el fichero.** No se normaliza, no se guarda a medias y el
    /// `settings.json` que hubiera se queda exactamente como estaba; lo único que cambia es
    /// `strideOutcome`, que es lo que la pantalla pinta en línea.
    ///
    /// **Una sola escritura por pulsación**, y gana el último guardado: no hay estado
    /// intermedio que reconciliar.
    ///
    /// La zancada nueva **no toca ninguna sesión**, ni la viva ni su snapshot: `Session.strideM`
    /// es un `let` del agregado. La siguiente sesión la recoge al abrirse, porque
    /// `SessionStore.openSession()` resuelve la zancada en ese momento y no al construirse.
    func saveStride(fromText text: String) {
        guard let meters = AppSettings.strideMeters(fromText: text) else {
            log.info("Zancada rechazada: el campo no contiene un número")
            strideOutcome = .rejected(.notANumber)
            return
        }
        guard AppSettings.isRepresentableStride(meters) else {
            log.info("Zancada rechazada: el número no cabe (desborda a infinito)")
            strideOutcome = .rejected(.tooLarge)
            return
        }
        // La frontera se prueba sobre una copia y **antes** de tocar nada: un valor inválido no
        // llega a `save(applying:)`, así que no puede disparar una relectura ni una escritura.
        var probe = settings
        do {
            try probe.setStrideM(meters)
        } catch {
            log.info("Zancada rechazada en la frontera: \(String(describing: error), privacy: .public)")
            strideOutcome = .rejected(.notPositive)
            return
        }
        // Ya validado justo arriba, y `setStrideM` solo mira el valor —no el receptor—, así que
        // aquí no puede rechazar. Va dentro del `change` para que, si la lectura se recupera en
        // el reintento, la zancada se escriba sobre lo que hay en disco y no sobre los valores
        // por omisión: es lo que salva la ventana de frases que el fichero ya tenía.
        guard save(applying: { _ = try? $0.setStrideM(meters) }) else {
            strideOutcome = .notPersisted
            return
        }
        strideOutcome = AppSettings.isHumanStride(meters)
            ? .saved
            : .savedOutsideHumanRange(meters)
    }

    /// "Usar el valor por defecto" en Ajustes: quita el override y vuelve a `formulas.json`
    /// (decisión de Paul, 2026-09-19).
    ///
    /// **Es la única vuelta atrás, y por eso es una acción aparte.** Vaciar el campo no sirve:
    /// la matriz congelada dice que el campo vacío se **rechaza**, y esa fila no cambia. Sin
    /// este botón, un dedazo guardado (0,067) dejaba a Paul sin manera de recuperar el 0,655
    /// salvo reinstalando la app.
    ///
    /// Sin nada que quitar no escribe nada: apaga el mensaje anterior y se acabó.
    func clearStride() {
        guard settings.strideM != nil else {
            log.info("Volver al valor por defecto sin override que quitar: no se escribe nada")
            strideOutcome = nil
            return
        }
        strideOutcome = save { $0.clearStrideM() } ? .clearedToDefault : .notPersisted
    }

    /// Paul vuelve a escribir en el campo: el mensaje anterior ya no habla de lo que hay en
    /// pantalla, así que se apaga. Es una intención, no una escritura de la vista.
    func strideEditingDidChange() {
        guard strideOutcome != nil else { return }
        strideOutcome = nil
    }

    /// Ajustes se va de pantalla: el mensaje era de **aquella** pulsación y no sobrevive a la
    /// salida.
    ///
    /// Sin esto, `strideOutcome` solo se apagaba al volver a escribir, así que salir de Ajustes
    /// y volver enseñaba otra vez el "Zancada guardada" —o el error— de hace diez minutos, como
    /// si acabara de pasar.
    func strideScreenDidDisappear() {
        guard strideOutcome != nil else { return }
        strideOutcome = nil
    }

    /// La zancada con la que debe nacer una sesión ahora mismo: la configurada si la hay, y si
    /// no el default de `formulas.json`, que es el único sitio donde vive el 0,655.
    ///
    /// **Se llama al abrir la sesión, no al construir el store**: ahí está el criterio central
    /// de la 2.3. Leerla una vez en el arranque haría que recalibrar solo surtiera efecto tras
    /// relanzar la app.
    func resolvedStrideM(default defaultStrideM: Double) -> Double {
        settings.resolvedStrideM(default: defaultStrideM)
    }
}
