---
title: 'B-9 — La tabla de degradación deja de prometer un tipo, y la atribución tiene dueño'
type: 'chore'
created: '2026-09-21'
baseline_commit: 'a97c5f69468b88eb4ce0380c08a3ca72ba0bcd49'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-retro-2026-09-20.md'
  - '{project-root}/_bmad-output/implementation-artifacts/decisiones-2026-09-20.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** dos obligaciones que vienen señaladas desde la retro del Epic 1 y se han aplazado dos
veces, empaquetadas en un mismo action item pese a ser de naturaleza distinta.

1. **AD-11 declara *"una única `DegradationPolicy`"* y el tipo no existe.** El Structural Seed lo
   lista y `Domain/Ports/PermissionStatus.swift:7` lo cita por su nombre. De las seis filas de la
   tabla, **tres son de épicas que no existen** (Salud 6.1, notificaciones 6.2, Live Activity Epic 7),
   y las tres vivas no comparten más que un booleano: qué pantalla, qué texto y en qué momento son
   distintos por naturaleza. Y la fila de red **ni siquiera es un permiso**.
2. **La atribución de Open-Meteo se cayó porque nadie la poseía.** AD-24 la sitúa en "Ajustes →
   Acerca de"; hoy vive dentro de `if let weather` en la tarjeta de clima, así que **no se ve sin
   clima ni fuera de una sesión**. Y `epics.md` **no menciona "Acerca de" ni una vez**: no es que se
   olvidara, es que no era de nadie. El comentario de `SettingsView.swift:6-7` dice que "llega con su
   historia" — una historia que no existe.

**Y un tercer hallazgo que nadie había mirado:** el repo **no tiene `LICENSE` ni `NOTICE`**, y el
texto de CC-BY 4.0 **no está citado en ninguna parte**. Toda la cadena —AD-24, el SPEC, la spec de la
2.1— se cita a sí misma sin haber transcrito nunca la cláusula.

**Enfoque:** que los documentos digan lo que el producto es, que la atribución tenga un sitio y un
dueño, y que la obligación de licencia quede por escrito con su fuente.

## Boundaries & Constraints

**Decisiones de Paul (2026-09-21):**
- **AD-11 se enmienda, no se construye el tipo.** La tabla **vincula** y cada frontera la cumple. Hoy
  un `DegradationPolicy` tendría dos llamantes y una sola rama bloqueante, y **no eliminaría ningún
  `switch`**: añadiría una indirección antes de él. Precedente en el propio spine: AD-10 se dejó como
  conjunto cerrado con dos miembros sin escribir, en vez de cambiar la regla.
- **La atribución se añade en Ajustes y se queda también en la tarjeta.** CC-BY premia el crédito
  junto al dato, así que quitarla de la tarjeta empeoraría el cumplimiento donde el dato se ve — y
  borrarla revertiría un criterio de aceptación de la 2.1, ya aceptada.
- **Se escribe un `NOTICE`** con lo que exige la licencia y lo que se decidió a partir de ello.

**Decisión de Paul (2026-09-21, posterior a la aprobación — renegocia este bloque):**
- **"Acerca de" lleva también el enlace al texto de la licencia.** §3(a)(1)(C) pide nombrar la
  licencia **e incluir su texto o un enlace a ella**, y la app solo hacía la primera mitad: el
  enlace vivía únicamente en el `NOTICE`, que **no viaja dentro del `.app`**. Esto **renegocia**
  el `Never` de *"ni otras licencias"* de abajo y la fila de matriz que declaraba **un** enlace:
  no se adelanta "otra licencia" —es **la misma** obligación, la de los datos de clima, con su
  segunda mitad cumplida—, y sigue habiendo **dos** entradas, no tres. La URL es la canónica que
  `NOTICE` §2 verificó descargando la fuente, no una escrita de memoria. Lo demás del `Never`
  —versión de la app, ajustes del Epic 3, la 4.2 o el Epic 5— **sigue en pie**. El rastro de que
  el hueco estuvo abierto no se borra: `NOTICE` §5 lo conserva con fecha.

**Always:**
- **La enmienda de AD-11 dice la verdad completa**, incluido lo incómodo: qué filas tienen
  implementación hoy, cuáles no, y que la fila de red no pasa por el vocabulario de permisos. Una
  enmienda que declare las seis "cumplidas por convención" sería cambiar una mentira por otra.
- **El `NOTICE` cita la cláusula, no la parafrasea de memoria.** Si el texto exacto no se puede
  verificar, se dice eso en vez de inventarlo. Lleva enlace a la licencia y a Open-Meteo.
- **El "Acerca de" gana dueño.** Que exista no basta: hay que dejar registrado que es suyo, o la
  próxima historia que toque Ajustes —la meta semanal del Epic 3, el sonido de la 4.2— puede rehacer
  la pantalla y volver a perderlo. Es la lección L2, y ya pasó con esto mismo.
- **La pantalla nace cumpliendo los gates**: tokens de `UI/Style/`, sin lados de marco numéricos, sin
  colores cromáticos del sistema nombrados, sin UIKit, con sus cadenas y sus `comment:` en el catálogo.
- El enlace se abre con `Link`/`openURL` de SwiftUI, como ya hace `MotionBlockedView`.

**Never:**
- Construir `DegradationPolicy`, ni un sucedáneo con otro nombre.
- Quitar la atribución de la tarjeta de clima.
- Adelantar nada más del "Acerca de": ni versión de la app, ni otras licencias, ni ajustes que
  pertenezcan al Epic 3 o al 5.
- Tocar la lógica del clima (2.1), el campo de zancada (2.3) ni el flujo de permisos.
- Declarar cumplidas las filas de la tabla que no tienen implementación.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Atribución sin clima | Ajustes, sin sesión y sin clima nunca capturado | la atribución **se ve** | hoy no se ve en ningún sitio |
| Atribución con clima | sesión con clima | se ve **en los dos sitios**: tarjeta y Ajustes | — |
| El enlace | se toca la atribución de Ajustes | abre open-meteo.com | — |
| El enlace de licencia *(decisión de Paul, 2026-09-21)* | se toca la segunda fila de "Acerca de" | abre `https://creativecommons.org/licenses/by/4.0/`, la URL canónica de `NOTICE` §2 | hoy la licencia se nombra y no se enlaza: §3(a)(1)(C) a medias |
| Objetivo táctil | el enlace en Ajustes | ≥ 44 pt, desde el token | — |
| Dynamic Type y VoiceOver | texto al máximo, lector activo | sin recortes; el enlace se anuncia como tal | — |
| Claro y oscuro | los dos temas | legible en ambos, sin color cromático nombrado | — |
| `PermissionStatus.swift:7` | se lee el comentario | nombra **las fronteras**, no un tipo inexistente | hoy cita `DegradationPolicy` |
| AD-11 tras la enmienda | se lee la regla | dice que la tabla vincula y **cuáles filas no tienen implementación** | — |
| `NOTICE` | se lee | cita la cláusula con su fuente y explica la decisión | hoy no existe |
| Gates | todo lo anterior | `check-project-shape` y `verify-domain` verdes | — |

</frozen-after-approval>

## Code Map

**Mitad 1 — la enmienda**
- `ARCHITECTURE-SPINE.md` AD-11 (`:203-214`) — la tabla de seis filas y la nota de A-5 que ya declara
  el problema abierto. La enmienda sustituye esa nota.
- `ARCHITECTURE-SPINE.md` Structural Seed (`:366`) — `DegradationPolicy.swift` marcado `⚠️ NO existe`.
  Al enmendar AD-11, esa entrada **sale** del árbol objetivo.
- `Domain/Ports/PermissionStatus.swift:7` — *"la respuesta a 'falta esta capacidad' vive en
  `DegradationPolicy`, no aquí"*. Es un comentario, nada compila contra él, y por eso lleva desde el
  Epic 1 citando un tipo inexistente. **Dejarlo en "no aquí" a secas pierde el puntero** y reabre el
  hallazgo por tercera vez: debe nombrar las fronteras reales.
- `_bmad-output/implementation-artifacts/epic-2-context.md:48-49` — el bullet que carga el encargo.
- **Las fronteras que hoy cumplen la tabla**, para nombrarlas bien:
  `SessionStore+StartFlow.swift:20-29` (Motion → pantalla bloqueante, la **única** fila bloqueante),
  `SessionStore+Weather.swift:27-35` (ubicación → sigue sin clima),
  `OpenMeteoAdapter.swift:61-64` → `SessionStore+Weather.swift:141-170` (red → `nil` silencioso).
- **Huecos ya registrados** que la enmienda no puede tapar: `reviews/review-vigencia-tecnologica.md:358-363`
  (la fila de Live Activity se evalúa una sola vez) y `:422-424` (falta una fila para datos históricos
  truncados).

**Mitad 2 — la atribución**
- `WalkTracker/UI/Session/WeatherCard.swift:45` `attributionURL`, `:50-58` el `Link`. **No se toca**,
  salvo para darle su `comment:` de catálogo, que hoy no tiene.
- `WalkTracker/UI/Settings/SettingsView.swift:50-91` — `NavigationStack > Form >` una sola `Section`.
  La nueva va al lado. `:6-7` es el comentario **falso** que hay que corregir.
- `WalkTracker/UI/Permission/MotionBlockedView.swift:55-63` — el patrón de abrir una URL desde la UI,
  y su `settingsURL` interno es el **precedente de cómo probar un enlace sin renderizar** (lo fija
  `WalkTrackerTests/UI/MotionBlockedViewTests.swift`). Es también lo que la decisión D1 del 2026-09-21
  eligió como arnés: lógica de presentación en tipos probables.
- `WalkTracker/Resources/Localizable.xcstrings` — poblado por extracción; toda cadena con su `comment:`.
- `Scripts/check-project-shape.sh` — sección 12 (familia cromática, marcos, radios), sección 6
  (receptores por tipo), sección 10 (sin UIKit). Una sección que solo pinta texto y un enlace no toca
  ningún store: limpia por construcción.
- `_bmad-output/implementation-artifacts/deferred-work.md:103` — **`SessionMetrics.degraded` colgaba de
  B-9**: nadie registra ni pinta la bandera que produce `Session.swift`. Si este chore cierra sin
  darle destino, esa entrada queda huérfana por segunda vez.

## Tasks & Acceptance

**Execution:**
- [x] `ARCHITECTURE-SPINE.md` — enmendar AD-11 (la tabla vincula, cada frontera la cumple, con la
      verdad de qué filas tienen implementación) y quitar `DegradationPolicy.swift` del Structural Seed.
- [x] `Domain/Ports/PermissionStatus.swift` — el comentario nombra las fronteras, no un tipo.
- [x] `_bmad-output/implementation-artifacts/epic-2-context.md` — el bullet del encargo, resuelto.
- [x] `NOTICE` — la cláusula con su fuente, qué se decidió y dónde se cumple.
- [x] `WalkTracker/UI/Settings/SettingsView.swift` — la sección "Acerca de" con la atribución, y el
      comentario falso de `:6-7` corregido.
- [x] `WalkTracker/Resources/Localizable.xcstrings` — las cadenas nuevas y el `comment:` que le falta
      a la de la tarjeta.
- [x] `WalkTrackerTests/` — que la atribución no dependa del clima, con el precedente de
      `MotionBlockedViewTests`.
- [x] **Dar dueño al "Acerca de"**: registrarlo donde la próxima historia de Ajustes lo vea.
- [x] `deferred-work.md` — destino para `SessionMetrics.degraded`, y lo que quede.

**Acceptance Criteria:**
- Dada una instalación sin clima capturado nunca, cuando se abre Ajustes, entonces **la atribución se
  ve** — y hoy no se ve en ningún sitio.
- Dado el spine tras la enmienda, cuando se lee AD-11, entonces **no promete ningún tipo** y dice
  cuáles de sus seis filas no tienen implementación.
- Dado `grep DegradationPolicy` sobre el árbol, cuando se ejecuta, entonces **no aparece** como algo
  que exista o vaya a existir.
- Dado el `NOTICE`, cuando se lee, entonces se sabe **qué exige la licencia** y **dónde se cumple**,
  con su enlace.
- Dada la próxima historia que toque Ajustes, cuando busque qué hay en esa pantalla, entonces
  **encuentra que el "Acerca de" tiene dueño**.

## Implementation Notes

**Mitad 1 — la enmienda.** AD-11 pasa de *"la respuesta está en **una única** `DegradationPolicy`"*
a *"la respuesta **es esta tabla**, y la cumple cada frontera en su sitio"*. La tabla gana una
tercera columna, **"Dónde se cumple hoy"**, que es donde cabe la verdad incómoda: tres filas con
ruta y línea, tres marcadas `⏳ ni una línea` con la épica que las trae, la de Motion señalada como
la **única bloqueante** y la de red con el motivo por el que no encaja en la regla —no hay
`PermissionStatus` de la red ni puerto con `status`—. La nota de A-5 se sustituye por la enmienda,
que recoge el argumento de Paul (dos llamantes, ningún `switch` eliminado, el precedente de AD-10)
y **cita los dos huecos ya registrados** de `review-vigencia-tecnologica.md` en vez de taparlos.
`DegradationPolicy.swift` sale del Structural Seed, y con él el único `⚠️` del árbol: el encabezado
lo dice, porque un árbol objetivo puede tener cosas por escribir (`⏳`), no cosas dadas por escritas.

**El comentario de `PermissionStatus.swift` no se queda en "no aquí" a secas**, que era el riesgo
que la Code Map señalaba: nombra las dos fronteras escritas con su tipo y su método, y dice que la
tercera fila viva no pasa por este vocabulario. Perder el puntero habría reabierto el hallazgo por
tercera vez.

**Mitad 2 — la atribución.** Lo que la sección contiene vive en `AboutSection` (`UI/Settings/`, sin
SwiftUI), y `SettingsView` solo lo recorre: es la decisión D1 del 2026-09-20 aplicada donde es
barata. `items` es una **constante escrita a mano** —no `Item.allCases`— por dos razones: no hay
ninguna entrada de la que colgar un `if`, y el test puede comparar las dos listas, con lo que una
entrada declarada que nunca llegue a la pantalla también falla. La URL se escribe a mano como
`MotionBlockedView.settingsURL` y un test la empareja con la de `WeatherCard`, que **no se
centraliza**: acoplar Ajustes a la pantalla de sesión para ahorrar una constante habría sido peor
que probar que coinciden.

**El texto vive en la vista y no en `AboutSection`** porque es donde la extracción del String
Catalog lo ve con su `comment:`. Tres cadenas nuevas, y la de la tarjeta recupera el `comment:` que
le faltaba en el código —el catálogo lo tenía a mano, así que una re-extracción lo habría perdido—.

**El `NOTICE` cita, no parafrasea.** La Sección 3(a) entera y la 4(c) de CC BY 4.0 están transcritas
del texto plano canónico descargado el 2026-09-21, con URL, fecha, tamaño y **SHA-256** del fichero;
lo de Open-Meteo, de su página de licencia, misma fecha. De ahí salió el dato que zanja el diseño:
Open-Meteo pide el enlace *"next to any location Open-Meteo data are displayed"* — **junto al dato**,
no "en algún sitio de la app". Eso convierte la atribución de la tarjeta en un requisito, no en una
duplicación por indecisión, y es más fuerte que el argumento con el que se entró a este chore.

**Lo que el `NOTICE` dice que NO se cumple**, en vez de callarlo: §3(a)(1)(C) pide indicar la
licencia **e incluir su texto o un enlace**. La app la nombra ("CC BY 4.0") y no enlaza a ella; el
enlace vive solo en el `NOTICE`, que no viaja dentro del `.app`. Añadir esa fila queda fuera del
bloque congelado ("Never: … ni otras licencias"; la matriz declara **un** enlace en Ajustes y su
destino), así que se registra en `deferred-work.md` con dueño: la 3.1, que es la siguiente historia
que toca Ajustes.

> **Cerrado el mismo 2026-09-21, después de escribir lo de arriba** (decisión de Paul, fila 6 del
> Spec Change Log): el hueco no espera a la 3.1. "Acerca de" tiene una segunda fila que enlaza a
> `https://creativecommons.org/licenses/by/4.0/`, y el párrafo anterior se conserva porque describe
> el estado que hubo y el razonamiento que lo dejó abierto — borrarlo sería quitar el rastro, que es
> justo el defecto que este chore existe para arreglar.

**El dueño del "Acerca de" se registra en cinco sitios a propósito**, porque cada uno lo lee alguien
distinto: `NOTICE`, AD-24, el bloque 🔒 de `epics.md` bajo la 2.3 —con las historias que van a tocar
Ajustes nombradas: 3.1, 4.2 y Epic 5—, la nota del épico 3 y los doc comments de `SettingsView` y
`AboutSection`. La redundancia es la respuesta a la lección L2: el compilador de contexto de cada
épica lee planificación, así que un dueño escrito solo en el código no llega a la historia siguiente.

**`SessionMetrics.degraded` se parte en dos y cada mitad gana dueño nombrado:** el registro en
`OSLog` va a **B-10** —"un nivel de log por clase de suceso" en `SessionStore` es literalmente su
encargo—, y "si la pantalla debe decir algo" queda como decisión de producto de **Paul**, con plazo
(la retro del Epic 3). Se dice por escrito por qué B-9 no lo cierra: su bloque congelado prohíbe
tocar la lógica de la sesión. Dejarlo otra vez en "la historia que vuelva a tocar X" lo habría
dejado huérfano por tercera vez.

**Fuera de la Code Map, y hecho igual porque la Intent lo pedía** ("que los documentos digan lo que
el producto es"): la restricción de Licencias de `SPEC.md` llevaba un ⚠️ *"ABIERTO … dueño B-9"* y
las dos menciones de `review-vigencia-tecnologica.md` hablaban de *"la `DegradationPolicy` de
AD-11"*. Cerrar B-9 dejando en pie documentos que lo nombran como dueño pendiente habría recreado
exactamente el fallo que este chore arregla. Los hallazgos del review **siguen abiertos**: solo
cambia el nombre de lo que señalan.

## Spec Change Log

| # | Qué | Decisión |
|---|---|---|
| 1 | *(Vigente hasta el cierre del chore; **superada por la fila 6**, que sí edita el bloque, con permiso explícito de Paul y anotándolo.)* **El bloque congelado no se tocó y nada se resolvió en su contra.** Se registra explícitamente porque la retro del Epic 2 señaló el caso contrario como fallo de proceso (una "Decisión de Paul" congelada en la 2.2, resuelta en contra sin editar el bloque ni anotarlo aquí) | Sin cambios que registrar en la Intent ni en los Boundaries |
| 2 | **Cuatro ficheros tocados fuera de la Code Map:** `SPEC.md` (restricción de Licencias), `reviews/review-vigencia-tecnologica.md` (dos menciones), `epics.md` (el registro de dueño, que la Code Map pedía sin nombrar fichero) y `sprint-status.yaml` | **Aplicado.** Los tres primeros nombran a `B-9` como dueño pendiente o citan el tipo inexistente: cerrar B-9 dejándolos en pie recrearía el fallo que el chore arregla, y la Intent pide que "los documentos digan lo que el producto es". El cuarto es la contabilidad del sprint, como en A-5 y B-5. **Los hallazgos del review siguen abiertos**: solo cambia el nombre de lo que señalan |
| 3 | La Code Map decía que `WeatherCard.swift` "no se toca, salvo para darle su `comment:`". Además del `comment:`, su `attributionURL` gana **cinco líneas de doc comment** | **Aplicado.** Ni una línea de comportamiento: dice que esa atribución no se quita y por qué, con la frase de Open-Meteo. Evitar que alguien la borre al ver que ya existe en Ajustes es el objeto del chore, y un `Never` del bloque congelado |
| 4 | El `comment:` de la cadena "Zancada" decía *"Encabezado de la **única** sección de la pantalla de Ajustes"* | **Aplicado.** Deja de ser cierto al añadir la segunda sección. Mismo criterio que el resto del chore: un comentario que afirma de más es lo que se está arreglando |
| 5 | La matriz congelada declara **un** enlace en Ajustes, a `open-meteo.com`. CC BY 4.0 §3(a)(1)(C) pide además enlazar al **texto de la licencia** | **No se añade un segundo enlace.** Se respeta la matriz y el `Never` de "ni otras licencias". El incumplimiento queda escrito en `NOTICE` §5, en la nota de AD-24 y en `deferred-work.md`, con dueño la 3.1 — en vez de resolverse en contra del bloque sin registrarlo. **Superado por la fila 6** |
| 6 | **Paul renegoció la fila 5 el mismo 2026-09-21**, después de aprobado el bloque: el hueco se cierra ahora y no en la 3.1 | **Aplicado, y por el camino que el proceso pide.** La decisión se anota **dentro** del bloque congelado (apartado "Decisión de Paul (2026-09-21, posterior a la aprobación)") y la matriz gana su fila —las dos únicas ediciones hechas ahí—, en vez de resolverse en contra del bloque en silencio, que es el fallo de proceso que la retro del Epic 2 señaló y que la fila 1 de esta tabla registra. **Qué cambia en el árbol:** `AboutSection` gana `licenseTextURL` y el `case licenseText`, `items` pasa a dos entradas, `SettingsView` pinta su fila, `AboutSectionTests` la fija con host **y ruta** (más un test de que las dos filas no comparten destino), y hay una cadena nueva con su `comment:`. **Qué NO cambia:** siguen siendo **dos** filas —el resto del `Never` sigue vigente: ni versión de la app, ni ajustes del Epic 3, 4.2 o Epic 5—, y el `NOTICE` §5, AD-24 y `deferred-work.md` **conservan** la descripción del hueco con la fecha en que se cerró, en vez de borrarla |

## Review Triage Log

## Design Notes

**Por qué enmendar y no construir.** El tipo se escribiría hoy con **dos llamantes** y las cuatro
filas restantes las escribiría quien haga 6.1, 6.2 y el Epic 7 — diseñar la abstracción antes de
tener el segundo ejemplo real de cada clase. Y no capturaría lo que de verdad varía: qué pantalla,
qué texto, en qué momento. El `switch` de la frontera no desaparecería; se le pondría una indirección
delante. Lo compartido **ya está tipado**: `PermissionStatus` y `CapabilityError`, los dos en
`Domain/`.

**Lo que la enmienda no puede hacer.** Declarar las seis filas "cumplidas por convención" sería
sustituir una mentira por otra: tres no tienen una línea de código y dos tienen huecos ya registrados.
La enmienda honesta dice qué se cumple, dónde, y qué está por escribir.

**Por qué la atribución se queda en los dos sitios.** No es indecisión: CC-BY premia el crédito junto
al dato, y la tarjeta es el único sitio donde el dato se ve. Ajustes cubre el caso de que nunca haya
habido clima. Quitar una de las dos empeora algo.

**El riesgo de fondo no es técnico.** La obligación se cayó porque **nadie poseía el "Acerca de"** —
`epics.md` no lo nombra. Mover el `Link` sin arreglar eso deja el mismo agujero para la próxima
historia que rehaga Ajustes. Es la lección L2, y esta es su segunda vuelta con este mismo tema.

## Verification

**Commands:**
- `grep -rn "DegradationPolicy" --include="*.swift" --include="*.md" .` — no debe quedar ninguna
  afirmación de que existe o existirá.
- `bash Scripts/check-project-shape.sh` y `check-project-shape-tests.sh` — verdes, con la pantalla nueva.
- `bash Scripts/verify-domain.sh` — verde y sin cambios: esto no toca el dominio.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` — TEST SUCCEEDED.
- **Mutación:** esconder la atribución de Ajustes tras una condición de clima debe hacer fallar el test
  nuevo. Es el defecto que este chore arregla.

**Manual checks (simulador):** Ajustes en una instalación limpia, sin haber capturado clima nunca — la
atribución se ve y el enlace abre. En claro y en oscuro, y con el texto al máximo.

---

## Verification — resultados (2026-09-21)

| Comprobación | Resultado |
|---|---|
| `grep -rn "DegradationPolicy"` sobre `*.swift`, `*.md`, `*.sh`, `*.yml`, `*.yaml` | **0 aciertos en Swift.** En `.md` quedan solo registros históricos (retros, specs cerradas) y las notas nuevas, que dicen *"nunca existió"*. **Ninguna afirmación de que existe o existirá** |
| `bash Scripts/check-project-shape.sh` | **verde** — "forma del proyecto correcta", con `AboutSection.swift` y la sección nueva en el árbol |
| `bash Scripts/verify-domain.sh` | **verde** — 240 tests en 16 suites. Mismo conteo que antes: esto no toca el dominio |
| `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` | **TEST SUCCEEDED** — **642 tests en 51 suites** (antes 638 en 50): +1 suite, +4 casos |
| El suite nuevo corrió de verdad (lección D10: contar los casos) | `-only-testing:WalkTrackerTests/AboutSectionTests` → **4 tests en 1 suite**, los cuatro ejecutados por nombre |

**Mutación 1 — la que pide la Verification: esconder la atribución tras una condición de clima.**
`static let items: [Item] = [.openMeteoAttribution]` → `static func items(hasCapturedWeather: Bool)
-> [Item] { hasCapturedWeather ? [.openMeteoAttribution] : [] }`, con `SettingsView` llamándola.
**TEST FAILED**, y antes de ejecutar nada:

```
AboutSectionTests.swift:28:36: error: value of type '@Sendable (Bool) -> [AboutSection.Item]'
                               has no member 'contains'
AboutSectionTests.swift:36:30: error: cannot convert value of type
                               '@Sendable (Bool) -> [AboutSection.Item]' to expected argument type
                               '[AboutSection.Item]'
```

No hay forma de condicionar la atribución al clima dejando la suite en verde: la firma constante es
el invariante.

**Mutación 2 — la sección pierde su fila al reorganizar la pantalla.** `items = []`, que sí compila:
**TEST FAILED** en tiempo de ejecución, 2 de 4 casos, con el valor a la vista:

```
✘ Expectation failed: (AboutSection.items → []).contains(.openMeteoAttribution)
✘ Expectation failed: (AboutSection.items → []) == (AboutSection.Item.allCases →
                      [WalkTracker.AboutSection.Item.openMeteoAttribution])
```

El árbol se revirtió tras cada mutación y la suite volvió a verde.

**Lo que la suite NO cubre, y queda registrado en `deferred-work.md`:** el cableado físico de la
vista —Dynamic Type sin recortes, VoiceOver anunciando la fila **como enlace**, los 44 pt medidos de
verdad—. Quitarle a `aboutLabel` su `.frame(minHeight:)` o cambiar el `Link` por un `Text` deja todo
en verde. Es el mismo hueco ya conocido del resto de Ajustes (2.3, B-2), no uno nuevo.

**No ejecutado:** los checks manuales en simulador y dispositivo de la lista de arriba. Se suman a
los que ya esperan una salida (2.1 / B-8).

---

## Verification — segunda ronda (2026-09-21, cierre de §3(a)(1)(C))

Lo que cubre esta ronda es el añadido de la fila 6 del Spec Change Log: la **segunda entrada**
de "Acerca de", con el enlace al texto de CC BY 4.0.

| Comprobación | Resultado |
|---|---|
| `bash Scripts/check-project-shape.sh` | **verde** — "forma del proyecto correcta" |
| `bash Scripts/check-project-shape-tests.sh` | **verde** — 208 casos, 0 fallos |
| `bash Scripts/verify-domain.sh` | **verde** — 240 tests en 16 suites, el mismo conteo: esto tampoco toca el dominio |
| `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` | **TEST SUCCEEDED** — **645 tests en 51 suites** (antes 642 en 51): +3 casos, ninguna suite nueva |
| Los tres casos nuevos corrieron **por nombre** (lección D10) | Leídos del `.xcresult`, no del "TEST SUCCEEDED": `AboutSectionTests` pasa de 4 a **7** casos, los siete `Passed` — "El enlace al texto de la licencia está en «Acerca de» sin depender de nada", "El enlace de licencia lleva al texto de CC BY 4.0 por HTTPS" y "Las dos entradas de «Acerca de» no llevan al mismo sitio" |

**Mutación — la entrada nueva se declara y no se pinta.** Es el defecto exacto por el que esta
obligación se perdió la primera vez: `static let items: [Item] = [.openMeteoAttribution, .licenseText]`
→ `[.openMeteoAttribution]`, dejando `case licenseText` en el `enum`. Compila y **TEST FAILED**,
2 de 7 casos, con los dos valores a la vista:

```
✘ Expectation failed: (AboutSection.items → [openMeteoAttribution]).contains(.licenseText)
✘ Expectation failed: (AboutSection.items → [openMeteoAttribution]) ==
                      (AboutSection.Item.allCases → [openMeteoAttribution, licenseText])
```

El árbol se revirtió y la suite volvió a verde (645 en 51, gate de forma verde).

**Lo que esta ronda NO cubre**, y es el mismo hueco ya registrado en `deferred-work.md` para la
fila anterior, sin ampliarlo: lo físico de la vista. Que la fila nueva no se recorte con Dynamic
Type, que VoiceOver la anuncie **como enlace** y que sus 44 pt se midan de verdad sigue pidiendo el
simulador y el iPhone. Los checks manuales **no se ejecutaron**.
