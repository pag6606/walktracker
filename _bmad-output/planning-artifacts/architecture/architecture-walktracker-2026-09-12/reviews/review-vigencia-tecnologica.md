---
name: 'Revisión de vigencia tecnológica — ARCHITECTURE-SPINE'
type: review
lens: vigencia-tecnologica
target: ../ARCHITECTURE-SPINE.md
reviewed: '2026-09-12'
method: 'verificación en la web (WebSearch/WebFetch). Ninguna afirmación se da por buena de memoria.'
---

# Revisión de vigencia tecnológica — WalkTracker iOS

**Fecha de la revisión:** 12 de septiembre de 2026
**Objeto:** `ARCHITECTURE-SPINE.md` (status: draft, created/updated 2026-09-12)

Toda afirmación de abajo se ha contrastado contra fuente primaria (documentación de Apple,
swift.org, developer.apple.com/news/releases, open-meteo.com) o, cuando no existe fuente
primaria, contra fuente secundaria consistente y así marcada.

> **Nota de método.** La documentación de Apple es una SPA y no se puede leer con un fetch
> normal. Se ha usado el endpoint de datos `developer.apple.com/tutorials/data/documentation/<path>.md`,
> que devuelve el símbolo con sus anotaciones de disponibilidad. Las citas literales de Apple
> vienen de ahí.

---

## Veredicto

El spine es **técnicamente sólido en sus decisiones**, pero su **tabla de Stack está caducada
o mal emparejada**, y **tres afirmaciones técnicas concretas son imprecisas de un modo que
costará tiempo de build real**: la de Liquid Glass (AD-13), la del App Group de la Live
Activity (AD-15) y la de concurrencia estricta con CoreMotion (AD-12 + AD-7).

Y hay un hecho de calendario que el spine no contempla y que le llega en **dos días**:
**iOS 27 sale el 14 de septiembre de 2026**.

---

## Tabla resumen

| # | Afirmación del spine | Veredicto | Severidad |
| --- | --- | --- | --- |
| 1 | Swift 6.3.2 | **DESACTUALIZADA** | ALTA |
| 2 | Xcode 26.6 | **CONFIRMADA** (caduca en 2 días) | ALTA |
| 3 | iOS deployment target 26.0 | **CONFIRMADA** (contexto cambia el 14 sep) | ALTA |
| 4 | AD-13 "el SDK de iOS 26 adopta Liquid Glass automáticamente" | **PARCIALMENTE CONFIRMADA** | ALTA |
| 5 | Swift Testing para nuevos tests; XCTest para UI/performance | **CONFIRMADA** | BAJA |
| 6 | `@Observable` + `@MainActor` como patrón de estado | **CONFIRMADA y reforzada** | BAJA |
| 7 | AD-15 ActivityKit = Widget Extension + App Group | **PARCIALMENTE DESACTUALIZADA** | MEDIA |
| 8 | `HKWorkoutBuilder` para escribir workouts | **CONFIRMADA** | NINGUNA |
| 9 | CMPedometer `queryPedometerData` (CAP-3) | **CONFIRMADA, más estricta de lo asumido** | MEDIA |
| 10 | Open-Meteo gratuita y sin key | **CONFIRMADA con matiz de licencia** | MEDIA |
| 11 | Concurrencia estricta completa + callbacks de CoreMotion | **DESACTUALIZADA / INCOMPLETA** | ALTA |
| 12 | Xcode 26.6 podrá depurar en un iPhone con iOS 27 | **NO VERIFICABLE** | MEDIA |

---

## 1. Swift 6.3.2 — DESACTUALIZADA · severidad ALTA

**Lo que dice el spine:** tabla Stack, fila `Swift | 6.3.2`.

**Lo verificado:**

- La versión estable de Swift publicada en swift.org hoy es **6.3.3**, del **11 de mayo de 2026**.
  Fuente: <https://www.swift.org/install/macos/>
- **Xcode 26.6 (17F113) no trae Swift 6.3.2 — trae Swift 6.3.3 (6.3.3.1.3).** Swift 6.3.2
  (6.3.2.1.108) fue lo que trajo **Xcode 26.5**.
  Fuente: <https://xcodereleases.com/>
- Además existe ya **Swift 6.4**, presentado en la WWDC26, que es el que empaqueta
  **Xcode 27.0 RC (Swift 6.4, 6.4.0.34.1)**.
  Fuentes: <https://www.swift.org/blog/embedded-swift-improvements-coming-in-swift-6.4/> ·
  <https://forums.swift.org/t/swift-6-4-release-process/85421> · <https://xcodereleases.com/>

**El problema no es solo que 6.3.2 sea vieja: es que la fila de Swift y la fila de Xcode del
spine son incompatibles entre sí.** Nadie que instale Xcode 26.6 obtendrá Swift 6.3.2. El
número parece copiado de una instalación previa o de memoria, no leído de la toolchain que el
propio spine manda usar.

**Corrección mínima:** `Swift | 6.3.3 (la que trae Xcode 26.6)`.
**Corrección recomendada:** ver hallazgo 2 — probablemente toca saltar a Swift 6.4 / Xcode 27.

---

## 2. Xcode 26.6 — CONFIRMADA hoy, caduca en dos días · severidad ALTA

**Lo verificado:**

- **Xcode 26.6 (17F113)** se publicó el **25 de junio de 2026** y es, a día de hoy, la última
  versión **liberada** (no beta) de Xcode. La afirmación del spine es correcta *hoy*.
- Pero **Xcode 27 RC (27A266a) salió el 9 de septiembre de 2026**, junto con los RC de
  iOS 27.0, iPadOS 27.0, macOS 27.0, tvOS 27.0, visionOS 27.0 y watchOS 27.0.
  Fuente: <https://developer.apple.com/news/releases/>
- Xcode 27 lleva en beta desde el **8 de junio de 2026** (27A5194q) y ya tiene notas de
  release publicadas.
  Fuente: <https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes>
- **A partir de abril de 2027, App Store Connect exigirá builds hechos con el SDK de iOS 27
  o posterior**, es decir, Xcode 27.
  Fuente: <https://developer.apple.com/news/> (anuncio de requisitos de envío)

**Consecuencia para el spine.** El spine está fijando una toolchain que quedará obsoleta
literalmente esta semana. Como el propio spine dice que la distribución por TestFlight es
*opcional* y que no hay CI, esto no es un bloqueo de producto — pero sí conviene que la
decisión de quedarse en Xcode 26.6 sea **explícita y fechada**, no un accidente de haber
escrito el documento el 12 de septiembre. Si no se declara, en la primera actualización de
Xcode el spine deja de describir el proyecto.

---

## 3. iOS deployment target 26.0 — CONFIRMADA, pero AD-2 caduca el 14 de septiembre · severidad ALTA

**Lo que dice el spine (AD-2):** "deployment target 26.0. Prohibido `if #available` hacia
versiones anteriores. El dispositivo de validación es un iPhone 14 (A15, sin Dynamic Island)
**con iOS 26**."

**Lo verificado:**

- **Apple confirmó el 9 de septiembre de 2026 que iOS 27 se publica el 14 de septiembre de 2026.**
  Fuentes: <https://9to5mac.com/2026/09/09/apple-confirms-ios-27-release-date-september-14/> ·
  <https://www.macrumors.com/2026/09/09/apple-announces-ios-27-release-date/>
- El iPhone 14 **sigue siendo compatible con iOS 27** (no queda fuera de la lista de soporte).
  Fuente: <https://www.macworld.com/article/2986799/ios-27-new-iphone-features-release-date-beta-compatiblity-apple-intelligence-siri.html>
- Un deployment target de 26.0 **sigue siendo legal en Xcode 27**, cuyo rango de deployment
  target soportado es 15.0–27.0.
  Fuente (secundaria): <https://bleepingswift.com/blog/deployment-target-supported-range-xcode-27>

**Tres cosas que AD-2 no cubre y debería:**

1. **La premisa "el dispositivo de validación tiene iOS 26" deja de ser cierta pasado mañana**,
   salvo que se decida activamente no actualizar el iPhone 14. Esa decisión hay que tomarla
   antes del día 14, no descubrirla después.
2. AD-2 prohíbe `if #available` **hacia atrás**, y hace bien. Pero no dice nada de `if #available`
   **hacia delante** (iOS 27). Con un universo de instalación de un solo dispositivo que sí se
   va a actualizar a iOS 27, la regla debería ser simétrica: *no se ramifica por versión, ni
   hacia atrás ni hacia delante; se elige un SDK y se vive en él.*
3. Compilar contra el SDK de iOS 26 y ejecutar en iOS 27 es un escenario soportado, pero
   **no es el escenario que Apple optimiza ni el que el spine valida**. La combinación real de
   trabajo a partir del día 14 será "SDK 26 sobre OS 27" mientras no se salte a Xcode 27.

---

## 4. AD-13 "compilar contra el SDK de iOS 26 adopta Liquid Glass automáticamente" — PARCIALMENTE CONFIRMADA · severidad ALTA

Esta es la afirmación con más matiz de todo el spine. **El núcleo es correcto; los bordes no.**

### Lo que Apple dice literalmente

> "If your app uses standard components from SwiftUI, UIKit, or AppKit, your interface picks up
> the latest look and feel on the latest platform releases for iOS, iPadOS, macOS, tvOS, and
> watchOS. In Xcode, build your app with the latest SDKs, and run it on the latest platform
> releases to see the changes in your interface."

> "**Leverage system frameworks to adopt Liquid Glass automatically.** In system frameworks,
> standard components like bars, sheets, popovers, and controls automatically adopt this material."

Fuente: <https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass>

Hasta aquí, AD-13 es exacto.

### Matiz 1 — hay un requisito de doble cara que el spine no dice

Apple exige **dos** cosas, no una: compilar con el SDK más reciente **y ejecutar en la release
de plataforma más reciente** ("build your app with the latest SDKs, **and run it on the latest
platform releases**"). El spine solo menciona la primera mitad.

### Matiz 2 — sí existe una key de Info.plist, y el spine no la nombra

**`UIDesignRequiresCompatibility`** (Boolean, disponible desde iOS 26.0 / iPadOS 26.0 /
macOS 26.0 / tvOS 26.0). Puesta a `YES`, el sistema ejecuta la app en modo de compatibilidad y
la muestra "as it looks when built against previous versions of the SDKs".

Apple la etiqueta con un *Warning*: "Temporarily use this key while reviewing and refining your
app's UI for the design in the latest SDKs."

Fuente: <https://developer.apple.com/documentation/BundleResources/Information-Property-List/UIDesignRequiresCompatibility>

**AD-13 debería prohibirla explícitamente.** Es exactamente el tipo de escape que alguien
añadiría "temporalmente" al ver que los mockups v3 planos no cuadran, y que dejaría puesto para
siempre — que es el fallo que AD-13 dice querer prevenir.

### Matiz 3 — dato duro que refuerza AD-13 y que conviene citar

Apple documenta, en la misma página del key:

> "**The system ignores this key when you build for iOS 27 or later**, iPadOS 27 or later,
> Mac Catalyst 27 or later, macOS 27 or later, or tvOS 27 or later."

Es decir: **en cuanto el proyecto salte a Xcode 27 / SDK 27, Liquid Glass deja de ser opcional
por completo.** No hay opt-out. AD-13 no solo es correcto: es inevitable a un año vista (abril
de 2027, deadline de App Store Connect). Merece decirlo en la propia regla, porque convierte
AD-13 de preferencia en hecho consumado.

### Matiz 4 — "automáticamente" tiene excepciones concretas que afectan a este spine

Apple lista APIs que **hay que adoptar a mano**; no se heredan por recompilar:

- `.glassEffect(_:in:)` y `GlassEffectContainer` — para las piezas custom.
- `.buttonStyle(.glass)` / `.glassProminent`.
- `ConcentricRectangle` y `Shape.rect(corners:isUniform:)` — para que las esquinas de las piezas
  dibujadas sean concéntricas con su contenedor.
- `.safeAreaBar(edge:...)` y `.scrollEdgeEffectStyle(_:for:)` — legibilidad al hacer scroll
  bajo controles.
- `.backgroundExtensionEffect()`.
- `Tab(role: .search)` y `.tabBarMinimizeBehavior(.onScrollDown)`.

Los dos últimos afectan a **AD-14**, que fija un `TabView` de cuatro pestañas: el comportamiento
de minimizado del tab bar de iOS 26 es **opt-in**, no automático. AD-14 debería decidir si lo
adopta o no.

Y `GlassEffectContainer` afecta a **las tres piezas dibujadas de AD-13** (anillo de meta, gráfico
de tendencia, insignias): si alguna lleva efecto glass, Apple pide combinarlas en un container
por rendimiento. Aquí AD-13 tiene una **tensión interna menor**: prohíbe "dibujar materiales,
cristales o barras propias" pero autoriza tres piezas dibujadas. Conviene aclarar que la
prohibición es sobre *recrear el material del sistema*, no sobre *usar la API oficial de glass
en las tres piezas*.

### Matiz 5 — un cambio de iOS 26 que impacta la UI en español y no está en el spine

> "**Check capitalization in section headers.** Lists, tables, and forms optimize for legibility
> by adopting title-style capitalization for section headers. This means section headers no
> longer render entirely in capital letters regardless of the capitalization you provide."

Con la UI en español y el `Localizable.xcstrings` como única fuente de textos (convención de
"Textos" del spine), esto significa que las cabeceras de sección hay que **reescribirlas en
capitalización de título**, porque el sistema ya no las convierte a mayúsculas. Es trabajo real
sobre el String Catalog, no un detalle estético.

### Matiz 6 — el spine ya lo previene a medias, y bien

Apple: "**Reduce your use of custom backgrounds in controls and navigation elements.** Any custom
backgrounds and appearances you use in these elements might overlay or interfere with Liquid
Glass". AD-13 ya prohíbe dibujar barras propias, así que este punto está cubierto. Bien visto.

**Redacción sugerida para la Rule de AD-13:** añadir tres frases — (a) prohibir
`UIDesignRequiresCompatibility` por nombre; (b) hacer constar que el sistema la ignora a partir
del SDK 27, así que la adopción es terminal; (c) listar las APIs de adopción manual que sí se
usan (`.glassEffect`, `GlassEffectContainer`, `ConcentricRectangle`) frente a las que se heredan.

---

## 5. Swift Testing por defecto, XCTest para UI y performance — CONFIRMADA · severidad BAJA

**Lo que dice el spine:** convención de Tests — "Swift Testing para dominio y aplicación;
XCUITest diferido". Y en Stack: "Swift Testing | incluido en Xcode 26".

**Lo verificado** (fuentes secundarias consistentes; Apple no publica una declaración de
"default" como tal):

- Swift Testing es el marco recomendado por defecto para tests unitarios y de integración
  nuevos en 2026; ambos marcos coexisten en el mismo target de test.
- **XCTest sigue siendo obligatorio** para: tests de UI (`XCUIApplication` / XCUITest), tests de
  rendimiento (`XCTMetric`, sin equivalente en Swift Testing) y código Objective-C.
- La recomendación de migración es incremental: escribir lo nuevo en Swift Testing, migrar lo
  viejo al tocarlo.

Fuentes: <https://blakecrosley.com/blog/swift-testing-vs-xctest> ·
<https://www.codeanatomybyaher.com/articles/swift-unit-testing-xctest-swift-testing-compared> ·
<https://blog.micoach.itj.com/swift-testing-vs-xctest>

**El spine acierta.** El único apunte: Swift Testing viene con la toolchain de Swift, no
"con Xcode 26" — y como el spine difiere XCUITest (sección Deferred), la dependencia de XCTest
hoy es cero. Coherente.

---

## 6. `@Observable` + `@MainActor` como patrón de estado — CONFIRMADA y **reforzada** · severidad BAJA

**Lo que dice el spine (AD-7):** "`SessionStore` es `@Observable` y `@MainActor`".

**Lo verificado:** Apple **no ha empujado nada que lo sustituya**. Al contrario, en la WWDC26 lo
reforzó:

- `@Observable` sigue siendo el mecanismo vigente y preferido sobre `ObservableObject`.
- El cambio grande de WWDC26 en gestión de estado **no es una API nueva**, es que **`@State` deja
  de ser un property wrapper y pasa a ser una macro**. Con ello, los objetos `@Observable`
  guardados en `@State` **se inicializan exactamente una vez por ciclo de vida de la vista**, y
  sobreviven a la reinicialización del padre — cerrando el hueco histórico frente a `@StateObject`.
  Apple lo retroportó a iOS 17+.

Fuentes: <https://developer.apple.com/videos/play/wwdc2026/269/> ·
<https://dev.to/arshtechpro/wwdc26-whats-new-in-swiftui-a-developers-breakdown-1333> ·
<https://byteiota.com/swiftui-wwdc-2026-asyncimage-caching-and-state-fixed/>

**Esto es una buena noticia no aprovechada por el spine.** AD-7 apuesta por un escritor único
`@MainActor @Observable`; la garantía de inicialización única de WWDC26 es justamente lo que
hace que esa apuesta sea segura frente a rebuilds de vista. Vale la pena citarla en AD-7 como
respaldo, porque hoy la regla se sostiene solo sobre criterio propio.

**Lo que sí falta decidir (relacionado con AD-12).** Swift 6.2 introdujo **SE-0466: default actor
isolation a nivel de módulo** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), que hace `@MainActor`
el aislamiento por defecto de todo el módulo y vuelve innecesario anotarlo a mano en cada tipo.
Para una app con "un único escritor en el main actor" como paradigma declarado, esto es
directamente el ajuste que corresponde — y el spine no lo menciona.
Fuente: <https://www.avanderlee.com/concurrency/default-actor-isolation-in-swift-6-2/>

---

## 7. AD-15 — ActivityKit: Widget Extension **sí**, App Group **no es requisito** · severidad MEDIA

**Lo que dice el spine (AD-15):** "`WalkTrackerActivity` es un Widget Extension que solo renderiza
el `ContentState` que la app le entrega. […] El `ContentState` vive en `Shared/`, **compartido por
App Group**."

**Lo verificado** en <https://developer.apple.com/documentation/ActivityKit/displaying-live-data-with-live-activities>:

### Lo que se confirma

- **El Widget Extension sigue siendo la forma de hacer Live Activities.** Literal: "To offer Live
  Activities, add code to your existing widget extension or create a new widget extension if your
  app doesn't already include one. Live Activities use WidgetKit functionality and SwiftUI for
  their user interface. ActivityKit's role is to handle the life cycle."
- La estructura `ActivityAttributes` con su `ContentState` anidado es el contrato de datos.
  Correcto en el spine.
- "Each Live Activity runs in its own sandbox, and — unlike a widget — **it can't access the
  network or receive location updates**." → respalda AD-15 ("no calcula, no lee ficheros").

### Lo que el spine se deja: el requisito de Info.plist

Apple lista como paso 2 de la adopción:

> "If your project includes an `Info.plist` file, add the Supports Live Activities entry to it,
> and set its Boolean value to `YES`. […] add the **`NSSupportsLiveActivities`** key".

**El spine no lo menciona en ningún sitio.** Sin esa key la Live Activity no arranca. Es
exactamente el tipo de requisito de configuración que un spine debería fijar, porque no vive en
el código y no lo atrapa ningún test.

### Lo que el spine afirma de más: el App Group

**ActivityKit no requiere App Group.** El `ContentState` viaja **por ActivityKit**, no por un
contenedor compartido: se pasa en `Activity.request(attributes:content:)` y en `activity.update(_:)`,
con un tope duro documentado:

> "Static and dynamic data for a Live Activity, including data for ActivityKit updates and
> ActivityKit push notifications, **can't exceed a combined size of 4 KB**."

Compartir el **tipo** `ContentState` entre la app y la extensión se hace con **pertenencia a
target o un framework/paquete compartido** — que es precisamente lo que la carpeta `Shared/` del
Structural Seed ya resuelve. Un **App Group** sirve para otra cosa: compartir *ficheros* o
`UserDefaults` en un contenedor común, cosa que AD-15 justamente prohíbe ("no lee ficheros").

**AD-15 mezcla los dos mecanismos.** El diseño es correcto; la justificación es errónea. Tal como
está redactado, invita a crear un App Group que la arquitectura no necesita y que contradice la
propia regla de "solo renderiza".

**Corrección:** "El `ContentState` vive en `Shared/`, **con pertenencia a ambos targets**. Se
entrega por ActivityKit (`request` / `update`), **nunca por disco ni por App Group**, y no puede
exceder 4 KB."

### Cambios de iOS 26 que AD-15 no contempla

- **Live Activities aparecen ahora también en CarPlay, en un Mac emparejado y en un Apple Watch
  emparejado** ("Display up-to-date data […] in the Dynamic Island, on the Lock Screen, in CarPlay,
  and on a paired Mac or Apple Watch"). AD-15 dice "en el iPhone 14 se valida solo el layout de
  pantalla de bloqueo" — cierto para el hardware disponible, pero **si hay un Apple Watch o un Mac
  emparejado, la Live Activity se renderiza ahí sin que nadie la haya validado**. Conviene que la
  regla lo diga en vez de dejarlo implícito.
- **`ActivityStyle.transient`** (`request(attributes:content:pushType:style:)`) — Live Activities
  efímeras que terminan al bloquear el dispositivo o salir de la app.
- **Live Activities programadas** con `request(...startDate:)` y `AlertConfiguration` obligatoria.
- **`activityEnablementUpdates`** — stream asíncrono de cambios de autorización, además del
  `areActivitiesEnabled` síncrono. Relevante para la fila "Live Activity no disponible" de la
  tabla de degradación de AD-11: hoy esa fila se evaluaría una sola vez; el usuario puede
  desactivar Live Activities en Ajustes en mitad de una caminata.

  > **Nota (2026-09-21, `B-9`):** este punto decía *"la `DegradationPolicy` de AD-11"*. Ese tipo
  > **nunca existió** y AD-11 quedó enmendado para no prometerlo: la tabla vincula y la cumple
  > cada frontera en su sitio. **El hallazgo sigue abierto tal cual**, solo cambia el nombre de
  > lo que señala; queda citado desde la enmienda de AD-11, con dueño el Epic 7.

### Un límite duro que conviene tener escrito

> "A Live Activity can be active for **up to eight hours** unless its app or a person ends it
> before this limit. […] the Live Activity remains on the Lock Screen […] for up to four
> additional hours […] **a maximum of 12 hours**."

Para CAP-18 (una caminata) 8 horas sobra. Pero como el spine promete cronómetro wall-clock que no
se pausa al cambiar de app, merece una línea: **a las 8 h el sistema mata la Live Activity, no la
sesión.** Son dos ciclos de vida distintos y el spine los trata como uno.

---

## 8. `HKWorkoutBuilder` — CONFIRMADA, sin deprecación · severidad NINGUNA

**Lo verificado** en <https://developer.apple.com/documentation/HealthKit/HKWorkoutBuilder>:

- Disponibilidad: **iOS 12.0 –** (sin fecha de cierre), iPadOS 12.0 –, macCatalyst 13.1 –,
  visionOS 1.0 –, watchOS 5.0 –. **No hay anotación de deprecación de ningún tipo.**
- `finishWorkout(completion:)` sigue siendo el método documentado para "create an `HKWorkout`
  sample and save it to the HealthKit store". Es exactamente lo que necesita CAP-11.
- La clase conforma a **`Sendable`** y a `SendableMetatype` — relevante para AD-12: el adapter de
  HealthKit no arrastrará fricción de concurrencia estricta por este lado.
- Único desvío documentado: "**For watchOS**, use an `HKWorkoutSession` and an `HKLiveWorkoutBuilder`
  instead." No aplica: no hay target de watchOS en el spine.
- Novedades recientes que existen y no estorban: `setCustomZoneConfiguration(_:for:)` y
  `zoneConfiguration(for:)` con `async throws`.

**AD-10 / CAP-11 están bien fundados.** Nada que corregir.

---

## 9. CMPedometer `queryPedometerData` — CONFIRMADA, y **más estricta de lo que CAP-3 asume** · severidad MEDIA

**Lo verificado** en
<https://developer.apple.com/documentation/CoreMotion/CMPedometer/queryPedometerData(from:to:withHandler:)>.
Cita literal de la sección Discussion:

> "Use this method to retrieve historical pedestrian data between the specified dates. This method
> runs asynchronously and delivers the data to the block you provide. **Only the past seven days
> worth of data is stored and available for you to retrieve. Specifying a start date that is more
> than seven days in the past returns only the available data.**"

> "It is safe to call this method at the same time that you are generating continuous updates
> using the `startUpdates(from:withHandler:)` method."

### Lo que esto significa para CAP-3 y AD-8

**El límite real es 7 días, y el modo de fallo es silencioso.** Un `start` de hace más de siete
días **no lanza error**: devuelve "only the available data". Un `GapEstimator` que reste
`pasos(fin) − pasos(inicio)` con una ventana larga obtendrá un número **plausible y equivocado**,
sin ninguna señal de que se ha truncado.

Para la reconstrucción de gap de CAP-3 esto es benigno en el caso normal (el gap de una caminata
son minutos u horas, no días). Es peligroso en dos casos que el spine sí contempla:

1. **Una sesión que sobrevive un cierre largo de la app** — si el dispositivo se apaga o la app
   queda descargada más de siete días con una sesión activa, la reconciliación de AD-8 producirá
   un conteo truncado que pasará por bueno.
2. **La tabla de degradación de AD-11 no tiene fila para esto.** Tiene "Motion & Fitness denegado",
   pero no "los datos históricos existen pero están truncados". Son situaciones distintas con
   respuestas distintas.

   > **Nota (2026-09-21, `B-9`):** este punto decía *"la `DegradationPolicy` de AD-11"*. Ese tipo
   > **nunca existió** y AD-11 quedó enmendado para no prometerlo. **El hallazgo sigue abierto**:
   > la fila que falta sigue faltando, y la enmienda la cita como uno de sus dos huecos, con
   > dueño AD-8 / la historia que vuelva a tocar la reconstrucción.

**Recomendación:** AD-8 debería añadir una condición explícita — *si `startDate` de la
reconciliación es anterior a 7 días, la reconstrucción no se intenta: se degrada directamente a
estimación marcada `~`.* Es una comprobación de dos líneas que convierte un fallo silencioso en
una degradación declarada, que es exactamente la filosofía del resto del spine.

Vale la pena registrar también el buen dato: "It is safe to call this method at the same time
that you are generating continuous updates" — el patrón de AD-8 (reconciliar mientras el
`startUpdates` sigue vivo) está **explícitamente bendecido por Apple**. Eso respalda AD-8.

---

## 10. Open-Meteo — CONFIRMADA gratuita y sin key, pero con **un choque de licencia** · severidad MEDIA

**Lo que dice el spine:** Stack — "Open-Meteo | API pública, sin key, timeout 3 s". Y en el
contrato heredado del SPEC: "**licencias Apache-2.0 / MIT**".

**Lo verificado** en <https://open-meteo.com/en/terms> y <https://open-meteo.com/en/pricing>:

- **Sigue sin API key, sin registro y sin tarjeta.** Confirmado.
- Es gratuita **solo para uso no comercial**, con límites de **menos de 10.000 llamadas/día,
  5.000/hora y 600/minuto**. WalkTracker (usuario único, sin suscripción ni publicidad) cae de
  lleno en la definición de no comercial de Open-Meteo ("private […] apps without subscriptions
  or advertising"). Sin problema por volumen: una app de un solo usuario no roza esos números.
- **No hay garantía de uptime** en el tier gratuito. Compatible con AD-11, que ya dice que el
  clima nunca bloquea la sesión.

### El choque

**Open-Meteo se distribuye bajo CC-BY 4.0, que exige atribución.** El SPEC restringe las
dependencias a "licencias **Apache-2.0 / MIT**". CC-BY 4.0 no es ninguna de las dos, y a
diferencia de MIT/Apache —donde el aviso vive en un fichero de licencias— **CC-BY pide atribución
visible**.

No es un impedimento: es un **requisito de UI no capturado**. Alguien tiene que decidir dónde va
el crédito a Open-Meteo (lo natural: la pantalla de Ajustes). Hoy no aparece ni en el spine, ni en
`CAP-5`, ni en la fila de "Clima no disponible" de AD-11.

**Nota adicional.** El spine ya difiere "WeatherKit en lugar de Open-Meteo" con el argumento de
que "el cambio es de adapter, aislado por AD-10". Correcto — y este hallazgo lo refuerza: WeatherKit
también exige atribución con un enlace legal de Apple, así que el requisito de crédito no
desaparece cambiando de proveedor. Mejor resolverlo ahora en el diseño de Ajustes.

---

## 11. Concurrencia estricta completa + callbacks de CoreMotion — DESACTUALIZADA / INCOMPLETA · severidad ALTA

**Lo que dice el spine (AD-12):** "*strict concurrency* completa activada. Todos los tipos de
`Domain/` son value types `Sendable`."
**Y AD-7:** "Adapters y temporizadores no escriben: **entregan eventos y saltan al main actor**."

**Este es el hallazgo con consecuencia de compilación más directa del informe.** Hay un problema
conocido, y el spine, tal como está redactado, no compila.

### El hecho verificado

`CMPedometerData` es una clase Objective-C y **no conforma a `Sendable`**. Su lista completa de
conformances, según Apple:

`NSSecureCoding`, `NSCoding`, `NSCopying`, `Hashable`, `CustomStringConvertible`,
`CustomDebugStringConvertible`, `CVarArg`, `Equatable`, `NSObjectProtocol`.

**`Sendable` no está en la lista.**
Fuente: <https://developer.apple.com/documentation/CoreMotion/CMPedometerData>

Y el handler es:

```swift
typealias CMPedometerHandler = (CMPedometerData?, (any Error)?) -> Void
```

Fuente: <https://developer.apple.com/documentation/CoreMotion/CMPedometerHandler>

Apple documenta además que el bloque "is called once on **the same serial dispatch queue** used
to process continuous updates" — es decir, **nunca en el main actor**.

### Por qué esto rompe AD-7 tal como está escrito

El patrón ingenuo —el que describe AD-7 literalmente, "entregan eventos y saltan al main actor"—
es este, y **es un error de compilación** bajo concurrencia estricta completa:

```swift
pedometer.startUpdates(from: start) { data, error in
    Task { @MainActor in
        self.sessionStore.apply(data)   // ❌ CMPedometerData no es Sendable
    }
}
```

El compilador rechaza cruzar el límite de aislamiento con un `CMPedometerData`. Y no se arregla
con un `@unchecked Sendable` sobre un tipo que no es tuyo.

**El patrón obligatorio** es extraer los valores **dentro** del handler, en la cola de CoreMotion,
y cruzar al main actor solo con un DTO propio de valores:

```swift
struct StepSample: Sendable {              // en Domain/ o Adapters/Motion/
    let steps: Int
    let distanceMeters: Double?
    let start: Date
    let end: Date
}

pedometer.startUpdates(from: start) { data, error in
    guard let data else { return }
    let sample = StepSample(                // extracción en la cola de CoreMotion
        steps: data.numberOfSteps.intValue,
        distanceMeters: data.distance?.doubleValue,
        start: data.startDate,
        end: data.endDate
    )
    Task { @MainActor in
        self.sessionStore.apply(sample)     // ✅ solo cruza un value type Sendable
    }
}
```

Ojo también con las propiedades: `numberOfSteps` es `NSNumber` (clase, no `Sendable`), igual que
`distance`, `currentPace`, `currentCadence`. **Hay que desenvolverlas a `Int`/`Double` antes de
cruzar**, no pasar el `NSNumber`.

**Corrección para el spine.** AD-7 dice "entregan eventos" sin definir qué es un evento. Debería
fijarlo: *cada puerto de sistema define un DTO `Sendable` de valores propio; lo que cruza al main
actor es siempre ese DTO, nunca un tipo del framework de Apple.* Es la diferencia entre una regla
que se cumple sola y una que se descubre a base de errores del compilador en la story 8.x.

### Un segundo cambio que afecta a cómo se escriben los adapters

Swift 6.2 cambió el comportamiento de las funciones `nonisolated async`
(**`nonisolated(nonsending)`**, feature `NonisolatedNonsendingByDefault`): antes saltaban siempre
al pool cooperativo global; ahora **heredan el contexto de aislamiento del llamador**. Si el
adapter se escribe con métodos `async` no aislados, ya no se comportan como en Swift 6.0/6.1 — lo
que cambia dónde se ejecutan las envolturas asíncronas alrededor de los callbacks de CoreMotion.
Para forzar concurrencia real hay que marcar `@concurrent` explícitamente.

Fuentes: <https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/> ·
<https://www.avanderlee.com/concurrency/swift-6-2-concurrency-changes/>

Como el spine ya fija Swift 6.3.x (o 6.4), este comportamiento es el vigente. AD-12 debería
mencionarlo, aunque sea en una línea, porque es la clase de cambio semántico que no da error de
compilación — solo comportamiento distinto.

---

## 12. Xcode 26.6 depurando en un iPhone con iOS 27 — NO VERIFICABLE · severidad MEDIA

**Por qué importa:** la "Envoltura operativa" del spine dice que el flujo de desarrollo es "build
local desde Xcode al iPhone 14 físico", y que "el simulador no tiene coprocesador de movimiento y
no sirve para validar CAP-2/CAP-3". **El desarrollo de este proyecto depende por completo de poder
depurar en un dispositivo físico.** Y ese dispositivo puede actualizarse a iOS 27 el día 14.

**Lo que se ha podido verificar:**

- Xcode 26 soporta dispositivos y simuladores desde **iOS 15 en adelante** (el límite documentado
  es el inferior; iOS 12 ya no se puede depurar).
  Fuente: <https://developer.apple.com/forums/thread/805506>

**Lo que NO se ha podido verificar:** no se ha encontrado ninguna fuente —ni de Apple ni fiable de
terceros— que confirme o desmienta si **Xcode 26.6 puede depurar en un dispositivo con iOS 27**.
Históricamente Xcode necesita un *device support package* para cada major nuevo de iOS; desde
Xcode 15 se descargan automáticamente, pero no hay documento que lo garantice para este par
concreto.

**Recomendación operativa, y es la acción más urgente de todo el informe:** decidir **antes del 14
de septiembre** si el iPhone 14 de validación se actualiza a iOS 27. Si se actualiza y Xcode 26.6
no puede depurarlo, el proyecto se queda sin su único entorno de validación de CAP-2 y CAP-3 —
que son las dos capacidades que el propio spine identifica como no simulables. Es un riesgo de
parada total con una ventana de dos días para evitarlo.

---

## Acciones concretas, por orden de urgencia

| # | Acción | Plazo |
| --- | --- | --- |
| 1 | Decidir si el iPhone 14 se actualiza a iOS 27, y verificar antes que Xcode 26.6 puede depurar en él (hallazgo 12) | **Antes del 14 sep** |
| 2 | Corregir `Swift | 6.3.2` → `6.3.3`, o saltar a Xcode 27 / Swift 6.4 con decisión fechada (hallazgos 1 y 2) | Inmediato |
| 3 | AD-7: definir que lo que cruza al main actor es un DTO `Sendable` propio, nunca un tipo de framework (hallazgo 11) | Antes de la story del adapter de Motion |
| 4 | AD-13: prohibir `UIDesignRequiresCompatibility` por nombre; añadir que el SDK 27 la ignora; listar las APIs de adopción manual (hallazgo 4) | Antes de la primera story de UI |
| 5 | AD-15: sustituir "compartido por App Group" por "pertenencia a ambos targets"; añadir `NSSupportsLiveActivities` y el tope de 4 KB (hallazgo 7) | Antes de CAP-18 |
| 6 | AD-8: degradar a `~` sin intentar la consulta si el gap supera 7 días (hallazgo 9) | Antes de CAP-3 |
| 7 | AD-2: hacer la regla de `if #available` simétrica (ni hacia atrás ni hacia delante) y actualizar la premisa del dispositivo (hallazgo 3) | Tras la decisión 1 |
| 8 | Resolver la atribución CC-BY 4.0 de Open-Meteo en Ajustes (hallazgo 10) | Antes de CAP-5 |
| 9 | AD-12: evaluar `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` y anotar el cambio de `nonisolated async` de Swift 6.2 (hallazgos 6 y 11) | Al abrir el proyecto |
| 10 | AD-13/Textos: revisar capitalización de cabeceras de sección en el String Catalog (hallazgo 4, matiz 5) | Con la v4 de mockups |

---

## Lo que el spine acierta y conviene no tocar

Para que la revisión no se lea como una lista de reproches: **ocho de las doce afirmaciones
verificadas se sostienen**, y dos de ellas se sostienen mejor de lo que el propio spine sabe.

- **AD-13 es más correcto de lo que su autor podía saber:** Apple ignora el opt-out a partir del
  SDK 27, así que Liquid Glass no es una preferencia estética, es el único futuro disponible.
- **AD-7 acierta en la apuesta de fondo:** la garantía de inicialización única de `@Observable` en
  `@State` de WWDC26 es exactamente el respaldo que necesitaba el escritor único.
- **AD-8 está bendecido por la documentación de Apple:** reconciliar con `queryPedometerData`
  mientras `startUpdates` sigue activo es seguro, y Apple lo dice literalmente.
- **CAP-11 no tiene deuda:** `HKWorkoutBuilder` está vivo, sin deprecación, y además es `Sendable`.
- **Open-Meteo sigue siendo la elección barata y correcta** para un usuario único.

Los problemas de este spine no son de criterio arquitectónico. Son de **números copiados sin
comprobar** (Swift 6.3.2) y de **mecanismos de plataforma descritos de memoria en vez de leídos**
(App Group de la Live Activity, Sendable de CoreMotion). Se corrigen en una tarde.

---

## Fuentes consultadas

**Apple — documentación primaria**

- Adopting Liquid Glass — <https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass>
- `UIDesignRequiresCompatibility` — <https://developer.apple.com/documentation/BundleResources/Information-Property-List/UIDesignRequiresCompatibility>
- Displaying live data with Live Activities — <https://developer.apple.com/documentation/ActivityKit/displaying-live-data-with-live-activities>
- `ActivityStyle` — <https://developer.apple.com/documentation/ActivityKit/ActivityStyle>
- `HKWorkoutBuilder` — <https://developer.apple.com/documentation/HealthKit/HKWorkoutBuilder>
- `CMPedometer.queryPedometerData(from:to:withHandler:)` — <https://developer.apple.com/documentation/CoreMotion/CMPedometer/queryPedometerData(from:to:withHandler:)>
- `CMPedometerData` — <https://developer.apple.com/documentation/CoreMotion/CMPedometerData>
- `CMPedometerHandler` — <https://developer.apple.com/documentation/CoreMotion/CMPedometerHandler>
- Releases (Xcode / iOS) — <https://developer.apple.com/news/releases/>
- Xcode 27 RC Release Notes — <https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes>
- What's new in SwiftUI, WWDC26 — <https://developer.apple.com/videos/play/wwdc2026/269/>
- Requisitos de envío a App Store — <https://developer.apple.com/news/>
- Deployment targets en Xcode 26 (foros) — <https://developer.apple.com/forums/thread/805506>

**Swift**

- Instalación / última estable — <https://www.swift.org/install/macos/>
- Swift 6.4 release process — <https://forums.swift.org/t/swift-6-4-release-process/85421>
- Embedded Swift en 6.4 — <https://www.swift.org/blog/embedded-swift-improvements-coming-in-swift-6.4/>
- Mapa Xcode ↔ Swift — <https://xcodereleases.com/>

**Open-Meteo**

- Términos — <https://open-meteo.com/en/terms>
- Precios y límites — <https://open-meteo.com/en/pricing>

**Secundarias (marcadas como tales en el cuerpo)**

- Swift Testing vs XCTest — <https://blakecrosley.com/blog/swift-testing-vs-xctest>
- XCTest y Swift Testing comparados (2026) — <https://www.codeanatomybyaher.com/articles/swift-unit-testing-xctest-swift-testing-compared>
- Cuándo migrar a Swift Testing — <https://blog.micoach.itj.com/swift-testing-vs-xctest>
- Default actor isolation en Swift 6.2 — <https://www.avanderlee.com/concurrency/default-actor-isolation-in-swift-6-2/>
- Approachable Concurrency en Swift 6.2 — <https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/>
- Cambios de concurrencia en Swift 6.2 — <https://www.avanderlee.com/concurrency/swift-6-2-concurrency-changes/>
- WWDC26 SwiftUI, desglose — <https://dev.to/arshtechpro/wwdc26-whats-new-in-swiftui-a-developers-breakdown-1333>
- `@State` como macro en WWDC26 — <https://byteiota.com/swiftui-wwdc-2026-asyncimage-caching-and-state-fixed/>
- Fecha de iOS 27 — <https://9to5mac.com/2026/09/09/apple-confirms-ios-27-release-date-september-14/> · <https://www.macrumors.com/2026/09/09/apple-announces-ios-27-release-date/>
- Compatibilidad de iOS 27 con iPhone 14 — <https://www.macworld.com/article/2986799/ios-27-new-iphone-features-release-date-beta-compatiblity-apple-intelligence-siri.html>
- Rango de deployment target en Xcode 27 — <https://bleepingswift.com/blog/deployment-target-supported-range-xcode-27>
