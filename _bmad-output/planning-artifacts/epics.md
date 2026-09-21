---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
inputDocuments:
  - _bmad-output/specs/spec-walktracker-ios/SPEC.md
  - _bmad-output/specs/spec-walktracker-ios/capabilities.md
  - _bmad-output/specs/spec-walktracker-ios/domain-model.md
  - _bmad-output/specs/spec-walktracker-ios/achievements.md
  - _bmad-output/specs/spec-walktracker-ios/platform-matrix.md
  - _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-09-12/ARCHITECTURE-SPINE.md
  - _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-09-12/DEROGACIONES.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/DESIGN.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/EXPERIENCE.md
---

> 🧭 **Corregido el 2026-09-20 — el puntero apuntaba a lo derogado.** Este frontmatter declaraba como
> entrada `architecture/architecture-walktracker-2026-07-28/ARCHITECTURE-SPINE.md`: el spine de la era
> **Capacitor**, que sigue en el repo junto a otros cinco y que **AD-1 derogó entero**. El documento
> cuyo propósito es que el contexto se compile de lo vigente apuntaba a lo superado. Ahora apunta a
> `architecture-walktracker-2026-09-12/`, y se añade su companion `DEROGACIONES.md`, que es
> **vinculante** y sin el cual media docena de referencias de aquí (UX-DR*, AR-*, §5, §6) no aterrizan.
>
> **Comprobadas las demás entradas:** las cinco del paquete SPEC existen y están reconciliadas
> (`platform-matrix.md` incluido, reescrito a mecanismos nativos). `DESIGN.md` y `EXPERIENCE.md` del
> `2026-07-04` **siguen vigentes y no se tocan**: no están superados, sino **parcialmente derogados**
> por `DEROGACIONES.md §4`, que mantiene UX-DR3, UX-DR4, UX-DR6 y UX-DR8 en pie — por eso el companion
> tiene que leerse con ellos, y por eso entra en la lista.

# WalkTracker iOS - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for WalkTracker iOS, decomposing the requirements from the SPEC package, Architecture spine, and UX design into implementable stories. Es la reimplementación de la PWA v3 como **app SwiftUI nativa**: el dominio validado se **porta a Swift idiomático** —no se reutiliza intacto, y la equivalencia se demuestra por los vectores de AD-6, nunca por parecido del código— y la frontera nativa aporta conteo 24/7, HealthKit, Live Activity, recordatorios y storage garantizado.

> ⛔ **REESCRITO el 2026-09-12.** Esta frase decía *"app **Capacitor** instalable"* y *"el dominio validado se reutiliza **intacto** (salvo 2 correcciones de portación)"*. **AD-1** derogó Capacitor: no hay WebView ni capa híbrida. Y las "2 correcciones de portación" que AR-1 toleraba dejaron de ser excepciones: hoy la tabla de divergencias declaradas de **AD-6** tiene **dos filas, no cuatro**. Las que quedan son **obligatorias** y de plataforma —hora local en vez de UTC (**AD-19**) y código WMO en vez de regex—; las otras dos **eran defectos de la v3**, se corrigieron en la referencia el mismo día y por eso **salieron** de la tabla: `domain.js` ya pasa esos vectores y están tachadas en AD-6. Una divergencia declarada es una decisión que se mantiene, no un bug que se tolera. [`ARCHITECTURE-SPINE.md` AD-1, AD-6; `DEROGACIONES.md §1`, `§5`, `§6` (*"la tabla de divergencias declaradas pasa de cuatro filas a dos"*)]

## Requirements Inventory

### Functional Requirements

- **FR-1**: Control de sesión con cronómetro wall-clock — iniciar/pausar/finalizar; pausa solo explícita; cambiar de app no pausa.
- **FR-2**: Conteo automático de pasos 24/7 vía coprocesador del sistema (foreground, background, pantalla bloqueada, teléfono en bolsillo).
- **FR-3**: Reconstrucción de intervalos en background por query exacta al sistema; estimación por cadencia solo como degradación excepcional, marcada "~" y descartable.
- **FR-4**: Métricas en vivo — pasos, distancia (sistema preferida, fallback pasos×zancada), tiempo, ritmo, cadencia; ritmo solo si distancia ≥100 m.
- **FR-5**: Snapshot de clima congelado al inicio (temp, sensación, condición, humedad, UV, viento); sin red/permiso → sesión inicia sin clima.
- **FR-6**: Frase motivacional al iniciar (banco 100, sin repetición en últimas 20), overlay 3–4 s saltable con tap.
- **FR-7**: Meta semanal de km configurable (default 10), anillo de progreso sobre semana ISO, celebración al cumplir.
- **FR-8**: Catálogo de 14 logros evaluado al cierre de sesión, celebración visual+sonora+háptica; sin re-disparo.
- **FR-9**: Persistencia local garantizada no evictable: sesiones, logros y config sobreviven reinicio sin respaldos manuales.
- **FR-10**: Historial lista descendente con totales semana/mes y gráfico de tendencia; sesiones con pasos estimados marcadas "~".
- **FR-11**: Cada sesión finalizada se escribe automáticamente en Apple Salud como workout de caminata con distancia y pasos.
- **FR-12**: Feedback háptico + sonoro en eventos (inicio, km, meta, logro), sin interrumpir música en reproducción.
- **FR-13**: Recalibración de zancada in-app; sesiones cerradas conservan zancada congelada.
- **FR-14**: Export CSV/JSON compartible + re-import JSON restaura historial; CSV abre en Numbers/Excel.
- **FR-15**: Eliminar sesiones individuales del historial.
- **FR-16**: Notificaciones locales de recordatorio de meta semanal (reprogramación idempotente).
- **FR-17**: Live Activity en pantalla de bloqueo + Dynamic Island (hardware que la tenga) con métricas en vivo; se cierra al finalizar.

### NonFunctional Requirements

- **NFR-1**: **SwiftUI nativo como sustrato** — app iOS contra el SDK de iOS 26, sin WebView y sin capa híbrida; el dominio se porta a Swift idiomático y las capacidades del sistema se consumen por adapters detrás de puertos; deployment target 26.0, sin `if #available` hacia atrás.
  - > ⛔ **REESCRITO el 2026-09-12.** Decía *"Capacitor como capa nativa — web app v3 en WKWebView"*. OQ-1 se reabrió y se resolvió de nuevo: no hay Capacitor. La condición de viabilidad ligada al rendimiento del WebView **desaparece** — ese riesgo no existe sin WebView; lo que queda es NFR-8. Gobernado por **AD-1 y AD-2**. [`DEROGACIONES.md §2`]
- **NFR-2**: No-backend — todo on-device; única llamada de red = clima; sin auth/cuentas/sync cloud/servidor propio.
- **NFR-3**: Usuario único (Paul) — sin multi-cuenta, perfiles ni UX de identidad.
- **NFR-4**: Privacidad — datos en dispositivo; sin analítica/telemetría; coordenadas clima a 2 decimales.
  - > ℹ️ El redondeo a 2 decimales tiene dueño desde el 2026-09-12: **`LocationPort` (AD-10)**, el único punto donde la restricción es verificable.
- **NFR-5**: Dominio preservado — invariantes v3 (wall-clock, pausa explícita, sesión finalizada inmutable, zancada congelada al cierre, validación en frontera, cadencia solo sobre tramos medidos, pasos estimados siempre desglosados).
  - > ⚠️ **PRECISADO el 2026-09-12** → se preservan los invariantes, **no los defectos**. Cuatro divergencias obligatorias respecto al código v3, declaradas en **AD-6**: hora local en vez de UTC, código WMO en vez de regex, las pausas restadas una sola vez y las rachas comparadas como fechas. Las dos últimas eran bugs vivos, corregidos en la referencia el mismo día. [`DEROGACIONES.md §6`]
- **NFR-6**: Arquitectura hexagonal — dominio puro sin frameworks de plataforma/UI; puertos en dominio, adapters en borde.
- **NFR-7**: Licencias — solo Apache-2.0/MIT; copyleft fuerte bloqueante.
  - > ⚠️ **ENMENDADO el 2026-09-12** → Apache-2.0/MIT en **código**; en **fuentes de datos** se admite CC-BY 4.0 con atribución visible. Open-Meteo es CC-BY, no MIT (**AD-24**). Copyleft fuerte sigue bloqueante.
- **NFR-8**: Batería — sesión de 30 min con conteo continuo sin degradación notoria.
  - > ⚠️ **ENMENDADO el 2026-09-13** → antes 60 min. Umbral verificable: ≤ 5 % de caída total en los 30 min y WalkTracker no destacado en Ajustes → Batería. [`SPEC.md` Constraints · Batería]
- **NFR-9**: UX — targets ≥44 pt, claro/oscuro, "celebrar nunca culpar", números grandes, overlay 3–4 s saltable, UI en español.

### Additional Requirements

- **AR-1 (AD-C1)**: Capacitor como capa nativa; web app v3 empaquetada intacta en bundle local; código web solo toca Capacitor en adapters `Capacitor*` y composition root. Excepción deliberada: `domain.js` admite 2 correcciones de portación — logros temporales en hora local del dispositivo (no UTC) y mapeo de condición climática por código WMO → categoría interna `rain` (no regex sobre strings localizados).
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-1, AD-3**. Capacitor y la web app intacta desaparecen. Las dos "correcciones de portación" que autorizaba (hora local, mapeo WMO) se promueven a divergencias obligatorias en AD-6 y AD-19. [`DEROGACIONES.md §5`]
- **AR-2 (AD-C2)**: Un solo plugin custom `walktracker-kit` (paquete local `./walktracker-kit`, podspec propio, referencia `file:` en package.json) envuelve CMPedometer (live + query), HKWorkout y bridge ActivityKit. Adapters JS `CapacitorMotionAdapter`, `CapacitorHealthKitAdapter`, `CapacitorLiveActivityAdapter` hablan solo con él. Keep-awake y local-notifications en plugins comunitarios verificados (MIT).
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-10, AD-23**. No hay plugin `walktracker-kit`: cada capacidad de sistema se consume por su puerto desde un adapter. [`DEROGACIONES.md §5`]
- **AR-3 (AD-C4)**: Reconstrucción background por `queryPedometerData` como camino primario; `GapEstimator` solo si query falla/vacía (reglas heredadas: muestra ≥120 s, desglosado, "~", descartable); en web el GapEstimator sigue siendo el camino principal.
- **AR-4 (AD-C5)**: Distribución = builds locales Xcode (`pnpm cap run ios`) para iterar + TestFlight como canal duradero. Gate de promoción = prueba de performance del Success signal (60 min background, ≤10 % vs Salud, sin degradación batería). App Store fuera de scope. PWA se despliega por GitFlow a Pages.
  - > ⛔ **PARCIAL el 2026-09-12** → heredero: **Story 8.3**. TestFlight sobrevive; el mecanismo `pnpm cap run ios` no. [`DEROGACIONES.md §5`]
  - > ⚠️ **ENMENDADO el 2026-09-13** → el gate pasa a **30 min** (≤ 5 % de batería, WalkTracker no destacado en Ajustes → Batería) y corre en la **Story 8.4 tras el Epic 1**. [`sprint-change-proposal-2026-09-13.md`]
- **AR-5 (AD-C6)**: Live Activity alimentada por eventos nativos (callbacks CMPedometer en `walktracker-kit`), NO por WebView; el WebView solo ordena estado mayor (inicio/pausa/fin) vía `LiveActivityPort`.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-15**. No hay WebView que ordene el estado: la app alimenta la Live Activity directamente. [`DEROGACIONES.md §5`]
- **AR-6 (AD-C7)**: Bundle local únicamente; prohibido `server.url` en producción; actualizaciones vía build/TestFlight; única red = Open-Meteo.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **—**. Sin WebView no hay `server.url` ni bundle local que gobernar. [`DEROGACIONES.md §5`]
- **AR-7 (AD-C8)**: HealthKit write una vez al finalizar (dato inmutable completo); toda petición de permiso con pre-pantalla; recordatorios de meta idempotentes (cancel→schedule) desde GoalEngine al finalizar sesión y al abrir la app.
- **AR-8 (Stack verificado)**: @capacitor/core/cli/ios 8.4.2, @capacitor/local-notifications 8.2.1, @capacitor-community/keep-awake 8.0.1, @capacitor/preferences 8.0.1 (todos MIT); iOS deployment target 16.1; Xcode 26+; Node ≥22; gestión con pnpm.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-2 + Stack**. Stack Capacitor y target 16.1 sustituidos por **Swift 6.2.4 / Xcode 26.3 (17C529) / iOS deployment target 26.0**, que es el toolchain **instalado y verificado en la máquina** (`swift --version`, `xcodebuild -version`) y lo que fija el Stack del spine. *(Corregido el 2026-09-20: esta línea decía "Swift 6.3.3 / Xcode 26.6", versiones que existen pero no son las del proyecto — el propio spine ya lo decía bien en su tabla de Stack.)* [`DEROGACIONES.md §5`; `ARCHITECTURE-SPINE.md` § Stack]
- **AR-9 (Structural Seed)**: Repo único GitFlow; `walktracker-kit/` plugin local con podspec; `ios/` proyecto Xcode commiteado; `capacitor.config.json` sin `server.url`, `webDir` local; adapters nuevos `Capacitor*Adapter` en la capa web.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-23**. El seed estructural es el árbol SwiftUI, no el repo Capacitor. [`DEROGACIONES.md §5`]
- **AR-10 (Port contracts)**: MotionPort nativo (`onSteps(cumulativeCount, distanceM?)`, `query→{steps,distanceM}|null`) y web (`onSample` @60 Hz); HealthKitPort (`writeWorkout` una vez); LiveActivityPort (`start/updateState/stop`); NotificationPort (`rescheduleWeeklyReminder` idempotente); KeepAwakePort (`acquire/release` en foreground).
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-10**. Los contratos de puerto se redefinen: 11 puertos, entre ellos LocationPort, WakeLockPort y RandomPort que AR-10 no tenía. [`DEROGACIONES.md §5`]
- **AR-11 (Entornos)**: dev = builds locales Xcode en iPhone físico (simulator sin acelerómetro real) + `http://localhost`; prod = TestFlight (app principal) + GitHub Pages (PWA secundaria); sin backend, sin CI de servidor.
  - > ⛔ **PARCIAL el 2026-09-12** → heredero: **envoltura operativa del spine**. Dev en dispositivo físico sobrevive; el canal PWA a GitHub Pages no. [`DEROGACIONES.md §5`]
- **AR-12 (Inherited v3)**: AD-1 hexagonal, AD-4 Session aggregate (stepsMeasured/Estimated, strideM), AD-5 strideM congelada, AD-6 wall-clock, AD-7 validación frontera, AD-8 autosave+recuperación silenciosa, AD-14 Open-Meteo timeout 3s, AD-17 geolocation 2dp, AD-18 quotes.json — todos vigentes, read-only.
- **AR-13 (Deferred)**: protocolo de performance a nivel epic/story; canal háptico (CoreHaptics en walktracker-kit vs web) se resuelve como adapter tras puerto; contenido/formato de Live Activity a nivel story; sync PWA↔app fuera (arranque limpio); calibración interactiva futura; cache-busting SW PWA heredado.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **sección Deferred del spine**. El protocolo de performance lo fija **AD-21**; el canal háptico deja de ser una duda (`CoreHaptics` vía `FeedbackPort`, AD-10) y el sync PWA↔app no aplica sin PWA. [`DEROGACIONES.md §5`]

### UX Design Requirements

- **UX-DR1**: Design tokens Volt — canvas `#1A1A1A`/`#F5F5F7`, surface `#2A2A2A`/`#FFFFFF`, accent `#CCFF00`/`#CC9900`, secondary `#FF6600`, danger `#FF453A`, success `#30D158`, estimated `#FFB347`/`#CC7A00`, text `#FFFFFF`/`#1D1D1F`, muted `#999999`/`#666666`, border `#555555`/`#8E8E93`; dark-mode-first con light igual; sin gradientes (solo overlay), máx 2 colores cromáticos por pantalla.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-13**. Los tokens Volt (`#CCFF00`, `#1A1A1A`…) se sustituyen por colores del sistema y Liquid Glass heredado del SDK de iOS 26. Cablear hexadecimales pelea con la plataforma. [`DEROGACIONES.md §4`]
  - > ℹ️ **Con una excepción declarada, y son exactamente tres colores.** El chore de tokens (2026-09-18) promovió dos y **B-2 añadió el tercero** (2026-09-20): los colorsets `AccentColor`, `EstimatedSteps` y `ErrorMessage`, en `WalkTracker/Resources/Assets.xcassets/`, con variante clara y oscura y **contraste medido contra el fondo real** sobre el que se pintan — `DesignTokensTests` lo recalcula en cada ejecución de la suite. No vuelve la paleta Volt y **ninguna vista cablea un hexadecimal**: se referencian por nombre desde `WalkTracker/UI/Style/DesignTokens.swift` y la sección 12 de `Scripts/check-project-shape.sh` lo impide. Son tres decisiones de color, no una capa de apariencia. **Los hexadecimales y los ratios medidos no se copian aquí:** viven en `DEROGACIONES.md §4`, que es su **fuente única**. [`DEROGACIONES.md §4`; spec-b2]
- **UX-DR2**: Tipografía system-fonts (`-apple-system`); tokens: `metric-hero` 64px (48px mobile) 900, `metric-sub` 16px 700, `label` 11px 400, `body` 15px 400, `button-primary` 24px 900, `button-secondary` 14px 600, `header-title` 17px 700, `status-badge` 12px 600, `quote-hero` 28px (22px mobile) 700, `ring-value` 36px 900, `ring-label` 14px 600; Dynamic Type obligatorio con `clamp()` (hero ≤80px, quote ≤36px a 200%).
  - > ⛔ **PARCIAL el 2026-09-12** → heredero: **AD-13 + convención de accesibilidad**. `px`, `clamp()` y los tamaños fijos son conceptos de CSS y **no aplican**: en SwiftUI se usan estilos de texto del sistema y Dynamic Type. Lo que sobrevive es la intención — jerarquía con números grandes y escalado accesible sin recortes. [`DEROGACIONES.md §4`]
- **UX-DR3**: Espaciado/Layout — escala 4/8/12/16/24/32 px; márgenes 16 px; card padding 20 px; goal ring 300 px diámetro centrado; touch targets ≥44 pt; safe areas `env(safe-area-inset-bottom)`; single-column siempre; modal máx 1 nivel.
- **UX-DR4**: Componentes visuales (DESIGN.md) — Goal Ring, Metric Card, Weather Card, Session Controls (Pausar/Reanudar/Finalizar, 44 px min, danger/success), Estimated Steps Banner, Wake Lock Banner, Recovery Indicator, Motivational Overlay, Achievement Badge, Celebration Toast, Summary Screen, History Row (delete 44×44 pt + confirm), Settings Field, Motion Denied Screen, Status Badge, Toggle Switch (hit 48×44 px).
- **UX-DR5**: Arquitectura de información — 9 superficies (Home, Session, Motivational Overlay, Summary, Settings, History, Achievements, Motion Denied); navegación iconos top-right (⚙📋🏆) sin tab bar; screen replacements no modales; overlay transitorio; estados: cold open, active, paused, background→foreground (wall-clock + estimated banner), finished (Summary forward-only), goal completed, achievement unlocked, wake lock failed, no network, motion denied, empty history/achievements, backup overdue, recovery from purge.
  - > ⛔ **PARCIAL el 2026-09-12** → heredero: **AD-14**. La navegación con **iconos arriba a la derecha y sin tab bar** queda derogada: `TabView` de cuatro pestañas con la sesión como `fullScreenCover`. Lo que sobrevive es el inventario de superficies y la lista de estados (cold open, motion denied, empty history, recuperación…), que sigue siendo vinculante. [`DEROGACIONES.md §4`]
- **UX-DR6**: Accesibilidad WCAG AA — VoiceOver completo (distance "3.2 kilómetros", steps con estimated, aria-labels en nav icons, overlay `role=dialog aria-modal`, toast `role=status aria-live=polite`, achievement locked aria-label); Dynamic Type con clamp; Reduce Motion (overlay sin fade, toast sin animación, ring instant); contraste verificado (accent-dark 15.4:1, estimated 7.2:1/4.6:1, muted 4.9:1/5.0:1); focus ring accent 2px; Escape dismiss; Tab order visual.
  - > ⚠️ **TRADUCIDO el 2026-09-12** → la *intención* sigue vinculante (WCAG AA, VoiceOver completo, Dynamic Type sin recortes, Reduce Motion, contraste verificado), pero **sus mecanismos son de la web y no aplican**: `aria-label` → `.accessibilityLabel`, `role=dialog aria-modal` → presentación modal nativa, `role=status aria-live` → `.accessibilityAddTraits(.updatesFrequently)`, `focus ring`/`Tab order`/`Escape` → foco y descarte del sistema, `clamp()` → Dynamic Type. Los ratios de contraste se recalculan contra colores del sistema —salvo los **tres** colorsets propios que `DEROGACIONES.md §4` declara como excepción (`AccentColor`, `EstimatedSteps`, `ErrorMessage`), medidos en los **dos** temas contra sus fondos reales por `WalkTrackerTests/UI/DesignTokensTests.swift`; **los números están en §4 y solo en §4**—, no contra los tokens Volt de UX-DR1, que está derogado. Las tres piezas dibujadas de AD-13 necesitan etiqueta explícita: un `Canvas` no la trae. [`DEROGACIONES.md §4`]
- **UX-DR7**: Interacciones — tap-to-act (sin long-press/swipe); "Iniciar caminata" primary grande; beep feedback primario (inicio, km, meta, logro) volumen respetuoso; goal ring anchor 300 px; prohibidos: carousels, hero animations, badge counts, streaks, pull-to-refresh, swipe-to-delete; nuevos: overlay tap-skip, estimated banner dismissable, celebration toast non-blocking.
  - > ⛔ **PARCIAL el 2026-09-12** → heredero: **AD-20**. La **prohibición de swipe-to-delete queda derogada**: en iOS el swipe *es* el gesto de borrado y el icono en la fila es el antipatrón (B-11 de la validación). Sobrevive todo lo demás: tap-to-act, beep primario a volumen respetuoso, y las prohibiciones de carousels, hero animations, badge counts y pull-to-refresh. [`DEROGACIONES.md §4`]
- **UX-DR8**: Flujos clave — 6 flows documentados (walk+progreso, meta cumplida, tendencia historial, logros, recalibración, motion denied).

### FR Coverage Map

- FR-1: Epic 1 — Sesión y cronómetro wall-clock
- FR-2: Epic 1 — Conteo pasos 24/7 (coprocesador)
- FR-3: Epic 1 — Reconstrucción background por query
- FR-4: Epic 1 — Métricas en vivo
- FR-5: Epic 2 — Clima snapshot
- FR-6: Epic 2 — Frase motivacional
- FR-7: Epic 3 — Meta semanal + anillo
- FR-8: Epic 3 — Logros (14)
- FR-9: Epic 5 — Persistencia garantizada
- FR-10: Epic 5 — Historial + totales + tendencia
- FR-11: Epic 6 — HealthKit workout
- FR-12: Epic 4 — Feedback háptico+sonoro (transversal)
- FR-13: Epic 2 — Recalibración zancada
- FR-14: Epic 5 — Export CSV/JSON + re-import
- FR-15: Epic 5 — Eliminar sesiones
- FR-16: Epic 6 — Notificaciones recordatorio
- FR-17: Epic 7 — Live Activity / Dynamic Island

## Epic List

### Epic 1: Sesión y conteo de pasos nativo
Paul puede iniciar una caminata y que el iPhone cuente sus pasos automáticamente —con pantalla bloqueada, en el bolsillo, con música— gracias al coprocesador de movimiento, con métricas en vivo y reconstrucción exacta de los intervalos en background. Es el corazón del producto: sin esto nada más importa.
**FRs covered:** FR-1, FR-2, FR-3, FR-4
**NFRs:** NFR-1, NFR-2, NFR-5, NFR-6, NFR-8, NFR-9
**ARs:** AR-1, AR-2, AR-3, AR-9, AR-10, AR-12
**UX:** UX-DR2, UX-DR4, UX-DR5, UX-DR6

### Story 1.1: Iniciar sesión de caminata con cronómetro wall-clock

As a caminante (usuario único),
I want iniciar una sesión que mida el tiempo por reloj de pared (wall-clock) y no por temporizadores de la app,
So that el tiempo de mi caminata sea exacto incluso si cambio de app o bloqueo el teléfono.

**Acceptance Criteria:**

**Given** que no hay ninguna sesión activa y estoy en la pantalla Home
**When** toco "Iniciar caminata"
**Then** se crea un aggregate `Session` en estado `active` con `startedAt` = ahora (ISO-8601), `stepsMeasured`=0, `stepsEstimated`=0 y `source`=`"ios"`

**Given** que hay una sesión activa en la app
**When** la app pasa a segundo plano (cambio de app o pantalla bloqueada) y vuelvo
**Then** el tiempo transcurrido se recalcula como `elapsedS = (now − startedAt) − totalPausesS` usando wall-clock — ningún timer es fuente de verdad [fuente: domain-model.md#3]

**Given** que hay una sesión activa con 10 minutos transcurridos
**When** la dejo 5 minutos en otra app y vuelvo
**Then** `elapsedS` ≈ 15 minutos (los 5 de otra app cuentan como tiempo de caminata) [fuente: SPEC.md#CAP-1]

**Given** una sesión recién iniciada
**When** `strideM` del perfil de calibración es ≤ 0 o no finito
**Then** la creación se rechaza en la frontera con error de dominio específico (input inválido), sin materializar el aggregate [fuente: domain-model.md#51]

**And** el dominio (module `domain`) no importa UI ni framework: el `now` llega por un `ClockPort` y la creación de sesión es una función pura del dominio [fuente: domain-model.md#3; **AD-3**, **AD-10** — el dominio no llama a `Date()`: el reloj es un puerto]

### Story 1.2: Conteo de pasos en vivo vía coprocesador (MotionPort)

As a caminante (usuario único),
I want que el iPhone cuente mis pasos automáticamente con el coprocesador de movimiento,
So that el conteo funcione con pantalla bloqueada, en el bolsillo y con música sonando — sin que yo haga nada.

**Acceptance Criteria:**

**Given** una sesión activa y el permiso de movimiento concedido
**When** el coprocesador reporta pasos (callback `onSteps` del MotionPort)
**Then** el aggregate `Session` acumula los pasos en `stepsMeasured` (≥ 0, nunca decrece) y la UI en vivo los refleja sin tocar el dominio desde la capa de UI [fuente: domain-model.md#30]

**Given** una caminata de 10 minutos con la pantalla bloqueada y música sonando
**When** la finalizo
**Then** los pasos registrados difieren ≤ 10 % de los que reporta la app Salud [fuente: SPEC.md#CAP-2]

**Given** una sesión activa y el sistema reporta pasos mientras la app está en background o el teléfono en el bolsillo
**When** vuelvo a foreground
**Then** los pasos acumulados durante ese intervalo se incluyen en `stepsMeasured` (sin pasar por estimación, si el sistema los proveyó)

**Given** que el usuario denegó el permiso de movimiento
**When** intento iniciar una sesión
**Then** se muestra la pantalla Motion Denied con explicación y acceso a Ajustes, y la app no inicia su núcleo de conteo — es la única degradación **bloqueante** de la tabla [fuente: SPEC.md#CAP-2; AD-11, UX-DR5 (inventario de superficies, vigente)]

**And** el flujo de pasos entra al dominio por el puerto `MotionPort`, con un `MotionAdapter` que es el **único** punto del código que conoce `CMPedometer`; ninguna vista importa CoreMotion [**AD-10**]

**And** el handler de CoreMotion corre en su propia cola serie y **`CMPedometerData` no conforma a `Sendable`** —ni sus `NSNumber`—: el adapter extrae los valores a un `struct` `Sendable` propio **dentro del handler**, y solo ese DTO cruza al main actor. Pasar el objeto de CoreMotion es un error de compilación bajo concurrencia estricta, no una preferencia de estilo [**AD-7**, **AD-12**]

**And** el `StepDetector` de la PWA (pipeline propio 60 Hz, α=0.2, ventana refractaria 300 ms) queda retirado en nativo: la detección la hace el SO [fuente: domain-model.md#9]

### Story 1.3: Métricas en vivo — distancia, tiempo, ritmo y cadencia

As a caminante (usuario único),
I want ver mis métricas en tiempo real durante la caminata —pasos, distancia, tiempo, ritmo y cadencia—,
So that pueda entender cómo va mi caminata sin esperar a terminarla.

**Acceptance Criteria:**

**Given** una sesión activa con datos del coprocesador fluyendo
**When** la UI se refresca
**Then** muestra pasos, distancia, tiempo (wall-clock), ritmo (min/km) y cadencia (spm) en vivo, con la métrica principal en jerarquía dominante mediante estilos de texto del sistema y Dynamic Type — **sin tamaños fijos en px** [fuente: capabilities.md#CAP-4; AD-13, deroga los tokens en px de UX-DR2]

**Given** una sesión activa y el sistema provee distancia (CMPedometer)
**When** la UI muestra la distancia
**Then** usa la distancia del sistema como fuente preferida, sin distinción visible de fuente (la elección es interna, decisión de CAP-4) [fuente: capabilities.md#CAP-4]

**Given** una sesión activa y el sistema NO provee distancia
**When** la UI muestra la distancia
**Then** calcula `distanceM = (stepsMeasured + stepsEstimated) × strideM` con la zancada del perfil (default 0,655 m) [fuente: domain-model.md#45, capabilities.md#CAP-4]

**Given** una sesión activa con menos de 100 m recorridos
**When** la UI muestra el ritmo
**Then** muestra "—". El ritmo es un **opcional del dominio** (`nil`), no un `0` ni un `-1`: una métrica ausente se representa como ausente [fuente: domain-model.md#47, capabilities.md#CAP-4; **AD-4**, **AD-22**]

**And** la pantalla **solo muestra magnitudes que el dominio produce**. Añadir una métrica nueva a la UI exige antes un cálculo en `Domain/` con su vector de AD-6 — es la regla que impide repetir las calorías sin peso corporal y los puntos sin economía que la validación de mockups encontró inventados [**AD-22**]

**Given** una sesión activa
**When** la UI muestra la cadencia
**Then** `cadenceSpm = stepsMeasured / minutosConSensorActivo` — calculada **solo sobre tramos medidos**, nunca sobre pasos estimados [fuente: domain-model.md#48]

### Story 1.4: Pausar, reanudar y finalizar sesión (controles)

As a caminante (usuario único),
I want pausar, reanudar y finalizar mi caminata con controles claros,
So that tenga control total sobre cuándo se mide y cuándo se cierra mi sesión.

**Acceptance Criteria:**

**Given** una sesión activa mostrando los controles (Pausar / Finalizar, ≥44 pt)
**When** toco "Pausar"
**Then** la sesión pasa a estado `paused`, se registra el inicio de la pausa y la UI muestra "Reanudar / Finalizar" [fuente: domain-model.md#13, UX-DR4]

**Given** una sesión en estado `paused`
**When** toco "Reanudar"
**Then** la sesión vuelve a `active`, la pausa abierta se acumula en `totalPausesS` y el cronómetro continúa desde el wall-clock [fuente: domain-model.md#13]

**Given** una sesión en estado `paused` con una pausa abierta sin cerrar
**When** toco "Finalizar"
**Then** primero se acumula la pausa abierta en `pausesS` y luego se cierra la sesión (nunca se pierde tiempo de pausa) [fuente: domain-model.md#30]

**Given** una sesión finalizada
**When** se intenta cualquier mutación (pausar, reanudar, acumular pasos, cambiar zancada)
**Then** se lanza error de dominio: una sesión finalizada es **inmutable** [fuente: domain-model.md#13]

**Given** una sesión activa y la app pasa a segundo plano o se bloquea la pantalla
**When** no se tocó el botón de pausa
**Then** la sesión sigue `active` — el tiempo de fondo cuenta como caminata; **cambiar de app nunca pausa** [fuente: capabilities.md#CAP-1]

**Given** una sesión en estado `active`
**When** la UI muestra el cronómetro
**Then** `elapsedS` = (now − startedAt) − totalPausesS, refrescado por un timer que solo actualiza UI — el wall-clock sigue siendo la fuente de verdad [fuente: domain-model.md#35-38]

### Story 1.5: Reconstrucción de intervalos en background por query al sistema

As a caminante (usuario único),
I want que al volver a la app (o al finalizar) se recuperen los pasos exactos de los intervalos que pasé en background,
So that mi caminata quede completa y correcta aunque la app no estuviera en primer plano.

**Acceptance Criteria:**

**Given** una sesión activa con un intervalo en background (p. ej. 5 min con música)
**When** vuelvo a foreground (o finalizo la sesión)
**Then** se consulta el sistema (`queryPedometerData` por rango) por los pasos de ese intervalo y se suman a `stepsMeasured`, con `stepsEstimated` permaneciendo en 0 [fuente: capabilities.md#CAP-3]

**Given** que el sistema **no da respuesta** del intervalo en background (`nil`, error o timeout agotado)
**When** se intenta reconstruir el gap
**Then** se usa el `GapEstimator` como **degradación excepcional**: estimación por cadencia `stepsEstimated += cadenceSpm × (gapS/60)`, y solo si pasan, en este orden, las cuatro guardas de `GapEstimator.outcome`:

1. **precondición** — la sesión está `active` (`notActive` en otro caso);
2. el stream **no ha avanzado ya** sobre el gap (`stepsMeasured ≤` los medidos al empezar el gap), porque entonces esos pasos ya están contados;
3. hay **cadencia representable**: la cadencia se toma **en el inicio del gap**, nunca con los pasos de ahora, y con menos de **120 s** de sesión en ese instante no hay muestra previa que la sostenga;
4. el gap **cabe en `maxEstimableGapS`** de `formulas.json` (20 min hoy).

Las tres últimas son **"las tres defensas"**, que es como las nombra el código. **R1** (2026-09-17) puso la 2, la 4 y la mitad de la 3 —que la cadencia se tome **en el inicio del gap** y no con los pasos de ahora—. **El mínimo de 120 s no es de R1**: es anterior, y el propio `GapEstimator` lo atribuye a `domain-model.md §4`. Si alguna guarda corta, no se estima nada y el registro dice **qué defensa actuó** — un 0 no distingue "el tope cortó" de "estimó y salió 0" [fuente: domain-model.md#49, domain-model.md#73; `Domain/Session/GapEstimator.swift:18-20`, `:95-102`; spec-r1]

**Given** una estimación por cadencia aplicada a un intervalo
**When** se muestra en la UI
**Then** los pasos estimados van **desglosados y marcados "~"**, y el usuario puede **descartarlos** — si los descarta, esos pasos no cuentan [fuente: capabilities.md#CAP-3, domain-model.md#20]

**Given** una estimación por cadencia marcada "~"
**When** el usuario elige descartarla
**Then** `stepsEstimated` vuelve a **0 entero** —el descarte es **global**, no "de ese gap": hay un único contador de estimados por sesión— y la distancia y el ritmo se recomputan sin ellos [fuente: `Domain/Session/Session.swift:205-218`; retro del Epic 1, S2]

**Given** una sesión en estado `paused` (o finalizada) con un gap
**When** se intenta estimar pasos por cadencia
**Then** no se estima nada: gap = 0 — la estimación solo opera sobre sesiones activas [fuente: domain-model.md#49]

**And** **estimar** solo opera sobre sesiones `active`, pero **descartar** se permite en `active` **y en `paused`** —el Estimated Banner también se ve en pausa—, y diverge a propósito de la v3, cuyo `addEstimatedSteps(-n)` lanzaba en pausa; solo una sesión `finished` lo rechaza. Las dos reglas son distintas y conviene no leer una por la otra [fuente: `Domain/Session/Session.swift:195-218`; retro del Epic 1, S2]

**And** la consulta al sistema pasa por el `MotionPort` (`query→{steps, distanceM}|null`); el `GapEstimator` vive en el dominio puro y solo se invoca cuando el puerto **no da respuesta** — `null`, error o timeout. **Cualquier respuesta no nula es dato y corta la estimación**, aunque traiga menos pasos de los ya vistos: el sistema consolida su histórico con retraso y la consulta va unos pasos por detrás del stream, y `record` nunca resta, así que un acumulado menor no baja nada. "Vacío" no es un caso aparte de "sin dato" (R1, zanjado midiendo en el iPhone 14 el 2026-09-17). **Y un quinto caso de "sin respuesta" es un tramo de más de 7 días**, que **no se consulta** y pasa directo al estimador: ojo a que la condición de los 7 días mira el **tramo** (`[segmentStart, end]`) y la estimación se hace sobre el **gap** (`[backgroundedAt, end]`), así que un tramo viejo con un gap corto **sí estima** — decide `maxEstimableGapS`, no la antigüedad del tramo [fuente: `WalkTracker/Application/SessionStore+Reconciliation.swift:23-26`, `:46`, `:60-95`; spec-r1; **AD-8**, **AD-10** — AR-3 y AR-10 están derogados, `DEROGACIONES.md §5`]

**And** la consulta al sistema está acotada por el **timeout de reconciliación** de AD-8, leído de `formulas.json`. *(Al día 2026-09-20: **ya no es provisional**. Esta historia lo introdujo con valor provisional marcado y la **8.4 lo midió**; con la regla de Paul del 2026-09-14 quedó fijado en **1 s**, y `formulas.json` tiene hoy `"provisional": []`. Lo que esta línea describía como trabajo futuro está hecho.)* [AD-8, reubicación del 2026-09-13; `WalkTracker/Resources/formulas.json`; `8-4-medicion-referencia.md:104`, `:189`]

### Story 1.6: Recuperación foreground — wall-clock + Estimated Banner

As a caminante (usuario único),
I want que al volver a la app la sesión se recupere mostrando el tiempo real transcurrido y cualquier pasos estimados de forma transparente,
So que nunca me sienta engañado sobre el estado de mi caminata.

**Acceptance Criteria:**

**Given** una sesión activa y la app fue **forzada a cerrarse** (force-quit) o el sistema la mató
**When** **relanzo** la app
**Then** la sesión se recupera silenciosamente desde el snapshot, con `elapsedS` recomputado desde `startedAt` (el tiempo cerrado cuenta), y se muestra el indicador "Sesión recuperada" durante 3 s [fuente: capabilities.md#CAP-1, domain-model.md#38]

**Given** una sesión activa que solo estuvo **en background**, con el proceso vivo
**When** vuelvo a foreground
**Then** **no** se muestra el indicador "Sesión recuperada": no hubo nada que recuperar —la sesión nunca dejó de existir en memoria— y lo único que ocurre es la reconstrucción del gap de la historia 1.5. El indicador es **exclusivo del relanzamiento** [fuente: `WalkTracker/Application/SessionStore.swift:138-141`, `SessionStore+Recovery.swift:110`; spec-1-6, Boundaries congeladas, `EXPERIENCE.md` #95 frente a #84]

**Given** que la sesión recuperada incluye pasos estimados ("~")
**When** se muestra la UI en foreground
**Then** aparece el Estimated Banner descartable con los pasos estimados desglosados y marcados "~", coherente con UX-DR4 [fuente: UX-DR4, UX-DR5]

**Given** el Estimated Banner visible con pasos estimados
**When** el usuario toca "Descartar"
**Then** `stepsEstimated` vuelve a **0 entero** —el descarte es **global**: un solo contador para toda la sesión, no uno por gap— y las métricas se recomputan sin ellos. Se permite en `active` y en `paused`; solo una sesión `finished` lo rechaza [fuente: capabilities.md#CAP-3, `Domain/Session/Session.swift:205-218`; retro del Epic 1, S2]

**Given** una sesión activa que estuvo en background
**When** vuelvo a foreground
**Then** la reconstrucción por query (historia 1.5) se ejecuta ANTES de refrescar la UI, y la UI muestra el estado consolidado (medidos + estimados si los hubo)

**And** la recuperación usa el snapshot `activeSession` persistido `{startedAtMs, stepsMeasured, stepsEstimated, ...}` y es silenciosa (sin bloqueos ni pantallas de carga) [fuente: domain-model.md#98]

**And** si la app arranca con una sesión activa más antigua que el **umbral de sesión huérfana** de AD-18, se cierra recortada al último dato real, marcada `recovered: true` y sin logros ni celebración; el umbral vive en `formulas.json`. *(Al día 2026-09-20: **ya no es provisional, y no lo fijó una medición**. La 8.4 no pudo medirlo —no es observable en una caminata de 30 min— y se quedó en las **6 h** (`orphanSessionThresholdS: 21600`) como **valor decidido**. Salió de `provisional` igual: `formulas.json` tiene hoy `"provisional": []`.)* [AD-18, reubicación del 2026-09-13; `WalkTracker/Resources/formulas.json`; `8-4-medicion-referencia.md:105`, `:189`]

### Epic 2: Clima, motivación y calibración
Paul inicia cada sesión con un snapshot del clima y una frase motivacional, y puede recalibrar su zancada sin alterar el historial cerrado.
**FRs covered:** FR-5, FR-6, FR-13
**NFRs:** NFR-2, NFR-4, NFR-9
**ARs:** AR-1 (corrección WMO→rain), AR-12
**UX:** UX-DR1, UX-DR2, UX-DR4, UX-DR8 (flows 1, 5)

### Story 2.1: Clima snapshot al inicio de sesión (Open-Meteo)

As a caminante (usuario único),
I want que al iniciar una caminata se capture un snapshot del clima actual,
So that la sesión quede asociada a las condiciones en las que caminé, sin que la falta de red me impida salir.

**Acceptance Criteria:**

**Given** que toco "Iniciar caminata" con red disponible y permiso de ubicación concedido
**When** se inicia la sesión
**Then** se captura el snapshot `{tempC, feelsLikeC, condition, humidityPct, uvIndex, windKmh, capturedAt}` desde Open-Meteo y queda asociado a la sesión como `weather` [fuente: capabilities.md#CAP-5]

**Given** que estoy iniciando la sesión en modo avión o sin red
**When** se intenta capturar el clima
**Then** la sesión inicia **sin clima** (`weather` = null) sin bloquear — degradación limpia, no bloqueante [fuente: capabilities.md#CAP-5]

**Given** que el permiso de ubicación fue denegado
**When** se intenta capturar el clima
**Then** la sesión inicia sin clima y **no se vuelve a pedir permiso en cada sesión** [fuente: capabilities.md#CAP-5]

**Given** que el clima llega con condición lluviosa (código WMO de lluvia)
**When** se guarda el snapshot
**Then** la condición se mapea por código WMO → categoría interna `rain` (no por regex sobre strings localizados) [fuente: achievements.md; **AD-6** — es una de las **divergencias declaradas** frente a `domain.js`, que usa regex sobre string localizado: aquí el vector lleva el valor corregido y el JS falla a propósito]

**And** las coordenadas de geolocalización se redondean a **2 decimales** antes de la llamada y el timeout de Open-Meteo es de **3 s** [fuente: AR-12, capabilities.md#CAP-5]

**And** el snapshot se congela al iniciar (no se actualiza durante la sesión) [fuente: SPEC.md#FR-5]

### Story 2.2: Frase motivacional al iniciar sesión

As a caminante (usuario único),
I want ver una frase motivacional al empezar mi caminata,
So that tenga un empujón mental antes de salir.

**Acceptance Criteria:**

**Given** que inicio una sesión
**When** la sesión arranca
**Then** se muestra una frase del banco `quotes.json` (100 frases, empaquetado como asset local del bundle) en un overlay de 3–4 s [fuente: capabilities.md#CAP-6]

**Given** que existen frases en `recentQuoteIds` (últimas 20 mostradas)
**When** se selecciona la frase aleatoriamente
**Then** se excluyen las últimas 20; si todas están excluidas, se ignora el filtro (regla heredada de la PWA) [fuente: capabilities.md#CAP-6]

**Given** 20 sesiones consecutivas con frases mostradas
**When** se revisa la secuencia
**Then** no hay repetición de frases en ese período [fuente: capabilities.md#CAP-6]

**Given** el overlay de frase está visible
**When** el usuario hace tap sobre él
**Then** el overlay se descarta antes de los 4 s y la sesión ya está corriendo [fuente: capabilities.md#CAP-6]

**And** el overlay se presenta como hoja modal nativa con la frase en jerarquía dominante y Dynamic Type sin recortes; accesible por VoiceOver como contenido modal, descartable con un tap, y respetando Reduce Motion. **Los conceptos `role=dialog`, `aria-modal`, `focus ring` y `clamp()` son de la web y no aplican** [fuente: UX-DR6; AD-13, deroga los tokens en px de UX-DR2]

**And** el `quoteId` mostrado se guarda en la sesión y se registra en `recentQuoteIds` [fuente: domain-model.md#27]

### Story 2.3: Recalibración de zancada en Ajustes

As a caminante (usuario único),
I want ajustar mi zancada en Ajustes,
So que mis métricas de distancia sean más precisas sin alterar el historial ya cerrado.

**Acceptance Criteria:**

**Given** que abro la pantalla de Ajustes y veo el campo de zancada
**When** edito el valor de `strideM`
**Then** se guarda con validación en la frontera, que son **tres reglas distintas y no una**: **(a) rechazo duro** — debe ser > 0 y finita, y un campo vacío, no numérico, cero o negativo se rechaza con mensaje y no se persiste; **(b) tope derivado, también rechazo duro** — debe **caber en la fórmula de la distancia** (`MetricsCalculator.maxRepresentableStrideM`, derivado factor a factor del tope de pasos del agregado, **no** un máximo "razonable" de producto), porque comprobar que es finita no bastaba: `1e307` es finita, entraba, y hacía que `pasos × zancada` dejara de ser un número en cada caminata posterior, y su mensaje dice "no cabe" y no "tiene que ser mayor que cero"; **(c) aviso de rango humano, que no bloquea** — fuera de 0,3–1,2 m (rango **cerrado**: en el borde exacto no hay aviso) **se guarda igual**, con un aviso, porque es una regla de **producto** y no del dominio: cubre el dedazo real (0,067 por 0,67) sin quitarle a Paul el control de su app, y una zancada absurda pero representable —50 m— se sigue guardando [fuente: capabilities.md#CAP-13, domain-model.md#51, `Domain/Ports/AppSettings.swift:95-130`; spec-2-3, spec-b3 (hallazgo D3 de la retro del Epic 2); decisión de Paul, 2026-09-19]

**Given** que el campo de zancada está vacío o con un valor inválido (≤0, NaN, no numérico)
**When** intento guardar
**Then** se muestra mensaje de error y no se persiste el valor inválido [fuente: capabilities.md#CAP-13]

**Given** que recalibro la zancada a un nuevo valor
**When** reviso el historial de sesiones cerradas
**Then** las sesiones cerradas conservan su `strideM` **congelado** — recalibrar nunca reescribe historial [fuente: capabilities.md#CAP-13, domain-model.md#21]

**Given** que recalibro la zancada
**When** inicia la siguiente sesión
**Then** la nueva zancada se usa para los cálculos de distancia de esa sesión [fuente: capabilities.md#CAP-13]

**And** el campo de Ajustes sigue UX-DR4 (Settings Field) y el flujo de recalibración sigue UX-DR8 flow 5. La zancada es un **override opcional**, no un campo con valor: `AppSettings.strideM` es `nil` mientras Paul nunca la toque, y entonces la sesión nace con `formulas.defaultStrideM` —**el único sitio donde vive el 0,655**—. "Usar el valor por defecto" vuelve a `nil`, no escribe 0,655. Diverge a propósito de `domain-model.md:95`, que mete el default dentro de la config: duplicarlo en dos ficheros los deja divergir sin que nadie lo note [fuente: capabilities.md#CAP-13, `Domain/Ports/AppSettings.swift:37-52`; spec-2-3]

### Epic 3: Metas, logros y motivación
Paul persigue su meta semanal de km con un anillo de progreso y desbloquea logros al cerrar sesiones, con celebraciones que no interrumpen su caminata ni su música.
**FRs covered:** FR-7, FR-8
**NFRs:** NFR-9
**ARs:** AR-1 (corrección hora local logros), AR-12
**UX:** UX-DR1, UX-DR4, UX-DR5, UX-DR6, UX-DR8 (flows 1, 2, 4)
**Nota:** FR-12 (feedback) vive en Epic 4 — las celebraciones de este epic **consumen** ese canal.

### Story 3.1: Meta semanal configurable con anillo de progreso

As a caminante (usuario único),
I want fijar mi meta semanal de kilómetros y ver mi progreso en un anillo,
So que sepa cómo voy hacia mi objetivo cada semana.

**Acceptance Criteria:**

**Given** que abro Ajustes y veo el campo de meta semanal
**When** configuro un valor (p. ej. 15 km)
**Then** se guarda con validación en la frontera: > 0 y finito; valores ≤ 0 o no numéricos se rechazan con mensaje [fuente: capabilities.md#CAP-7, domain-model.md#51]

**Given** que no he configurado la meta
**When** se muestra el anillo de progreso
**Then** el valor por defecto es **10 km** [fuente: capabilities.md#CAP-7]

**Given** que tengo sesiones en distintos días de la semana actual
**When** se calcula el progreso
**Then** el anillo suma la distancia de las sesiones de la **semana ISO** (de lunes a domingo) calculada en **hora local del dispositivo**, y muestra el porcentaje de cumplimiento. El cálculo usa el **`AppCalendar` único** —`identifier = .iso8601`, `firstWeekday = 2`, `timeZone` = la del dispositivo—; nadie construye su propio `Calendar` y `Calendar.current` está prohibido [fuente: capabilities.md#CAP-7, domain-model.md#60; **AD-19** — resuelve la contradicción entre `domain-model.md §5` (UTC) y `§9` (hora local) **a favor de §9**, y es una de las divergencias declaradas de AD-6]

**Given** que el anillo muestra mi progreso
**When** la suma de la semana alcanza o supera la meta
**Then** el anillo muestra el 100 % y se dispara la celebración de meta — **una sola vez por semana** (no se re-dispara al refrescar) [fuente: capabilities.md#CAP-7]

**And** el GoalEngine evalúa el logro `weekly_goal` al cumplirse la meta (no en el loop de cierre de sesión) [fuente: achievements.md#11]

**And** el anillo es una de las **tres únicas piezas dibujadas a mano** que AD-13 autoriza (junto al gráfico de tendencia y la insignia): centrado, dominante en la pantalla, con su etiqueta accesible explícita — un `Canvas` no la trae. Sin diámetro ni tamaños fijos en px [fuente: UX-DR4; AD-13]

### Story 3.2: Evaluación de logros al cierre de sesión (AchievementEngine)

As a caminante (usuario único),
I want que al terminar una caminata se evalúen automáticamente mis logros,
So que vaya desbloqueando reconocimientos a medida que progreso.

**Acceptance Criteria:**

**Given** que finalizo una sesión
**When** se cierra la sesión
**Then** el `AchievementEngine` evalúa las reglas de los 14 logros del catálogo contra la sesión cerrada [fuente: capabilities.md#CAP-8, achievements.md]

**Given** que una sesión cumple la regla de un logro no desbloqueado (p. ej. `first_km` con `distanceM ≥ 1000`)
**When** se evalúa
**Then** el logro se desbloquea con `unlockedAt` (ISO-8601) y se dispara la celebración [fuente: achievements.md#7-8, achievements.md#28]

**Given** que un logro ya está desbloqueado
**When** se evalúa una sesión posterior que también cumple la regla
**Then** el logro **no se re-dispara** (no hay celebración repetida) [fuente: capabilities.md#CAP-8]

**Given** que un logro fue desbloqueado por una sesión
**When** esa sesión se elimina del historial (CAP-15)
**Then** el logro **no se revoca** — permanece desbloqueado, ni siquiera al borrar la sesión que lo desbloqueó (CAP-15 recalcula totales y el progreso de los **no** desbloqueados, y deja intactos los ya conseguidos) [fuente: achievements.md#3; **AD-17**]

**And** la evaluación ocurre en **un único punto** —al finalizar la sesión, dentro de la misma transacción que la persiste— y nunca al abrir el historial ni al pintar el grid. `achievements.json` tiene **un solo escritor**, `AchievementsStore`; cualquier otro lo lee a través de él, nunca del disco [**AD-17**, **AD-16**]

**Given** una sesión con `weather` = null (sin clima)
**When** se evalúan los logros climáticos (`rain_walker`, `hot_walker`, `cold_walker`)
**Then** no se evalúan como cumplidos [fuente: achievements.md#25]

**And** los logros temporales (`early_bird` entre **05:00 y 07:59**, `night_walker` entre **21:00 y 23:59**) y las rachas se evalúan en **hora local** del dispositivo, no UTC. Las dos franjas son `comparison: "between"` sobre `startHourLocal`, con `threshold: [5, 7]` y `[21, 23]`, y **`between` es inclusiva en los dos extremos**: la franja es de horas locales enteras, así que incluye toda la hora del extremo superior [fuente: achievements.md#27, `Resources/achievements.json`; **AD-5**, enmienda del esquema del 2026-09-12; **AD-19**]

**And** los logros acumulados (`marathon_42km` Σ ≥ 42000 m, `consistency_30` ≥ 30 sesiones) cuentan todas las sesiones `source: "ios"` [fuente: achievements.md#24]

### Story 3.3: Pantalla de logros — grid locked/unlocked con progreso

As a caminante (usuario único),
I want ver la lista de mis logros con su estado y progreso,
So que sepa qué reconocimientos he ganado y qué me falta para los próximos.

**Acceptance Criteria:**

**Given** que abro la pantalla de Logros (icono 🏆)
**When** se renderiza el grid
**Then** se muestran los 14 logros del catálogo con su estado: unlocked (icono + nombre) o locked (mostrado como bloqueado) [fuente: achievements.md#28]

**Given** que un logro está desbloqueado
**When** se muestra en el grid
**Then** se ve `unlockedAt` y el badge correspondiente [fuente: achievements.md#28]

**Given** que un logro está bloqueado
**When** se muestra en el grid
**Then** se ve su progreso `0.0..1.0` hacia el desbloqueo (p. ej. `marathon_42km` muestra km acumulados vs 42 km) [fuente: achievements.md#28]

**Given** que no hay ningún logro desbloqueado aún
**When** abro la pantalla de Logros
**Then** se muestra el grid completo en locked con sus progresos (no un empty state: los 14 siempre visibles) [fuente: UX-DR5]

**And** el grid sigue UX-DR4 (Achievement Badge) y es accesible: logros locked con `aria-label` de bloqueo, VoiceOver lee nombre y estado [fuente: UX-DR6]

### Story 3.4: Celebración de meta y logros (no bloqueante)

As a caminante (usuario único),
I want que al cumplir mi meta o desbloquear un logro haya una celebración visible y sonora,
So que me motive sin interrumpir mi caminata ni mi música.

**Acceptance Criteria:**

**Given** que cruzo el 100 % de mi meta semanal
**When** se dispara la celebración de meta
**Then** se muestra un toast no bloqueante de celebración y suena/haptica el feedback correspondiente — sin interrumpir la música en reproducción [fuente: capabilities.md#CAP-7, UX-DR4, UX-DR7]

**Given** que se desbloquea un logro al cierre de sesión
**When** se dispara la celebración
**Then** se muestra la celebración visual + sonora + háptica del Achievement Badge [fuente: capabilities.md#CAP-8, achievements.md#29]

**Given** que la celebración de meta está visible
**When** el usuario sigue caminando o toca el toast
**Then** el toast se descarta sin bloquear la sesión activa — no es modal, no detiene el cronómetro [fuente: UX-DR4]

**Given** que se desbloquean varios logros en la misma sesión
**When** se muestran las celebraciones
**Then** se encolan y muestran una tras otra, sin solaparse ni bloquear [fuente: UX-DR4]

**And** el canal de celebración **consume** el feedback del Epic 4 (beep + háptica), que es el dueño del canal transversal — este epic no implementa sonido/háptica directamente [fuente: epics.md#Epic 4, AR-13]

**And** los toasts de celebración son accesibles: `role=status aria-live=polite`, Reduce Motion sin animación [fuente: UX-DR6]

### Epic 4: Feedback háptico y sonoro (mini-epic transversal)
Paul recibe un beep respetuoso y una vibración en los momentos clave — inicio, cada km, meta cumplida, logro desbloqueado — sin interrumpir la música en reproducción. Es un canal de eventos transversal que E1 y E3 consumen; este epic lo posee y lo expone.
**FRs covered:** FR-12
**NFRs:** NFR-9
**ARs:** AR-10 (puertos), AR-12 (AD-18 quotes/feedback), AR-13 (canal háptico CoreHaptics vs web se resuelve como adapter tras puerto)
**UX:** UX-DR4 (Session Controls), UX-DR7 (beep feedback primario, volumen respetuoso)
**Nota:** mini-epic por decisión de mesa (party mode 2026-08-01): el feedback corta a través de E1/E3/E4; nace en su propio epic para que su diseño sea consistente y reutilizable.

### Story 4.1: Canal de feedback — puerto y disparo de eventos

As a caminante (usuario único),
I want que la app dispare feedback en los momentos clave de mi caminata,
So que reciba una confirmación discreta de inicio, km, meta y logro sin tener que mirar la pantalla.

**Acceptance Criteria:**

**Given** que se define el contrato del canal de feedback
**When** se expone el `FeedbackPort`
**Then** ofrece un punto único de disparo por evento: inicio de sesión, cruce de cada km, meta cumplida, logro desbloqueado [fuente: capabilities.md#CAP-12]

**Given** que inicio una sesión (historia 1.1)
**When** la sesión arranca
**Then** se dispara el evento de feedback de inicio a través del puerto [fuente: capabilities.md#CAP-12]

**Given** que cruzo un km completo durante la sesión
**When** la distancia acumulada pasa el umbral del km siguiente
**Then** se dispara el evento de feedback de km a través del puerto [fuente: capabilities.md#CAP-12]

**Given** que se cumple la meta semanal (Epic 3)
**When** la meta se cruza
**Then** se dispara el evento de feedback de meta a través del puerto [fuente: capabilities.md#CAP-12]

**Given** que se desbloquea un logro al cierre de sesión (Epic 3)
**When** se evalúa el logro
**Then** se dispara el evento de feedback de logro a través del puerto [fuente: capabilities.md#CAP-12]

**And** el `FeedbackPort` vive en el dominio (puerto), los adapters en el borde; el dominio no conoce CoreHaptics ni AVFoundation — el canal háptico vs sonoro se resuelve como adapter tras puerto [fuente: AR-10, AR-13]

**And** E1 (inicio/km) y E3 (meta/logro) **consumen** este puerto — este epic es el dueño del canal [fuente: epics.md#Epic 4]

### Story 4.2: Háptica nativa (CoreHaptics) y sonido respetuoso con música

As a caminante (usuario único),
I want que el feedback se sienta en el teléfono con vibración y sonido corto,
So que note los eventos incluso con la música sonando y pueda apagar el sonido si quiero.

**Acceptance Criteria:**

**Given** que un evento de feedback se dispara en un dispositivo físico
**When** el adapter procesa el evento
**Then** produce háptica (CoreHaptics) y, si el sonido está habilitado, un sonido corto — sin interrumpir la música en reproducción (sin ducking agresivo) [fuente: capabilities.md#CAP-12]

**Given** que el evento de feedback es de inicio, km, meta o logro
**When** se reproduce el feedback
**Then** se usan sonidos cortos de volumen respetuoso, coherentes con UX-DR7 [fuente: UX-DR7]

**Given** que abro Ajustes
**When** veo el toggle de sonido
**Then** puedo activar/desactivar `soundEnabled`; desactivado, los eventos producen solo háptica (sin sonido) [fuente: capabilities.md#CAP-12]

**Given** que `soundEnabled` está desactivado
**When** se dispara un evento
**Then** solo hay háptica, nunca sonido [fuente: capabilities.md#CAP-12]

**And** el adapter de háptica (CoreHaptics) y el de sonido (AVFoundation) son adapters del borde tras el `FeedbackPort` — el dominio no conoce ninguna de las dos tecnologías [fuente: AR-10, AR-13]

### Epic 5: Historial, persistencia y respaldos
Las sesiones se guardan de forma garantizada en el dispositivo y Paul puede consultar su historial con totales y tendencia, exportar respaldos y eliminar sesiones.
**FRs covered:** FR-9, FR-10, FR-14, FR-15
**NFRs:** NFR-2, NFR-4, NFR-5
**ARs:** AR-9, AR-10, AR-12
**UX:** UX-DR4, UX-DR5, UX-DR6, UX-DR8 (flows 3, 5)

### Story 5.1: Persistencia garantizada en sandbox (StoragePort)

As a caminante (usuario único),
I want que mis sesiones, logros y configuración queden guardados de forma permanente en el dispositivo,
So que mi historial sobreviva a reinicios sin que yo tenga que hacer respaldos manuales.

**Acceptance Criteria:**

**Given** que hay sesiones finalizadas, logros desbloqueados y configuración guardada
**When** reinicio el iPhone
**Then** historial, logros y config aparecen íntegros — la evicción de la PWA (home-screen) no aplica a una app instalada con sandbox [fuente: capabilities.md#CAP-9]

**Given** que tengo una sesión activa y fuerzo el cierre de la app (force-quit)
**When** la reabro
**Then** la sesión se recupera silenciosamente desde el snapshot `activeSession` (`startedAtMs, stepsMeasured, stepsEstimated, ...`) [fuente: capabilities.md#CAP-9, domain-model.md#98]

**Given** que una sesión se finaliza
**When** se guarda
**Then** queda como registro **inmutable** en el store `sessions` (`{id, startedAt, endedAt, stepsMeasured, stepsEstimated, strideM, ...}`) [fuente: domain-model.md#101, capabilities.md#CAP-9]

**And** el storage se accede por el `StoragePort`. La forma concreta la fija **AD-9**: ficheros JSON `Codable` en Application Support con **escritura atómica** (temp + rename), uno por preocupación —`sessions.json`, `achievements.json`, `settings.json`, `activeSession.json`— cada uno con `schemaVersion`. **AD-16**: cada fichero tiene exactamente un tipo que lo escribe; los demás lo leen a través de su dueño, nunca del disco. `domain-model.md §8` define el snapshot en milisegundos y la conversión a segundos ocurre en el adapter, nunca dentro del dominio [AD-9, AD-16]

**And** **esta historia no parte de cero: `StoragePort` ya existe y cubre 2 de los 4 ficheros.** Al cerrar el Epic 2 el puerto tiene **seis métodos** —`loadActiveSession` / `saveActiveSession` / `clearActiveSession` / `setAsideActiveSession` para `activeSession.json` (dueño `SessionStore`), y `loadSettings` / `saveSettings` para `settings.json` (dueño `SettingsStore`)—, y hay **sustrato reutilizable**: `JSONFileStore` absorbió la escritura atómica, el apartado de ficheros corruptos y los nombres de fichero, y lo usan los dos adapters a través de un compositor puro. Lo que la 5.1 añade son `sessions.json` y `achievements.json` con sus dueños, **no el mecanismo**; y hereda dos reglas ya vigentes: un fichero ilegible **se aparta, no se destruye**, y `nil` ("no hay nada") no es lo mismo que un error de lectura ("hay algo que no se pudo leer"), que **no deja escribir** (B-1) [fuente: `Domain/Ports/StoragePort.swift:32-65`, `WalkTracker/Adapters/Persistence/JSONFileStore.swift`; retro del Epic 1, S8]

**And** **el snapshot de la sesión activa se guarda por evento y por muestras, nunca con un temporizador** (AD-21): al iniciar, al pausar, al reanudar, al pasar a background y al reconciliar, más con la muestra del podómetro que llegue al menos `autosaveIntervalS` (10 s) después del último guardado. **Los 10 s son el espaciado mínimo entre escrituras por muestra, no una cadencia**: quieto no hay muestras y no hay escrituras, y por eso no hay un "cada 10 s" que gastar batería contra el presupuesto de AD-21. Se borra al finalizar [fuente: `WalkTracker/Application/SessionStore.swift:29-32`, `SessionStore+StepCounting.swift:90`; **AD-9**, **AD-21**; retro del Epic 1, S4]

### Story 5.2: Historial — lista descendente + totales semana/mes + tendencia

As a caminante (usuario único),
I want ver mi historial de sesiones ordenado y con totales de semana y mes,
So que pueda revisar mi progreso y mi tendencia a lo largo del tiempo.

**Acceptance Criteria:**

**Given** que abro la pantalla de Historial
**When** se renderiza la lista
**Then** las sesiones aparecen **descendentes** (más reciente primero) con fecha, distancia, duración y ritmo [fuente: capabilities.md#CAP-10]

**Given** que una sesión del historial tiene pasos estimados
**When** se muestra en la lista
**Then** se marca con "~" para distinguirla de las sesiones medidas [fuente: capabilities.md#CAP-10]

**Given** que hay 5 sesiones en la semana y el mes actuales
**When** se muestran los totales
**Then** los totales de semana y mes cuadran exactamente con la suma de las sesiones [fuente: capabilities.md#CAP-10]

**Given** que hay más de una sesión
**When** se muestra la tendencia
**Then** se ve un gráfico de tendencia simple de la distancia a lo largo del tiempo [fuente: capabilities.md#CAP-10]

**Given** que no hay ninguna sesión registrada
**When** abro el Historial
**Then** se muestra el empty state "Aún no hay sesiones registradas" [fuente: capabilities.md#CAP-10, UX-DR5]

**And** las filas del historial siguen UX-DR4 (History Row) y el flujo de tendencia sigue UX-DR8 flow 3 [fuente: UX-DR4, UX-DR8]

### Story 5.3: Export CSV/JSON + re-import (share sheet)

As a caminante (usuario único),
I want exportar mi historial como archivo y poder restaurarlo,
So que tenga un respaldo voluntario de mis datos que pueda abrir en Numbers/Excel o recuperar si cambio de dispositivo.

**Acceptance Criteria:**

**Given** que abro la opción de exportar desde Ajustes
**When** toco "Exportar historial"
**Then** se abre el share sheet de iOS con el historial en **JSON** y **CSV** [fuente: capabilities.md#CAP-14]

**Given** que exporto el historial en CSV
**When** abro el archivo en Numbers o Excel
**Then** se lee sin pelear, con el contrato exacto que fija **AD-9** — columnas en este orden `fecha;hora;duracion_s;pasos_medidos;pasos_estimados;distancia_m;ritmo_s_km;fuente`, **separador de campo `;` y decimal `,`** (la UI está en español y la coma decimal rompe el CSV separado por comas), cabecera siempre presente, UTF-8 con BOM [fuente: capabilities.md#CAP-14; **AD-9**]

**And** el **JSON** de export **no tiene serializador propio**: reutiliza la serialización de `sessions.json`, para que no haya dos formas de escribir el mismo dato divergiendo en silencio. El **CSV sí es un segundo serializador**, y por eso su contrato está fijado arriba en vez de dejarse a la historia [**AD-9**]

**Given** que exporté un JSON del historial
**When** importo ese JSON de vuelta en la app
**Then** el historial se **restaura íntegro** (prueba de respaldo/restauración). El **import acepta solo JSON, nunca CSV**: el CSV es un formato de salida hacia hojas de cálculo, no un formato de entrada [fuente: capabilities.md#CAP-14; **AD-9**]

**Given** que tengo datos actuales en la app e importo un JSON de respaldo
**When** el import completa
**Then** las sesiones del respaldo quedan restauradas sin romper los registros existentes (verificación de merge/restauración coherente)

**And** **no** existe el aviso de "respaldo >30 días" (RF-17): con storage garantizado (FR-9) esa mitigación pierde su razón de ser y se retira del producto [fuente: capabilities.md#CAP-14]

### Story 5.4: Eliminar sesiones individuales

As a caminante (usuario único),
I want eliminar una sesión concreta de mi historial,
So que pueda depurar registros que no quiero conservar.

**Acceptance Criteria:**

**Given** que veo el historial
**When** toco el botón de eliminar (44×44 pt) de una sesión
**Then** se pide **confirmación** antes de borrar [fuente: UX-DR4]

**Given** que confirmo la eliminación de una sesión
**When** se elimina
**Then** la sesión se remueve de la lista, de los totales de semana/mes, del anillo semanal y de los acumulados de logros **no desbloqueados aún** [fuente: capabilities.md#CAP-15]

**Given** que un logro ya estaba desbloqueado y su sesión origen se elimina
**When** se elimina la sesión
**Then** el logro **no se revoca** — permanece desbloqueado [fuente: capabilities.md#CAP-15, achievements.md#3]

**Given** que quiero eliminar una sesión
**When** intento deslizar la fila (swipe)
**Then** se revela la acción destructiva nativa de iOS y borra tras confirmación explícita — el **swipe ES el gesto**, y el icono de papelera embebido en la fila queda prohibido (era el antipatrón B-11 de la validación de mockups). El objetivo táctil mide ≥ 44 pt, verificable [AD-20; deroga la prohibición de swipe de UX-DR7]

### Epic 6: Lo que Apple recibe — Salud y recordatorios
Al finalizar una sesión, Paul sabe que su caminata queda escrita en Apple Salud como workout de caminata (distancia y pasos) y que su recordatorio semanal de meta está reprogramado — dos writes deterministas, idempotentes, sin pantalla nueva, que integran el producto con el ecosistema Apple.
**FRs covered:** FR-11, FR-16
**NFRs:** NFR-1, NFR-7, NFR-8
**ARs:** AR-2, AR-4, AR-7, AR-8, AR-10, AR-11
**UX:** UX-DR5
**Nota:** Dividido del antiguo Epic 5 por decisión de la mesa (party mode 2026-08-01): HealthKit+recordatorios comparten el patrón "writes deterministas al cierre de sesión"; Live Activity se fue sola (ver Epic 7).

### Story 6.1: Escritura de workout en Apple Salud al finalizar

As a caminante (usuario único),
I want que al terminar mi caminata quede registrada como workout en Apple Salud,
So que mis datos estén en el ecosistema Apple sin hacer nada manual (adiós CSV + Shortcuts).

**Acceptance Criteria:**

**Given** que finalizo una sesión y el permiso de Salud está concedido
**When** se cierra la sesión
**Then** se escribe un workout de tipo caminata en Apple Salud con **distancia, pasos y duración** de la sesión [fuente: capabilities.md#CAP-11]

**Given** que la sesión se finaliza
**When** se intenta escribir el workout
**Then** el write ocurre **una sola vez** al finalizar (dato inmutable completo), nunca por partes ni retries duplicados, y la petición de permiso va precedida de pre-pantalla explicativa [**AD-11**]

**And** si HealthKit está denegado o la escritura falla, **la sesión se guarda local igual** y el resumen muestra "no sincronizado" — nunca un error: es la fila de HealthKit de la tabla única de degradación [**AD-11**]

**Given** que la app pide permiso de Salud por primera vez
**When** se solicita el permiso
**Then** se muestra antes una **pre-pantalla explicativa** (qué se escribirá y por qué), no se pide en frío [fuente: capabilities.md#CAP-11, AR-7]

**Given** que el usuario denegó el permiso de Salud
**When** finaliza una sesión
**Then** la sesión se guarda **localmente igual** y la app sigue funcionando completa — sin bloqueo ni pantallas de error [fuente: capabilities.md#CAP-11]

**And** el write pasa por el **`HealthPort`** —así se llama en el conjunto cerrado de 11 puertos de AD-10— con un **`HealthAdapter`** en `Adapters/Health/` que es el único punto del código que conoce `HKWorkoutBuilder`; el dominio solo expone el puerto [**AD-10**; AR-2 y AR-10 están **derogados**: no hay plugin `walktracker-kit` ni adapters `Capacitor*`, `DEROGACIONES.md §5`]

**And** la app **solo escribe** en Salud; no lee datos de Salud (non-goal explícito) [fuente: capabilities.md#CAP-11]

### Story 6.2: Recordatorio semanal de meta (notificaciones locales)

As a caminante (usuario único),
I want recibir un recordatorio semanal sobre el estado de mi meta,
So que sepa cuánto me falta sin abrir la app.

**Acceptance Criteria:**

**Given** que el permiso de notificaciones está concedido
**When** se programa el recordatorio
**Then** se agenda una notificación local semanal con el estado de la meta (p. ej. domingo por la tarde: "Te faltan 2 km esta semana") a través del **`NotificationPort`**, implementado por un adapter sobre `UserNotifications` del SDK [fuente: capabilities.md#CAP-17; **AD-10** — `@capacitor/local-notifications` desaparece con AR-8, y el proyecto no tiene dependencias de terceros, `DEROGACIONES.md §5`]

**Given** que el recordatorio ya está programado (p. ej. de la última sesión)
**When** se reprograma al finalizar una sesión o al abrir la app
**Then** se hace **cancel → schedule** (idempotente: nunca hay dos recordatorios duplicados), y el cálculo de "esta semana" usa el **`AppCalendar` único** —ISO-8601, lunes como primer día, zona horaria del dispositivo—: nadie construye su propio `Calendar` y `Calendar.current` está prohibido [**AD-19**, **AD-11**]

**Given** que el recordatorio fue programado
**When** la app está cerrada y llega el momento
**Then** la notificación llega con la app cerrada, respetando el permiso de notificaciones [fuente: capabilities.md#CAP-17]

**Given** que el usuario denegó el permiso de notificaciones
**When** se intenta programar el recordatorio
**Then** la app funciona completa sin recordatorios — degradación limpia [fuente: capabilities.md#CAP-17]

**And** el programador pasa por el `NotificationPort` (`rescheduleWeeklyReminder` idempotente), disparado desde el `GoalEngine` al finalizar sesión y al abrir la app [fuente: AR-7, AR-10]

### Epic 7: Live Activity en pantalla de bloqueo

*(Reescrito el 2026-09-12. El epic entero estaba escrito para Capacitor: un bridge dentro de
`walktracker-kit` alimentado desde el WebView. Nada de eso existe ya — y `walktracker-kit` lo borra
del árbol la historia 8.5.)*

Paul ve las métricas de su caminata en la pantalla de bloqueo, sin desbloquear el teléfono.

**FRs covered:** FR-17
**NFRs:** NFR-1, NFR-8
**ADs:** AD-15 (la extensión no tiene dominio), AD-21 (presupuesto de energía), AD-11 (degradación), AD-13 (Liquid Glass)
**UX:** UX-DR4 — **con la salvedad de abajo**
**Riesgo:** medio-bajo. El iPhone 14 no tiene Dynamic Island: se valida el layout de pantalla de bloqueo y la isla se limita a compilar. `Activity.request`/`update`/`end` ya están escritos en la capa nativa que rescató la historia 8.6 (`LiveActivityAdapter`), y **Paul los verificó en el iPhone 14 el 2026-09-12**: la actividad se inicia y termina. Queda por validar el ciclo por eventos (7.2) y el layout con Liquid Glass (7.3).

> ⚠️ **Encargo pendiente para UX.** `UX-DR4` documenta un layout de Live Activity diseñado como
> tarjeta plana de iOS 17. Desde iOS 26 la Live Activity de pantalla de bloqueo **también hereda
> Liquid Glass**. El layout hay que rehacerlo antes de implementar 7.3; implementarlo tal como está
> documentado sería construir el mockup viejo con la bendición aparente de UX.

### Story 7.1: Widget Extension y contrato de `ContentState`

As a caminante (usuario único),
I want que la app pueda publicar una Live Activity,
So that mis métricas puedan llegar a la pantalla de bloqueo.

**Acceptance Criteria:**

**Given** el proyecto SwiftUI de la historia 8.5
**When** se añade el soporte de Live Activity
**Then** existe un target **Widget Extension** (`WalkTrackerActivity`) y un target **`Shared`** con el tipo de `ContentState`; el `Info.plist` de la app declara **`NSSupportsLiveActivities`**, sin la cual la Live Activity no arranca [AD-15]

**Given** el contrato entre app y extensión
**When** se define el `ContentState`
**Then** lleva **valores ya formateados** más `startedAt`, cabe en el **presupuesto de 4 KB** de ActivityKit, y viaja por `request`/`update` — **no por App Group ni por disco** [AD-15]

**Given** la extensión
**When** se revisa qué puede importar
**Then** importa **solo `Shared`**: no calcula, no lee ficheros y **no importa `Domain`**. Su único cálculo permitido es animar el cronómetro con `Text(timerInterval:)`, y existe para no gastar actualizaciones en refrescar un reloj [AD-15, AD-21]

**And** el `LiveActivityPort` ofrece `start / updateState / stop` y es el único camino por el que la app habla con ActivityKit [AD-10]

### Story 7.2: Ciclo de vida, alimentado por eventos

As a caminante (usuario único),
I want que la tarjeta de la pantalla de bloqueo siga mi caminata de principio a fin,
So that no tenga que desbloquear el teléfono para saber cómo voy.

**Acceptance Criteria:**

**Given** que inicio una sesión
**When** la sesión arranca
**Then** `SessionStore` —único escritor— pide al `LiveActivityPort` que la cree con las métricas iniciales [CAP-18, AD-7]

**Given** una sesión activa con el teléfono bloqueado
**When** cambian las métricas
**Then** la Live Activity se actualiza **por evento** —cambio de kilómetro, pausa, reanudación, fin— y **nunca de forma periódica**; el reloj lo anima la extensión, con coste cero de actualizaciones [AD-21]

**Given** que pauso la sesión
**When** la pausa se registra
**Then** la tarjeta muestra un estado visible de pausa: no se cierra, cambia de estado [CAP-18]

**Given** que finalizo la sesión
**When** la sesión se cierra
**Then** la Live Activity se cierra [CAP-18]

**Given** que la extensión falla, el sistema la rechaza o el usuario tiene las Live Activities desactivadas
**When** se intenta crear
**Then** **se omite y no es un fallo de sesión**: el conteo y la sesión siguen al 100 % — es la fila "Live Activity no disponible" de la tabla de degradación [AD-11]

**And** app y tarjeta muestran **el mismo número** porque hay **una sola fuente**: el `ContentState` que publica `SessionStore`. La extensión no recalcula nada [AD-15, AD-22]

**Given** la Live Activity actualizándose por evento durante una caminata de 30 min con la pantalla bloqueada
**When** se repite la medición de batería de la **8.4**
**Then** la batería sigue cayendo **≤ 5 %** en los 30 min y WalkTracker no aparece como consumidor destacado en Ajustes → Batería: la Live Activity no rompe el presupuesto de AD-21 [NFR-8, AD-21, reubicación del 2026-09-13]

### Story 7.3: Layout de pantalla de bloqueo (y la isla, que solo compila)

As a caminante (usuario único),
I want que la tarjeta se lea de un vistazo,
So that mirar el teléfono un segundo me baste.

**Acceptance Criteria:**

> **Bloqueada hasta que UX entregue el layout con Liquid Glass** (ver el encargo en la cabecera del epic).

**Given** una Live Activity activa en pantalla de bloqueo
**When** se renderiza
**Then** muestra pasos, distancia y tiempo en formato glanceable, legible de un vistazo y sin desbloquear [CAP-18]

**Given** que se compila contra el SDK de iOS 26
**When** se construye el layout
**Then** usa controles y estilos de texto del sistema y **hereda Liquid Glass**; no se dibujan materiales ni cristales a mano [AD-13]

**Given** que el iPhone 14 no tiene Dynamic Island
**When** se compila el layout de la isla
**Then** **compila y ahí acaba el criterio**: no hay hardware para validarla y no se invierte más esfuerzo en ella. El layout de pantalla de bloqueo sí se valida en dispositivo [CAP-18]

**Given** el contenido de la tarjeta
**When** se decide qué se muestra
**Then** solo magnitudes que el dominio produce; una métrica ausente se representa como tal, nunca como `0` [AD-22]

**And** accesibilidad: etiquetas explícitas que digan la magnitud completa ("3,2 kilómetros"), y los pasos estimados anunciados **como estimados** [UX-DR6 traducido, AD-6]

### Epic 8: Fundaciones del sustrato SwiftUI

*(Reescrito el 2026-09-12. El epic se llamaba "Validación de la apuesta nativa" y existía para
demostrar que Capacitor era viable. Esa apuesta ya no se juega: OQ-1 se reabrió y el sustrato es
SwiftUI nativo. Lo que queda de fundacional es distinto — y sigue corriendo PRIMERO, **salvo su gate final (8.4), que mide una sesión real y corre después del Epic 1** (reubicación del 2026-09-13).)*

Levantar el sustrato sobre el que se construye todo lo demás: el proyecto SwiftUI limpio, la capa
nativa rescatada, y el arnés que demuestra que el dominio portado se comporta como el validado en
producción. Sin esto, cada epic posterior improvisa su propia versión de la verdad.

**FRs covered:** ninguno directamente — es sustrato
**NFRs:** NFR-5 (dominio preservado), NFR-6 (hexagonal), NFR-7 (licencias), NFR-8 (batería)
**ADs:** AD-1, AD-2, AD-3, AD-4, AD-5, AD-6, AD-12, AD-23, AD-24
**Deroga:** AR-1, AR-2, AR-6, AR-8, AR-9 (ver `DEROGACIONES.md §5`)

#### Orden de ejecución

`8.5 → 8.6 → 8.7 → 8.3`, y después **Epic 1 (1.1–1.6) → 8.4**, antes de los epics 2–7. Los números ya no son el orden: es el precio de no reciclar IDs.

**Por qué 8.4 va detrás del Epic 1** (2026-09-13): sus criterios miden una sesión con conteo continuo, `stepsEstimated = 0` y reconstrucción del background, que no existen hasta 1.1–1.6. Y hay una dependencia circular: 8.4 **fija** el timeout de reconciliación y el umbral de sesión huérfana que 1.5 y 1.6 **usan**. Se rompe así: el Epic 1 arranca con valores provisionales en `formulas.json` y 8.4 los fija. *(Al día 2026-09-20: **ejecutado y cerrado**, y no "por los medidos" en plural — el timeout se **midió** (1 s) y el umbral de huérfana se **decidió** (6 h), porque no es medible en una caminata de 30 min. `formulas.json` tiene hoy `"provisional": []` y sus cuatro constantes fijadas.)* [`sprint-change-proposal-2026-09-13.md`; `WalkTracker/Resources/formulas.json`; `8-4-medicion-referencia.md:104-105`, `:189`]
#### Historias anuladas — fuera del tracking

| ID | Título | Por qué |
|---|---|---|
| ~~8.1~~ | Montaje Capacitor — web v3 en WebView + plugin scaffold | Figuraba como `done` sobre un sustrato que **AD-1 derogó**. El trabajo equivalente vive en 8.5, 8.6 y 8.7 |
| ~~8.2~~ | Build local en dispositivo + keep-awake | Su mecanismo (`pnpm cap run ios`) desaparece con Capacitor. El build local a dispositivo es la envoltura operativa del spine. **El wake lock, en cambio, no tiene destino: ver la nota de abajo** |

> ⚠️ **El wake lock está abierto, y esta tabla decía lo contrario.** Hasta el 2026-09-20 la fila de
> la 8.2 afirmaba que *"el wake lock sobrevive como `WakeLockPort` (AD-10) en Epic 1"*. **Es falso:**
> el Epic 1 cerró con sus seis historias en `done` y **sin `WakeLockPort`** —ninguna lo asumió y la
> 1.6 lo excluye explícitamente en sus Boundaries—, y de los 11 puertos del conjunto cerrado de
> AD-10 **existen 9**: faltan `WakeLockPort` y `NotificationPort` (este último tiene dueño, la
> historia 6.2).
>
> **Qué hacer con él no se decide aquí.** Es la **pregunta abierta Q-3** de la retrospectiva del
> Epic 1: *¿`WakeLockPort` sigue siendo necesario, ahora que el conteo funciona con la pantalla
> bloqueada? Si lo es, ¿en qué epic?* Hasta que Paul la responda, el puerto **no tiene historia
> dueña** y AD-10 mantiene su conjunto cerrado de 11 con dos sin implementar.
> [`epic-1-retro-2026-09-14.md`, hallazgo S5 y Q-3; `Domain/Ports/`]

**Los IDs 8.1 y 8.2 no se reutilizan.** No aparecen en `sprint-status.yaml`: el vocabulario del
generador es `backlog · ready-for-dev · in-progress · review · done` y ninguno significa "anulada",
así que el tracking sigue la regla de listar solo trabajo vivo. El registro de la anulación vive
aquí y en los propios ficheros de historia, que se conservan con banner. [`DEROGACIONES.md §1`]



### Story 8.5: Proyecto SwiftUI y limpieza del árbol

As a desarrollador,
I want un proyecto Xcode SwiftUI limpio y un único árbol de producto,
So that cada build sepa qué está compilando y no haya tres sustratos compitiendo.

**Acceptance Criteria:**

**Given** el repositorio con los restos de Capacitor y Flutter
**When** se completa la historia
**Then** existe un proyecto Xcode con tres targets —app, `Shared`, Widget Extension— con deployment target **26.0** y sin un solo `if #available` hacia versiones anteriores [AD-2]

**Given** el proyecto creado
**When** se revisa el árbol
**Then** han desaparecido `ios/App/`, `ios/capacitor-cordova-ios-plugins/`, `www/`, `adapters/`, `capacitor.config.json` y `walktracker-kit/`; y `domain.js`, `motivation.js`, `climate.js`, `storage.js` y `test/` **permanecen congelados** como referencia de contraste [AD-23]

**Given** el target de la app
**When** se inspecciona `Info.plist` y los entitlements
**Then** están `NSMotionUsageDescription`, `NSHealthUpdateUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSSupportsLiveActivities` y el entitlement de HealthKit; el bundle id es `com.walktracker.app` [AD-1, AD-15]

**Given** el esquema de compilación
**When** se compila
**Then** *strict concurrency* completa está activada y el build pasa sin warnings de aislamiento [AD-12]

**And** `Domain/` no puede importar frameworks de plataforma: un `import SwiftUI` o `import CoreMotion` ahí es un fallo de build, no una nota de revisión [AD-3]

### Story 8.6: Extracción de la capa nativa desde `feature/flutter-substrate`

As a desarrollador,
I want rescatar las 446 líneas de Swift que ya implementan podómetro, háptica, Salud y Live Activity,
So that no reescriba desde cero lo único del proyecto que ya funciona en nativo.

**Acceptance Criteria:**

**Given** el commit `d9d3fbc` de la rama `feature/flutter-substrate`, que **no es ancestro de `HEAD`**
**When** se extrae la capa nativa
**Then** se hace por `git checkout feature/flutter-substrate -- ios/Runner/AppDelegate.swift`, **sin merge de la rama** [AD-23]

**Given** el `AppDelegate.swift` extraído (CMPedometer, CoreHaptics, AudioToolbox, `HKWorkoutBuilder`, `Activity.request`)
**When** se integra
**Then** queda troceado en los adapters que le corresponden —`Adapters/Motion`, `Feedback`, `Health`, `LiveActivity`— cada uno detrás de su puerto; no queda lógica de sistema en el `AppDelegate` [AD-10]

**Given** el handler de CoreMotion, que corre en su propia cola serie
**When** entrega datos al `SessionStore`
**Then** extrae los valores a un `struct` `Sendable` propio **dentro del handler**; `CMPedometerData` y sus `NSNumber` no cruzan la frontera de aislamiento [AD-7, AD-12]

**Given** que ese código **nunca se ejecutó en dispositivo**
**When** se cierra la historia
**Then** se ha verificado en el iPhone 14 físico que el podómetro reporta, que la háptica dispara y que una escritura de prueba aparece en la app Salud — si algo no funciona, se registra como coste adicional de Epic 6 y Epic 7

### Story 8.7: Sustrato de verificación del dominio

As a desarrollador,
I want un arnés que demuestre que el dominio Swift se comporta como el validado en producción,
So that "idiomático" no sea una coartada para cambiar comportamiento sin que nadie lo note.

**Acceptance Criteria:**

**Given** la suite JS existente (281 aserciones ejecutadas)
**When** se reparte según AD-6
**Then** cada aserción queda en **exactamente una** categoría: ~65 **vectores** extraídos a datos, ~111 **escenarios** portados a mano a Swift Testing, y ~52 **excluidos** por probar la agregada v1 de vueltas que `domain-model.md §2` elimina — los excluidos quedan **declarados**, no olvidados

**Given** que ni `GoalEngine` ni `AchievementEngine` tienen una sola aserción en la suite JS, y que 8 de los 14 logros no tienen cobertura
**When** se completa la historia
**Then** existen vectores **escritos de nuevo** para los 14 logros (caso que desbloquea y caso que no) y para el `GoalEngine` (semana ISO, límites de lunes y de domingo) [AD-6, AD-5]

**Given** los vectores en datos
**When** se ejecuta `Scripts/verify-domain.sh`
**Then** corre **ambos runtimes** —`domain.js` y el dominio Swift— contra el mismo fichero, y su paso en verde es Definition of Done de toda historia que toque `Domain/` (no hay CI: el mecanismo es local) [AD-6]

**Given** la tabla de divergencias declaradas
**When** se ejecutan los vectores contra `domain.js`
**Then** solo divergen **dos** conductas —hora local y mapeo WMO, ambas decisiones de plataforma—; las otras dos (doble resta de pausas, rachas lexicográficas) ya no divergen porque se corrigieron en la referencia el 2026-09-12 [`DEROGACIONES.md §6`]

**Given** `Resources/achievements.json`
**When** arranca la app
**Then** valida 14 entradas, claves únicas, todas las de `achievements.md` y `metric` dentro del enum cerrado; **falla ruidosamente** si no cuadra, nunca degrada [AD-5]

### Story 8.3: Distribución TestFlight con versionado SemVer

As a desarrollador del producto (Paul),
I want instalar la app de forma duradera en mi iPhone vía TestFlight,
So that tenga la app instalada sin depender de cables ni de builds locales.

**Acceptance Criteria:**

**Given** la cuenta Apple Developer activa y el proyecto SwiftUI de la historia 8.5
**When** se configura TestFlight
**Then** la app se sube como build y queda instalable en el iPhone 14 de Paul, con bundle id `com.walktracker.app` [AD-1]

**Given** que se sube un build
**When** se etiqueta el release
**Then** sigue versionado SemVer

**Given** que el toolchain está congelado durante el ciclo
**When** se genera el build
**Then** se compila con el toolchain fijado en el Stack del spine —**Xcode 26.3 / Swift 6.2.4 / SDK iOS 26.2**, verificado en la máquina— y el destino corre iOS 26; no se sube a Xcode 27 mientras dure el desarrollo [AD-2, SPEC OQ-5]

**And** App Store está **fuera de scope**: TestFlight o build local es suficiente, no es requisito de éxito [SPEC Non-goals]

**And** *(derogado)* la PWA ya no se despliega como canal secundario: con el sustrato nativo no hay doble canal que mantener [DEROGACIONES.md §5, AR-11]

### Story 8.4: Gate del Success signal — batería y precisión en dispositivo físico

*(Reubicada el 2026-09-13: se ejecuta **después del Epic 1**. Sus criterios miden una sesión real
—conteo, reconstrucción del background, UI de sesión— que construyen las historias 1.1–1.6. Duración
enmendada de 60 a 30 min: `SPEC.md` Constraints · Batería. [`sprint-change-proposal-2026-09-13.md`])*

*(Cambió de significado con el pivot: ya no valida "si el WebView aguanta" —ese riesgo desaparece con
el sustrato nativo—. Valida NFR-8 y la precisión de CAP-2/CAP-3.)*

As a desarrollador del producto (Paul),
I want validar en mi iPhone que una caminata de 30 minutos se registra con precisión y sin castigar la batería,
So that el criterio de éxito del SPEC quede demostrado en hardware antes de construir sobre el conteo.

**Acceptance Criteria:**

**Given** las historias 1.1–1.6 en `done` y la app instalada en el iPhone 14 por TestFlight
**When** Paul sale a caminar **30 min** con el teléfono en el bolsillo, auriculares con música y pantalla bloqueada
**Then** al terminar, los pasos y la distancia difieren **≤ 10 %** de los que reporta Apple Salud [SPEC Success signal, CAP-2]

**Given** la misma caminata
**When** se evalúa el consumo
**Then** la batería cae **≤ 5 %** en los 30 min y **Ajustes → Batería** no muestra a WalkTracker como consumidor destacado del periodo [NFR-8, AD-21]

**Given** la caminata con pantalla bloqueada
**When** Paul no toca la pantalla en ningún momento
**Then** la sesión queda registrada completa y **`stepsEstimated` es 0**: los intervalos en background se reconstruyeron por consulta al sistema, no por estimación [CAP-3, AD-8]

**Given** las cadencias de AD-21 que existen al terminar el Epic 1 (**conteo continuo y UI a 1 Hz**)
**When** se mide la sesión
**Then** el resultado se registra como medición de referencia y los dos valores provisionales de `formulas.json` quedan fijados, **pero no de la misma forma**: el **timeout de reconciliación** se reemplaza por el **medido** —la regla de Paul (2026-09-14) sobre la duración máxima real de la consulta lo dejó en **1 s**—, mientras que el **umbral de sesión huérfana no es medible en una caminata de 30 min** y se queda en las **6 h** como **valor decidido, no medido**. Los dos salen de `provisional`; la diferencia entre "medido" y "decidido" queda escrita [AD-8, AD-18; `8-4-medicion-referencia.md:104-105, :189`]

**And** la cadencia de la Live Activity por evento **no** se mide aquí: no existe hasta la 7.2, que recomprueba la batería con ella activa

**Given** el resultado del gate
**When** la prueba falla algún criterio
**Then** se revisa antes de seguir con los epics 2–7: el riesgo se paga aquí, no después
