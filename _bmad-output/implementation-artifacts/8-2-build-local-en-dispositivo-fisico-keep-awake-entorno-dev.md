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

# Story 8.2: Build local en dispositivo físico + keep-awake (entorno dev)

Status: in-progress

## Story

As a desarrollador del producto (Paul),
I want correr la app en mi iPhone físico con un comando y que el keep-awake use el plugin nativo en la app,
so that pueda iterar rápido con acelerómetro real y validar el comportamiento foreground del wake lock en hardware.

## Acceptance Criteria

1. **Build dev en iPhone físico** — Given el proyecto Capacitor de la story 8.1, When ejecuto `pnpm cap run ios --target=<mi-iphone>`, Then la app se compila y despliega en mi iPhone físico (sin simulator) y arranca mostrando la web v3. [fuente: AD-C5, AR-8, AR-11]
2. **Keep-awake nativo en foreground** — Given que la app corre en el iPhone físico, When hay una sesión activa y la app está en foreground, Then `CapacitorKeepAwakeAdapter.acquire()` mantiene la pantalla encendida vía `@capacitor-community/keep-awake` 8.0.1. [fuente: AR-8, AR-10]
3. **Liberación en background** — Given que hay sesión activa, When la app pasa a background, Then `CapacitorKeepAwakeAdapter.release()` se invoca (no consume batería de más en background). [fuente: AR-10]
4. **Validación en device físico** — Given que el simulador de iOS no tiene acelerómetro real, When valido el conteo de pasos, Then la verificación se hace en el iPhone físico, no en el simulador. [fuente: AR-11]
5. **Doble configuración dev/prod** — Given los dos canales (app nativa, PWA), When configuro el entorno, Then dev usa `http://localhost` para iterar la web dentro del WebView (Xcode + iPhone físico) y prod (TestFlight + GitHub Pages PWA) usa bundle local — ambos documentados en README/dev-notes. [fuente: AR-11, AR-6, AD-C7]

## Tasks / Subtasks

- [ ] Task 1: Preparación del entorno y device físico (AC: 1)
  - [ ] Verificar que el iPhone físico está conectado y confiado por macOS (Aparecerá en `xcrun devicectl list devices` o Xcode → Window → Devices)
  - [ ] Identificar el UDID del iPhone físico (`xcrun xctrace list devices` o desde Xcode)
  - [ ] Verificar que el bundle ID `com.walktracker.app` está firmado con el Apple Development Team de Paul (Xcode → Signing & Capabilities, automatic signing)
  - [ ] **No usar simulador** para esta story — el simulador iOS no tiene acelerómetro real (AR-11). La validación de pasos va al iPhone físico (gate 8.4).
  - [ ] Si el iPhone no está conectado, **bloqueante**: pedir a Paul que lo conecte vía USB y lo desbloquee con Face ID/passcode

- [x] Task 2: Adapter nativo `CapacitorKeepAwakeAdapter` (AC: 2, 3)
  - [x] Crear `adapters/capacitor-keep-awake-adapter.js` con interfaz `{ acquire(), release(), isAvailable() }`
  - [x] El adapter usa `@capacitor-community/keep-awake` (8.0.1, MIT, ya instalado en story 8.1) y llama a `KeepAwake.keepAwake()` / `KeepAwake.allowSleep()` — **solo en nativo** (guard `isNative` del composition root, story 8.1)
  - [x] El adapter delega al `WakeLockPort` heredado de v3 cuando NO es nativo (PWA, canal secundario, AR-12) — `WakeLockPort` ya está en `runtime.js` y `index.html` lo inyecta como `wlPort`
  - [x] Sin lógica de dominio nueva (AR-12, AD-1): el contrato es `acquire()` / `release()`; cero dependencias de Capacitor en `domain.js` o `runtime.js` [fuente: AR-1, AD-C1]
  - [x] Tests del adapter: `test/adapters/capacitor-keep-awake-adapter-tests.js` con jsdom, mockeando el plugin

- [x] Task 3: Composition root — inyección según plataforma (AC: 2, 3)
  - [x] En `index.html`, junto al guard `isNative` (creado en story 8.1), seleccionar el adapter:
    - `isNative` → `CapacitorKeepAwakeAdapter` (nuevo, envuelve el plugin)
    - `!isNative` → `WakeLockPort` existente (Web Wake Lock API via `navigator.wakeLock`)
  - [x] Verificar que las llamadas `wlPort.acquire()` / `wlPort.release()` existentes (en `init()`, recovery, fin de sesión) **siguen funcionando** con el adapter inyectado (mismo contrato, sin cambios en call sites)
  - [x] Acotar a foreground: el `BackgroundHandler` (en `runtime.js`) ya dispara `onBackground`/`onForeground` por `visibilitychange`; verificar que el adapter libera en `onBackground` (sin consumo extra de batería) y re-adquiere en `onForeground` (recuperación silenciosa AD-8) — comportamiento ya implementado en el código, **no romperlo**

- [ ] Task 4: Build local y deploy al iPhone físico (AC: 1, 4)
  - [ ] `pnpm build:web` (regenera el bundle `www/`)
  - [ ] `npx cap sync ios` (copia bundle + pod install)
  - [ ] Compilar y desplegar al iPhone físico: `npx cap run ios --target=<udid>` (Capacitor 8 invoca `xcodebuild` con destino el device físico; el `xcworkspace` ya está en `ios/App/`)
  - [ ] Verificar que la app arranca en el device físico mostrando la web v3 (Humo test objetivo = distinto del humo de la 8.1 que fue en simulador)
  - [ ] Probar manualmente: iniciar una sesión → la pantalla no debe apagarse en foreground; enviar la app a background → la pantalla debe poder apagarse; volver a foreground → wake lock re-adquirido
  - [ ] Si la firma falla: Xcode → seleccionar el target `App` → Signing & Capabilities → Team = Paul; dejar que Xcode gestione el provisioning profile (automatic signing). **No commitear** `ios/App/App.xcodeproj/project.pbxproj` con datos específicos de Paul (puede tener ya referencias; revisar)

- [x] Task 5: Documentar el doble canal dev/prod (AC: 5)
  - [x] Añadir a `README.md` (o crear si no existe) la sección "Entornos" con:
    - **dev (Xcode + iPhone físico):** `pnpm cap run ios --target=<udid>`, WebView carga `http://localhost` (Capacitor 8 + `server.url` solo en dev), el bundle se sirve desde un dev server local
    - **dev (PWA local):** `python3 -m http.server` o similar en la raíz; abre `http://localhost:8000`; Web Wake Lock API disponible
    - **prod (TestFlight app):** `xcodebuild archive` → App Store Connect → TestFlight; bundle local (`webDir: "www"`), sin `server.url`
    - **prod (GitHub Pages PWA):** deploy directo del repo a Pages; PWA intacta
  - [x] Añadir nota explícita: **nunca** commitear con `server.url` en producción (AD-C7, bundle local)
  - [x] Documentar en la story la diferencia entre `WakeLockPort` (nombre del código heredado, runtime.js) y `KeepAwakePort` (nombre del spine/AR-10) — son el mismo concepto; el código mantiene `WakeLockPort` por estabilidad de v3

## Dev Notes

### Stack (verificado en story 8.1, AR-8)

- **Capacitor 8.4.2** + **@capacitor-community/keep-awake 8.0.1** (MIT, ya instalados) [fuente: story 8.1, AR-8]
- **iOS deployment target 16.1** (piso ActivityKit) [fuente: ARCHITECTURE-SPINE.md#171]
- **Xcode 26.3** configurado [fuente: story 8.1]
- **Simulador objetivo: iPhone 14** (decision Paul 2026-08-01) — **PERO esta story NO usa simulador**, requiere iPhone físico (AR-11)

### Contexto del dominio (heredado, AR-12)

- **`WakeLockPort` ya existe en `runtime.js`** (createWakeLockPort): contrato `{ acquire, release, onLost, onAcquired }` que usa la Web Wake Lock API (`navigator.wakeLock.request('screen')`). El spine lo llama `KeepAwakePort` por AR-10; el código mantiene `WakeLockPort` por compatibilidad con v3.
- **NO se introduce lógica de dominio nueva** en esta story. El puerto es read-only del AR-12 (heredado v3). Esta story solo añade el adapter nativo y la inyección según plataforma.
- El call site de `wlPort.acquire()` / `wlPort.release()` ya existe en `index.html` (líneas 571, 612, 844, etc.) y depende solo del contrato. Mantener la interfaz estable.
- **`BackgroundHandler`** (createBackgroundHandler en `runtime.js`) ya emite `onBackground`/`onForeground` por `visibilitychange`; el adapter nativo debe liberar/adquirir en esos eventos. Verificar que el comportamiento de la v3 (recuperación silenciosa AD-8) sigue funcionando.

### Arquitectura a respetar (invariantes)

- **Hexagonal:** el dominio (incluyendo `runtime.js` con `WakeLockPort`) NO importa Capacitor. El adapter es el único punto que conoce el plugin. [fuente: AR-1, AD-C1]
- **AD-C2 (una frontera):** `walktracker-kit` es para código nativo propio (CMPedometer/HKWorkout/ActivityKit). El keep-awake va por plugin comunitario (`@capacitor-community/keep-awake`), no se reimplementa en `walktracker-kit`. [fuente: spine §AD-C2]
- **AD-C7 (bundle local):** `webDir: "www"` ya fijado en story 8.1; **no** añadir `server.url` en producción. La nota "dev usa http://localhost" del AC 5 se documenta, pero el flujo de build que se valida en esta story es bundle local en el device físico (no dev server). [fuente: AR-6]
- **Entornos (AR-11):** dev = build local Xcode en iPhone físico + (opcional) dev server para hot reload de la web; prod = TestFlight + bundle local. El simulador iOS no tiene acelerómetro real — la validación de pasos va al device físico. [fuente: AR-11]

### Archivos del repo (estado actual verificado)

- `adapters/` — **NO existe aún**; hay que crearlo en esta story. Convención del spine: `adapters/Capacitor<Xxx>Adapter.js` [fuente: ARCHITECTURE-SPINE.md §Consistency Conventions]
- `index.html` — tiene el guard `isNative` (story 8.1) y `wlPort = R.createWakeLockPort()`. Punto de inyección del adapter: donde se crea `wlPort`. (línea ~296)
- `runtime.js` — `createWakeLockPort` (Web Wake Lock API), `createBackgroundHandler` (visibilitychange). Read-only (AR-12).
- `walktracker-kit/` — plugin local (story 8.1), sin uso en esta story. `walktracker-kit` es para CMPedometer/HKWorkout/ActivityKit (Epics 1/6/7), NO para keep-awake.
- `ios/App/App.xcworkspace` — workspace Xcode con CocoaPods; 6 pods instalados (Capacitor, CapacitorCordova, KeepAwake, LocalNotifications, Preferences, WalktrackerKit). [fuente: story 8.1]
- `ios/App/capacitor.config.json` — regenerado por cap sync; `webDir: "www"`, `appId: com.walktracker.app`, `packageClassList` con los 4 plugins. [fuente: story 8.1]
- **Bundle iOS actual** compilado en `ios/build/` (Debug-iphonesimulator). **No es válido para device físico** — Xcode recompilará para el destino físico cuando ejecute `cap run ios --target=<udid>`.

### ⚠️ Bloqueante explícito

**Esta story NO se puede ejecutar sin el iPhone físico de Paul conectado y desbloqueado.** El simulador iOS no tiene acelerómetro real (AR-11) y el gate 8.4 (60 min walk, ≤10% vs Apple Salud) requiere hardware real. Antes de empezar las tasks 1+:
1. Pedir a Paul que conecte el iPhone vía USB (o Wi-Fi sync si está configurado).
2. Confirmar que macOS lo reconoce: `xcrun devicectl list devices` o abrir Xcode → Window → Devices.
3. Obtener el UDID del iPhone físico (Xcode muestra el "Identifier" del device).

Si Paul no tiene el iPhone a mano, la story queda bloqueada. Alternativa parcial: compilar para device sin instalar (verificar firma) — pero NO satisface el AC 1 (necesita la app corriendo en el device).

### Learnings de la story 8.1 (a aplicar)

- **webDir:** `www/` (subdirectorio) ya fijado; no tocar.
- **bundle www/:** siempre correr `pnpm build:web` antes de `cap sync` para regenerar.
- **plugin file: deps:** pnpm respeta `files` del package.json del plugin; los `*.podspec` deben listarse. (No afecta a esta story, solo `walktracker-kit`.)
- **Podfile 16.1:** ya fijado en story 8.1.
- **Verify siempre** que `domain.js` y `runtime.js` NO importan Capacitor (`rg -i capacitor` debe dar 0) — invariante AD-C1.

### Testing

- **Esta story NO introduce lógica de dominio nueva** → no hay tests de dominio nuevos (AR-12: read-only de v3). TDD aplica solo al adapter.
- Tests del adapter: jsdom, mockear el plugin `@capacitor-community/keep-awake`. Verificar:
  - `acquire()` en nativo llama a `KeepAwake.keepAwake()`
  - `release()` en nativo llama a `KeepAwake.allowSleep()`
  - `isAvailable()` devuelve `true` solo si `isNative && typeof KeepAwake !== 'undefined'`
  - En PWA, `acquire()/release()` delegan al `WakeLockPort` heredado (sin invocar el plugin)
- Verificación de humo: build en Xcode + arranque en iPhone físico + wake lock en foreground + release en background (prueba manual de Paul).
- Sin regresiones: `pnpm test:legacy` → 383 tests passing (línea base, story 8.1).

### Project Structure Notes

Alineación con el seed estructural (AR-9, spine §Structural Seed):

```text
walktracker/
  index.html                  # composition root: guard isNative (story 8.1) + inyección adapter (8.2)
  domain.js storage.js migration.js climate.js motivation.js runtime.js   # read-only (AR-12)
  quotes.json manifest.webmanifest sw.js icons/                           # PWA (canal secundario)
  adapters/                   # NUEVO en 8.2 — adapters del borde
    capacitor-keep-awake-adapter.js
  test/
    adapters/                 # NUEVO en 8.2 — tests del adapter (jsdom)
      capacitor-keep-awake-adapter-tests.js
  walktracker-kit/            # plugin custom (story 8.1) — sin cambios en 8.2
  ios/                        # proyecto Xcode (story 8.1) — recompila en device físico
  capacitor.config.json       # sin server.url (AD-C7); webDir www (story 8.1)
  package.json                # +@capacitor-community/keep-awake (story 8.1)
  README.md                   # NUEVO/actualizado en 8.2 — sección Entornos
```

Convención: `Capacitor<Xxx>Adapter` para adapters del borde nativo; puertos en domain layer (`domain.js`, `runtime.js`) con sufijo `Port` y nunca importan infra.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#852-877] — Story 8.2 (ACs originales)
- [Source: _bmad-output/planning-artifacts/epics.md#68-70] — AR-10 (KeepAwakePort), AR-11 (entornos)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-28/ARCHITECTURE-SPINE.md#169,213] — keep-awake 8.0.1 (MIT) + contrato `acquire/release`
- [Source: ARCHITECTURE-SPINE.md#216] — Entornos (dev iPhone físico, prod TestFlight)
- [Source: ARCHITECTURE-SPINE.md#§Consistency Conventions] — Convención `Capacitor*Adapter`
- [Source: _bmad-output/implementation-artifacts/8-1-montaje-capacitor-web-v3-en-webview-proyecto-xcode-plugin-scaffold.md] — Learnings webDir/bundle/podspec (a aplicar)
- [Source: runtime.js#4-66] — `createWakeLockPort` (Web Wake Lock API, heredado v3)
- [Source: index.html#296,571,612,844] — Call sites de `wlPort` (inmutables en esta story)
- [Source: research: @capacitor-community/keep-awake 8.0.1 docs] — API: `keepAwake()`, `allowSleep()`

## Dev Agent Record

### Agent Model Used

opencode/deepseek-v4-flash-free

### Debug Log References

- **Task 2 (adapter):** creado `adapters/capacitor-keep-awake-adapter.js` como IIFE vanilla (patrón runtime.js, se expone como `WT.CapacitorKeepAwake.createAdapter()`). 18 tests vitest pasando (mock del plugin). El plugin `KeepAwake` es global en el WebView (inyectado por Capacitor) → el adapter lo recibe como deps sin importarlo.
- **Task 3 (composition root):** `isNative` movido ANTES de `wlPort` (estaba en `init()`, ahora en el closure del IIFE principal). `wlPort` se selecciona: `isNativeKeepAwake ? CapacitorKeepAwakeAdapter : WakeLockPort`. Script del adapter cargado como `<script>` tag en index.html. `adapters/` añadido a `scripts/build-web.mjs` (DIRS) para que el bundle del WebView lo incluya. Verificado invariante AD-C1: 0 referencias a Capacitor en `domain.js`/`runtime.js`. 383 tests legacy sin regresiones.
- **Task 5 (README):** `README.md` creado con sección "Entornos" completa (dev iPhone físico, dev PWA, prod TestFlight, prod GitHub Pages) + sección "Arquitectura" breve. Documentada la divergencia WakeLockPort/KeepAwakePort (spine AR-10 vs código v3).

### Completion Notes List

- Story 8.2 creada desde el epics.md (ACs 1-5 + And), con dev notes que incluyen: contexto del `WakeLockPort` heredado v3, alcance del adapter nativo, learnings de la story 8.1, y bloqueante explícito (iPhone físico)
- **IMPLEMENTACIÓN PARCIAL 2026-08-03 (Tasks 2, 3, 5 ✓; Tasks 1, 4 BLOQUEADAS):**
  - Task 2: `CapacitorKeepAwakeAdapter` — IIFE vanilla (`adapters/capacitor-keep-awake-adapter.js`, 18 tests vitest ✓), contrato `{ acquire, release, onLost, onAcquired, isAvailable }` compatible con WakeLockPort
  - Task 3: Composition root — `isNative` reubicado antes de `wlPort`; inyección condicional `isNativeKeepAwake ? CapacitorKeepAwakeAdapter : WakeLockPort`; adapter y `adapters/` incluidos en el bundle `www/`; AD-C1 verificado (0 Capacitor en dominio), 383 tests legacy sin regresiones
  - Task 5: `README.md` creado con documentación de 4 entornos (dev iPhone físico, dev PWA, prod TestFlight, prod GitHub Pages) + invariantes de arquitectura
  - **Bloqueante de entorno (Tasks 1, 4):** iPhone físico de Paul (`Paul Alarcon's iPhone`, UDID `00008110-001C318E0CF8401E`) aparece como `unavailable` en `xcrun devicectl list devices`. El desbloqueo del iPhone y la conexión USB son necesarios para ejecutar `npx cap run ios --target=<UDID>` y el humo test en hardware real.
- Decisión sobre el `WakeLockPort` (código) vs `KeepAwakePort` (spine AR-10): se documenta en dev notes y README; el código mantiene `WakeLockPort` por estabilidad de v3 (AR-12 read-only)

### File List

- `_bmad-output/implementation-artifacts/8-2-build-local-en-dispositivo-fisico-keep-awake-entorno-dev.md` (este archivo)
- `adapters/capacitor-keep-awake-adapter.js` (NUEVO — adapter nativo IIFE vanilla)
- `test/adapters/capacitor-keep-awake-adapter-tests.js` (NUEVO — 18 tests vitest)
- `index.html` (MODIFICADO — script del adapter, isNative reubicado, wlPort condicional)
- `scripts/build-web.mjs` (MODIFICADO — DIRS incluye adapters/)
- `www/` + `ios/App/App/public/` (regenerados con cap sync)
- `README.md` (NUEVO — documentación de entornos + arquitectura)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (MODIFICADO — 8-2 → in-progress)
