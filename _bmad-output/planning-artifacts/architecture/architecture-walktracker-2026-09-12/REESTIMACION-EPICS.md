---
id: REESTIMACION-EPICS-swiftui
fecha: 2026-09-12
companion_de: ARCHITECTURE-SPINE.md
base_anterior: OPCIONES-SUSTRATO.md (Opción B ≈ 5,5 fines de semana)
estimacion_nueva: 7,25 fines de semana
---

# Reestimación de los 8 epics — sustrato SwiftUI

Unidad: **fin de semana de trabajo**, la misma de `PLAN-CAPACITOR-v2.md` y `OPCIONES-SUSTRATO.md`.

## El número subió, y digo por qué

Coste con el que se adoptó la Opción B: **5,5**. Coste con el spine escrito: **7,25**. **Δ +1,75.**

El aumento no es inflación: son decisiones tomadas *después* de aquel costeo, en la sesión de coaching y
en la puerta de revisión. Desglosado:

| Origen del incremento | Δ |
| --- | --- |
| **AD-6 con su alcance real.** El costeo asumía "extraer los tests". La suite tiene 281 aserciones ejecutadas, no 168; solo 65 son extraíbles a vectores, 111 hay que portarlas a mano como escenarios, y 52 son de la agregada v1 que desaparece. Y lo peor: **ni GoalEngine ni AchievementEngine tienen una sola aserción** — los vectores de los 14 logros y de la meta semanal hay que **escribirlos**, no extraerlos | +0,75 |
| **AD-16 a AD-21**, los cinco agujeros que el adversario encontró: dueño de fichero, disparador único de logros, sesión huérfana, calendario único, superficies de comando, presupuesto de energía | +0,50 |
| **AD-9: el CSV no es gratis.** Se costeó como "el formato en disco es el de intercambio". CAP-14 exige CSV que abra en Numbers — es un segundo serializador, con separador `;` y decimal `,` por la UI en español | +0,25 |
| **AD-5: esquema publicado + evaluador exhaustivo + validación de arranque** | +0,25 |
| Reutilización de `AppDelegate.swift` **confirmada** pero no gratuita: hay que extraerla de una rama que no es ancestro de `HEAD` y trocearla en adapters (AD-23) | 0 (ya contado en 0,5) |

## Por epic

| Epic | Historias | Antes | Ahora | Qué cambia |
| --- | --- | --- | --- | --- |
| **E1** Sesión y conteo | 6 | — | **1,50** | Dominio `Session`/`Metrics`/`GapEstimator` en Swift, `SessionStore`, adapter CoreMotion con el DTO `Sendable` de AD-7, reconciliación atómica (AD-8) y sesión huérfana (AD-18). 1.2 pierde el `CapacitorMotionAdapter` y la retirada del `StepDetector` deja de ser trabajo: el SO cuenta |
| **E2** Clima, motivación, calibración | 3 | — | **0,50** | `LocationPort` con redondeo a 2 decimales (nuevo, era invisible), Open-Meteo directo sin plugin, `RandomPort` para las frases |
| **E3** Metas y logros | 4 | — | **1,00** | `AppCalendar` único (AD-19) resolviendo el conflicto UTC/local, `achievements.json` con esquema y evaluador exhaustivo (AD-5), disparador único e irrevocabilidad (AD-17) |
| **E4** Feedback háptico y sonoro | 2 | — | **0,25** | Lo más barato del plan: `AppDelegate.swift` ya trae CoreHaptics y AudioToolbox funcionando. Solo puerto y cableado |
| **E5** Historial y persistencia | 4 | — | **1,00** | Store JSON con dueños de fichero (AD-16), `activeSession.json` con autosave de 10 s, historial y tendencia, export JSON **+ CSV**, borrado con confirmación y swipe nativo (AD-20) |
| **E6** Lo que Apple recibe | 2 | — | **0,50** | `HKWorkoutBuilder` ya escrito y verificado vigente; los recordatorios son nuevos pero triviales con `UNUserNotificationCenter` |
| **E7** Live Activity | 3 | — | **0,75** | `Activity.request`/`update`/`end` ya escritos. Nuevo: target `Shared`, contrato de `ContentState` (AD-15), `NSSupportsLiveActivities`, y el layout de pantalla de bloqueo. Sin App Group: no hacía falta |
| **E8** Fundaciones | **reescrito** | — | **1,75** | Ver abajo |
| | **28+** | **5,50** | **7,25** | |

## Epic 8 se reescribe entero

Sus dos primeras historias mueren con Capacitor. La 8.1 ya está marcada `done` en `sprint-status.yaml`
sobre un sustrato que ya no existe.

| Historia | Estado |
| --- | --- |
| 8.1 Montaje Capacitor — web v3 en WebView + plugin scaffold | **ANULADA.** Su `done` es sobre un sustrato derogado |
| 8.2 Build local en dispositivo + keep-awake | **ANULADA** en su mecanismo (`pnpm cap run ios`). El wake lock sobrevive como `WakeLockPort` (AD-10) dentro de E1 |
| 8.3 Distribución TestFlight con SemVer | **SOBREVIVE** sin cambios de fondo |
| 8.4 Gate del Success signal (60 min en dispositivo) | **SOBREVIVE y cambia de significado.** Ya no valida "si el WebView aguanta" —ese riesgo desaparece— sino NFR-8: batería y precisión ≤10 % vs Salud. Es el gate de AD-21 |

**Historias nuevas de E8:**

| Nueva | Contenido |
| --- | --- |
| 8.1′ Proyecto SwiftUI y limpieza del árbol | Xcode project, targets (app + `Shared` + Widget Extension), entitlements y usage strings, y la limpieza de AD-23: fuera `ios/App/`, `www/`, `adapters/`, `capacitor.config.json`, `walktracker-kit/` |
| 8.2′ Extracción de la capa nativa | Sacar `AppDelegate.swift` de `feature/flutter-substrate` (`d9d3fbc`) y trocear sus 446 líneas en los adapters de AD-10. **Sin merge de esa rama** |
| 8.5′ Sustrato de verificación del dominio | Los vectores de AD-6, los ~111 escenarios, los vectores nuevos de logros y meta, y `Scripts/verify-domain.sh` corriendo ambos runtimes |

## Riesgos que mueven el número

| Riesgo | Efecto si se materializa |
| --- | --- |
| **iOS 27 el 14 de septiembre.** Sin confirmación de que Xcode 26.6 depure en un dispositivo con iOS 27, y el simulador no sirve para CAP-2/CAP-3 | Parada total hasta subir a Xcode 27. Decisión pendiente de Paul |
| Los ~111 escenarios portados a mano son la partida más blanda del plan | Si su port resulta más caro de lo estimado, E8 crece |
| El troceado de `AppDelegate.swift` supone que ese código es correcto — está escrito pero **nunca se ejecutó en dispositivo** | Si HealthKit o ActivityKit no funcionan tal cual, E6 y E7 vuelven a su coste completo (+1,5) |
