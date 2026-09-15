---
title: 'Retro Epic 1 · A-6 — gates de arquitectura en check-project-shape.sh'
type: 'chore'
created: '2026-09-14'
baseline_commit: 'cf5725ba1ab490466b1dc65523e6975e3c29e734'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-retro-2026-09-14.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** hoy estas reglas de arquitectura se cumplen, pero solo porque se revisan a mano, sin ningún gate:
- solo `MotionAdapter` conoce CoreMotion;
- el dominio no llama a `Date()`;
- solo `SessionStore` usa `StoragePort` (AD-16);
- ninguna vista importa un framework de sistema (AD-10).

Ya existe una excepción: `MotionBlockedView` importa `UIKit` [fuente: epic-1-retro A3, A-6, Q-4]. El A-1 cubrió la parte de escribir el estado del store.

**Enfoque:** añadir esas reglas a `Scripts/check-project-shape.sh`, con los mismos mensajes `fichero:línea: error:`, cada una con su caso rojo, y dejar el árbol real en verde.

## Boundaries & Constraints

**Always:**
- Cada regla nueva tiene caso rojo en `Scripts/check-project-shape-tests.sh`. El fixture limpio sigue pasando e incluye los usos legítimos, para que ninguna regla pase por marcarlo todo.
- **CoreMotion:** el `import CoreMotion` solo se admite en `WalkTracker/Adapters/Motion/`. Los tests de adapters (`WalkTrackerTests/Adapters/`) quedan fuera del gate.
- **Tiempo en el dominio:** en `Domain/` no hay `Date()`, `Date.now` ni `Calendar.current` en código. Los comentarios que los nombran no cuentan [fuente: AD-3, AD-19; `Domain/Ports/ClockPort.swift`].
- **`StoragePort`:** las llamadas a `loadActiveSession`, `saveActiveSession`, `clearActiveSession` y `setAsideActiveSession` solo se admiten en `WalkTracker/Application/SessionStore*.swift`, más su implementación en `WalkTracker/Adapters/Persistence/`.
- **Frameworks en la UI:** `WalkTracker/UI/` no importa CoreMotion, CoreLocation, HealthKit, ActivityKit, WidgetKit, CoreHaptics, AVFoundation, AudioToolbox ni UserNotifications [fuente: AD-10]. También `UIKit` (ver Decisiones).
- `check-project-shape.sh` en verde sobre el árbol real; también `verify-domain.sh` y la suite completa.

**Decisiones de Paul (2026-09-14):**
- **`UIKit` en la UI:** prohibido, sin excepciones. `MotionBlockedView` deja de importarlo y abre Ajustes con
  `URL(string: "app-settings:")`, el valor documentado de `UIApplication.openSettingsURLString`, mediante el
  `openURL` de SwiftUI que ya usa. El comportamiento no cambia.

**Never:**
- Tocar las secciones 1–6 existentes salvo para numerar las nuevas.
- Gates que dependan de la red o de herramientas que el repo no usa: se sigue con `grep`/`sed` en bash, como el resto.
- Aplicar las reglas a `WalkTrackerTests/`, `Shared/` o `WalkTrackerActivity/`, salvo lo que ya comprueban las secciones 2 y 5.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| CoreMotion fuera del adapter | `import CoreMotion` en `WalkTracker/UI/X.swift` o en `WalkTracker/Application/Y.swift` | falla con AD-10 y fichero:línea | exit 1 |
| CoreMotion en su sitio | `import CoreMotion` en `WalkTracker/Adapters/Motion/MotionAdapter.swift` | pasa | — |
| Tiempo en el dominio | `let now = Date()` o `Date.now` o `Calendar.current` en `Domain/Session/X.swift` | falla con AD-3/AD-19 | exit 1 |
| Comentario en el dominio | `/// Nunca \`Date()\` dentro del dominio.` | pasa | — |
| `StoragePort` fuera del store | `storage.saveActiveSession(…)` en `WalkTracker/UI/X.swift` o `WalkTracker/App/Y.swift` | falla con AD-16 | exit 1 |
| `StoragePort` legítimo | llamadas en `SessionStore+Recovery.swift` y en el adapter de persistencia | pasa | — |
| Framework de sistema en la UI | `import HealthKit` o `import UIKit` en `WalkTracker/UI/X.swift` | falla con AD-10 | exit 1 |
| Árbol real | el repositorio tras el cambio | `check-project-shape: forma del proyecto correcta.` | — |

</frozen-after-approval>

## Code Map

- `Scripts/check-project-shape.sh` (205 líneas):
  - secciones 1–6, con el helper `err "fichero:línea" "mensaje"`, `fail_count` y el veredicto final;
  - la sección 4 prohíbe frameworks en `Domain/` con `banned=…` y `grep -rnE`: patrón a copiar;
  - la sección 6 cubre las escrituras del store (A-1).
- `Scripts/check-project-shape-tests.sh` (200 líneas): `make_fixture` monta un árbol temporal con `project.yml` y
  un `WalkTracker/UI/SessionView.swift` legítimo; `assert_gate name root want needle` es el patrón de cada caso.
  Hoy hay 21 casos.
- **Estado del árbol real:**
  - `import CoreMotion` solo en `WalkTracker/Adapters/Motion/MotionAdapter.swift` (también en
    `WalkTrackerTests/Adapters/MotionAdapterTests.swift`, fuera del gate).
  - `ActivityKit` en `Shared/` y `WalkTrackerActivity/`, legítimo y fuera del gate.
  - Las llamadas a `StoragePort` están solo en `SessionStore+Recovery.swift` y `ActiveSessionFileAdapter.swift`.
  - `Domain/Ports/ClockPort.swift:3,7` nombra `Date()` en comentarios.
  - `UIKit` solo en `MotionBlockedView.swift:2`.
- Build: el gate corre como preBuildScript de `WalkTracker` y de `WalkTrackerActivity` (`project.yml`).

## Tasks & Acceptance

**Execution:**
- [x] `Scripts/check-project-shape.sh`: secciones 7–10 (CoreMotion, tiempo en el dominio, `StoragePort`, frameworks
      en la UI), con la cabecera del script actualizada.
- [x] `Scripts/check-project-shape-tests.sh`: un caso rojo por fila `exit 1` de la matriz y los usos legítimos en el
      fixture limpio.
- [x] `WalkTracker/UI/Permission/MotionBlockedView.swift`: quitar `import UIKit` y abrir Ajustes con `URL(string: "app-settings:")`, sin cambiar el comportamiento.

**Acceptance Criteria:**
- Given cada fila de la matriz, when corro `check-project-shape-tests.sh`, then se cumple; y quitar cualquier regla
  nueva pone rojo su caso.

## Implementation Notes

- **Solo código:** las secciones 8, 9 y el escaneo de símbolos de la 10 leen el código sin comentarios (`code_lines`:
  quita `// …` y `/* … */` anidados y multilínea). Dentro de `"…"` (con escapes) y `"""…"""` no hay marcadores de
  comentario; el contenido del literal se conserva y cuenta como código. No distingue cadenas crudas (`#"…"#`).
  Si el escaneo falla, el gate da rojo con "no se pudo escanear".
- **Imports:** las secciones 7 y 10 reconocen atributos con o sin argumentos (`@preconcurrency`, `@_spi(X)`), el
  nivel de acceso de Swift 6 (`internal import`), imports de símbolo y submódulos.
- **Tiempo:** además de `Date()`, `Date.now` y `Calendar.current`, la 8 marca `Date.init()`,
  `Date(timeIntervalSinceNow:)` y `Calendar.autoupdatingCurrent`.
- **`StoragePort`:** la sección 9 mira `WalkTracker/` y `Domain/`. Quita de la línea las declaraciones
  `func …ActiveSession` y busca llamadas en lo que queda. Se admite `Application/SessionStore*.swift`, sin
  subdirectorios.
- **UIKit sin import:** SwiftUI reexporta UIKit, así que la 10 también busca `UIApplication`, `UIDevice`, `UIScreen`,
  `UIViewController` y `UIView` en el código de `UI/`.
- **`MotionBlockedView.settingsURL`:** `"app-settings:"` escrito a mano; `MotionBlockedViewTests` lo compara con
  `UIApplication.openSettingsURLString`.
- **CoreMotion en `UI/`** lo marcan la 7 y la 10. Cada caso rojo busca el mensaje propio de su sección.
- **Verificación:** 57 casos del camino rojo en verde. Cada regla, las guardas (subdirectorios, `Domain/` en la 9,
  columna 0, cadenas, anidamiento, profundidad entre líneas, escaneo fallido) y la lista de frameworks se mutaron en
  una copia y pusieron rojo su caso.

## Spec Change Log

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | BH/EC · Los imports con nivel de acceso (`internal import UIKit`) y con atributo con argumentos (`@_spi(X) import`) no se detectan | medium | Verificado en un fixture: sale en verde. Proyecto en Swift 6 | patch |
| 2 | EC · Una llamada a `Date()` o a `StoragePort` en la columna 0 no se reporta | medium | Verificado: el patrón exige un carácter previo | patch |
| 3 | BH/EC · Un `"/*"` dentro de un string oculta el resto del fichero a las secciones 8 y 9, y el comentario del script lo subestima | medium | Verificado: un `Date()` posterior pasa | patch |
| 4 | BH/EC · Si `find`/`awk` fallan, el gate da verde sin haber comprobado nada | medium | Real: stderr a `/dev/null` y no se mira el estado de salida | patch |
| 5 | BH/EC · `Date.init()`, `Date(timeIntervalSinceNow:)` y `Calendar.autoupdatingCurrent` pasan | low | Verificado. Leen el reloj o el calendario del sistema (AD-3/AD-19); añadirlos es directo | patch |
| 6 | EC/VG · Una línea que declara y llama a un método del puerto se salta entera | low | Verificado (`extension StoragePort { func … { try clearActiveSession() } }`) | patch |
| 7 | BH/EC · Prohibir `import UIKit` no impide usar UIKit en una vista con solo `import SwiftUI` | medium | Verificado: `UIApplication` compila vía SwiftUI. Sin esto, la decisión de Paul (UIKit prohibido) sería simbólica | patch |
| 8 | BH/VG · El literal `"app-settings:"` no tiene test, y el comentario llama "documentado" a un valor que Apple no documenta | medium | Real: es la única salida de la pantalla bloqueante (AD-11) y una errata no rompería nada | patch |
| 9 | VG · Mutaciones que dejan los 36 casos en verde: `Domain/` en la sección 9, guarda de subdirectorios, `ui_banned` a medias, profundidad y anidamiento de comentarios | medium | Pre-verificado mutación a mutación | patch |
| 10 | EC/VG · La sección 4 no reconoce imports con atributo, y el nombre del módulo en el mensaje de la sección 10 no tiene test | medium | Verificado (`@preconcurrency import CoreMotion` en `Domain/` pasa). La sección 4 es preexistente y la spec prohíbe tocar las secciones 1–6 | defer |
| 11 | EC · Un import dentro de un comentario de bloque rompe el build | low | Falso positivo ruidoso y raro; alimentar las secciones 7 y 10 con `code_lines` cambia el enfoque | rechazado |
| 12 | EC · Los nombres de `StoragePort` dentro de un string rompen el build | low | Falso positivo ruidoso; el salto de strings del parche 3 lo reduce | rechazado |
| 13 | EC · `Date(` partido en varias líneas no se detecta | low | Forma rara; unir líneas complica el escaneo | rechazado |
| 14 | BH · La sección 9 lista los nombres a mano, no mira el tipo `StoragePort` y admite rutas amplias | low | La regla es por llamadas, como fija la spec; hoy no hay más métodos | rechazado |
| 15 | BH · `Shared/` queda sin la regla de CoreMotion | false | La spec excluye `Shared/` a propósito | rechazado |
| 16 | VG/BH · Los casos rojos solo se ejecutan a mano, sin CI | low | Preexistente y documentado en el README; el proyecto no tiene CI | rechazado |
| 17 | BH · Huecos de redacción en la spec y doble escaneo de `Domain/` | low | Editaría la spec; unos milisegundos por build | rechazado |

## Verification

**Commands:**
- `bash Scripts/check-project-shape-tests.sh`: esperado verde.
- `bash Scripts/check-project-shape.sh`: esperado `forma del proyecto correcta.`.
- `bash Scripts/verify-domain.sh` y `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO`:
  esperado verde.
