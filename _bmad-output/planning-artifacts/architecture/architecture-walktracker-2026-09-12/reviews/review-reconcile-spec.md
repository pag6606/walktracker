---
type: review
lens: reconciliación SPEC → spine
subject: ARCHITECTURE-SPINE.md (WalkTracker iOS SwiftUI nativa, 2026-09-12)
against:
  - ../../../../specs/spec-walktracker-ios/SPEC.md
  - ../../../../specs/spec-walktracker-ios/capabilities.md
  - ../../../../specs/spec-walktracker-ios/domain-model.md
  - ../../../../specs/spec-walktracker-ios/achievements.md
  - ../../../../specs/spec-walktracker-ios/platform-matrix.md
date: '2026-09-12'
---

# Revisión de reconciliación — qué del SPEC no aterrizó en el spine

## Veredicto

El spine cubre bien la **estructura** (18 capabilities mapeadas, capas, puertos, persistencia) y es fuerte donde el SPEC era vago; falla en los **requisitos silenciosos**: la corrección deliberada de zona horaria y del mapeo de lluvia (`domain-model.md §9`) no solo falta sino que **AD-6 la contradice de frente**, el redondeo de coordenadas a 2 decimales y el límite de batería desaparecen sin dejar rastro, el snapshot de sesión activa (§8) no tiene fichero en AD-9, y la derogación de Capacitor se declara en AD-1 pero no se ejecuta en ningún sitio (los dos companions que debían documentarla no existen).

Cuenta gruesa: **18/18 capabilities** con casilla en el mapa, pero **9 reglas normativas** de sus criterios de aceptación sin sustrato; **2 de 9 constraints** perdidas (privacidad-coordenadas, batería); **1 non-goal violado sin acta** (reescritura SwiftUI); **3 de 9 secciones** de `domain-model.md` sin cobertura (§7, §8 parcial, §9 nula).

---

## 1. Hallazgos por severidad

### F-1 · CRÍTICA — AD-6 congela como contrato el bug que `domain-model.md §9` ordena corregir

`domain-model.md §9` y las dos notas transversales de `achievements.md` son explícitas: en iOS, `early_bird`, `night_walker` y el cálculo de racha se evalúan en **hora local**, no en UTC, y `rain_walker` mapea la condición del proveedor a una categoría interna `rain` en vez de aplicar regex sobre el string localizado. La nota dice literalmente "para que la portación lo corrija deliberadamente, no por arrastre".

AD-6 dice: las aserciones de `test/{domain,session-v3,motivation,gapestimator}-tests.js` se extraen a vectores, **`domain.js` y el dominio Swift ejecutan el mismo fichero**, y **un vector que falla bloquea el merge**.

El comportamiento heredado que se convertiría en contrato está en el código, verificado hoy:

- `motivation.js:175` → `const h = new Date(session.startedAt).getUTCHours();` (`early_bird` / `night_walker`)
- `motivation.js:158` → clave de día de racha con `getUTCFullYear/Month/Date`
- `motivation.js:194-199` → semana de meta con `getUTCDay` y `getUTC*`
- `motivation.js:116` → `/lluv|llovi|torment/i.test(session.weather.condition)`

Y las reglas de logros viven precisamente en `motivation-tests.js`, uno de los cuatro ficheros que AD-6 nombra. Resultado: el dominio Swift correcto **fallará los vectores** y el merge quedará bloqueado, o alguien "arreglará" el Swift hacia UTC para que pasen — exactamente el arrastre que §9 quería evitar.

**Falta:** AD-6 no tiene cláusula de excepción. Necesita una lista explícita de **divergencias intencionadas** (vectores marcados `legacy-only`, o vectores nuevos escritos a mano para el comportamiento corregido, con `domain.js` excluido de ejecutarlos).

### F-2 · CRÍTICA — La derogación de Capacitor se declara pero no se ejecuta; el contrato canónico queda contradiciendo al spine

AD-1 "deroga `PLAN-CAPACITOR-v2.md` y reabre OQ-1". Nada de eso llegó a los documentos:

- El SPEC sigue teniendo **Capacitor como primer Constraint** ("decisión Paul, OQ-1"), lista `PLAN-CAPACITOR-v2.md` en `companions:` (= contrato canónico), y su sección Open Questions sigue diciendo **"Ninguna abierta"** cuando AD-1 acaba de reabrir OQ-1.
- El SPEC tiene como **Non-goal explícito**: *"Reescritura SwiftUI total de la app (decisión Paul, OQ-1: Capacitor)"*. AD-1 hace exactamente ese non-goal. El spine no lo menciona: deroga el plan de implementación pero no reconoce que está atravesando un non-goal declarado con nombre y fecha de decisión.
- El frontmatter del spine declara `companions: [REESTIMACION-EPICS.md, DEROGACIONES.md]`. **Ninguno de los dos existe** en la carpeta (solo hay `ARCHITECTURE-SPINE.md` y `.memlog.md`). El acta de derogación es una referencia colgante.
- El Success signal del SPEC exige *"La viabilidad de Capacitor queda demostrada en su iPhone físico"*. Con Capacitor fuera, esa mitad del Success signal queda sin traducir (ver F-6).

Esto no es cosmético: cualquier agente que abra el SPEC como "contrato canónico, preservation-validated" construirá Capacitor.

### F-3 · ALTA — Privacidad: el redondeo de coordenadas a 2 decimales desaparece, y la ubicación no tiene puerto ni dueño

El Constraint de Privacidad tiene tres partes; el spine conserva dos (datos en dispositivo, sin analítica/telemetría/crash reporting) y **pierde la tercera**: *"si el clima sale por red, las coordenadas se redondean a 2 decimales antes de enviarse"*. Es el único mecanismo de privacidad activo del producto (la única llamada de red que existe) y no aparece en ningún AD, convención, Stack ni Deferred. Hoy solo sobrevive en `capabilities.md` CAP-5 y en la sección "Lo que NO cambia" de `platform-matrix.md` — un documento escrito para Capacitor y, por tanto, en vía de obsolescencia (F-15).

Agravante estructural: AD-10 enumera ocho puertos —`MotionPort`, `HealthPort`, `FeedbackPort`, `WeatherPort`, `NotificationPort`, `LiveActivityPort`, `ClockPort`, `StoragePort`— y **no hay `LocationPort`**. Pero AD-11 lista "Clima no disponible (sin red, **sin ubicación**)" como caso de degradación, y el snapshot de clima necesita coordenadas. Nadie posee el permiso de ubicación ni el redondeo. Si cae dentro de `WeatherAdapter`, entonces un adapter posee dos permisos, lo que roza la regla "cada adapter posee el estado de su permiso" de AD-11 y deja el redondeo escondido en un detalle de implementación en vez de ser una regla arquitectónica.

### F-4 · ALTA — El snapshot de sesión activa (`domain-model.md §8`) no tiene fichero en AD-9

AD-9 fija "un fichero por preocupación — `sessions.json`, `achievements.json`, `settings.json`". Falta el cuarto: `activeSession`, cuya forma el SPEC define campo a campo (`{startedAtMs, stepsMeasured, stepsEstimated, totalPausesMs, paused, pausedAtMs, strideM, weather|null, quoteId}`), con **autosave cada 10 s y al ir a background** y **recuperación silenciosa al reabrir**.

Sin él no hay sustrato para dos criterios de aceptación *Must*:
- CAP-1: *"Force-quit de la app con sesión activa → al reabrir, la sesión se recupera con el tiempo correcto"* + indicador **"Sesión recuperada" 3 s**.
- CAP-9: *"Force-quit con sesión activa → recuperación silenciosa desde snapshot"*.

AD-8 cubre el retorno a foreground de una app **viva** (reconciliación atómica del gap), que es un caso distinto del proceso muerto. La cadencia de autosave y el indicador de 3 s tampoco aparecen en ninguna convención.

### F-5 · ALTA — CAP-18 en background: no hay política de ejecución en segundo plano, y AD-8 la presupone ausente

CAP-18 es *Must* y su criterio es *"sesión activa + teléfono bloqueado → métricas **actualizándose** en la Live Activity"*. Actualizar una Live Activity con la app suspendida requiere, o bien mantener el proceso vivo (background mode / actualizaciones en vivo de CMPedometer con su entitlement), o bien **push tokens de ActivityKit** — que exigirían servidor y chocarían con el invariante No-backend.

El spine no menciona modos de background, entitlements, `NSMotion*`/`NSHealth*` usage descriptions, ni la cadencia/presupuesto de actualización de la Live Activity. Peor: AD-8 está construido sobre la premisa contraria —*"al volver a foreground, la reconstrucción del gap"*— que solo tiene sentido si la app **no** estuvo ejecutándose. Las dos decisiones no pueden ser ambas ciertas sin una regla que las concilie (p. ej.: la app sí vive en background durante la sesión, y AD-8 cubre solo el caso de terminación/suspensión forzada). Tampoco hay política de `staleDate` ni de descarte de la actividad.

### F-6 · ALTA — El Constraint de batería desaparece por completo

*"Batería: una sesión de 60 min con conteo continuo no degrada la batería de forma notoria"* es un Constraint del SPEC y la mitad del Success signal. En el spine no hay AD, convención, ítem de Stack ni Deferred que lo recoja. La "Envoltura operativa" menciona validación en iPhone 14 físico, pero solo para CAP-2/CAP-3 (precisión), no para consumo. Con F-5 sin resolver (¿la app vive en background?), es precisamente el constraint que decidirá si la arquitectura de la Live Activity es viable — y es el que no está escrito.

### F-7 · ALTA — CAP-14: AD-9 niega el serializador que el CSV necesita

AD-9: *"El export de CAP-14 **no tiene serializador propio**: emite el mismo formato"*. Pero CAP-14 exige **CSV y JSON**, con criterio propio *"el CSV abre en Numbers/Excel"*. El CSV es por definición un segundo serializador, con sus propias decisiones (columnas, separador, locale decimal, encoding/BOM para Excel). AD-9 hay que matizarlo: la regla "sin serializador propio" aplica al JSON re-importable; el CSV es una proyección de solo salida. Tampoco se menciona el **share sheet** como vehículo de export.

### F-8 · MEDIA — La interacción CAP-15 ↔ logros no está escrita en ningún sitio

Regla del SPEC y de `achievements.md`: al borrar una sesión, esta desaparece de lista, totales, anillo semanal y **acumulados de logros aún no desbloqueados**, pero los **logros ya desbloqueados no se revocan** (ni siquiera el que originó esa sesión). El mapa asigna CAP-15 a `HistoryStore` + AD-9, que solo hablan de persistencia. Es una regla de dominio no trivial (asimetría deliberada) y no tiene dueño arquitectónico ni vector garantizado.

### F-9 · MEDIA — `domain-model.md §7` (provenance / `source`) no llegó al contrato de datos

El campo `source` (`"ios" | "v3" | "migrated"`, más `"corrupt"` en validación de import) debe **conservarse en el esquema por compatibilidad futura** aunque en v1 sea siempre `"ios"`, y la tabla define quién cuenta para Goal/Achievement y quién alimenta cadencia. El spine no nombra `source` en ningún sitio. Como AD-9 hace que **el formato en disco sea el formato de export**, omitir el campo hoy compromete la reactivación de CAP-16 y la compatibilidad del JSON exportado. El Deferred cubre la *migración de esquema*, no la *presencia del campo*.

### F-10 · MEDIA — Semana ISO: el spine fija el `Calendar` pero no la zona, y el SPEC es internamente incoherente aquí

Convención del spine: *"Semana ISO (lunes–domingo) siempre con un `Calendar` configurado explícitamente — nunca `Calendar.current` sin fijar `firstWeekday`"*. Fija el primer día pero **no la zona horaria**, que es la variable que decide el resultado. `domain-model.md §5` dice **"lunes 00:00 UTC"**; `achievements.md` dice que rachas y logros horarios pasan a **hora local**. Con Paul fuera de UTC, la semana de la meta cambiaría de tramo a una hora local arbitraria mientras la racha usa medianoche local — dos calendarios distintos en la misma pantalla. El spine tenía la oportunidad de zanjarlo y lo dejó implícito.

### F-11 · MEDIA — CAP-12: "sin interrumpir la música" no tiene política de sesión de audio

Criterio de éxito de CAP-12 y del Success signal completo (*auriculares con música*): *"cada evento produce háptica/sonido **mientras la música sigue sonando**"*, con la nota *"sonidos cortos, sin ducking agresivo"*. Eso es una decisión concreta de categoría de `AVAudioSession` (ambient / mixWithOthers) que un `FeedbackPort` genérico no impone. Tampoco aparece `soundEnabled` (config de Ajustes, `domain-model.md §8`) como interruptor que el puerto deba respetar.

### F-12 · MEDIA — CAP-11: falta la pantalla de pre-permiso, y el non-goal "solo escritura" no está declarado en el puerto

CAP-11 exige *"permiso HealthKit solicitado con pantalla explicativa previa (pre-permission), **no en frío**"*. AD-11 solo modela la **denegación**, no la **solicitud**. Y el non-goal *"Lectura de datos de Apple Salud (solo escritura de workouts propios)"* no se refleja en el contrato de `HealthPort`: nada impide que el puerto crezca un método de lectura. Un puerto de solo escritura es la forma barata de hacer cumplir un non-goal.

### F-13 · MEDIA — Convenciones numéricas y de fecha del contrato de datos, sin recoger o alteradas

`domain-model.md §8` fija: distancia float en metros con **2 decimales**, cadencia float **1 decimal**, duraciones en segundos enteros, pasos enteros, timestamps **ISO-8601**. El spine cubre unidades (metros/segundos) pero **no las precisiones**, que son parte del contrato de intercambio y afectan a los vectores dorados y al round-trip export→import. Además la convención del spine dice ISO-8601 **"con fracción y zona"**, una variante más estricta que la del SPEC: si el JSON exportado es también el formato en disco (AD-9), conviene decidir a conciencia si se aparta del formato v3.

### F-14 · MEDIA — Reglas transversales de `achievements.md` sin sitio donde vivir

- *"Clima ausente: si `session.weather` es `null`, los logros climáticos (`rain_walker`, `hot_walker`, `cold_walker`) no se evalúan como cumplidos"* — regla de dominio no recogida. Cruza con AD-11, que garantiza que la sesión sin clima es normal, no excepcional: el caso `null` será frecuente.
- El **mapeo de lluvia** (enum WeatherKit, o **códigos WMO 51–67, 80–82, 95–99** para Open-Meteo) no tiene ubicación. AD-5 manda a JSON *"los 14 logros y las constantes de las fórmulas (umbrales, ventanas, mínimos)"* — un mapa de códigos de proveedor a categoría interna no es un umbral, y además pertenece al borde (adapter de clima), no al catálogo. Sin decidirlo, reaparece como un `switch` de strings dentro del engine.
- Forma del store de logros `{key, unlockedAt, progress: 0.0..1.0}`: el spine tiene `achievements.json` pero no restata la forma; el campo `progress` es el que alimenta el grid de CAP-8 y no se menciona.

### F-15 · BAJA — Cabos sueltos y ruido de obsolescencia

- **A-2** ("iPhone con iOS 17+") queda superada por AD-2 (iOS 26.0, prohibido `if #available`). Es una mejora, pero el SPEC no lo refleja y A-2 sigue siendo la asunción vigente sobre el papel.
- **A-1** (Mac + Xcode + cuenta Apple Developer **de pago**) sostiene la envoltura operativa (dispositivo físico, TestFlight, entitlements de HealthKit/ActivityKit); el spine la usa sin citarla.
- **A-3**: AD-5 valida `achievements.json` ruidosamente al arranque (14 entradas, claves únicas). `quotes.json` no tiene validación equivalente pese a que A-3 fija **100 frases íntegras** (verificado: el fichero tiene hoy 100 entradas) y CAP-6 depende de que sean ≥ 21 para la regla de no repetición.
- AD-6 habla de **"las 168 aserciones"**; hoy los cuatro ficheros suman **191** llamadas a `assert` (54 + 86 + 33 + 18). El número está desactualizado o mal contado; conviene no cablear una cifra que envejece.
- **Non-goal "GPS de ruta ni mapas"** no está declarado en el spine, justo cuando se va a introducir permiso de ubicación (F-3) y workouts de HealthKit — los dos sitios donde la ruta se cuela sola.
- Detalles de aceptación sin sustrato: *"permiso de ubicación denegado → sesión sin clima, **sin re-pedir en cada sesión**"* (CAP-5); *"cruzar el 100 % dispara celebración **una sola vez por semana**"* (CAP-7); *"números grandes"* (Constraint UX); *"orden de construcción: CAP-18 como capa aditiva al final"* (podría ser materia de epics, pero hoy no está en ningún artefacto vivo).
- Divergencia menor de modelo: `domain-model.md §2` define estados `active → paused → active → finished`; el spine añade `idle`. Benigno y probablemente correcto, pero es una ampliación del agregado que nadie registró.

---

## 2. Cobertura capability por capability

| CAP | Cubierta por | Qué no aterrizó |
|---|---|---|
| CAP-1 sesión / cronómetro | AD-3, AD-7, AD-14, contrato heredado | Snapshot `activeSession` + autosave 10 s + indicador "Sesión recuperada" 3 s (F-4) |
| CAP-2 conteo 24/7 | AD-10, AD-11 (pantalla bloqueante) | Entitlement / modo background y su coste de batería (F-5, F-6) |
| CAP-3 gap | **AD-8**, AD-6 | — (bien cubierta; el "descartable" viene del contrato heredado) |
| CAP-4 métricas | AD-4, AD-6 | Preferencia distancia-del-sistema sobre `pasos × strideM` y "fuente invisible en UI" no declarada; precisiones (F-13) |
| CAP-5 clima | AD-10, AD-11, Stack (timeout 3 s ✓) | **Redondeo a 2 decimales**, `LocationPort`, no re-pedir permiso cada sesión (F-3) |
| CAP-6 frase | AD-5, `Resources/quotes.json` | Validación de las 100 frases; persistencia de `recentQuoteIds` (≤20) en `settings.json`; overlay 3–4 s saltable (F-15) |
| CAP-7 meta | AD-5, AD-6, convención de fechas | Zona horaria de la semana ISO (F-10); celebración una sola vez por semana |
| CAP-8 logros | **AD-5**, AD-6 | §9 timezone + mapeo lluvia (F-1), clima ausente, forma del store con `progress` (F-14) |
| CAP-9 persistencia | AD-9 | Snapshot de sesión activa (F-4) |
| CAP-10 historial | AD-9, AD-13 | Marcado "~" en lista y empty state (menor); totales semana/mes comparten la ambigüedad de zona (F-10) |
| CAP-11 Salud | AD-10, AD-11 | Pre-permission screen; puerto de **solo escritura** (F-12) |
| CAP-12 feedback | AD-10 | Política de audio no intrusiva + `soundEnabled` (F-11) |
| CAP-13 zancada | AD-4, AD-6 | — (bien cubierta por "zancada congelada" del contrato heredado) |
| CAP-14 export/import | **AD-9** | Serializador CSV y share sheet (F-7); `source` en el formato (F-9); `lastExportAt` |
| CAP-15 borrado | AD-9 | Asimetría con logros desbloqueados / acumulados (F-8) |
| CAP-16 | Deferred (arranque limpio) | ✓ correctamente retirada; pero el campo `source` que la reactivación necesita no está (F-9) |
| CAP-17 recordatorios | AD-10, AD-11 | — (la condición "esfuerzo bajo" de Paul se cumple aún mejor en nativo; conviene registrarlo) |
| CAP-18 Live Activity | **AD-15**, AD-11 | Actualización con app suspendida vs No-backend; `staleDate`; estado de pausa visible (F-5) |

## 3. Constraints, Non-goals, Assumptions

| Elemento | Estado |
|---|---|
| Capacitor como capa nativa | **Derogado por AD-1 sin acta** (F-2) |
| No-backend | ✓ contrato heredado + Stack sin terceros — pero tensiona con CAP-18 (F-5) |
| Usuario único | ✓ |
| Privacidad — on-device, sin telemetría | ✓ (contrato heredado, Logging, Envoltura operativa) |
| Privacidad — **coordenadas 2 decimales** | ✗ **perdida** (F-3) |
| Dominio preservado | ✓ sección "Contrato heredado" — salvo §9, que exige lo contrario y no aparece (F-1) |
| Arquitectura hexagonal | ✓ AD-3, AD-10, AD-12 |
| Licencias Apache-2.0 / MIT | ✓ y reforzada ("Dependencias de terceros: ninguna") |
| **Batería 60 min** | ✗ **perdida** (F-6) |
| UX (44 pt, claro/oscuro, español, celebrar nunca culpar) | ✓ contrato heredado + convención de Textos; falta "números grandes" |
| Non-goal: backend / cuentas / cloud | ✓ |
| Non-goal: GPS de ruta ni mapas | ✗ no declarado (F-15) |
| Non-goal: Android / watchOS / iPad | ✓ implícito por scope |
| Non-goal: lectura de Apple Salud | ✗ no impuesto en el puerto (F-12) |
| Non-goal: sociales / control de música | ✓ (música: solo por omisión, ver F-11) |
| Non-goal: App Store como requisito | ✓ citado en Envoltura operativa |
| Non-goal: importación PWA (CAP-16) | ✓ Deferred |
| **Non-goal: reescritura SwiftUI total** | ✗ **violado sin acta** (F-2) |
| A-1 Mac + Xcode + cuenta de pago | ✓ implícito |
| A-2 iOS 17+ | Superada por AD-2, sin registrar (F-15) |
| A-3 100 frases + 14 logros íntegros | ✓ para logros (AD-5); sin validación para frases (F-15) |

## 4. `platform-matrix.md` — filas obsoletas o en contradicción con el spine

El documento está escrito **para Capacitor** desde el encabezado. Con AD-1 adoptado:

| Fila | Estado |
|---|---|
| Encabezado ("Stack decidido: Capacitor… `@capacitor-community/keep-awake` verificado MIT; CMPedometer y HealthKit requieren plugin custom o `capacitor-healthkit`") | **Obsoleto entero.** Además era el único sitio con una verificación de licencia concreta — con "dependencias de terceros: ninguna" el Constraint de Licencias queda satisfecho por vacío |
| R1 / R2 — columna "Framework nativo" CoreMotion | Capacidad **válida**; la comparativa "plugin custom ~80 líneas Swift" es obsoleta |
| R3 clima — *"el adapter de la PWA se reutiliza tal cual (fetch desde el WebView)"* | **Contradice el spine.** La decisión (Open-Meteo, WeatherKit diferido) sobrevive intacta y coincide con el Deferred; el mecanismo no |
| R4 Salud — *"plugin por verificar/custom"* | Obsoleto; HealthKit directo vía `HealthPort` |
| R5 feedback (CoreHaptics + AVFoundation) | **Válido** |
| R6 storage — *"WKWebView storage + `@capacitor/preferences`"* | **Obsoleto y sustituido** por AD-9 (JSON `Codable` en Application Support, escritura atómica). La *capacidad* (no evictable) se mantiene |
| R7 Live Activity — *"Widget Extension + bridge al WebView"* | El bridge es obsoleto (AD-15: App Group + `ContentState`); el resto vale |
| R8 distancia (CoreMotion distance) | **Válido**, y es la fila que sostiene la regla de preferencia de distancia que el spine no recoge |
| R9 timers (Foundation) | **Válido** |
| R10 recordatorios — columna dice UserNotifications ✓, pero `capabilities.md` CAP-17 dice `@capacitor/local-notifications` | Fila válida; la nota de CAP-17 es obsoleta |
| "Comparativa de cierre" (columna *iOS (Capacitor)*) | Encabezado y tres celdas con menciones a plugins: reetiquetar |
| "Lo que NO cambia de plataforma" | **Válido y crítico**: es donde vive hoy el redondeo a 2 decimales y `quotes.json` como asset local del bundle. Si esta matriz se archiva por obsoleta, esa regla se pierde con ella (F-3) |

---

## 5. Acciones recomendadas (ordenadas)

1. **AD-6 bis — divergencias intencionadas.** Enumerar las tres reglas de §9/`achievements.md` (hora local para `early_bird`/`night_walker`/racha; mapeo de lluvia por código, no por string) como vectores `expected-to-differ`, excluidos de la ejecución por `domain.js` y con vectores propios escritos a mano.
2. **Actualizar el SPEC y escribir `DEROGACIONES.md`.** Retirar el Constraint Capacitor y el Non-goal de reescritura SwiftUI, quitar `PLAN-CAPACITOR-v2.md` de `companions:`, reabrir OQ-1 en la sección Open Questions, y crear los dos companions que el frontmatter del spine ya declara.
3. **AD nuevo o extensión de AD-10/AD-11 para ubicación y privacidad de red:** `LocationPort`, dueño del permiso, y el redondeo a 2 decimales como regla arquitectónica del borde de red, no como detalle del adapter.
4. **AD-9 bis:** cuarto fichero `activeSession.json` con su cadencia de autosave (10 s + background) y la recuperación silenciosa; y matizar "sin serializador propio" para admitir el CSV de salida.
5. **Resolver F-5 antes de planificar CAP-18:** decidir y escribir si la app se ejecuta en background durante la sesión; de ahí cuelgan el criterio de batería (F-6) y la coherencia de AD-8.
6. **Añadir al contrato heredado o a Consistency Conventions** las reglas menores huérfanas: zona horaria de la semana ISO, clima ausente → logros climáticos no cumplidos, borrado no revoca logros, `source` en el esquema, precisiones numéricas, política de audio no intrusiva, HealthPort de solo escritura + pre-permiso.
