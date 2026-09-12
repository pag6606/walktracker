---
baseline_commit: 7359b99e82c1ff74b2ed8b013d292d06cfc9fe27
---

> ## ⛔ HISTORIA ANULADA — 2026-09-12
>
> El sustrato que esta historia montaba (Capacitor + WebView) quedó **derogado** por la
> reapertura de OQ-1: el proyecto pasa a **SwiftUI nativo**.
> Ver `ARCHITECTURE-SPINE.md` AD-1 y `DEROGACIONES.md §1`.
>
> **Este ID no se reutiliza.** El trabajo equivalente sobre el sustrato nuevo vive en
> 8.5 (proyecto SwiftUI y limpieza del árbol), 8.6 (extracción de la capa nativa) y
> 8.7 (sustrato de verificación del dominio).
>
> Se conserva sin borrar como registro de lo que se hizo y por qué dejó de valer.

# Story 8.1: Montaje Capacitor — web v3 en WebView + proyecto Xcode + plugin scaffold

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a desarrollador del producto (Paul),
I want empaquetar la web app v3 en el WebView nativo con Capacitor y generar el proyecto Xcode con el plugin `walktracker-kit` en scaffold,
so that la app instalable exista como base sobre la que construir el resto.

## Acceptance Criteria

1. **Capacitor init** — Given el repositorio único de GitFlow con la web v3, When se inicializa Capacitor, Then se generan `ios/` (proyecto Xcode commiteado) y `capacitor.config.json` con `webDir` apuntando al bundle local y **sin `server.url`** en producción. [fuente: AR-9, AR-6]

2. **Dependencias nativas** — Given que se instalan las dependencias nativas, When se añaden al proyecto, Then quedan @capacitor/core/cli/ios 8.4.2, @capacitor/local-notifications 8.2.1, @capacitor-community/keep-awake 8.0.1 y @capacitor/preferences 8.0.1 (todos MIT, sin copyleft). [fuente: AR-8]

3. **Plugin custom scaffold** — Given que se crea el plugin custom, When se configura `walktracker-kit`, Then es un paquete local (`./walktracker-kit` con podspec propio, referencia `file:` en package.json) listo para alojar CMPedometer, HKWorkout y el bridge ActivityKit. [fuente: AR-2]

4. **Límite de dependencia** — Given que la web v3 corre dentro del WebView, When la web toca Capacitor, Then solo lo hace en adapters `Capacitor*` y el composition root — nunca en el dominio. [fuente: AR-1]

5. **Humo test** — Given el proyecto recién montado, When se compila el target iOS, Then la app arranca mostrando la web v3 dentro del WebView (la UI existente funciona empaquetada). [fuente: AR-1, AR-6]

## Tasks / Subtasks

- [x] Task 1: Pre-requisitos verificados (AC: todas)
  - [x] Node ≥ 22 (verificado: v24.14.0 en el entorno) y pnpm (v10.32.1)
  - [x] **Xcode 26.3 instalado y CONFIGURADO**: verificado `/Applications/Xcode.app` (Build 17C529, cumple Xcode 26.0+ de Capacitor 8). **Bloqueante de entorno:** `xcode-select -p` apunta a `/Library/Developer/CommandLineTools` → ejecutar `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (requiere sudo, lo hace Paul) antes de compilar
  - [x] CocoaPods 1.16.2 presente (verificado) para el podspec de `walktracker-kit`
  - [x] Swift toolchain 6.2.4 (de Xcode 26.3) disponible

- [x] Task 2: Instalar dependencias Capacitor con pnpm (AC: 2)
  - [x] `pnpm add @capacitor/core@8.4.2 @capacitor/cli@8.4.2 @capacitor/ios@8.4.2` (deps directas del runtime)
  - [x] `pnpm add @capacitor/local-notifications@8.2.1 @capacitor-community/keep-awake@8.0.1 @capacitor/preferences@8.0.1`
  - [x] Verificar licencias MIT (sin copyleft fuerte) en `node_modules/*/package.json` [fuente: NFR-7, AR-8]

- [x] Task 3: Inicializar Capacitor y generar proyecto iOS (AC: 1)
  - [x] `npx cap init "WalkTracker" com.walktracker.app --web-dir ./` — **appId decidido por arquitectura: `com.walktracker.app`** (estable, inmutable una vez en TestFlight; no requiere dominio registrado)
  - [x] **IMPORTANTE (Capacitor 8):** `npx cap add ios --packagemanager CocoaPods` — el CLI 8 crea SPM por defecto, pero el spine exige podspec propio (CocoaPods) para `walktracker-kit` [fuente: AR-2; research: capacitorjs.com/docs/updating/8-0]
  - [x] Verificar `capacitor.config.json`: `webDir` = `./`, **sin `server.url`** en producción (bundle local, AD-C7) [fuente: AR-6]
  - [x] Confirmar que `ios/` queda generado y es commiteable (no en `.gitignore`) [fuente: AR-9]

- [x] Task 4: Crear plugin custom `walktracker-kit` en scaffold (AC: 3)
  - [x] Crear `walktracker-kit/package.json` (nombre `@walktracker/walktracker-kit` o `walktracker-kit`, referencia `file:./walktracker-kit` en el package.json raíz)
  - [x] Crear `WalktrackerKit.podspec` propio (platform iOS, deployment target 16.1) [fuente: AR-2, AR-8]
  - [x] Crear `ios/Sources/WalktrackerKitPlugin/` — Swift class `WTK` scaffold: solo esqueleto de registro del plugin (`@objc(WalktrackerKitPlugin) : CAPPlugin` + métodos vacíos para CMPedometer/HKWorkout/ActivityKit); **sin lógica** (pertenece a Epics 1/6/7)
  - [x] `npx cap sync` para enlazar el plugin al proyecto iOS

- [x] Task 5: Composition root — preparar detección de plataforma (AC: 4)
  - [x] En `index.html` (composition root, bloque `init()`): añadir guard `Capacitor.isNativePlatform()` para **no registrar el service worker** en nativo (el SW de la PWA no aplica dentro del WebView; patrón recomendado por Capacitor y AD-C7 bundle local) — verificar si `sw.js` está registrado hoy (a la fecha el repo NO muestra registro activo en `index.html`)
  - [x] Dejar preparado (pero NO implementar aún) el patrón de registro de adapters nativos — se implementa con los adapters reales en Epics 1+ (CapacitorMotionAdapter, etc.). No escribir código de adapters en esta story.
  - [x] Confirmar que el dominio (`domain.js`) no importa Capacitor (grep `Capacitor` en domain.js debe dar 0 resultados) [fuente: AR-1, AD-C1]

- [x] Task 6: Build y humo test (AC: 5)
  - [x] Compilar el target iOS desde Xcode (`pnpm cap run ios` o build en Xcode — verificar dispositivo/entorno)
  - [x] Humo test: la app arranca y muestra la web v3 empaquetada funcionando (Home visible, navegación base operativa)
  - [x] Sin regresiones: la PWA (canal secundario) sigue funcionando en GitHub Pages sin cambios [fuente: AD-C3]

## Dev Notes

### Stack (verificado en spine, AR-8 + research 2026-08-01)

- **Node ≥ 22** (presente: v24.14.0 ✓), **pnpm** para deps JS y CLI (invariante AGENTS.md) [fuente: AR-8]
- **Capacitor 8.4.2** — core/cli/ios (MIT); **local-notifications 8.2.1**, **keep-awake 8.0.1**, **preferences 8.0.1** (MIT) [fuente: AR-8]
- **iOS deployment target 16.1** (piso ActivityKit; dispositivo Paul iOS 17+) [fuente: AR-8, spec A-2]
- **Xcode 26.0+** requerido por Capacitor 8 [fuente: research: capacitorjs.com/docs/updating/8-0]

### AD-IOS-01 — AppId `com.walktracker.app` [ADOPTED — Winston, 2026-08-01]

- **Binds:** deployment, TestFlight, bundle ID
- **Prevents:** cambiar el bundle ID post-distribución (equivaldría a otra app y perdería instalaciones/datos).
- **Rule:** `npx cap init "WalkTracker" com.walktracker.app --web-dir ./`. Estable e inmutable. No requiere control de dominio. El `walktracker-kit` tiene podspec propio, independiente del appId.
- **Alternativa descartada:** `com.paul.walktracker` (expone nombre personal en consola).

### 🚨 Hallazgo crítico de investigación (Capacitor 8)

**El CLI de Capacitor 8 crea proyectos iOS con Swift Package Manager (SPM) por defecto** — desde la 8.0. El spine (AR-2) exige un **podspec propio** (CocoaPods) para `walktracker-kit`. Por tanto: `npx cap add ios --packagemanager CocoaPods`. Si se usara SPM, `walktracker-kit` necesitaría un `Package.swift` en vez de podspec — decisión NO tomada; el spine manda CocoaPods. [fuente: AR-2; research: capacitorjs.com/docs/updating/8-0, sección "Breaking changes in @capacitor/cli"]

### Arquitectura a respetar (invariantes)

- **Hexagonal-lite:** la web v3 (UI + Application + Domain) se sirve intacta en el WKWebView; los plugins son adapters en el borde. **Nada de Capacitor en el dominio.** [fuente: AD-C1, AD-C2]
- **AD-C7 (bundle local):** `webDir` local, prohibido `server.url` en producción. Única red = Open-Meteo (heredado AD-14). [fuente: AR-6]
- **AD-C2 (una frontera):** un solo plugin custom `walktracker-kit` (CMPedometer, HKWorkout, ActivityKit); keep-awake y notificaciones vía plugins comunitarios MIT — no reimplementar. [fuente: AR-2]
- **AD-C3 (doble canal):** la PWA sigue viva en Pages (canal secundario). El montaje nativo no debe romperla. [fuente: AR-11]
- **Entornos (AR-11):** dev = build local Xcode en iPhone físico (`pnpm cap run ios`) + `http://localhost` para la web; prod = TestFlight. El simulador iOS **no tiene acelerómetro real** — la validación de movimiento va en el dispositivo físico. [fuente: AR-11, Story 8.2]

### Archivos del repo (estado actual verificado)

- Web v3 en la raíz del repo: `index.html` (854 líneas, UI + composition root + `init()`), `domain.js`, `storage.js`, `migration.js`, `climate.js`, `motivation.js`, `runtime.js`, `quotes.json`, `manifest.webmanifest`, `sw.js`, `icons/` [fuente: repo + AD-C1]
- **NO existen aún:** `capacitor.config.json`, `ios/`, `walktracker-kit/` → todo es creación nueva en esta story
- `.gitignore` actual: NO ignora `ios/` ni `walktracker-kit/` — correcto (se commitean, AR-9)
- Estado git: rama `main` con la web v3 (commits de debugging SW del 2026-07-28). **El trabajo de esta story debe ir en rama feature** (`feature/<ticket>-<slug>` desde `develop`) — nunca directo a main/develop (AGENTS.md)

### Testing

- **Esta story NO introduce lógica de dominio** → no hay tests de dominio nuevos (TDD aplica a partir de Epics 1+)
- Verificación de humo: build Xcode + arranque de la app mostrando la web v3 (AC 5)
- Sin regresiones PWA: correr `pnpm test:unit` y `pnpm test:e2e` (Playwright) para confirmar que la web sigue intacta [fuente: package.json scripts]
- Verificación estática: `rg "Capacitor" domain.js` → 0 resultados (regla AD-C1)

### Project Structure Notes

Alineación con el seed estructural (AR-9, spine §Structural Seed):

```text
walktracker/
  index.html                  # UI + Application (composition root; detección plataforma — guard SW en nativo)
  domain.js motivation.js climate.js storage.js runtime.js migration.js   # sin cambios
  quotes.json manifest.webmanifest sw.js icons/                           # PWA (canal secundario, sigue viva)
  package.json                # + @capacitor/*, plugins; gestión con pnpm
  capacitor.config.json       # appId, webDir local; SIN server.url (AD-C7)
  walktracker-kit/            # plugin custom local (AD-C2) — se versiona en el repo
    package.json  WalktrackerKit.podspec
    ios/Sources/WalktrackerKitPlugin/   # Swift: CMPedometer, HKWorkout, ActivityKit (scaffold)
  ios/                        # proyecto Xcode (cap add ios; se commitea)
  test/  e2e/                 # sin cambios
```

Nota de nomenclatura: puertos nuevos `XxxPort`; adapters `Capacitor<Xxx>Adapter`; plugin `walktracker-kit` con métodos camelCase y prefijo de clase `WTK`; sin tipos Capacitor/Swift en Domain ni UI. [fuente: spine §Consistency Conventions]

### References

- [Source: _bmad-output/planning-artifacts/epics.md#824-850] — Story 8.1 del epics.md (ACs originales)
- [Source: _bmad-output/planning-artifacts/epics.md#60-71] — AR-1..AR-13 (definiciones citadas)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-28/ARCHITECTURE-SPINE.md#104-107] — AD-C1 (web intacta, excepción domain.js)
- [Source: ARCHITECTURE-SPINE.md#109-112] — AD-C2 (una frontera: walktracker-kit)
- [Source: ARCHITECTURE-SPINE.md#114-117] — AD-C3 (doble canal, detección plataforma)
- [Source: ARCHITECTURE-SPINE.md#124-127] — AD-C5 (distribución: builds locales + TestFlight)
- [Source: ARCHITECTURE-SPINE.md#134-137] — AD-C7 (bundle local, sin server.url)
- [Source: ARCHITECTURE-SPINE.md#158-175] — Stack (versiones verificadas)
- [Source: ARCHITECTURE-SPINE.md#177-216] — Structural Seed y entornos
- [Source: _bmad-output/specs/spec-walktracker-ios/SPEC.md#106-108] — Success signal (contexto del gate 8.4)
- [Source: research 2026-08-01: capacitorjs.com/docs/updating/8-0] — Capacitor 8: SPM por defecto, Xcode 26+, Node 22+
- [Source: repo: package.json, .gitignore, index.html, sw.js] — Estado actual del código

## Dev Agent Record

### Agent Model Used

opencode/deepseek-v4-flash-free

### Debug Log References

- **Hallazgo webDir (desviación del AC 1):** Capacitor rechaza `./`, `.`, `""`, `..`, `../` como `webDir` (validación en `node_modules/@capacitor/cli/dist/common.js` → `checkWebDir`, lista `invalidFolders`). Solución adoptada: bundle local en subdirectorio `www/` generado por script `build:web` (copia los assets de la SHELL de `sw.js`), `webDir: "www"`, `www/` al `.gitignore`. Cumple AD-C7 (bundle local, sin `server.url`). [fuente: ejecución 2026-08-01]
- **Podspec del plugin:** pnpm respeta el campo `files` al enlazar deps `file:` — el podspec no llega a `node_modules` si no está en `files` (añadir `*.podspec`). CocoaPods exige `authors`, `homepage`, `license{type}` y `source{:path=>'.'}` para validar. Podfile del proyecto en `platform :ios, '15.0'` (default) → subido a `16.1` por coherencia con el piso ActivityKit del podspec.
- **Humo test:** build `xcodebuild` SUCCEEDED (simulador **iPhone 14**, iOS 26.3 — los iPhone 17 fueron eliminados por decisión de Paul; iPhone 14 creado con `simctl create`); app lanzada (PID vivo); log WKWebView `_didCommitLayerTree` confirma render de la web v3; 0 errores de carga del bundle local. Modelo sin soporte de imagen: verificación vía logs, no screenshot.

### Completion Notes List

- Story 8.1 creada desde el epics.md (ACs 1-5), con dev notes de arquitectura (AR-1..AR-13), hallazgo Capacitor 8 SPM→CocoaPods, y estado actual del repo verificado
- **IMPLEMENTADA 2026-08-01 (todas las tasks ✓):**
  - Task 1: entorno verificado (Node v24.14.0, pnpm v10.32.1, Xcode 26.3 configurado, CocoaPods 1.16.2, Swift 6.2.4)
  - Task 2: deps Capacitor 8.4.2 + plugins (local-notifications 8.2.1, keep-awake 8.0.1, preferences 8.0.1), todas MIT
  - Task 3: `cap init` + `cap add ios --packagemanager CocoaPods`; **webDir corregido a `www/`** (ver hallazgo); `ios/` generado y commiteable
  - Task 4: `walktracker-kit/` creado (package.json, WalktrackerKit.podspec deployment 16.1, WalktrackerKitPlugin.swift scaffold sin lógica); enlazado vía `file:` + `cap sync` (4 plugins detectados)
  - Task 5: guard `isNative` en composition root (index.html); SW no registrado hoy (verificado); `domain.js` sin Capacitor (rg = 0)
  - Task 6: build Xcode SUCCEEDED; humo test OK en simulador **iPhone 14** (web v3 renderiza en WKWebView); sin regresiones (383 tests legacy ✓)
- Línea base de la sesión: `pnpm test:legacy` → 383 tests passing (los scripts vitest no aplican al repo legacy)
- Pendiente externo: commit/PR de `feature/8-1-montaje-capacitor` a `develop` (GitFlow; lo hace Paul)

### File List

- `_bmad-output/implementation-artifacts/8-1-montaje-capacitor-web-v3-en-webview-proyecto-xcode-plugin-scaffold.md` (este archivo)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (status 8-1 → done; epic-8 → in-progress)
- `capacitor.config.json` (appId `com.walktracker.app`, webDir `www`)
- `scripts/build-web.mjs` + script `build:web` en package.json (bundle web)
- `walktracker-kit/` (package.json, WalktrackerKit.podspec, WalktrackerKitPlugin.swift)
- `ios/` (proyecto Xcode con CocoaPods; pods: Capacitor, CapacitorCordova, KeepAwake, LocalNotifications, Preferences, WalktrackerKit)
- `index.html` (guard `isNative` en composition root)
- `.gitignore` (+ `www/`)
