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
  - _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-28/ARCHITECTURE-SPINE.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/DESIGN.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/EXPERIENCE.md
---

# WalkTracker iOS - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for WalkTracker iOS, decomposing the requirements from the SPEC package, Architecture spine, and UX design into implementable stories. Es la reimplementación de la PWA v3 como app Capacitor instalable: el dominio validado se reutiliza intacto (salvo 2 correcciones de portación) y la frontera nativa aporta conteo 24/7, HealthKit, Live Activity, recordatorios y storage garantizado.

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

- **NFR-1**: Capacitor como capa nativa — web app v3 en WKWebView; plugins como adapters en el borde; el dominio no conoce Capacitor; viabilidad condicionada a performance 60 min en dispositivo físico.
- **NFR-2**: No-backend — todo on-device; única llamada de red = clima; sin auth/cuentas/sync cloud/servidor propio.
- **NFR-3**: Usuario único (Paul) — sin multi-cuenta, perfiles ni UX de identidad.
- **NFR-4**: Privacidad — datos en dispositivo; sin analítica/telemetría; coordenadas clima a 2 decimales.
- **NFR-5**: Dominio preservado — invariantes v3 (wall-clock, pausa explícita, sesión finalizada inmutable, zancada congelada al cierre, validación en frontera, cadencia solo sobre tramos medidos, pasos estimados siempre desglosados).
- **NFR-6**: Arquitectura hexagonal — dominio puro sin frameworks de plataforma/UI; puertos en dominio, adapters en borde.
- **NFR-7**: Licencias — solo Apache-2.0/MIT; copyleft fuerte bloqueante.
- **NFR-8**: Batería — sesión de 60 min con conteo continuo sin degradación notoria.
- **NFR-9**: UX — targets ≥44 pt, claro/oscuro, "celebrar nunca culpar", números grandes, overlay 3–4 s saltable, UI en español.

### Additional Requirements

- **AR-1 (AD-C1)**: Capacitor como capa nativa; web app v3 empaquetada intacta en bundle local; código web solo toca Capacitor en adapters `Capacitor*` y composition root. Excepción deliberada: `domain.js` admite 2 correcciones de portación — logros temporales en hora local del dispositivo (no UTC) y mapeo de condición climática por código WMO → categoría interna `rain` (no regex sobre strings localizados).
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-1, AD-3**. Capacitor y la web app intacta desaparecen. Las dos "correcciones de portación" que autorizaba (hora local, mapeo WMO) se promueven a divergencias obligatorias en AD-6 y AD-19. [`DEROGACIONES.md §5`]
- **AR-2 (AD-C2)**: Un solo plugin custom `walktracker-kit` (paquete local `./walktracker-kit`, podspec propio, referencia `file:` en package.json) envuelve CMPedometer (live + query), HKWorkout y bridge ActivityKit. Adapters JS `CapacitorMotionAdapter`, `CapacitorHealthKitAdapter`, `CapacitorLiveActivityAdapter` hablan solo con él. Keep-awake y local-notifications en plugins comunitarios verificados (MIT).
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-10, AD-23**. No hay plugin `walktracker-kit`: cada capacidad de sistema se consume por su puerto desde un adapter. [`DEROGACIONES.md §5`]
- **AR-3 (AD-C4)**: Reconstrucción background por `queryPedometerData` como camino primario; `GapEstimator` solo si query falla/vacía (reglas heredadas: muestra ≥120 s, desglosado, "~", descartable); en web el GapEstimator sigue siendo el camino principal.
- **AR-4 (AD-C5)**: Distribución = builds locales Xcode (`pnpm cap run ios`) para iterar + TestFlight como canal duradero. Gate de promoción = prueba de performance del Success signal (60 min background, ≤10 % vs Salud, sin degradación batería). App Store fuera de scope. PWA se despliega por GitFlow a Pages.
  - > ⛔ **PARCIAL el 2026-09-12** → heredero: **Story 8.3**. TestFlight sobrevive; el mecanismo `pnpm cap run ios` no. [`DEROGACIONES.md §5`]
- **AR-5 (AD-C6)**: Live Activity alimentada por eventos nativos (callbacks CMPedometer en `walktracker-kit`), NO por WebView; el WebView solo ordena estado mayor (inicio/pausa/fin) vía `LiveActivityPort`.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-15**. No hay WebView que ordene el estado: la app alimenta la Live Activity directamente. [`DEROGACIONES.md §5`]
- **AR-6 (AD-C7)**: Bundle local únicamente; prohibido `server.url` en producción; actualizaciones vía build/TestFlight; única red = Open-Meteo.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **—**. Sin WebView no hay `server.url` ni bundle local que gobernar. [`DEROGACIONES.md §5`]
- **AR-7 (AD-C8)**: HealthKit write una vez al finalizar (dato inmutable completo); toda petición de permiso con pre-pantalla; recordatorios de meta idempotentes (cancel→schedule) desde GoalEngine al finalizar sesión y al abrir la app.
- **AR-8 (Stack verificado)**: @capacitor/core/cli/ios 8.4.2, @capacitor/local-notifications 8.2.1, @capacitor-community/keep-awake 8.0.1, @capacitor/preferences 8.0.1 (todos MIT); iOS deployment target 16.1; Xcode 26+; Node ≥22; gestión con pnpm.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-2 + Stack**. Stack Capacitor y target 16.1 sustituidos por Swift 6.3.3 / Xcode 26.6 / iOS 26.0. [`DEROGACIONES.md §5`]
- **AR-9 (Structural Seed)**: Repo único GitFlow; `walktracker-kit/` plugin local con podspec; `ios/` proyecto Xcode commiteado; `capacitor.config.json` sin `server.url`, `webDir` local; adapters nuevos `Capacitor*Adapter` en la capa web.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-23**. El seed estructural es el árbol SwiftUI, no el repo Capacitor. [`DEROGACIONES.md §5`]
- **AR-10 (Port contracts)**: MotionPort nativo (`onSteps(cumulativeCount, distanceM?)`, `query→{steps,distanceM}|null`) y web (`onSample` @60 Hz); HealthKitPort (`writeWorkout` una vez); LiveActivityPort (`start/updateState/stop`); NotificationPort (`rescheduleWeeklyReminder` idempotente); KeepAwakePort (`acquire/release` en foreground).
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-10**. Los contratos de puerto se redefinen: 11 puertos, entre ellos LocationPort, WakeLockPort y RandomPort que AR-10 no tenía. [`DEROGACIONES.md §5`]
- **AR-11 (Entornos)**: dev = builds locales Xcode en iPhone físico (simulator sin acelerómetro real) + `http://localhost`; prod = TestFlight (app principal) + GitHub Pages (PWA secundaria); sin backend, sin CI de servidor.
  - > ⛔ **PARCIAL el 2026-09-12** → heredero: **envoltura operativa del spine**. Dev en dispositivo físico sobrevive; el canal PWA a GitHub Pages no. [`DEROGACIONES.md §5`]
- **AR-12 (Inherited v3)**: AD-1 hexagonal, AD-4 Session aggregate (stepsMeasured/Estimated, strideM), AD-5 strideM congelada, AD-6 wall-clock, AD-7 validación frontera, AD-8 autosave+recuperación silenciosa, AD-14 Open-Meteo timeout 3s, AD-17 geolocation 2dp, AD-18 quotes.json — todos vigentes, read-only.
- **AR-13 (Deferred)**: protocolo de performance a nivel epic/story; canal háptico (CoreHaptics en walktracker-kit vs web) se resuelve como adapter tras puerto; contenido/formato de Live Activity a nivel story; sync PWA↔app fuera (arranque limpio); calibración interactiva futura; cache-busting SW PWA heredado.

### UX Design Requirements

- **UX-DR1**: Design tokens Volt — canvas `#1A1A1A`/`#F5F5F7`, surface `#2A2A2A`/`#FFFFFF`, accent `#CCFF00`/`#CC9900`, secondary `#FF6600`, danger `#FF453A`, success `#30D158`, estimated `#FFB347`/`#CC7A00`, text `#FFFFFF`/`#1D1D1F`, muted `#999999`/`#666666`, border `#555555`/`#8E8E93`; dark-mode-first con light igual; sin gradientes (solo overlay), máx 2 colores cromáticos por pantalla.
  - > ⛔ **DEROGADO el 2026-09-12** → heredero: **AD-13**. Los tokens Volt (`#CCFF00`, `#1A1A1A`…) se sustituyen por colores del sistema y Liquid Glass heredado del SDK de iOS 26. Cablear hexadecimales pelea con la plataforma. [`DEROGACIONES.md §4`]
- **UX-DR2**: Tipografía system-fonts (`-apple-system`); tokens: `metric-hero` 64px (48px mobile) 900, `metric-sub` 16px 700, `label` 11px 400, `body` 15px 400, `button-primary` 24px 900, `button-secondary` 14px 600, `header-title` 17px 700, `status-badge` 12px 600, `quote-hero` 28px (22px mobile) 700, `ring-value` 36px 900, `ring-label` 14px 600; Dynamic Type obligatorio con `clamp()` (hero ≤80px, quote ≤36px a 200%).
  - > ⛔ **PARCIAL el 2026-09-12** → heredero: **AD-13 + convención de accesibilidad**. `px`, `clamp()` y los tamaños fijos son conceptos de CSS y **no aplican**: en SwiftUI se usan estilos de texto del sistema y Dynamic Type. Lo que sobrevive es la intención — jerarquía con números grandes y escalado accesible sin recortes. [`DEROGACIONES.md §4`]
- **UX-DR3**: Espaciado/Layout — escala 4/8/12/16/24/32 px; márgenes 16 px; card padding 20 px; goal ring 300 px diámetro centrado; touch targets ≥44 pt; safe areas `env(safe-area-inset-bottom)`; single-column siempre; modal máx 1 nivel.
- **UX-DR4**: Componentes visuales (DESIGN.md) — Goal Ring, Metric Card, Weather Card, Session Controls (Pausar/Reanudar/Finalizar, 44 px min, danger/success), Estimated Steps Banner, Wake Lock Banner, Recovery Indicator, Motivational Overlay, Achievement Badge, Celebration Toast, Summary Screen, History Row (delete 44×44 pt + confirm), Settings Field, Motion Denied Screen, Status Badge, Toggle Switch (hit 48×44 px).
- **UX-DR5**: Arquitectura de información — 9 superficies (Home, Session, Motivational Overlay, Summary, Settings, History, Achievements, Motion Denied); navegación iconos top-right (⚙📋🏆) sin tab bar; screen replacements no modales; overlay transitorio; estados: cold open, active, paused, background→foreground (wall-clock + estimated banner), finished (Summary forward-only), goal completed, achievement unlocked, wake lock failed, no network, motion denied, empty history/achievements, backup overdue, recovery from purge.
  - > ⛔ **PARCIAL el 2026-09-12** → heredero: **AD-14**. La navegación con **iconos arriba a la derecha y sin tab bar** queda derogada: `TabView` de cuatro pestañas con la sesión como `fullScreenCover`. Lo que sobrevive es el inventario de superficies y la lista de estados (cold open, motion denied, empty history, recuperación…), que sigue siendo vinculante. [`DEROGACIONES.md §4`]
- **UX-DR6**: Accesibilidad WCAG AA — VoiceOver completo (distance "3.2 kilómetros", steps con estimated, aria-labels en nav icons, overlay `role=dialog aria-modal`, toast `role=status aria-live=polite`, achievement locked aria-label); Dynamic Type con clamp; Reduce Motion (overlay sin fade, toast sin animación, ring instant); contraste verificado (accent-dark 15.4:1, estimated 7.2:1/4.6:1, muted 4.9:1/5.0:1); focus ring accent 2px; Escape dismiss; Tab order visual.
  - > ⚠️ **TRADUCIDO el 2026-09-12** → la *intención* sigue vinculante (WCAG AA, VoiceOver completo, Dynamic Type sin recortes, Reduce Motion, contraste verificado), pero **sus mecanismos son de la web y no aplican**: `aria-label` → `.accessibilityLabel`, `role=dialog aria-modal` → presentación modal nativa, `role=status aria-live` → `.accessibilityAddTraits(.updatesFrequently)`, `focus ring`/`Tab order`/`Escape` → foco y descarte del sistema, `clamp()` → Dynamic Type. Los ratios de contraste se recalculan contra colores del sistema, no contra los tokens Volt de UX-DR1, que está derogado. Las tres piezas dibujadas de AD-13 necesitan etiqueta explícita: un `Canvas` no la trae. [`DEROGACIONES.md §4`]
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

**And** el dominio (module `domain`) no importa UI ni framework: el `now` llega por un `ClockPort` y la creación de sesión es una función pura del dominio [fuente: domain-model.md#3, ARCHITECTURE-SPINE.md AD-C1]

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

**And** el flujo de pasos entra al dominio por el puerto `MotionPort` (`onSteps(cumulativeCount, distanceM?)`), con un adapter `CapacitorMotionAdapter` que es el único punto que conoce `walktracker-kit`/CMPedometer [fuente: ARCHITECTURE-SPINE.md AR-2, AR-10]

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
**Then** muestra "—" (ritmo `null`, `paceSecPerKm` no se computa) [fuente: domain-model.md#47, capabilities.md#CAP-4]

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

**Given** que el sistema NO puede proveer el dato del intervalo en background
**When** se intenta reconstruir el gap
**Then** se usa el `GapEstimator` como **degradación excepcional**: estimación por cadencia `stepsEstimated += cadenceSpm × (gapS/60)`, solo si la sesión está activa y hay muestra previa ≥ 120 s [fuente: domain-model.md#49, domain-model.md#73]

**Given** una estimación por cadencia aplicada a un intervalo
**When** se muestra en la UI
**Then** los pasos estimados van **desglosados y marcados "~"**, y el usuario puede **descartarlos** — si los descarta, esos pasos no cuentan [fuente: capabilities.md#CAP-3, domain-model.md#20]

**Given** una estimación por cadencia marcada "~"
**When** el usuario elige descartarla
**Then** `stepsEstimated` vuelve a 0 para ese gap y la distancia/ritmo se recomputan sin ella

**Given** una sesión en estado `paused` (o finalizada) con un gap
**When** se intenta estimar pasos por cadencia
**Then** no se estima nada: gap = 0 — la estimación solo opera sobre sesiones activas [fuente: domain-model.md#49]

**And** la consulta al sistema pasa por el `MotionPort` (`query→{steps, distanceM}|null`); el `GapEstimator` vive en el dominio puro y solo se invoca cuando el puerto devuelve `null` o vacío [fuente: ARCHITECTURE-SPINE.md AR-3, AR-10]

### Story 1.6: Recuperación foreground — wall-clock + Estimated Banner

As a caminante (usuario único),
I want que al volver a la app la sesión se recupere mostrando el tiempo real transcurrido y cualquier pasos estimados de forma transparente,
So que nunca me sienta engañado sobre el estado de mi caminata.

**Acceptance Criteria:**

**Given** una sesión activa y la app fue forzada a cerrarse o estuvo en background
**When** la reabro
**Then** la sesión se recupera silenciosamente con `elapsedS` recomputado desde `startedAt` (el tiempo cerrado cuenta) y se muestra el indicador "Sesión recuperada" durante 3 s [fuente: capabilities.md#CAP-1, domain-model.md#38]

**Given** que la sesión recuperada incluye pasos estimados ("~")
**When** se muestra la UI en foreground
**Then** aparece el Estimated Banner descartable con los pasos estimados desglosados y marcados "~", coherente con UX-DR4 [fuente: UX-DR4, UX-DR5]

**Given** el Estimated Banner visible con pasos estimados
**When** el usuario toca "Descartar"
**Then** `stepsEstimated` se descarta para ese gap (vuelve a 0) y las métricas se recomputan sin ella [fuente: capabilities.md#CAP-3]

**Given** una sesión activa que estuvo en background
**When** vuelvo a foreground
**Then** la reconstrucción por query (historia 1.5) se ejecuta ANTES de refrescar la UI, y la UI muestra el estado consolidado (medidos + estimados si los hubo)

**And** la recuperación usa el snapshot `activeSession` persistido `{startedAtMs, stepsMeasured, stepsEstimated, ...}` y es silenciosa (sin bloqueos ni pantallas de carga) [fuente: domain-model.md#98]

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
**Then** la condición se mapea por código WMO → categoría interna `rain` (no por regex sobre strings localizados) [fuente: AR-1, ARCHITECTURE-SPINE.md AD-C1]

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
**Then** se guarda con validación en la frontera: debe ser > 0 y finito; valores ≤ 0 o no numéricos se rechazan con mensaje [fuente: capabilities.md#CAP-13, domain-model.md#51]

**Given** que el campo de zancada está vacío o con un valor inválido (≤0, NaN, no numérico)
**When** intento guardar
**Then** se muestra mensaje de error y no se persiste el valor inválido [fuente: capabilities.md#CAP-13]

**Given** que recalibro la zancada a un nuevo valor
**When** reviso el historial de sesiones cerradas
**Then** las sesiones cerradas conservan su `strideM` **congelado** — recalibrar nunca reescribe historial [fuente: capabilities.md#CAP-13, domain-model.md#21]

**Given** que recalibro la zancada
**When** inicia la siguiente sesión
**Then** la nueva zancada se usa para los cálculos de distancia de esa sesión [fuente: capabilities.md#CAP-13]

**And** el campo de Ajustes sigue UX-DR4 (Settings Field) y el flujo de recalibración sigue UX-DR8 flow 5; sin valor configurado el default es 0,655 m [fuente: capabilities.md#CAP-13]

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
**Then** el anillo suma la distancia de las sesiones de la **semana ISO** (lunes 00:00 UTC → domingo) y muestra el porcentaje de cumplimiento [fuente: capabilities.md#CAP-7, domain-model.md#60]

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
**Then** el logro **no se revoca** — permanece desbloqueado [fuente: achievements.md#3]

**Given** una sesión con `weather` = null (sin clima)
**When** se evalúan los logros climáticos (`rain_walker`, `hot_walker`, `cold_walker`)
**Then** no se evalúan como cumplidos [fuente: achievements.md#25]

**And** los logros temporales (`early_bird` entre 05:00–07:00, `night_walker` entre 21:00–23:00) y las rachas se evalúan en **hora local** del dispositivo, no UTC [fuente: achievements.md#27]

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

**And** el storage se accede por el `StoragePort`; `@capacitor/preferences` es refuerzo detrás del puerto si se necesita (decisión interna, el dominio no lo conoce) [fuente: capabilities.md#CAP-9, AR-10]

**And** la sesión activa se autoguarda al cambiar de estado (inicio, pausa, reanudación) para que el force-quit siempre tenga un snapshot fresco [fuente: AR-12 (AD-8)]

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
**Then** se lee correctamente (columnas de fecha, distancia, duración, ritmo, pasos) [fuente: capabilities.md#CAP-14]

**Given** que exporté un JSON del historial
**When** importo ese JSON de vuelta en la app
**Then** el historial se **restaura íntegro** (prueba de respaldo/restauración) [fuente: capabilities.md#CAP-14]

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
**Then** el write ocurre **una sola vez** al finalizar (dato inmutable completo), nunca por partes ni retries duplicados [fuente: AR-7, ARCHITECTURE-SPINE.md AD-C8]

**Given** que la app pide permiso de Salud por primera vez
**When** se solicita el permiso
**Then** se muestra antes una **pre-pantalla explicativa** (qué se escribirá y por qué), no se pide en frío [fuente: capabilities.md#CAP-11, AR-7]

**Given** que el usuario denegó el permiso de Salud
**When** finaliza una sesión
**Then** la sesión se guarda **localmente igual** y la app sigue funcionando completa — sin bloqueo ni pantallas de error [fuente: capabilities.md#CAP-11]

**And** el write pasa por el `HealthKitPort` (`writeWorkout` una vez), con un adapter `CapacitorHealthKitAdapter` que es el único punto que conoce HKWorkout — el dominio solo expone el puerto [fuente: AR-2, AR-10]

**And** la app **solo escribe** en Salud; no lee datos de Salud (non-goal explícito) [fuente: capabilities.md#CAP-11]

### Story 6.2: Recordatorio semanal de meta (notificaciones locales)

As a caminante (usuario único),
I want recibir un recordatorio semanal sobre el estado de mi meta,
So que sepa cuánto me falta sin abrir la app.

**Acceptance Criteria:**

**Given** que el permiso de notificaciones está concedido
**When** se programa el recordatorio
**Then** se agenda una notificación local semanal con el estado de la meta (p. ej. domingo por la tarde: "Te faltan 2 km esta semana") vía `@capacitor/local-notifications` [fuente: capabilities.md#CAP-17]

**Given** que el recordatorio ya está programado (p. ej. de la última sesión)
**When** se reprograma al finalizar una sesión o al abrir la app
**Then** se hace **cancel → schedule** (idempotente: nunca hay dos recordatorios duplicados) [fuente: AR-7, ARCHITECTURE-SPINE.md AD-C8]

**Given** que el recordatorio fue programado
**When** la app está cerrada y llega el momento
**Then** la notificación llega con la app cerrada, respetando el permiso de notificaciones [fuente: capabilities.md#CAP-17]

**Given** que el usuario denegó el permiso de notificaciones
**When** se intenta programar el recordatorio
**Then** la app funciona completa sin recordatorios — degradación limpia [fuente: capabilities.md#CAP-17]

**And** el programador pasa por el `NotificationPort` (`rescheduleWeeklyReminder` idempotente), disparado desde el `GoalEngine` al finalizar sesión y al abrir la app [fuente: AR-7, AR-10]

### Epic 7: Live Activity en pantalla de bloqueo
Paul cierra la app y su caminata sigue viva en la pantalla de bloqueo: métricas en vivo alimentadas por eventos nativos, que se cierran al finalizar. Es la escena más poderosa del producto. **El dispositivo de Paul no tiene Dynamic Island** (confirmado por Paul, sesión party mode 2026-08-01): la isla queda como historia de mantenimiento mínimo (que compile), y la estrella del epic es el layout de pantalla de bloqueo.
**FRs covered:** FR-17
**NFRs:** NFR-1, NFR-8
**ARs:** AR-2, AR-5, AR-8, AR-10, AR-11
**UX:** UX-DR4 (Live Activity layout), UX-DR5
**Riesgo:** medio-bajo — Dynamic Island es solo "que compile" (sin hardware de Paul para validar); ActivityKit disponible en runtime (iOS 16.1+); alimentada por callbacks nativos CMPedometer, NO por WebView (AR-5). El riesgo real está en el layout compacto de pantalla de bloqueo y el ciclo de vida del Activity.

### Story 7.1: Bridge ActivityKit en `walktracker-kit` (Widget Extension)

As a caminante (usuario único),
I want que la app pueda crear una Live Activity nativa,
So que mis métricas puedan mostrarse en la pantalla de bloqueo sin que la app esté en primer plano.

**Acceptance Criteria:**

**Given** que se construye el soporte de Live Activity
**When** se configura el proyecto
**Then** existe una **Widget Extension en Swift con ActivityKit** dentro de `walktracker-kit` (paquete local con podspec propio) y la app compila para iOS 16.1+ [fuente: capabilities.md#CAP-18, AR-2]

**Given** que la Live Activity está soportada en runtime
**When** se expone el puerto
**Then** el `LiveActivityPort` ofrece `start / updateState / stop` [fuente: AR-10]

**Given** que la app inicia una Live Activity
**When** el WebView pide iniciarla
**Then** el bridge la crea con las métricas iniciales de la sesión (pasos, distancia, tiempo) [fuente: capabilities.md#CAP-18]

**Given** que la extension falla o el SO la rechaza
**When** se intenta crear la Live Activity
**Then** la app funciona **completa sin ella** — degradación limpia, la sesión y el conteo siguen al 100 % [fuente: capabilities.md#CAP-18]

**And** la Live Activity se alimenta por **callbacks nativos** (CMPedometer en `walktracker-kit`), NO por el WebView — el WebView solo ordena estado mayor vía el puerto [fuente: AR-5]

### Story 7.2: Ciclo de vida de la Live Activity (crear, actualizar, cerrar)

As a caminante (usuario único),
I want que la Live Activity siga el ciclo de vida de mi sesión,
So que refleje el estado real de mi caminata y no quede huérfana al terminar.

**Acceptance Criteria:**

**Given** que inicio una sesión
**When** la sesión arranca
**Then** se crea la Live Activity con las métricas iniciales [fuente: capabilities.md#CAP-18]

**Given** que la sesión está activa con el teléfono bloqueado
**When** el coprocesador reporta nuevos pasos
**Then** la Live Activity actualiza sus métricas en vivo (pasos, distancia, tiempo) vía callbacks nativos — sin depender del WebView [fuente: capabilities.md#CAP-18, AR-5]

**Given** que pauso la sesión
**When** la pausa se registra
**Then** la Live Activity muestra un **estado visible de pausa** (no se cierra, solo cambia su estado) [fuente: capabilities.md#CAP-18]

**Given** que finalizo la sesión
**When** la sesión se cierra
**Then** la Live Activity **se cierra** [fuente: capabilities.md#CAP-18]

**Given** que la app está en foreground y la sesión activa
**When** se compara la UI con la Live Activity
**Then** ambas muestran el mismo contenido (pasos, distancia, tiempo) — mismo contenido que la pantalla Sesión, en formato glanceable [fuente: capabilities.md#CAP-18]

### Story 7.3: Layout de pantalla de bloqueo + Dynamic Island compilando

As a caminante (usuario único),
I want que la Live Activity se vea clara y glanceable en la pantalla de bloqueo,
So que pueda leer mis métricas de un vistazo sin desbloquear el teléfono.

**Acceptance Criteria:**

**Given** que hay una Live Activity activa en pantalla de bloqueo
**When** se renderiza el layout
**Then** muestra pasos, distancia y tiempo en formato **glanceable** (mismo contenido que la pantalla Sesión, legible de un vistazo) [fuente: capabilities.md#CAP-18]

**Given** que el iPhone de Paul no tiene Dynamic Island
**When** se compila el layout de la isla
**Then** la Dynamic Island compila correctamente pero no se muestra en hardware sin isla — el lock screen funciona igual [fuente: capabilities.md#CAP-18]

**Given** que el layout de la Live Activity usa tipografía de métrica
**When** se renderiza
**Then** usa los estilos de texto del sistema en tamaño compacto, dentro del presupuesto de 4 KB del `ContentState`, y **solo renderiza**: el cronómetro lo anima con `Text(timerInterval:)`, único cálculo permitido a la extensión [fuente: UX-DR4; AD-15, AD-21]

**And** el layout sigue UX-DR4 (Live Activity layout) y mantiene la isla como mantenimiento mínimo "que compile" — sin validación en hardware real (Paul no la tiene) [fuente: epics.md#Epic 7]

### Epic 8: Fundaciones del sustrato SwiftUI

*(Reescrito el 2026-09-12. El epic se llamaba "Validación de la apuesta nativa" y existía para
demostrar que Capacitor era viable. Esa apuesta ya no se juega: OQ-1 se reabrió y el sustrato es
SwiftUI nativo. Lo que queda de fundacional es distinto — y sigue corriendo PRIMERO.)*

Levantar el sustrato sobre el que se construye todo lo demás: el proyecto SwiftUI limpio, la capa
nativa rescatada, y el arnés que demuestra que el dominio portado se comporta como el validado en
producción. Sin esto, cada epic posterior improvisa su propia versión de la verdad.

**FRs covered:** ninguno directamente — es sustrato
**NFRs:** NFR-5 (dominio preservado), NFR-6 (hexagonal), NFR-7 (licencias), NFR-8 (batería)
**ADs:** AD-1, AD-2, AD-3, AD-4, AD-5, AD-6, AD-12, AD-23, AD-24
**Deroga:** AR-1, AR-2, AR-6, AR-8, AR-9 (ver `DEROGACIONES.md §5`)

#### Orden de ejecución

`8.5 → 8.6 → 8.7 → 8.3 → 8.4`. Los números ya no son el orden: es el precio de no reciclar IDs.
#### Historias anuladas — fuera del tracking

| ID | Título | Por qué |
|---|---|---|
| ~~8.1~~ | Montaje Capacitor — web v3 en WebView + plugin scaffold | Figuraba como `done` sobre un sustrato que **AD-1 derogó**. El trabajo equivalente vive en 8.5, 8.6 y 8.7 |
| ~~8.2~~ | Build local en dispositivo + keep-awake | Su mecanismo (`pnpm cap run ios`) desaparece con Capacitor. El wake lock sobrevive como `WakeLockPort` (AD-10) en Epic 1; el build local a dispositivo es la envoltura operativa del spine |

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
**Then** se compila con **Xcode 26.6 / Swift 6.3.3** contra el SDK de iOS 26, y el destino corre iOS 26 — no se sube a Xcode 27 mientras dure el desarrollo [AD-2, SPEC OQ-5]

**And** App Store está **fuera de scope**: TestFlight o build local es suficiente, no es requisito de éxito [SPEC Non-goals]

**And** *(derogado)* la PWA ya no se despliega como canal secundario: con el sustrato nativo no hay doble canal que mantener [DEROGACIONES.md §5, AR-11]

### Story 8.4: Gate del Success signal — batería y precisión en dispositivo físico

As a desarrollador del producto (Paul),
I want validar en mi iPhone que una caminata completa de 60 minutos se registra con precisión y sin castigar la batería,
So that el criterio de éxito del SPEC quede demostrado en hardware y no en un documento.

*(Esta historia cambia de significado con el pivot. Ya no valida "si el WebView aguanta" — ese riesgo
desaparece con el sustrato nativo. Ahora valida NFR-8 y la precisión de CAP-2/CAP-3.)*

**Acceptance Criteria:**

**Given** la app nativa instalada en el iPhone 14
**When** Paul sale a caminar 60 min con el teléfono en el bolsillo, auriculares con música y pantalla bloqueada
**Then** al terminar, los pasos y la distancia difieren **≤ 10 %** de los que reporta Apple Salud [SPEC Success signal, CAP-2]

**Given** la misma caminata
**When** se evalúa el consumo
**Then** no hay degradación notoria de batería con conteo continuo en background [NFR-8, AD-21]

**Given** la caminata con pantalla bloqueada
**When** Paul no toca la pantalla en ningún momento
**Then** la sesión queda registrada completa, y **`stepsEstimated` es 0**: los intervalos en background se reconstruyeron por consulta al sistema, no por estimación [CAP-3, AD-8]

**Given** las tres cadencias de refresco que fija AD-21 (conteo continuo, UI a 1 Hz, Live Activity por evento)
**When** se mide la sesión
**Then** el resultado se registra como la medición de referencia con la que se fijan el timeout de reconciliación y el umbral de sesión huérfana, hoy diferidos a `formulas.json` [AD-8, AD-18]

**Given** el resultado del gate
**When** la prueba falla algún criterio
**Then** se revisa antes de seguir construyendo — el riesgo se paga aquí, no después
