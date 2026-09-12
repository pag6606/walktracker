---
title: '8.5 — Proyecto SwiftUI y limpieza del árbol'
type: 'chore'
created: '2026-09-12'
status: 'done'
route: 'dispatch'
review_loop_iteration: 1
baseline_commit: 'b7c5307bfbb4d5732aec832d0d0ca428b1a38111'
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-09-12/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** el repositorio contiene el sustrato Capacitor —`ios/App/`, `www/`, `adapters/`,
`capacitor.config.json`— que el pivot a SwiftUI derogó, y no contiene ningún proyecto Xcode sobre
el que construir. Ninguna historia posterior de ningún epic puede empezar hasta que exista un árbol
de producto único y compilable.

**Enfoque:** generar el proyecto con **XcodeGen** desde un `project.yml` versionado —tres targets:
app, `Shared` y la Widget Extension—, sembrar el árbol de carpetas del spine con la frontera del
dominio ya exigible por el compilador, y retirar del árbol el sustrato derogado en el mismo cambio,
para que no exista un estado intermedio con dos proyectos Xcode compitiendo por `ios/`.

## Boundaries & Constraints

**Always:**
- Deployment target **iOS 26.0**; toolchain Xcode 26.3 / Swift 6.2.4 / SDK iOS 26.2 (AD-2).
- Bundle id `com.walktracker.app`, inmutable (AD-1).
- **Swift 6 con concurrencia estricta completa** en los tres targets; el build no emite warnings de
  aislamiento (AD-12).
- `Domain/` solo puede importar `Foundation`. La prohibición es **de compilador, no de revisión**:
  un `import SwiftUI` o `import CoreMotion` ahí tiene que romper el build (AD-3).
- `WalkTrackerActivity` importa **solo `Shared`**; nunca `Domain` (AD-15).
- Las dependencias apuntan hacia dentro: UI → Application → Domain; Adapters → Domain (AD-3).
- `domain.js`, `motivation.js`, `climate.js`, `storage.js` y `test/` **se conservan intactos** como
  referencia de contraste de AD-6.
  - **Excepción renegociada por Paul el 2026-09-12:** `test/adapters/` se elimina. Probaba los
    adapters de Capacitor que esta historia borra —"el anterior usaba otra tecnología"—, no es
    referencia de AD-6 de nada, y `vitest.config.js` lo recogía con `test/**/*.js`, así que dejarlo
    significaba una suite rota. Se va con el código que probaba y es recuperable del historial.

**Never:**
- Ningún `if #available` hacia versiones anteriores a 26.0 (AD-2).
- Ninguna dependencia de terceros en el producto. XcodeGen es herramienta de build, no dependencia
  de la app: no entra en ningún target.
- No se escribe lógica de dominio, de UI ni de adapters en esta historia. Solo el andamiaje mínimo
  que hace compilable cada target y verificable cada frontera.
- No se toca la rama `feature/flutter-substrate`; la extracción de su capa nativa es la historia 8.6.
- **`WalkTracker.xcodeproj` no se versiona.** Decidido por Paul el 2026-09-12: la fuente de verdad
  es `project.yml`; el proyecto se regenera con `xcodegen generate` y va al `.gitignore`. Nadie
  cambia un ajuste de build sin que aparezca en el diff, y no hay `.pbxproj` que resolver en un merge.
  Coste aceptado: añadir un fichero desde fuera de Xcode exige regenerar antes de abrirlo.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado |
|---|---|---|
| Generación limpia | `project.yml` + árbol de fuentes | `xcodegen generate` produce `WalkTracker.xcodeproj` con los tres targets |
| Frontera del dominio | un fichero de `Domain/` añade `import SwiftUI` | **el build falla**, nombrando fichero y regla |
| Frontera de la extensión | `WalkTrackerActivity` añade `import Domain` | **el build falla** |
| Aislamiento | un tipo no `Sendable` cruza una frontera de actor | **el build falla** (concurrencia estricta) |
| Build de simulador | `xcodebuild` contra iPhone 16e, sin firma | los tres targets compilan sin warnings |

</frozen-after-approval>

## Code Map

- **Se elimina:** `ios/App/`, `ios/capacitor-cordova-ios-plugins/`, `www/`, `adapters/`,
  `capacitor.config.json`. `walktracker-kit/` ya no está: se fue en `d9d3fbc` a `feature/flutter-substrate`.
- **No se toca el dominio de referencia:** `domain.js` (626 líneas), `motivation.js`, `climate.js`,
  `storage.js` y las suites de `test/*.js` que corren con node — es lo que AD-6 verificará en la 8.7.
- **Sí se tocan, porque la limpieza no puede quedarse en el sistema de ficheros:**
  - `package.json` — declara `@capacitor/*` y `"walktracker-kit": "file:./walktracker-kit"`, cuyo
    directorio **ya no existe**: un clon nuevo no puede `pnpm install`.
  - `index.html` líneas 264/266/267 — tres `<script src="./adapters/…">` que quedarían en 404.
  - `scripts/build-web.mjs` — copia `walktracker-kit/dist/plugin.js` (línea 30) y `adapters/`
    (línea 20), ambos inexistentes; genera en `www/`.
- `ARCHITECTURE-SPINE.md` §Structural Seed — el árbol exacto a sembrar.
- **Herramienta verificada:** XcodeGen 2.46.0, probada generando app + framework + app-extension
  con `embed: true` y listada por `xcodebuild -list`.

## Tasks & Acceptance

**Execution:**
- [x] `project.yml` — manifiesto de XcodeGen con **cuatro** targets de producto: `Domain` (framework),
      `Shared` (framework), `WalkTracker` (app) y `WalkTrackerActivity` (app-extension embebida),
      más el target de test `WalkTrackerTests` (tarea propia, abajo).
      Deployment 26.0, `SWIFT_VERSION=6.0`, `SWIFT_STRICT_CONCURRENCY=complete` en los cuatro.
      `ENABLE_USER_SCRIPT_SANDBOXING: NO` **solo** en los targets que ejecutan build phases.
- [x] `Domain/` — **su propio módulo**, fuera del árbol de la app. Contiene `Ports/`, `Engines/`,
      `DomainError.swift`. Es lo que hace estructural la dirección de dependencias: desde `Domain`
      no se puede nombrar un tipo de `UI` ni de `Adapters` **aunque no haya ningún import**, porque
      esos símbolos no existen en su módulo.
- [x] `WalkTracker/` — `App/` (entrada SwiftUI + composition root **cableado a la vista raíz**),
      `Application/`, `Adapters/`, `UI/`, `Resources/`. Depende de `Domain` y de `Shared`.
- [x] `Shared/ActivitySnapshot.swift` — `Sendable`, solo `Foundation`. Lleva `timerStart` **ya
      ajustado por las pausas** (no `startedAt` crudo) y `frozenElapsed` para el estado en pausa,
      de forma que reanudar no cuente el tiempo pausado. `pace` opcional, con un consumidor real.
- [x] `WalkTrackerActivity/` — Widget Extension que solo renderiza; depende de `Shared`, **no de
      `Domain`** (el grafo de targets lo impide, ya no hace falta un script para eso).
- [x] `WalkTrackerTests/` — target de test con Swift Testing, vacío salvo un caso de humo. La 8.7
      necesita un sitio donde poner los vectores de AD-6; sin él no lo tiene.
- [x] `WalkTracker/App/Info.plist` + entitlements — `NSMotionUsageDescription`,
      `NSHealthUpdateUsageDescription`, `NSLocationWhenInUseUsageDescription`,
      `NSSupportsLiveActivities`, entitlement de HealthKit.
- [x] `WalkTracker/Resources/Assets.xcassets/AppIcon.appiconset` — icono 1024×1024 real. Sin él, el
      archivado de la historia 8.3 falla aunque el simulador lo tolere.
- [x] `Scripts/check-project-shape.sh` — comprueba lo que el grafo de módulos **no** puede:
      que las `sources:` de `WalkTrackerActivity` no alcancen `Domain/`, y que todo `.swift` del
      árbol esté en algún target (un fichero añadido sin regenerar se compila en silencio: no).
      Falla ruidosamente si `Domain/` no existe. Sin parseo de imports: eso lo hace el compilador.
- [x] Eliminar el sustrato derogado (AD-23) — `ios/App/`, `ios/capacitor-cordova-ios-plugins/`,
      `www/`, `adapters/`, `capacitor.config.json`, `test/adapters/` — **y sus consumidores**:
      las seis dependencias `@capacitor/*` y `walktracker-kit` de `package.json`, las tres etiquetas
      `<script src="./adapters/…">` de `index.html`, y `scripts/build-web.mjs` con su entrada
      `build:web` (genera un bundle para un WebView que ya no existe).
- [x] `.gitignore` — retirar reglas de Capacitor huérfanas; añadir `WalkTracker.xcodeproj/`.
- [x] `README.md` — cómo se genera el proyecto, qué hace falta instalado, y el comando exacto de
      las suites de referencia de AD-6.

**Acceptance Criteria:**
- Dado el repositorio recién clonado, cuando se ejecuta `xcodegen generate`, entonces aparece
  `WalkTracker.xcodeproj` y `xcodebuild -list` muestra exactamente cinco targets: los cuatro de
  producto y `WalkTrackerTests`.
- Dado el proyecto generado, cuando se compila para simulador sin firma, entonces los cinco targets
  compilan **sin warnings de aislamiento**.
- Dado un fichero de `Domain/`, cuando referencia un tipo de `UI/` o de `Adapters/` **sin ningún
  import**, entonces el build falla: el símbolo no existe en su módulo. Es la prueba de que la
  dirección de dependencias es estructural y no una regla de revisión.
- Dado el árbol resultante, cuando se busca `ios/App`, `www/`, `adapters/`, `capacitor.config.json`
  o cualquier dependencia `@capacitor/*` en `package.json`, entonces no existe ninguna; y
  `domain.js`, `motivation.js`, `climate.js`, `storage.js` y las suites de `test/` que corren con
  node siguen intactas y pasando.
- Dado un repositorio recién clonado, cuando se ejecuta `pnpm install`, entonces termina sin error.
- Dado `index.html`, cuando se abre en un navegador, entonces no hay ningún 404 de script.

## Implementation Notes

**Verificado contra el diff, no contra el informe de implementación.** 43 ficheros, +610 −1030.

Dos defectos que el informe no mencionaba y que la revisión del diff destapó:

1. **El gate de AD-15 no se alcanzaba nunca en un build real.** El script estaba solo como
   `preBuildScript` del target de la app. Como la extensión es dependencia de la app, compila
   *antes*, y el compilador fallaba primero con `Unable to find module dependency: 'Domain'` —
   que no explica nada. El script detectaba la violación correctamente al ejecutarlo a mano; lo
   que fallaba era dónde estaba enganchado. Añadido también al target `WalkTrackerActivity`.
   Ahora el build falla con el mensaje de AD-15, nombrando fichero y línea.
2. **El renombrado `scripts/` → `Scripts/` dejó `package.json` apuntando a la ruta vieja.**
   macOS lo tolera por ser insensible a mayúsculas; un sistema de ficheros sensible habría roto
   `pnpm build:web`. Corregido.

**Sobre la auditoría de la matriz.** La fila de aislamiento costó tres intentos y merece quedar
escrito, porque las dos sondas fallidas parecían éxitos:
- La primera sonda era un fichero `.swift` **nuevo**. XcodeGen fija la lista de ficheros, así que
  nunca entró al target: el build pasó en verde sin compilar nada. **Consecuencia operativa real
  del modelo elegido: añadir un fichero sin regenerar no rompe el build, lo ignora en silencio.**
- La segunda transfería un valor no `Sendable` a `MainActor` **sin volver a usarlo después**. El
  aislamiento por regiones lo permite y hace bien: no hay carrera. La sonda estaba mal, no el ajuste.
- La tercera, con uso posterior, da `error: sending 'box' risks causing data races` y falla el build.
  Confirmado además por `-showBuildSettings`: `SWIFT_STRICT_CONCURRENCY = complete`,
  `SWIFT_VERSION = 6.0`, `IPHONEOS_DEPLOYMENT_TARGET = 26.0` en los tres targets.

**Decisión de implementación heredada del informe y conservada:** la build phase corre con
`basedOnDependencyAnalysis: false`. Declarar un fichero de salida la hacía cacheable y **desactivaba
el gate en silencio**. El precio es una `note:` de Xcode en cada build. Un gate fiable vale más que
un log limpio.

**Cabo suelto, resuelto por el humano.** `test/adapters/` probaba los adapters de Capacitor que
esta historia borra; se eliminó tras renegociar la restricción congelada con Paul. No era referencia
de AD-6 y `vitest.config.js` lo recogía, así que dejarlo era dejar la suite rota.

- **La frontera del dominio corre en cada build, y eso cuesta una `note:`.** El primer intento
  declaró un output falso en la build phase para silenciar el aviso de Xcode; el resultado fue que
  la fase se volvió cacheable y **el gate dejó de dispararse** (verificado: un `import SwiftUI` en
  `Domain/` pasó el build). La fase quedó con `basedOnDependencyAnalysis: false`, que la ejecuta
  siempre y deja una `note:` en el log. No es un warning y no es de aislamiento.
- **`Shared/` se partió en dos ficheros.** `ActivitySnapshot.swift` es el `ContentState`, solo
  `Foundation`, tal como pide la tarea. La conformidad a `ActivityAttributes` exige `import
  ActivityKit`, así que vive aparte en `WalkTrackerActivityAttributes.swift`: el contrato de datos
  no arrastra el framework.
- **`scripts/` pasó a `Scripts/`.** El repositorio ya tenía un `scripts/` en minúscula y macOS no
  distingue mayúsculas: el fichero nuevo habría quedado registrado en git como
  `scripts/check-domain-boundary.sh`, que no es la ruta del spine. Se renombró el directorio con
  `git mv`. `build-web.mjs` no sobrevive a la mudanza: se elimina junto con su entrada `build:web`
  de `package.json`, como pide la tarea de AD-23, así que no queda ninguna ruta vieja apuntando a
  `scripts/`. Git registra solo `Scripts/`.
- **`ios/` sobrevive vacío de contenido versionado.** Solo quedan restos de Flutter ya ignorados;
  sus reglas de `.gitignore` se conservan a propósito, porque la historia 8.6 hace
  `git checkout feature/flutter-substrate -- ios/Runner/AppDelegate.swift` sobre ese árbol.
- **Coste operativo de no versionar el proyecto:** añadir o borrar un fichero fuera de Xcode exige
  `xcodegen generate` antes de compilar. Se comprobó de la peor manera durante la verificación: un
  fichero nuevo sin regenerar simplemente no se compila, en silencio.

## Verification

**Commands:**
- `xcodegen generate` — esperado: proyecto creado, sin errores.
- `xcodebuild -project WalkTracker.xcodeproj -list` — esperado: `Domain`, `Shared`, `WalkTracker`,
  `WalkTrackerActivity`, `WalkTrackerTests`.
- Build de simulador (iPhone 16e, `CODE_SIGNING_ALLOWED=NO`) — esperado: `BUILD SUCCEEDED`, cero
  warnings de concurrencia.
- **Camino rojo, ejecutable y obligatorio:** `bash Scripts/check-project-shape-tests.sh` — monta un
  árbol temporal y afirma que el script falla cuando las `sources:` de la extensión alcanzan
  `Domain/`, cuando un `.swift` no está en ningún target, y cuando `Domain/` no existe; y que pasa
  sobre un árbol limpio. Un gate sin prueba de su camino rojo no es un gate.
- `pnpm install` sobre un clon limpio — esperado: termina sin error.
- `for t in domain session-v3 motivation gapestimator storage climate runtime migration stepdetector; do node test/$t-tests.js; done` — esperado: 438 aserciones en verde.

**Manual checks:**
- Añadir `func p() -> String { String(describing: RootView.self) }` a un fichero de `Domain/` y
  compilar: **debe fallar** por símbolo desconocido, sin necesidad de ningún import.
