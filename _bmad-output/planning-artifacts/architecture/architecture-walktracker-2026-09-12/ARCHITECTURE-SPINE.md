---
name: 'WalkTracker iOS (SwiftUI nativa)'
type: architecture-spine
purpose: build-substrate
altitude: feature
paradigm: 'hexagonal (ports & adapters) con un único escritor en el main actor'
scope: 'App iOS nativa SwiftUI que reemplaza el stack Capacitor/WebView. Gobierna dominio, aplicación, adapters de sistema, UI y la extensión de Live Activity.'
status: final
created: '2026-09-12'
updated: '2026-09-21'
binds: [CAP-1, CAP-2, CAP-3, CAP-4, CAP-5, CAP-6, CAP-7, CAP-8, CAP-9, CAP-10, CAP-11, CAP-12, CAP-13, CAP-14, CAP-15, CAP-17, CAP-18]
sources:
  - ../../../specs/spec-walktracker-ios/SPEC.md
  - ../../../specs/spec-walktracker-ios/domain-model.md
  - ../../../specs/spec-walktracker-ios/achievements.md
  - ../estandar-nativo-2026-09-12/OPCIONES-SUSTRATO.md
  - ../../ux-designs/ux-walktracker-native/VALIDATION-mockups-v3-2026-09-12.md
  - ../../../../domain.js
  - ../../../../motivation.js
companions:
  - DEROGACIONES.md
  - REESTIMACION-EPICS.md
---

# Architecture Spine — WalkTracker iOS (SwiftUI nativa)

> **El contrato de producto es `SPEC.md` y sus companions, por referencia, no por copia.** Este spine no reproduce restricciones del SPEC: las gobierna. Toda restricción del SPEC que exige un mecanismo arquitectónico tiene aquí un AD que la hace verificable; el resto sigue viva en el SPEC y vincula igual. `DEROGACIONES.md` lista lo que este spine anula y lo que absorbe.

## Design Paradigm

**Hexagonal (ports & adapters)** con **un único escritor en el main actor**.

| Capa | Directorio | Puede importar |
| --- | --- | --- |
| Domain | `Domain/` | Solo `Foundation` |
| Application | `Application/` | `Domain` |
| Adapters | `Adapters/` | `Domain` (implementa sus puertos) |
| UI | `UI/` | `Application`, `Domain` (solo lectura) |
| Shared | `Shared/` | Solo `Foundation` |
| Extensión | `WalkTrackerActivity/` | `Shared` únicamente |

```mermaid
graph TD
    UI[UI · SwiftUI] --> APP[Application · Stores]
    ADP[Adapters] -.implementa puertos.-> DOM
    APP --> DOM[Domain · puro]
    APP --> ADP
    APP --> SHR[Shared · ActivitySnapshot]
    EXT[WalkTrackerActivity] --> SHR
    DOM -.->|no importa nada de plataforma| X((∅))
```

## Invariants & Rules

### AD-1 — Sustrato: SwiftUI nativo [ADOPTED]

- **Binds:** todo
- **Prevents:** que el sustrato se decida por mockup en vez de por decisión explícita
- **Rule:** app SwiftUI contra el SDK de iOS 26. Sin WebView, sin Capacitor, sin Flutter en el producto. Deroga `PLAN-CAPACITOR-v2.md` y reabre OQ-1; el inventario completo de lo derogado y lo absorbido está en `DEROGACIONES.md`, que es vinculante. **Absorbe AD-IOS-01:** el bundle id es `com.walktracker.app`, inmutable.

### AD-2 — Suelo de despliegue iOS 26.0 [ADOPTED]

- **Binds:** todo
- **Prevents:** pagar compatibilidad hacia atrás para un universo de instalación de un dispositivo
- **Rule:** deployment target 26.0. **Prohibido `if #available` hacia versiones anteriores.** Dispositivo de validación: iPhone 14 (A15, sin Dynamic Island). Deroga A-2 del SPEC (iOS 17+) y el 16.1 del ciclo Capacitor.

### AD-3 — Dirección de dependencias

- **Binds:** todas las capas
- **Prevents:** lógica de negocio atrapada en una vista o en un adapter, y por tanto no verificable
- **Rule:** las dependencias apuntan **hacia dentro**. `Domain/` no importa `SwiftUI`, `CoreMotion`, `HealthKit`, `ActivityKit`, `CoreLocation` ni `UIKit`. Un `import` de plataforma en `Domain/` es un fallo de build. El dominio **nunca** llama a `Date()`, `Date.now` ni `random()` — llegan por puerto (corrige `domain.js:249` y `:392`).

### AD-4 — El dominio es Swift idiomático, no `domain.js` transliterado

- **Binds:** `Domain/`
- **Prevents:** Swift ilegible que nadie mantiene, y la falsa seguridad de creer que *parecerse* a `domain.js` equivale a *comportarse* como él
- **Rule:** value types, métodos, `throws`, errores tipados, opcionales para métricas ausentes (un ritmo por debajo de 100 m es `nil`, no `0` ni `-1`). Se conservan los nombres del lenguaje ubicuo de `domain-model.md §1`. La equivalencia con la v3 se demuestra por AD-6, nunca por parecido del código.

### AD-5 — Catálogo en datos, con esquema publicado y evaluación exhaustiva

- **Binds:** CAP-8, `AchievementEngine`
- **Prevents:** el incidente del 2026-09-11 (catálogo reteclado a mano en Dart: 7 logros, semántica alterada) **y** la divergencia de esquema que el propio "en datos" permite si no se publica
- **Rule:** `Resources/achievements.json` lleva **metadatos y umbrales**; la evaluación es **Swift**. No hay mini-DSL ni intérprete. Esquema, vinculante:

```jsonc
{ "schemaVersion": 1,
  "achievements": [
    { "key": "first_km",        // clave estable de achievements.md, nunca renumerada
      "name": "Tu primer kilómetro",
      "description": "Completa 1 km en una sesión",
      "icon": "🏅",
      "metric": "sessionDistanceM", // enum cerrado, ver más abajo
      "threshold": 1000,          // número · [min, max] para between · cadena para weatherCategory
      "comparison": "gte" }       // gte | lte | eq | gt | lt | between
  ] }
```

`metric` es un enum cerrado en Swift: `sessionDistanceM · totalDistanceM · sessionCount · consecutiveDays · startHourLocal · weatherCategory · tempC · paceSecPerKm · weeklyGoalMet`. El evaluador es un `switch` **exhaustivo** sobre ese enum — una métrica nueva sin rama no compila. El arranque valida: 14 entradas, claves únicas, todas las de `achievements.md`, `metric` conocida. **Falla ruidosamente**, no degrada.

**Enmienda del esquema — 2026-09-12, decisión de Paul (historia 8.7).** Con `gte · lte · eq` no cabían los 14 logros sin convenciones fuera de los datos: `speed_walker` es "menor que", `hot_walker` "mayor que" y `early_bird`/`night_walker` son una franja. Se amplía:

- `comparison` es `gte · lte · eq · gt · lt · between`. `between` es **inclusiva** en los dos extremos.
- `threshold` es un **número**; un **`[min, max]`** con `min ≤ max` para `between`; o una **cadena** para `weatherCategory` (hoy solo `"rain"`, y solo con `eq`). Cualquier otra combinación hace fallar el arranque (`invalidThreshold`).
- `early_bird` y `night_walker` conservan la conducta de la v3: hora local **entera** de 5 a 7 inclusive (05:00–07:59) y de 21 a 23 inclusive (21:00–23:59). No es una divergencia nueva.
- `weekly_goal` usa `weeklyGoalMet` con `threshold: 1` y `eq`; lo evalúa `GoalEngine`, no el cierre de sesión.

### AD-6 — Prueba de equivalencia con la v3: tres categorías y divergencias declaradas

- **Binds:** `Domain/`, CAP-1, CAP-3, CAP-4, CAP-7, CAP-8, CAP-13
- **Prevents:** que "idiomático" sea coartada para cambiar comportamiento en silencio — **y** que la prueba de equivalencia congele bugs conocidos como contrato
- **Rule:** la suite JS actual (**281 aserciones ejecutadas**, no 168 — el número anterior estaba reteclado sin verificar) se reparte en tres categorías, y cada aserción pertenece exactamente a una:

| Categoría | Qué | Cómo |
| --- | --- | --- |
| **Vectores** (~65) | Cálculos puros entrada → salida: `elapsedS`, `pace`, `v3distance`, cadencia, `recalibrate`, estimación de gap | Ficheros de datos neutrales. Los ejecutan `domain.js` **y** el dominio Swift |
| **Escenarios** (~111) | Secuencias de comandos sobre agregado mutable | Portados **a mano** a Swift Testing, con el test JS como referencia citada. No son vectores: el formato no los admite |
| **Excluidos** (~52) | La agregada v1 de vueltas | `domain-model.md §2` la elimina. No hay runtime Swift contra el que correrlos. **Declarados muertos, no olvidados** |

**Vectores nuevos, de autoría propia y obligatorios.** Ninguno de los cuatro ficheros JS contiene una sola aserción de `GoalEngine` ni de `AchievementEngine`, y **8 de los 14 logros no tienen ninguna cobertura** — entre ellos `first_5km`, precisamente el que cambió de semántica en Dart. La extracción sola no habría detectado el incidente que AD-5 previene. Se **escriben** vectores para los 14 logros (caso que desbloquea y caso que no) y para el `GoalEngine` (semana ISO, límites de lunes y domingo).

**Divergencias declaradas.** Estas son las conductas donde el dominio Swift **debe** diferir de `domain.js`. Su vector lleva el valor **corregido**, y `domain.js` está registrado como fallando ese vector a propósito:

| Divergencia | Fuente | Hoy en la v3 |
| --- | --- | --- |
| `early_bird`, `night_walker` y rachas en **hora local**, no UTC | `domain-model.md §9`, `achievements.md` | UTC |
| Lluvia por **código WMO** → categoría interna, no regex sobre string localizado | `achievements.md` | `/lluv\|llovi\|torment/i` |
| ~~Las pausas se restan una vez~~ | `domain-model.md §4` | **Ya no diverge:** corregido en la v3 el 2026-09-12. `domain.js` pasa el vector |
| ~~Rachas comparando fechas como fechas~~ | verificado | **Ya no diverge:** corregido en la v3 el 2026-09-12. `domain.js` pasa el vector |

Las dos primeras siguen siendo divergencias reales: son decisiones de plataforma. Las dos tachadas
eran **defectos**, y se arreglaron en la referencia antes de portar (decisión de Paul) — lo que además
permite **validar el arnés de vectores contra un runtime que ya existe**, antes de apostarle el port.

**Cumplimiento sin CI.** No hay servidor de integración (`SPEC` no-backend, AR-11). La ejecución de vectores y escenarios es un **script local** (`Scripts/verify-domain.sh`) que corre ambos runtimes, y su paso en verde es **Definition of Done de cada historia que toca `Domain/`**. Decir "bloquea el merge" sin mecanismo sería una aspiración, no una regla.

### AD-7 — Escritor único, y la frontera cruza con un DTO propio

- **Binds:** CAP-1, CAP-2, CAP-3, CAP-4, CAP-18
- **Prevents:** cuatro caminos de escritura concurrentes sobre un agregado que debe ser inmutable al cerrarse
- **Rule:** `SessionStore` es `@Observable` y `@MainActor` y es **el único** que muta la sesión. Adapters y temporizadores no escriben: publican eventos. **`CMPedometerData` no conforma a `Sendable`, y sus `NSNumber` tampoco** — el handler de CoreMotion, que corre en su propia cola serie, extrae los valores a un `struct` `Sendable` propio *dentro del handler* y solo ese DTO cruza al main actor. Pasar el objeto de CoreMotion es un error de compilación bajo AD-12, no un detalle de estilo. Descartado un `actor` fuera del main con proyección: cambia un riesgo de concurrencia inexistente a este volumen por un riesgo de coherencia real.

### AD-8 — La reconciliación es atómica, acotada, y vive fuera del dominio

- **Binds:** CAP-3, CAP-1
- **Prevents:** cerrar una sesión con pasos que llegan tarde; que `finish()` compita con una query en vuelo; y confiar en una query que falla en silencio
- **Rule:** al volver a foreground, la reconstrucción del gap es **atómica**: mientras dura, `SessionStore` rechaza todo comando y la UI los deshabilita. El flag es **`isReconciling`**, y es estado del **store**, nunca del agregado. **`SessionStatus` tiene tres casos: `active / paused / finished`.** No hay `idle`: "antes de iniciar" no es un estado del agregado, es que **no hay sesión** —`session == nil` en el store—, y modelarlo como cuarto caso obligaría a cada `switch` del dominio a tratar un estado que nunca existe. **`queryPedometerData` solo cubre 7 días y, pasado ese rango, devuelve datos parciales sin señalar error** — un tramo de más de 7 días **no se consulta**: se pasa directamente al estimador. La operación está acotada por timeout; al agotarse libera los comandos igual. Atómico sin timeout es un bloqueo con buenos modales.

  **El tramo y el gap no son lo mismo, y cada condición mira el suyo.** La condición de los 7 días mira el **tramo** —`[segmentStart, end]`, que es lo que se consulta—, mientras que la estimación se hace sobre el **gap** —`[backgroundedAt, end]`, el tiempo en background—. Por eso "no se consulta" **no equivale** a "no se estima": un tramo viejo con un gap corto **sí estima**, y lo que decide es si el **gap** cabe en `maxEstimableGapS` (20 min hoy). Si no hay `backgroundedAt` no hay gap que reconstruir y la reconciliación sale sin estimar y sin escribir nada en el registro. Es literalmente lo que dice el código al tomar ese camino: *"Tramo de más de 7 días: no se consulta; se estima solo si el gap cabe en el tope"*.

  **Cualquier respuesta no nula del sistema es dato** (R1, medido en el iPhone 14 el 2026-09-17): corta la estimación aunque traiga menos pasos de los ya vistos, porque el sistema consolida su histórico con retraso y la consulta va unos pasos por detrás del stream. Como `record` nunca resta, un acumulado menor no baja nada. Solo la **ausencia** de respuesta —`nil`, error, timeout o un tramo de más de 7 días— abre la puerta a estimar, y aun entonces `GapEstimator.outcome` decide con cuatro guardas en orden: la precondición de sesión `active`, y **las tres defensas** que nombra el código —el stream **no ha avanzado** ya sobre el gap, la **cadencia se toma en el inicio del gap** (y por debajo de `minPriorSampleS` = 120 s no hay cadencia representable, regla anterior a R1: `domain-model.md §4`) y el **tope** `maxEstimableGapS`—. *(Enmendado el 2026-09-20: esta regla decía que un tramo de más de 7 días "se degrada a estimación marcada `~`", y que se estimaba con el puerto devolviendo `null` **o vacío**. Las dos dejaron de ser ciertas con R1. **Re-enmendado el mismo día**: la primera reescritura decía que con más de 7 días "no se estima nada" y que "el registro dice que cortó el tope" — también falso, por confundir el tramo con el gap.)* [`SessionStore+Reconciliation.swift:23-26`, `:46`, `:60-95`; `GapEstimator.swift:18-20`, `:95-102`; spec-r1]

```mermaid
stateDiagram-v2
    [*] --> Active: iniciar (antes no hay sesión, no un estado idle)
    Active --> Paused: pausar (explícita)
    Paused --> Active: reanudar
    Active --> Finished: finalizar
    Paused --> Finished: finalizar
    Finished --> [*]
    note right of Active
        store.isReconciling = true al volver
        de background: comandos rechazados
        hasta resolver o agotar timeout.
        El agregado NO cambia de estado.
    end note
```

### AD-9 — Persistencia en JSON; el export es un contrato aparte

- **Binds:** CAP-9, CAP-10, CAP-14, CAP-15, CAP-1
- **Prevents:** acoplar el dominio a un framework de persistencia; y declarar resuelto el CSV que CAP-14 exige
- **Rule:** ficheros JSON `Codable` en Application Support, **escritura atómica** (temp + rename), cada uno con `schemaVersion`:

| Fichero | Contiene | Escrito por |
| --- | --- | --- |
| `sessions.json` | Historial de sesiones finalizadas | `HistoryStore` |
| `achievements.json` | Estado `{key, unlockedAt, progress}` | `AchievementsStore` |
| `settings.json` | Ajustes del producto. **Hoy: `recentQuoteIds` (ventana de frases) y `strideM`, que es un override *opcional*** — `nil` mientras nadie lo toque. La meta semanal y los toggles **aún no existen**: entran con la 3.1 y la 4.2 | `SettingsStore` |
| `activeSession.json` | Snapshot de la sesión viva; se guarda **por evento y por muestras, nunca con un temporizador** (ver abajo) | `SessionStore` |

`activeSession.json` es lo que hace posible la recuperación tras force-quit que CAP-1 y CAP-9 exigen (`domain-model.md §8`). **`§8` lo define en milisegundos; el dominio trabaja en segundos** — la conversión ocurre en el adapter de persistencia, nunca dentro.

**El autosave no es periódico, y decir "cada 10 s" lo describía mal.** El snapshot se escribe al **iniciar, pausar, reanudar, pasar a background y reconciliar**, más con la **muestra del podómetro** que llegue al menos `autosaveIntervalS` (**10 s**) después del último guardado. Los 10 s son un **espaciado mínimo entre escrituras por muestra**, no una cadencia: quieto no hay muestras y no hay escrituras, que es justo lo que AD-21 exige de cualquier unidad que quiera gastar presupuesto. Un temporizador de autosave escribiría con la sesión parada y sin nada que guardar. Se borra al finalizar. *(Enmendado el 2026-09-20; antes esta tabla decía "autosave cada 10 s".)* [`SessionStore.swift:29-32`, `SessionStore+StepCounting.swift:90`; AD-21; retro del Epic 1, S4]

**Export (CAP-14) es un contrato propio, no "el mismo formato".** El JSON de export **sí** reutiliza la serialización de `sessions.json`. El **CSV no**: es un segundo serializador y se especifica aquí porque dos historias lo escribirían distinto — columnas en este orden `fecha;hora;duracion_s;pasos_medidos;pasos_estimados;distancia_m;ritmo_s_km;fuente`, **separador de campo `;` y decimal `,`** (UI en español, y `,` como decimal rompe el CSV con separador `,`), cabecera siempre presente, UTF-8 con BOM para que Numbers y Excel lo abran sin pelear. El **import solo acepta JSON**, nunca CSV.

### AD-10 — Un puerto por capacidad de sistema, definido por el núcleo

- **Binds:** CAP-2, CAP-5, CAP-6, CAP-11, CAP-12, CAP-17, CAP-18
- **Prevents:** que dos pantallas hablen con un framework de sistema por su cuenta y cada una interprete el resultado a su manera
- **Rule:** un protocolo por capacidad en `Domain/Ports/`, implementado en `Adapters/`. **Ninguna vista importa un framework de sistema.** El conjunto es cerrado:

`MotionPort` · `LocationPort` · `WeatherPort` · `HealthPort` · `FeedbackPort` · `NotificationPort` · `LiveActivityPort` · `WakeLockPort` · `StoragePort` · `ClockPort` · `RandomPort`

`ClockPort` y `RandomPort` existen porque el dominio no puede llamar a `Date()` ni a un generador aleatorio: sin ellos, `MotivationEngine` (CAP-6) y todo cálculo temporal son invectorizables. `WakeLockPort` (`UIApplication.isIdleTimerDisabled`) recogería el wake lock que el PLAN derogado gobernaba y que si no se pierde. `LocationPort` es independiente de `WeatherPort`: **redondea las coordenadas a 2 decimales antes de entregarlas**, cumpliendo la restricción de Privacidad del SPEC en el único punto donde es verificable.

> ⚠️ **Estado al 2026-09-20: de los 11 existen 9.** Faltan `NotificationPort`, que **tiene dueño** —la historia **6.2**—, y `WakeLockPort`, que **no lo tiene**: el Epic 1 cerró sin él, ninguna de sus seis historias lo asumió y la 1.6 lo excluye en sus Boundaries. Qué hacer con él es la **pregunta abierta Q-3** de la retrospectiva del Epic 1 (*¿sigue siendo necesario, ahora que el conteo funciona con la pantalla bloqueada? Si lo es, ¿en qué epic?*), y **no se decide aquí**. El conjunto sigue cerrado como regla: lo que esta nota dice es que dos de sus miembros aún no están escritos, no que el conjunto cambie. [`epic-1-retro-2026-09-14.md`, S5 y Q-3]

### AD-11 — El permiso lo posee el adapter; la degradación es una sola tabla

- **Binds:** CAP-2, CAP-5, CAP-11, CAP-17, CAP-18
- **Prevents:** dos pantallas pidiendo el mismo permiso, y varios criterios sobre qué hacer cuando falta
- **Rule:** cada adapter posee el estado de su permiso y lo expone por el puerto como `status`; nadie más consulta al sistema. Toda petición va precedida de pre-pantalla explicativa. La respuesta a "falta esta capacidad" **es esta tabla**, y la cumple **cada frontera en su sitio**. La tabla vincula: ninguna frontera puede responder otra cosa, y una capacidad nueva entra añadiendo una fila aquí. Lo que la regla **no** exige es un tipo que la centralice — ver la enmienda de abajo:

| Capacidad ausente | Comportamiento | Dónde se cumple hoy |
| --- | --- | --- |
| Motion & Fitness denegado | Pantalla bloqueante con explicación y acceso a Ajustes. Sin ella no hay producto | `SessionStore+StartFlow.swift:17-30` (`start()`) → `MotionBlockedView`. **La única fila bloqueante de las seis** |
| Ubicación denegada | Sesión inicia sin clima. Nunca bloquea | `SessionStore+Weather.swift:26-35` (`beginWeatherForNewSession()`) |
| Red no disponible | Sesión inicia sin clima. Nunca bloquea | `OpenMeteoAdapter.swift:61-64` → `SessionStore+Weather.swift:141-170`: `CapabilityError` y `nil` silencioso. **Esta fila no es un permiso** — no hay `PermissionStatus` de la red, ni puerto con `status` que la exponga |
| HealthKit denegado o escritura fallida | La sesión se guarda local igual; el resumen muestra "no sincronizado", nunca un error | ⏳ **ni una línea**: no existe `Adapters/Health/` con escritura ni resumen que lo diga. La trae la **6.1** |
| Notificaciones denegadas | Recordatorios off en silencio | ⏳ **ni una línea**: falta `NotificationPort` (ver AD-10). La trae la **6.2** |
| Live Activity no disponible | Se omite. No es fallo de sesión | ⏳ **ni una línea** de esta decisión: `WalkTrackerActivity/` es solo render. La trae el **Epic 7** |

> ⚠️ **ENMENDADA el 2026-09-21 (B-9): la tabla vincula, y no hay ningún tipo que la implemente — ni lo va a haber.**
>
> Hasta hoy esta regla decía *"la respuesta a 'falta esta capacidad' está en **una única** `DegradationPolicy`"*, el Structural Seed listaba `Application/DegradationPolicy.swift` y `Domain/Ports/PermissionStatus.swift:7` lo citaba por su nombre. **Ese tipo nunca existió.** El Epic 2 traía el encargo explícito de reconciliarlo —era la primera degradación no bloqueante— y no se hizo ni se registró (D6 de la retro del Epic 2).
>
> **Decisión de Paul (2026-09-21): se enmienda la regla, no se construye el tipo.** Hoy tendría **dos llamantes** —las dos fronteras vivas— y **una sola rama bloqueante**; las otras cuatro filas las escribiría quien haga la 6.1, la 6.2 y el Epic 7, que es diseñar la abstracción antes de tener el segundo ejemplo real de cada clase. No eliminaría ningún `switch`: le pondría una indirección delante. Y no capturaría lo que de verdad varía entre filas —qué pantalla, qué texto y en qué momento—. Lo compartido ya está tipado y vive en `Domain/`: `PermissionStatus` y `CapabilityError`. **Precedente en este mismo documento:** AD-10 se dejó como conjunto cerrado con dos miembros sin escribir, en vez de cambiar la regla.
>
> **Lo que esta enmienda no hace, a propósito:** declarar las seis filas "cumplidas por convención". Sería cambiar una mentira por otra. La columna "Dónde se cumple hoy" dice la verdad completa: **tres filas tienen implementación y tres no tienen ni una línea**, y la fila de red **ni siquiera pasa por el vocabulario de permisos**, así que "el adapter posee el estado de su permiso" no la describe.
>
> **Dos huecos de la tabla siguen abiertos y no los tapa esta enmienda**, porque son de contenido y no de forma:
> 1. La fila de Live Activity **se evaluaría una sola vez**; el usuario puede desactivar Live Activities en mitad de una caminata, y existe `activityEnablementUpdates` para verlo. Dueño: el Epic 7. [`reviews/review-vigencia-tecnologica.md:359-362`]
> 2. **Falta una fila** para "los datos históricos existen pero están truncados" (CoreMotion guarda siete días): hoy la reconciliación de AD-8 produciría un conteo truncado que pasa por bueno, y eso no es "Motion denegado". Dueño: AD-8 / la historia que vuelva a tocar la reconstrucción. [`reviews/review-vigencia-tecnologica.md:427-429`]
>
> [`epic-2-retro-2026-09-20.md`, D6 y B-9; retro del Epic 1, S6; `spec-b9-degradacion-y-atribucion.md`]

### AD-12 — Swift 6, concurrencia estricta completa

- **Binds:** todo
- **Prevents:** que el aislamiento quede implícito habiendo cuatro caminos de escritura
- **Rule:** *strict concurrency* completa. Todos los tipos de `Domain/` son value types `Sendable`. Un `@unchecked Sendable` exige justificación en el propio código. Los tipos de framework que no son `Sendable` —`CMPedometerData` el primero— no cruzan fronteras de aislamiento: se traducen en el borde (AD-7).

### AD-13 — Liquid Glass se hereda, no se dibuja

- **Binds:** toda la UI
- **Prevents:** recrear a mano la estética iOS 17 plana de los mockups v3, peleando contra el SDK
- **Rule:** controles SwiftUI nativos; compilar contra el SDK de iOS 26 adopta Liquid Glass automáticamente. **Prohibida la key `UIDesignRequiresCompatibility`** (además, el sistema la ignora al compilar para iOS 27+: la adopción es inevitable, mejor asumirla). Para superficies propias se usan las APIs de adopción —`.glassEffect`, `GlassEffectContainer`, `ConcentricRectangle`—, nunca materiales dibujados a mano. Los colores del sistema se referencian, no se cablean en hexadecimal. Dibujo a medida limitado a **tres piezas**: anillo de meta, gráfico de tendencia, insignia de logro. Las cabeceras de sección ya **no** se renderizan en mayúsculas: los textos del String Catalog se escriben en su capitalización final.

  **Excepción declarada: tres colores propios** (chore de tokens 2026-09-18, ampliada por B-2 el 2026-09-20) — `AccentColor`, `EstimatedSteps` y `ErrorMessage`, como colorsets en `Resources/Assets.xcassets/`. Un color del sistema puede *ser* el problema: `.orange` daba **2,20:1** sobre blanco y `Color.red` da **3,55:1**, los dos por debajo del 4,5:1 que WCAG AA exige para texto normal, y los dos entraron en producción por esta puerta. Por eso el producto decide **exactamente tres** colores, y no más.

  **Los hexadecimales, los roles y los ratios medidos viven en un solo sitio: `DEROGACIONES.md §4`.** No se repiten aquí. Duplicar una tabla de datos es cómo divergen: esta misma copia llegó a omitir los ratios en oscuro de `ErrorMessage` que §4 sí daba, y el argumento contra duplicar el `0,655` vale igual para un ratio de contraste.

  Lo que esta regla sí fija, porque es la condición de la excepción y no un dato: son **colorsets con variante clara y oscura**, no hexadecimales en código; las vistas los referencian por nombre desde `UI/Style/DesignTokens.swift`; el **contraste está medido** contra el fondo real en los **dos** temas y `WalkTrackerTests/UI/DesignTokensTests.swift` lo **recalcula en cada ejecución de la suite**; y `Scripts/check-project-shape.sh` (sección 12) **veta la familia cromática entera** del sistema en `UI/`, no un color por su nombre. El resto de la paleta sigue siendo del sistema y se usa por su **rol** (`.primary`, `.secondary`, `.tint`), cuyo contraste garantiza el sistema. [`DEROGACIONES.md §4` — **fuente única de la tabla**; spec-ux-tokens-nativos, spec-b2]

### AD-14 — La sesión activa es un modo, no un destino

- **Binds:** CAP-1, navegación
- **Prevents:** poder navegar fuera de una sesión en curso como si fuera una pestaña más
- **Rule:** `TabView` de cuatro pestañas (Inicio · Historial · Logros · Ajustes), `NavigationStack` en cada una. La sesión activa se presenta como `fullScreenCover`. No es una quinta pestaña. **Deroga UX-DR5** ("navegación iconos top-right sin tab bar"), que describía una PWA de reemplazo de pantalla.

### AD-15 — La extensión de Live Activity no tiene dominio, y su contrato es un tipo

- **Binds:** CAP-18
- **Prevents:** una segunda implementación de las métricas viviendo en la extensión, y dos historias eligiendo `ContentState` incompatibles
- **Rule:** `WalkTrackerActivity` **solo renderiza**. No calcula, no lee ficheros, no importa `Domain`. **ActivityKit no usa App Group** para esto: el `ContentState` viaja por `request`/`update` con tope de 4 KB; compartir el tipo es **pertenencia a target**, no disco. Requiere `NSSupportsLiveActivities` en `Info.plist`. El `ContentState` vive en `Shared/` y lleva **valores ya formateados** más `startedAt` para que la extensión use `Text(timerInterval:)` en el cronómetro — es el único cálculo que se le permite, y existe porque refrescar el reloj por push consumiría el presupuesto de AD-21. `Shared/` incluye el formateo que la extensión necesita; `UI/Format/` no es importable desde la extensión.

### AD-16 — Un fichero, un dueño

- **Binds:** CAP-8, CAP-9, CAP-10, CAP-15
- **Prevents:** que dos stores escriban el mismo fichero con temp+rename y se pisen en silencio — sin error, sin conflicto, sin rastro
- **Rule:** cada fichero de AD-9 tiene **exactamente un** tipo que lo escribe (columna "Escrito por"). Los demás lo leen a través de su dueño, nunca del disco. Escribir un fichero del que no eres dueño es un fallo de revisión.

### AD-17 — Un solo disparador de logros; el desbloqueo es irrevocable

- **Binds:** CAP-8, CAP-15, CAP-7
- **Prevents:** que dos historias evalúen logros en momentos distintos del ciclo, y que borrar una sesión revoque un logro ya conseguido
- **Rule:** `AchievementEngine` se evalúa **en un único punto**: al finalizar una sesión, dentro de la misma transacción que la persiste. No se evalúa al abrir el historial, ni al pintar el grid, ni al borrar. Un logro con `unlockedAt` **nunca vuelve a `null`**: borrar una sesión (CAP-15) recalcula totales, meta y progreso de los **no** desbloqueados, y deja intactos los desbloqueados. `weekly_goal` es la excepción declarada: lo evalúa `GoalEngine` al cumplirse la meta, no el loop de sesión — y también es irrevocable.

### AD-18 — Sesión huérfana: se archiva, no se resucita

- **Binds:** CAP-1, CAP-9
- **Prevents:** que una historia restaure 72 h de wall-clock —26 km y `marathon_42km` por dejar el móvil en una mesa— y otra la descarte
- **Rule:** al arrancar con `activeSession.json` presente, `SessionStore` compara `now − startedAt` contra un umbral. **Por debajo:** se restaura como activa, con banner de recuperación. **Por encima:** se cierra automáticamente recortada al último dato real del coprocesador, se marca `recovered: true`, y **no dispara logros ni celebración** — una sesión que nadie finalizó no se premia. El umbral es una constante de `formulas.json`, no un número en el código.

### AD-19 — Un solo calendario, en hora local

- **Binds:** CAP-7, CAP-8, CAP-10, CAP-17
- **Prevents:** que el anillo de meta y el historial den **dos números distintos para la misma semana**, y que una sesión de domingo a las 23:30 pertenezca a dos días a la vez
- **Rule:** existe **un** `AppCalendar`, expuesto por `ClockPort`, con `identifier = .iso8601`, `firstWeekday = 2` (lunes) y **`timeZone` = la del dispositivo**. Nadie más construye un `Calendar`, y `Calendar.current` está prohibido. Semana ISO, rachas, `early_bird`, `night_walker` y agrupación del historial usan ese calendario. Esto resuelve la contradicción entre `domain-model.md §5` (UTC) y `§9` (hora local) **a favor de §9**, y es una de las divergencias declaradas de AD-6.

### AD-20 — Superficies de comando y acciones irreversibles

- **Binds:** CAP-1, CAP-15, CAP-14
- **Prevents:** que cada pantalla invente su propio gesto destructivo y su propio criterio de confirmación
- **Rule:** una acción irreversible (borrar sesión, borrar todos los datos, descartar pasos estimados, finalizar sesión) se dispara **solo** desde una superficie declarada, exige **confirmación explícita**, y su objetivo táctil mide **≥ 44 pt** — verificable, no aspiracional. El borrado en listas usa el gesto nativo de iOS (`swipe` + `.destructive`), no un icono embebido en la fila. **Deroga UX-DR7** en su prohibición de swipe-to-delete, que era una restricción de la PWA.

### AD-21 — Presupuesto de energía y cadencia de refresco

- **Binds:** NFR-8, CAP-2, CAP-4, CAP-18, Success signal
- **Prevents:** que cada unidad elija su propia frecuencia de actualización y la suma incumpla "30 min sin degradación notoria (≤ 5 % de caída)" — el criterio de éxito del SPEC, enmendado el 2026-09-13
- **Rule:** tres cadencias, fijadas aquí porque varias unidades deben compartirlas:
  - **Conteo:** `CMPedometer` en modo continuo mientras hay sesión activa; la query histórica se reserva a la reconciliación de AD-8. **Sus resultados no se *suman*.** Las dos fuentes **sí conviven** —la reconciliación consulta con el stream abierto, y así lo hacen la 1.5 y la 1.6—: lo que está prohibido es acumular las dos como si fueran incrementos independientes. El mecanismo que lo garantiza es que ambas entran por el mismo camino y el store **se queda con el máximo acumulado visto** (`highestCumulativeSteps`), así que lo que el stream entregue después de una consulta no vuelve a contarse. *(Enmendado el 2026-09-20: decía "No se combinan", y esa redacción daba pie a leer que no pueden estar abiertas a la vez, que no es la intención.)* [`SessionStore+Reconciliation.swift:19-21`, `SessionStore+StepCounting.swift:71-73`; retro del Epic 1, R10]
  - **UI:** el cronómetro refresca a **1 Hz** y solo redibuja la vista de sesión. Las métricas derivadas se recalculan con el dato del coprocesador, no con el tick.
  - **Live Activity:** actualización **por evento** (cambio de km, pausa, reanudación, fin), nunca periódica. El reloj lo anima la extensión con `Text(timerInterval:)`, coste cero de actualizaciones.
  - La medición de 30 min en el iPhone 14 es **gate de la historia 8.4**, que corre **al terminar el Epic 1** y antes de los epics 2–7: no es un chequeo posterior. Mide conteo y UI; la cadencia de la Live Activity la recomprueba la 7.2 con el mismo umbral. *(Reubicado y enmendado el 2026-09-13; antes "60 min" y "gate de la historia final".)*

### AD-22 — Sin fuente en el dominio, no se pinta

- **Binds:** toda la UI, CAP-4
- **Prevents:** la clase de invención que la validación de mockups documentó — calorías sin peso corporal, puntos sin economía, "restaurar compras" sin tienda
- **Rule:** una pantalla solo muestra magnitudes que el dominio produce. Una métrica nueva en la UI requiere primero un cálculo en `Domain/` con su vector (AD-6). Las métricas ausentes se representan como tales (`—`), nunca como `0`.

### AD-23 — Un solo árbol de producto

- **Binds:** repositorio
- **Prevents:** que el tercer sustrato conviva con los dos anteriores y cada build tenga que elegir
- **Rule:** el producto vive en `WalkTracker/`. Se eliminan del árbol de producto `ios/App/`, `ios/capacitor-cordova-ios-plugins/`, `www/`, `adapters/`, `capacitor.config.json` y `walktracker-kit/`. **`domain.js`, `motivation.js`, `climate.js`, `storage.js` y `test/` se conservan congelados** como referencia de contraste de AD-6, no como código vivo. Las 446 líneas de `ios/Runner/AppDelegate.swift` —única implementación existente de `HKWorkoutBuilder` y `Activity.request`— viven en `feature/flutter-substrate` (`d9d3fbc`), **que no es ancestro de `HEAD`**: entran por extracción explícita (`git checkout feature/flutter-substrate -- ios/Runner/AppDelegate.swift`) en la primera historia de fundaciones, troceadas en los adapters que les corresponden. No se hace merge de esa rama.

### AD-24 — Atribución de Open-Meteo

- **Binds:** CAP-5, restricción de Licencias del SPEC
- **Prevents:** incumplir una licencia por no haberla mirado
- **Rule:** Open-Meteo se publica bajo **CC-BY 4.0**, que exige atribución visible — no es copyleft, pero tampoco es Apache-2.0/MIT como la restricción del SPEC presupone. La atribución va **en dos sitios y los dos son obligatorios**: en **Ajustes → Acerca de**, que es lo que la ve alguien que nunca ha capturado clima, y **junto al dato** en la tarjeta de clima de la sesión, que es lo que pide Open-Meteo por escrito (*"You must include a link next to any location Open-Meteo data are displayed"*). La restricción de licencias del SPEC se enmienda para admitir CC-BY en fuentes de datos (no en código). Sustituir Open-Meteo por WeatherKit elimina la obligación y es un cambio de adapter (AD-10). **La cláusula, verificada y citada, y qué parte de ella cumple cada sitio, están en `NOTICE`** (raíz del repo), que es el documento que hay que leer antes de tocar cualquiera de los dos.

  > ✅ **CERRADO el 2026-09-21 (B-9).** Desde el 2026-09-20 esta regla llevaba un ⚠️ que decía *"abierto — no está cumplido, y esta regla lo daba por hecho"*: la atribución vivía solo en `WeatherCard.swift`, **dentro de `if let weather`**, así que no se veía sin clima ni fuera de una sesión, y la 2.3 creó Ajustes y la excluyó con un comentario, que no es un destino. Ya existe la sección **"Acerca de"** en `WalkTracker/UI/Settings/SettingsView.swift`, con `AboutSection` como fuente única de lo que pinta; la de la tarjeta **se queda**, porque quitarla empeoraría el cumplimiento justo donde el dato se ve. **La obligación tiene dueño escrito** —`NOTICE`, esta regla, la nota de `epics.md` bajo la 2.3 y una entrada de `deferred-work.md`—, que es lo que faltó la primera vez: se cayó porque nadie poseía el "Acerca de" (lección L2). [`epic-2-retro-2026-09-20.md`, D6 y B-9; `spec-b9-degradacion-y-atribucion.md`; `NOTICE`]
  >
  > ✅ **Y la segunda mitad de §3(a)(1)(C), cerrada también el 2026-09-21** (decisión de Paul, el mismo día y antes de que la 3.1 llegara). Esta nota decía hasta entonces que *la app nombra la licencia ("CC BY 4.0") pero **no enlaza al texto**: ese enlace vive solo en `NOTICE`, que no viaja dentro del `.app`*. Ya lo enlaza: "Acerca de" tiene una **segunda fila** a `https://creativecommons.org/licenses/by/4.0/` —la URL canónica que `NOTICE` §2 verificó descargándola—, declarada en `AboutSection.licenseTextURL` y fijada con su ruta por `AboutSectionTests`. Para hacerlo, Paul **renegoció** la línea del bloque congelado de B-9 que lo prohibía (*"Never: … ni otras licencias"*), anotada en la spec del chore y en su Spec Change Log. El rastro de cuando estuvo abierto **no se borra**: vive en `NOTICE` §5, que lo conserva con fecha. Siguen siendo **dos filas**: la versión de la app y los ajustes de otras épicas no se adelantan.

### AD-25 — El logro de la meta y la celebración de la meta son dos cosas distintas

- **Binds:** CAP-7, CAP-8, CAP-12, AD-5, AD-17
- **Prevents:** que la primera semana que Paul cumple su meta se celebre **dos veces** —una por el logro `weekly_goal` y otra por el anillo— y que, a partir de la segunda, no se celebre **ninguna**, porque el logro ya está desbloqueado y es irrevocable
- **Rule:** `weekly_goal` **sigue siendo un desbloqueo de por vida e irrevocable** —AD-5 congela el catálogo y AD-17 lo declara la excepción que evalúa `GoalEngine` al cumplirse la meta, no el cierre de sesión— y **no produce celebración propia**. Quien celebra es **siempre el anillo, una vez por semana**, con estado propio: `lastGoalCelebratedWeek` en `settings.json`, campo opcional cuyo dueño es `SettingsStore`, que guarda la semana ISO **local** (`GoalEngine.weekKey`, p. ej. `2026-W28`) y no sube el `schemaVersion`. Refrescar Inicio, volver de Ajustes o relanzar la app no vuelven a disparar nada. La regla la **heredan la 3.2** —el evaluador de logros no emite celebración para `weekly_goal`— y **la 3.4**, que engancha la celebración visible a la señal del anillo y no al desbloqueo.

  > Cierra **H-08** de `reviews/review-adversario.md`, que decía: *"el estado 'meta ya celebrada esta semana' no existe en ninguna forma de almacenamiento y ningún AD dice quién lo posee; `achievements.md` dice que `weekly_goal` se evalúa externamente vía GoalEngine — externamente **a qué store**, no lo dice nadie"*. Decisión de Paul del 2026-09-21 (D1 de `spec-3-1-meta-semanal-anillo.md`), registrada aquí y no solo en la spec porque es una decisión que **heredan dos historias posteriores**. Implementado en `WalkTracker/Application/SettingsStore+Goal.swift` (`goalRingDidUpdate()`) y `AchievementsStore+Goal.swift` (`unlockWeeklyGoal(at:)`, idempotente).

## Consistency Conventions

| Concern | Convention |
| --- | --- |
| Nombres | Lenguaje ubicuo de `domain-model.md §1`, en inglés en el código y español en la UI. Un tipo por fichero |
| Puertos | Puerto `XxxPort`; implementación `XxxAdapter`; doble de test `XxxStub` |
| Identidad | `UUID` v4 para sesiones; claves de logro las de `achievements.md`, estables, nunca renumeradas |
| Tiempo | **Segundos** en todo el dominio. Los milisegundos de `domain-model.md §8` se convierten en el adapter de persistencia. Serialización ISO-8601 con fracción y zona |
| Calendario | Solo `AppCalendar` (AD-19). `Calendar.current` prohibido |
| Unidades | Metros y segundos en el dominio, siempre. La conversión a km y `mm:ss` vive en `UI/Format/` y, para la extensión, en `Shared/` |
| Iconografía | **SF Symbols** en todo el chrome. Emoji **solo** en las insignias de logro, porque el catálogo canónico los especifica como dato (AD-5) |
| Errores | El dominio lanza errores tipados. Una única traducción a mensaje de usuario. Nunca se muestra un error crudo del sistema |
| Textos | String Catalog (`Localizable.xcstrings`), en su capitalización final. Sin literales de UI dispersos: es donde se sostiene "celebrar, nunca culpar" |
| Accesibilidad | VoiceOver con etiquetas que dicen la magnitud completa ("3,2 kilómetros"; los pasos estimados se anuncian como estimados). Dynamic Type sin recortes. Reduce Motion respetado. Las tres piezas dibujadas de AD-13 requieren etiqueta explícita: un `Canvas` no la trae |
| Estado | Mutación solo por métodos de intención en los stores. Nunca escritura directa a una propiedad publicada desde una vista |
| Constantes | Una constante va a `Resources/formulas.json` si es una **calibración medible**: un número que una medición en el iPhone puede cambiar sin cambiar ninguna regla (`defaultStrideM`, `reconciliationTimeoutS`, `orphanSessionThresholdS`, `maxEstimableGapS`). **No** van al fichero, y viven en el código junto a la regla que las usa: los **hechos del sistema** (los 7 días de histórico de `queryPedometerData`), las **reglas de producto** (el rango humano 0,3–1,2 m: avisa, no calibra), los **límites derivados** de la aritmética (`maxRepresentableStrideM`, que sale de la fórmula y no se elige) y las **cadencias de AD-21** (1 Hz de la UI, "por evento" de la Live Activity), que son decisiones de arquitectura y no parámetros. La prueba: si el número se pudiera medir de nuevo y el cambio fuera legítimo sin tocar nada más, va al JSON — el criterio es que el número **admita** una medición que lo cambie, no que esa medición se haya hecho. **Salir de `provisional` tiene por tanto dos caminos, y los dos están usados:** el valor se **mide** (`reconciliationTimeoutS`, fijado en 1 s por la 8.4 con la regla de Paul del 2026-09-14) o se **decide**, cuando la medición no es viable y esperarla bloquearía (`orphanSessionThresholdS`, que no es medible en una caminata de 30 min y se quedó en 6 h como **valor decidido, no medido**). Lo que la marca `provisional` significa es "este número aún no está fijado", no "aún no está medido"; lo que nunca debe perderse es **cuál de los dos caminos** lo fijó, y eso se escribe donde se fija [`8-4-medicion-referencia.md:104-105`, `:189`] |
| Tests | Swift Testing para dominio y aplicación. Todo cálculo del dominio pasa por AD-6 antes que por un test a mano. **XCUITest está descartado** (2026-09-20), no diferido: la lógica de presentación se extrae a tipos probables sin SwiftUI y se prueba con la suite que ya existe — sin target nuevo, sin fragilidad y sin romper la regla de cero dependencias de terceros. Lo que eso **no** cubre son los solapes entre capas, que solo se ven renderizando, y esos van a verificación manual [`decisiones-2026-09-20.md` D1] |
| Logging | `OSLog` con subsistema propio. Sin telemetría, sin red, sin terceros |

## Stack

| Name | Version |
| --- | --- |
| Swift | 6.2.4 *(el toolchain que trae Xcode 26.3)* |
| Xcode | 26.3 (17C529) — **suelo verificado en la máquina de Paul**, no un techo |
| iOS SDK | 26.2 |
| iOS deployment target | 26.0 |
| SwiftUI · Observation | SDK iOS 26 |
| CoreMotion · CoreLocation · HealthKit · ActivityKit · CoreHaptics · UserNotifications | SDK iOS 26 |
| Swift Testing | incluido en Xcode 26 |
| Open-Meteo | API pública sin key, timeout 3 s, **CC-BY 4.0** (AD-24) |
| Dependencias de terceros | **ninguna** |

Estas versiones son las **instaladas y comprobadas** el 2026-09-12 (`xcodebuild -version`,
`swift --version`), no las últimas publicadas — 26.6 / 6.3.3 existen y no están aquí. Subir dentro
del ciclo 26 es seguro y no requiere tocar este spine: Swift 6.2 ya trae concurrencia estricta
completa (AD-12) y el SDK 26.2 compila para un deployment target de 26.0 (AD-2). Lo que **no** se
mueve durante el desarrollo es el dispositivo, congelado en iOS 26 por decisión de Paul (SPEC OQ-5).

## Structural Seed

**Esto es el árbol *objetivo*, no un inventario de lo que hay hoy.** Fija dónde va cada cosa cuando
se escriba; buena parte aún no existe, y así debe ser a mitad de los epics. Para que no se lea como
inventario, lo que **todavía no está en el árbol** al **2026-09-21** lleva `⏳` con la historia que lo
trae.

> El `⚠️` estaba reservado a un caso distinto —algo que el propio documento y el código dan por
> existente sin estarlo— y solo hubo uno: `Application/DegradationPolicy.swift`. **Sale del árbol
> el 2026-09-21** (B-9): la enmienda de AD-11 decidió que ese tipo no se escribe, así que dejarlo
> aquí lo seguiría prometiendo. Hoy no queda ningún `⚠️`, y eso es lo correcto: un árbol objetivo
> puede tener cosas por escribir (`⏳`), no cosas que se dan por escritas.

```text
WalkTracker/
  App/                      # entrada + composition root (único sitio que conoce todas las capas)
  Domain/                   # PURO — solo Foundation · (vive en `Domain/` en la raíz, no bajo `WalkTracker/`)
    Session.swift  Metrics.swift  Calibration.swift
    Engines/                # Goal ⏳3.1 · Achievement ⏳3.2 — los dos escritos viven fuera de
                            #    `Engines/`: `Session/GapEstimator.swift` y `Motivation/MotivationEngine.swift`
    Ports/                  # los 11 puertos de AD-10 — existen 9 (ver la nota de AD-10)
    DomainError.swift
  Application/
    SessionStore.swift      # @MainActor @Observable — escritor único (AD-7)
    SettingsStore.swift
    HistoryStore.swift  AchievementsStore.swift     # ⏳ no existen — los trae la 5.1
                            # La tabla de degradación de AD-11 NO tiene fichero aquí: la cumple
                            #    cada frontera en su sitio (enmienda del 2026-09-21, B-9)
  Adapters/
    Motion/ Location/ Weather/ Health/ Feedback/ Persistence/ Clock/ Random/ LiveActivity/
    Notifications/          # ⏳ no existe — la trae la 6.2, con `NotificationPort`
    WakeLock/               # ⏳ no existe, y NO tiene historia dueña — pregunta abierta Q-3 (ver AD-10)
  UI/
    Home/ Session/ Settings/ Format/ Style/ Permission/
    Summary/ History/ Achievements/   # ⏳ no existen — 1.4 dejó un resumen mínimo; las trae 3.3 / 5.2
    Components/             # ⏳ no existe — GoalRing (3.1) · TrendChart (5.2) · AchievementBadge (3.3), las 3 de AD-13
  Resources/
    achievements.json  formulas.json  quotes.json  Localizable.xcstrings
    Assets.xcassets/        # los 3 colorsets de la excepción de AD-13 (`DEROGACIONES.md §4`)
Shared/                     # ActivitySnapshot + su formateo (AD-15) — target compartido
WalkTrackerActivity/        # Widget Extension — solo render
WalkTrackerTests/
  Vectors/                  # los ~65 vectores + los nuevos de logros y meta (AD-6)
  Scenarios/                # los ~111 portados a mano
Scripts/verify-domain.sh    # ejecuta ambos runtimes contra los vectores (AD-6)
```

**Envoltura operativa.** Dev: build local desde Xcode al iPhone 14 físico — el simulador no tiene coprocesador y no sirve para CAP-2/CAP-3. Distribución: TestFlight, opcional. Sin CI (AD-6 fija el mecanismo alternativo). Sin crash reporting ni analítica: la restricción de Privacidad del SPEC los prohíbe. Requiere cuenta Apple Developer de pago (A-1). Usage strings obligatorias en `Info.plist`: `NSMotionUsageDescription`, `NSHealthUpdateUsageDescription`, `NSLocationWhenInUseUsageDescription`, más `NSSupportsLiveActivities` y el entitlement de HealthKit.

## Capability → Architecture Map

| Capability | Lives in | Governed by |
| --- | --- | --- |
| CAP-1 sesión y cronómetro | `Domain/Session` + `SessionStore` | AD-3, AD-7, AD-14, **AD-18** |
| CAP-2 conteo continuo | `Adapters/Motion` | AD-7, AD-10, AD-11, AD-21 |
| CAP-3 reconstrucción del gap | `SessionStore` + `GapEstimator` | **AD-8**, AD-6 |
| CAP-4 métricas en vivo | `Domain/Metrics` | AD-4, AD-6, **AD-22** |
| CAP-5 clima | `Adapters/Weather` + `Adapters/Location` | AD-10, AD-11, **AD-24** |
| CAP-6 frase motivacional | `Engines/Motivation` + `RandomPort` | AD-10 |
| CAP-7 meta semanal | `Engines/Goal` | AD-5, AD-6, **AD-19** |
| CAP-8 14 logros | `Engines/Achievement` + `achievements.json` | **AD-5**, **AD-17**, AD-6 |
| CAP-9 persistencia garantizada | `Adapters/Persistence` | AD-9, **AD-16** |
| CAP-10 historial y tendencia | `HistoryStore` + `UI/History` | AD-9, AD-19 |
| CAP-11 Apple Salud | `Adapters/Health` | AD-10, AD-11 |
| CAP-12 feedback | `Adapters/Feedback` | AD-10 |
| CAP-13 recalibración | `Domain/Calibration` + `SettingsStore` | AD-4, AD-6 |
| CAP-14 export / import | `Adapters/Persistence` | **AD-9** |
| CAP-15 borrado de sesiones | `HistoryStore` | AD-16, **AD-17**, **AD-20** |
| CAP-17 recordatorios | `Adapters/Notifications` | AD-10, AD-11, AD-19 |
| CAP-18 Live Activity | `WalkTrackerActivity` + `Shared` | **AD-15**, AD-21 |

## Deferred

| Diferido | Por qué puede esperar |
| --- | --- |
| ~~Valor del timeout de reconciliación y del umbral de sesión huérfana~~ | **Cerrado el 2026-09-14, y no de la misma forma los dos.** El **timeout se midió**: la regla de Paul sobre la duración máxima real de la consulta lo dejó en **1 s**. El **umbral de huérfana no es medible** en una caminata de 30 min y se quedó en **6 h** como **valor decidido, no medido** — lo que la 8.4 afirmaba reemplazar "por los medidos" solo se cumplió para uno. `provisional` está vacío [`8-4-medicion-referencia.md:104-105`, `:189`] |
| Enumeración completa de `formulas.json` | El fichero existe desde el día uno; su contenido se llena al portar cada cálculo. Hay ≥ 30 constantes en el JS, con `0.655` triplicado — consolidarlas es parte del port, no una decisión previa |
| Migración de esquema | `schemaVersion` presente desde el día uno; con arranque limpio (OQ-3) no hay nada que migrar |
| Diseño visual de las tres piezas dibujadas | Depende de la v4 de mockups, congelada hasta este spine |
| WeatherKit en lugar de Open-Meteo | Cambio de adapter, aislado por AD-10; eliminaría la obligación de AD-24 |
| ~~XCUITest~~ | **Descartado el 2026-09-20, ya no es un diferido.** Decisión D1: la lógica de presentación se extrae a tipos probables sin SwiftUI y se prueba con la suite existente; sin target de XCUITest. Los solapes entre capas quedan en verificación manual, no esperando un arnés que no va a llegar [`decisiones-2026-09-20.md` D1] |
| Dynamic Island | Sin hardware para validarla (iPhone 14). Solo debe compilar |

## Preguntas abiertas

*(Ninguna. Las dos que había se resolvieron el 2026-09-12, el mismo día.)*

| Resuelta | Cómo |
| --- | --- |
| iOS 27 sale el 14 de septiembre y el dispositivo de validación se actualizaría | **Paul: el iPhone 14 se congela en iOS 26** hasta terminar el desarrollo; toolchain fijo en **Xcode 26.3 (17C529) / Swift 6.2.4**, que es lo que fija la tabla de Stack de arriba y lo que responde la máquina. Consecuencias aceptadas en `SPEC.md` OQ-5: sin parches nuevos durante el ciclo, y la primera sesión tras actualizar a iOS 27 es revalidación obligatoria de CAP-2 y CAP-3. *(Corregido el 2026-09-20: esta celda decía "Xcode 26.6 / Swift 6.3.3" y contradecía al propio Stack, que ya advertía que esas versiones "existen y no están aquí". Verificado con `swift --version` y `xcodebuild -version`.)* |
| `SPEC.md` seguía declarando Capacitor como Constraint y la reescritura SwiftUI como Non-goal | **Enmendado el 2026-09-12.** Constraints, Non-goals, A-2, Licencias y companions actualizados; `capabilities.md` y `platform-matrix.md` reescritos a mecanismos nativos. Inventario en `DEROGACIONES.md §2` y `§3` |
