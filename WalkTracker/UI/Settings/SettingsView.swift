import Domain
import SwiftUI

/// Pestaña Ajustes (AD-14). Nace en la 2.3 con **un solo** ajuste: la longitud de zancada.
///
/// La meta semanal (Epic 3), el sonido (4.2), exportar y borrar datos (Epic 5) y el "Acerca de"
/// con la atribución de Open-Meteo llegan con sus historias; aquí no se adelanta ninguno.
///
/// **La vista no decide nada** (sección 6 del gate). Entrega el texto crudo del campo a
/// `SettingsStore.saveStride(fromText:)` y pinta `strideOutcome`: qué es un número, qué se
/// rechaza y qué merece aviso vive en `SettingsStore+Stride.swift`, que es lo que se prueba.
///
/// **Primer campo de texto del producto.** No había ni un `TextField` en todo el árbol, así que
/// esto fija el patrón: teclado decimal (que en español da coma) **con su "Listo"**, valor
/// alineado a la derecha con su unidad al lado, botón Guardar explícito, mensaje en línea debajo
/// —anunciado también por VoiceOver— y una salida de vuelta al valor por defecto. El botón
/// explícito es decisión de Paul: hace inequívoco qué significa "no se persiste el valor
/// inválido" y permite escribir mal sin consecuencias.
///
/// **Sección 12 del gate desde el primer commit.** El ancho del campo **no** se fija con
/// `.frame(width:)` —no hay token para ese rol y el marco numérico está prohibido—: lo reparte
/// el layout, con la etiqueta a la izquierda y el valor alineado a la derecha, que además es lo
/// que hace Ajustes del sistema y lo que sobrevive con Dynamic Type grande.
struct SettingsView: View {

    /// Dueño de `settings.json` (AD-16). La vista le pide intenciones y le lee el estado;
    /// escribirlo es cosa suya, y eso lo comprueba la sección 6 del gate por el TIPO del
    /// receptor — renombrar esta propiedad ya no cambia nada (B-5, 2026-09-20).
    let settingsStore: SettingsStore

    /// La zancada por omisión de `formulas.json`, que es la que usa quien nunca recalibró.
    /// Llega desde el composition root, como el resto: la vista no lee ficheros ni conoce el
    /// 0,655, solo lo enseña de marcador de posición.
    let defaultStrideM: Double

    /// El texto tal y como está en el campo. Es de la vista —nadie más lo necesita— y no se
    /// valida aquí: se entrega entero al store al pulsar Guardar.
    @State private var text: String

    @FocusState private var isEditing: Bool

    init(settingsStore: SettingsStore, defaultStrideM: Double) {
        self.settingsStore = settingsStore
        self.defaultStrideM = defaultStrideM
        // Sin configurar el campo nace vacío, y el marcador de posición enseña el valor que
        // se está usando: un campo precargado con el default haría pensar que ya se eligió.
        _text = State(initialValue: settingsStore.strideM.map { Self.decimalText($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    strideField
                    if let outcome = settingsStore.strideOutcome {
                        outcomeMessage(outcome)
                    }
                    saveButton
                    if settingsStore.strideM != nil {
                        defaultButton
                    }
                } header: {
                    Text("Zancada", comment: "Encabezado de la única sección de la pantalla de Ajustes (2.3): la longitud de zancada.")
                } footer: {
                    Text("La distancia y el ritmo salen de multiplicar tus pasos por este valor. Se aplica a la siguiente caminata: las que ya hiciste no cambian.", comment: "Pie de la sección de zancada en Ajustes: qué hace el ajuste y desde cuándo.")
                }
            }
            // El `.decimalPad` no tiene tecla de retorno: sin estas dos, la única forma de
            // cerrarlo era pulsar Guardar, y con el teclado abierto el mensaje y el botón
            // pueden quedar debajo.
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { isEditing = false } label: {
                        Text("Listo", comment: "Botón de la barra sobre el teclado decimal de Ajustes: cierra el teclado sin guardar. El teclado decimal no trae tecla de retorno.")
                    }
                }
            }
            .navigationTitle("Ajustes")
        }
        // El mensaje era de aquella pulsación: salir de Ajustes lo apaga. Si no, volver a la
        // pestaña enseñaba otra vez el "Zancada guardada" de hace diez minutos.
        .onDisappear { settingsStore.strideScreenDidDisappear() }
        // VoiceOver no se entera de un texto que aparece debajo: el foco se queda en Guardar.
        // Mismo recurso que el "Sesión recuperada" de la pantalla de sesión (1.6).
        .onChange(of: settingsStore.strideOutcome) { _, outcome in
            guard let outcome else { return }
            AccessibilityNotification.Announcement(Self.message(for: outcome)).post()
        }
    }

    // MARK: - Campo

    /// Lo tecleado, con la señal de "esto lo está escribiendo Paul" atada al propio binding.
    ///
    /// No es un `.onChange(of: text)`: el botón de volver al valor por defecto también vacía el
    /// campo, y con `.onChange` ese vaciado apagaba el mensaje que el botón acababa de encender.
    /// Por el binding solo pasa lo que se teclea.
    private var editedText: Binding<String> {
        Binding(
            get: { text },
            set: { typed in
                text = typed
                // Lo que decía el mensaje ya no es lo que hay escrito: se apaga. Es una
                // intención del store, no una escritura desde la vista.
                settingsStore.strideEditingDidChange()
            }
        )
    }

    private var strideField: some View {
        LabeledContent {
            HStack(spacing: Spacing.s) {
                TextField(Self.decimalText(defaultStrideM), text: editedText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($isEditing)
                    // El objetivo táctil va en el CAMPO, no en la fila: en el `LabeledContent`
                    // solo hacía alta la fila, y tocar su hueco no enfocaba nada. Con el marco
                    // y la forma de contenido, el área tocable es la que se ve.
                    .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
                    .contentShape(Rectangle())
                Text("m", comment: "Unidad del campo de zancada en Ajustes: metros, junto al valor.")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } label: {
            // Una sola etiqueta: la visible del `LabeledContent`, que VoiceOver ya asocia al
            // campo. Ponerle además `.accessibilityLabel` al `TextField` hacía que leyera las dos.
            Text("Longitud de zancada, en metros", comment: "Etiqueta del campo de Ajustes donde Paul recalibra su zancada. Lleva la unidad porque es también lo que lee VoiceOver.")
        }
    }

    private var saveButton: some View {
        Button {
            // Se cierra el teclado antes de guardar: el mensaje en línea queda a la vista.
            isEditing = false
            settingsStore.saveStride(fromText: text)
        } label: {
            Text("Guardar", comment: "Botón explícito de la pantalla de Ajustes que persiste la zancada recalibrada.")
                .font(Typography.buttonLabel)
                .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
        }
        .buttonStyle(.glassProminent)
        // Sin fondo de fila: el botón ya trae su propia superficie y dos se verían apiladas.
        .listRowBackground(Color.clear)
    }

    /// La vuelta atrás (decisión de Paul, 2026-09-19): quita el override y manda otra vez el
    /// default de `formulas.json`.
    ///
    /// Solo aparece si hay algo que quitar. Vaciar el campo **no** vale —se rechaza, y así sigue
    /// siendo—, así que sin este botón un dedazo guardado no se podía deshacer sin reinstalar.
    private var defaultButton: some View {
        Button {
            isEditing = false
            // Directo al `@State`, no por `editedText`: por el binding pasa solo lo tecleado, y
            // este vaciado no debe apagar el mensaje que la intención va a encender.
            text = ""
            settingsStore.clearStride()
        } label: {
            Text("Usar el valor por defecto", comment: "Botón de Ajustes que borra la zancada recalibrada y devuelve la de fábrica. Es la única vuelta atrás: vaciar el campo se rechaza.")
                .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
        }
        .buttonStyle(.glass)
        .listRowBackground(Color.clear)
    }

    // MARK: - Mensaje en línea

    /// El resultado del último Guardar, debajo del campo (estructura de UX-DR4: etiqueta ·
    /// campo · mensaje en línea). Nunca culpa: dice qué pasó y qué hacer.
    private func outcomeMessage(_ outcome: SettingsStore.StrideOutcome) -> some View {
        Label {
            Text(verbatim: Self.message(for: outcome))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: Self.symbol(for: outcome))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Self.style(for: outcome))
        .labelStyle(.titleAndIcon)
    }

    /// El texto de cada resultado, **una sola vez**: lo pinta la fila y lo anuncia VoiceOver.
    ///
    /// Cada caso dice lo que de verdad pasó. En particular `notPersisted` no dice "guardada":
    /// el disco falló y el valor no sobrevive a relanzar la app, aunque esta ejecución ya lo use.
    static func message(for outcome: SettingsStore.StrideOutcome) -> String {
        switch outcome {
        case .saved:
            return String(localized: "Zancada guardada. La siguiente caminata la usará.", comment: "Mensaje en línea de Ajustes tras guardar una zancada válida y dentro de lo normal.")
        case .savedOutsideHumanRange:
            let bounds = humanRangeBounds()
            return String(localized: "Guardada, aunque lo normal en una persona es entre \(bounds.lower) y \(bounds.upper) m. Compruébala por si fue un dedazo.", comment: "Aviso en línea de Ajustes: la zancada se guardó igual, pero cae fuera del rango humano. Avisa, no bloquea. Los dos marcadores son los extremos del rango, ya formateados: hoy 0,3 y 1,2.")
        case .clearedToDefault:
            return String(localized: "Listo: vuelve a usarse el valor por defecto.", comment: "Mensaje en línea de Ajustes tras pulsar \"Usar el valor por defecto\": se borró la zancada recalibrada.")
        case .notPersisted:
            return String(localized: "La siguiente caminata la usará, pero no se pudo guardar: al cerrar la app volverá al valor anterior.", comment: "Mensaje en línea de Ajustes cuando el cambio se aplicó en memoria pero falló la escritura en disco. No dice \"guardada\", porque no lo está.")
        case .rejected(.notANumber):
            return String(localized: "Escribe la longitud en metros, por ejemplo 0,67.", comment: "Mensaje de error en línea de Ajustes cuando el campo está vacío o no contiene un número. Nada se ha guardado.")
        case .rejected(.tooLarge):
            return String(localized: "Ese número es demasiado grande para una zancada. Escribe la longitud de un paso, en metros.", comment: "Mensaje de error en línea de Ajustes cuando el número tecleado desborda (cientos de dígitos). Nada se ha guardado.")
        case .rejected(.notPositive):
            return String(localized: "La zancada tiene que ser mayor que cero.", comment: "Mensaje de error en línea de Ajustes cuando el número es cero o negativo. Nada se ha guardado.")
        }
    }

    private static func symbol(for outcome: SettingsStore.StrideOutcome) -> String {
        switch outcome {
        case .saved, .clearedToDefault: "checkmark.circle.fill"
        case .savedOutsideHumanRange, .notPersisted: "exclamationmark.circle.fill"
        case .rejected: "exclamationmark.triangle.fill"
        }
    }

    private static func style(for outcome: SettingsStore.StrideOutcome) -> AnyShapeStyle {
        switch outcome {
        case .saved, .clearedToDefault: AnyShapeStyle(.secondary)
        // El rango no es un error: se distingue por jerarquía, no por color.
        case .savedOutsideHumanRange, .notPersisted: AnyShapeStyle(.primary)
        // Un rechazo SÍ es un error, y "color de un error" es un rol del producto: vive
        // en `Colors`, con variante clara y oscura y contraste medido contra los dos
        // fondos sobre los que cae este mensaje. No se nombra aquí un color del sistema:
        // `Color.red` en claro da 3,55:1 y 3,18:1, por debajo del 4,5:1 de WCAG AA.
        case .rejected: AnyShapeStyle(Colors.error)
        }
    }

    // MARK: - Formato

    /// Metros como los teclearía Paul en su región: separador decimal suyo, **dígitos latinos**,
    /// **sin separador de millares** y con la precisión real del valor guardado.
    ///
    /// Interno, no privado, para que `SettingsViewTests` pueda emparejarlo con
    /// `AppSettings.strideMeters(fromText:)` sin renderizar la vista — el mismo trato que
    /// `MotionBlockedView.settingsURL`. El ida y vuelta se sostiene **por construcción**, y las
    /// tres condiciones son las tres maneras en que se rompía:
    ///
    /// - **Numeración.** Con el locale tal cual, `ar_EG` daba `٠٫٦٥٥`; el parser solo acepta
    ///   dígitos ASCII, así que la app rellenaba el campo con algo que ella misma rechazaba al
    ///   pulsar Guardar **sin haber tocado nada**. Se fija `latn`.
    /// - **Agrupamiento.** Una zancada grande salía `10.000,000` en español: dos separadores, y
    ///   el parser devuelve `nil`. Se desactiva.
    /// - **Precisión.** Con tres decimales fijos, un valor guardado con más se sembraba
    ///   redondeado y Guardar lo **sobrescribía en silencio**. Se siembran los decimales que el
    ///   valor necesita para volver a ser él mismo.
    ///
    /// Se eligió arreglar el que **escribe** y no enseñar al parser a leer cada locale: el
    /// parser vive en el dominio (`AppSettings`), y hacerlo depender del locale del sistema lo
    /// volvería no determinista y le metería una dependencia que AD-3 no quiere.
    static func decimalText(_ meters: Double, locale: Locale = .autoupdatingCurrent) -> String {
        meters.formatted(
            .number
                .precision(.fractionLength(0...exactFractionLength(of: meters)))
                .grouping(.never)
                .locale(latinDigits(locale))
        )
    }

    /// El mismo locale, con la numeración latina fijada: el usuario conserva su separador
    /// decimal y los dígitos son los que el campo sabe leer.
    private static func latinDigits(_ locale: Locale) -> Locale {
        var components = Locale.Components(locale: locale)
        components.numberingSystem = Locale.NumberingSystem("latn")
        return Locale(components: components)
    }

    /// Cuántos decimales hacen falta para que el número vuelva a ser exactamente él mismo.
    ///
    /// `%f` formatea en C, con punto y sin región, así que compararlo con `Double(_:)` es
    /// comparar el valor, no el texto. Diecisiete es el techo de un `Double`.
    private static func exactFractionLength(of meters: Double) -> Int {
        for length in 0...17 where Double(String(format: "%.\(length)f", meters)) == meters {
            return length
        }
        return 17
    }

    /// El rango humano, escrito una sola vez: sale de `AppSettings.humanStrideRangeM`, que es
    /// donde se decide, y no de dos números tecleados en un mensaje.
    ///
    /// Devuelve los dos extremos **por separado** para que el mensaje lleve dos marcadores: con
    /// "0,3 y 1,2" dentro de uno solo, el traductor recibía un token opaco y no podía ni
    /// reordenarlo ni cambiar la conjunción. Y recibe locale, como `decimalText`: es la misma
    /// decisión, y estaba tomada de dos formas distintas a un palmo.
    static func humanRangeBounds(locale: Locale = .autoupdatingCurrent) -> (lower: String, upper: String) {
        let range = AppSettings.humanStrideRangeM
        return (bound(range.lowerBound, locale: locale), bound(range.upperBound, locale: locale))
    }

    private static func bound(_ meters: Double, locale: Locale) -> String {
        meters.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(latinDigits(locale)))
    }
}
