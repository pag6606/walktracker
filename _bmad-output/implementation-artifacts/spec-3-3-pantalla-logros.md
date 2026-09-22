---
title: '3.3 — Pantalla de logros: grid locked/unlocked con progreso'
type: 'feature'
created: '2026-09-22'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: 'c2b77e024344f7e24de61da9f9bd57ba381f63a9'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-3-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-3-2-achievement-engine.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-3-1-meta-semanal-anillo.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** La 3.2 dejó los logros desbloqueándose de verdad y escribiéndose en
`achievements.json`, y **no hay dónde verlos**. La pestaña de Logros existe desde AD-14 ocupada
por un placeholder (`EmptyTabView`) cuyo propio comentario dice que la 3.3 la llena. Hoy, cerrar
una caminata de 1 km desbloquea `first_km` y `first_session` sin que la app diga una palabra.

**Approach:** El grid de los 14 logros del catálogo, siempre los 14, con la **insignia** —la
segunda de las tres piezas dibujadas que AD-13 autoriza— copiando el molde que dejó el anillo de
la 3.1. El progreso de los bloqueados **se calcula al pintar**, derivado del historial, y para eso
el motor de la 3.2 expone una función nueva: hoy su medición por métrica es `private`.

## Boundaries & Constraints

**Always:**
- **Los 14 siempre visibles.** No hay estado vacío: sin ningún logro conseguido se ve el grid
  completo en bloqueado con sus progresos. Lo dice el criterio de aceptación y UX-DR5.
- **El catálogo y los logros llegan por su propio camino**, desde `CompositionRoot` hasta la
  vista. **No** a través de `SessionStore`: la sección 6 del gate lo impide y la 3.2 escribió por
  qué — *"no hay razón para que una vista lea el catálogo a través del store"*.
- La insignia lleva **etiqueta y valor de accesibilidad explícitos**: una forma dibujada no los
  trae. VoiceOver lee nombre y estado, y un logro bloqueado **dice que está bloqueado**.
- Reduce Motion **desactiva la animación, no la acorta** — `nil`, como hace el anillo.
- Todo número visual nuevo entra en `DesignTokens.swift`. **Ojo:** la exención de la sección 12
  del gate es solo para ese fichero; un `UI/Style/AchievementBadge.swift` **no está exento**.
- Un texto que ya exista en el catálogo de cadenas con otro `comment:` se **unifica**: el String
  Catalog guarda un comentario por clave, y ya nos mordió en la 2.3 y en la 3.1.
- La fecha de desbloqueo se presenta en **hora local**, con el calendario del reloj (AD-19).

**Never:**
- **No se escribe nada.** Esta historia solo lee. Ni desbloquea, ni escribe filas de progreso, ni
  toca `achievements.json` — ver D1.
- No se evalúa ni se desbloquea al pintar el grid (AD-17). Calcular una barra **no es** evaluar,
  y la spec lo dice para que nadie confunda las dos cosas.
- No se toca el catálogo: ni claves, ni umbrales, ni textos (AD-5).
- No se añade una quinta pestaña (AD-14) ni un cuarto color (AD-13, exactamente tres colorsets).
- No se implementa la celebración (3.4) ni el resumen (3.5).

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Salida esperada | Error |
|---|---|---|---|
| Nada conseguido | `unlocks` vacío | los **14** en bloqueado, con sus progresos | N/A |
| Conseguido | fila con `unlockedAt` | insignia desbloqueada + **fecha local** | N/A |
| Bloqueado con avance | historial 20 km, `marathon_42km` | barra a ~0,48 y el acumulado frente a 42 km | N/A |
| Bloqueado sin avance | historial vacío, `marathon_42km` | barra a 0, no "sin dato" | N/A |
| **`weekly_goal` bloqueado** | su progreso **no** sale del historial: lo posee `GoalEngine` (AD-25) | se muestra **sin barra**, no con un 0 % falso | N/A |
| Logro de clima bloqueado | `rain_walker`, métrica de categoría | **sin barra**: una categoría no tiene fracción | N/A |
| Umbral cumplido y no escrito | historial de 42 km y `marathon_42km` sin fila | barra al 100 % y **sigue bloqueado** — desbloquear es del cierre, no del grid | N/A |
| Fichero ilegible | `readOutcome.isUnreadable` | **no** se pinta todo como bloqueado: se dice que no se pudo leer | aviso, como la 5.1 |
| Huérfana en el historial | registro con `recovered == true` | **no** cuenta para el progreso, igual que no cuenta para desbloquear | N/A |
| VoiceOver, bloqueado | cualquiera | lee nombre, que está bloqueado y su progreso | N/A |

</frozen-after-approval>

## Decisiones de Paul (2026-09-22)

**D1 — El progreso de los bloqueados se calcula al pintar; `achievements.json` solo guarda lo
conseguido.** Una fila en el fichero significa **ganado**. El progreso se deriva del historial cada
vez que se abre la pantalla, así que nunca está viejo. *Razón:* un progreso guardado es una
**caché**, y CAP-15 —borrar una sesión recalcula el progreso de los no desbloqueados— obligaría a
invalidarla o se quedaría mintiendo. Además evita un segundo escritor y una segunda ventana de
escritura. **AD-17 prohíbe *evaluar* al pintar el grid —desbloquear—, no calcular una barra**, y
la nota del propio AD-17 contempla recalcular "totales, meta y progreso de los no desbloqueados".

*Consecuencia asumida:* la rama de `AchievementsStore.upsert` que sustituye una fila con
`progress` y sin `unlockedAt` **se queda sin productor**. No se borra —es correcta y barata— pero
se registra en `deferred-work.md` con destino, para que nadie la lea como prueba de que alguien
escribe filas en curso.

## Code Map

**Campos compartidos de `SessionStore` que toca este cambio** (regla (b) del A-7): **ninguno**.
Esta historia no toca `SessionStore` ni lo recibe. El catálogo y los logros le llegan por su
propio camino desde `CompositionRoot`, que es justo lo que la sección 6 del gate exige:
`store.achievements` y `store.achievementCatalog` están prohibidos en `UI/` y `App/`.

**El hueco que hay que llenar**
- `WalkTracker/UI/RootView.swift:78-85` — la pestaña 3, "Logros", icono `trophy`, ocupada por
  `EmptyTabView` (L128-147), cuyo doc dice *"Historial (5.2) y Logros (3.3) siguen aquí"*. Las
  cuatro pestañas son las de AD-14 y no cabe una quinta.
- `RootView` recibe hoy `store`, `settingsStore`, `historyStore`, `defaultStrideM` — **no**
  recibe `AchievementsStore` ni `AchievementCatalog`. Hay que pasárselos desde
  `WalkTracker/App/WalkTrackerApp.swift:21-26` (DEBUG) y `:36-41` (Release).
- `WalkTracker/App/CompositionRoot.swift:34` `achievementCatalog` (validado al arrancar) y `:46`
  `achievementsStore`. De ahí salen.

**El molde de la pieza dibujada — copiarlo, no inventar otro**
- `WalkTracker/UI/Home/GoalRingView.swift` — la primera pieza de AD-13, con su doc diciendo que
  es "el patrón que copiarán" el gráfico de la 5.2 y **la insignia de la 3.3**. Lo que importa:
  `@Environment(\.accessibilityReduceMotion)` (L36) y `.animation(reduceMotion ? nil : …)` (L68)
  —**`nil`, no una animación más corta**—; `.accessibilityElement(children: .ignore)` (L46) con
  `accessibilityLabel` (L51) y `accessibilityValue` (L52), porque una forma no trae etiqueta;
  `@ScaledMetric(relativeTo:)` (L39) y `.aspectRatio(1, contentMode: .fit)` con
  `frame(maxWidth:)` (L73-74) en vez de diámetro fijo; y el formato en **funciones estáticas
  puras** (`kilometers`, `spokenValue`, L113-128) que se prueban sin renderizar nada.

**Lo que hay que exponer en el motor**
- `Domain/Engines/AchievementEngine.swift` — `measurement(of:closing:sessions:calendar:)` es
  **`private`** (L208-213) y devuelve `AchievementMeasurement`, que es **`internal`** (L18-21) con
  su doc diciendo *"no aparece en ninguna firma que salga de `Domain`"*. Así que la función nueva
  para el grid **no puede devolver ese tipo**: devuelve una fracción `Double?`, y `nil` cuando el
  logro no tiene fracción (categoría de clima, y `weekly_goal`).
- Su API pública hoy: `newlyUnlocked(...)` (L78), `isEarned(...)` (L108), `consecutiveDays(...)`
  (L146), `paceMetric(...)` (L189), `startHourLocal(...)` (L198). El `switch` sobre
  `AchievementMetric` es exhaustivo y **sin `default`**: una métrica nueva sin rama no compila, y
  eso se mantiene.

**De dónde salen los datos**
- `WalkTracker/Application/AchievementsStore.swift` — `unlocks` (L37), `readOutcome` (L40),
  `unlock(forKey:)` (L81). **No hay ninguna consulta agregada**: ni "todas las filas por
  catálogo", ni progreso. Lo que la pantalla necesite se compone en la vista o en una extensión
  de lectura del store.
- `Domain/Ports/AchievementUnlock.swift` — `key`, `unlockedAt: Date?`, `progress: Double`,
  `isUnlocked` (L41). **Hoy nadie escribe filas en curso**: las dos intenciones escriben siempre
  `progress: 1` con `unlockedAt`.
- `WalkTracker/Application/HistoryStore.swift` — `records` (L39) y `readOutcome` (L42). El
  progreso se deriva de aquí. Filtrar por `countsForAchievements` (`SessionRecord.swift:140`),
  que es `!recovered`.

**Tokens y gate**
- `WalkTracker/UI/Style/DesignTokens.swift` — hoy: `Spacing` (4/8/12/16/24), `LayoutMetrics`
  (margin 16, touchTargetMin 44, heroSize 88), **`GoalRing`** (lineWidth 14, maxDiameter 260,
  trackOpacity 0.15, fillDuration 0.6, minimumValueScale 0.5), `Radius.card = 20`, `Surface`,
  `Typography`, `Colors` (los **tres** colorsets, no ampliables). **No existe nada de grid ni de
  insignia.** La regla de admisión está en su cabecera (L19-34): entra si el rol se usa en ≥2
  sitios o si es normativo.
- `Scripts/check-project-shape.sh:635-673` — en `UI/` son error un `frame(width:/height: <n>)`,
  un `cornerRadius(<n>)`, un color en hexadecimal o cromático del sistema, y los peldaños
  4/8/12/16/24 en `spacing:`, `minLength:` o `.padding(…)`. **La exención es solo
  `UI/Style/DesignTokens.swift`**: un fichero nuevo bajo `UI/Style/` no está exento.

**Textos**
- `WalkTracker/Resources/Localizable.xcstrings` — 127 claves, `sourceLanguage: "es"`, **un
  `comment` por clave**. Patrón: `Text("…", comment: "…")` en vistas y
  `String(localized:locale:comment:)` en funciones puras probables. Si un texto de esta pantalla
  coincide con uno existente, **el comentario se fusiona nombrando los dos sitios**: es el
  hallazgo 14 de la 2.3, que volvió a morder en la 3.1 con `"Meta semanal"`.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Engines/AchievementEngine.swift` -- función pública que devuelva la **fracción
  `0…1`** de un logro sobre el historial, y `nil` cuando no tiene fracción -- sin exponer
  `AchievementMeasurement`, que es `internal` a propósito.
- [x] `WalkTracker/UI/Achievements/AchievementBadgeView.swift` -- la insignia, segunda pieza de
  AD-13, con etiqueta y valor de accesibilidad y Reduce Motion a `nil` -- molde: `GoalRingView`.
- [x] `WalkTracker/UI/Achievements/AchievementsView.swift` -- el grid de los 14, con el aviso de
  fichero ilegible -- los 14 siempre, sin estado vacío.
- [x] `WalkTracker/UI/Style/DesignTokens.swift` -- los tokens de grid e insignia -- la sección 12
  del gate rechaza cablearlos en la vista.
- [x] `WalkTracker/UI/RootView.swift` y `WalkTracker/App/WalkTrackerApp.swift` -- sustituir el
  `EmptyTabView` de Logros y pasar catálogo y store **por su propio camino** -- no por
  `SessionStore`.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` -- registrar con `Destino:` que la
  rama de `upsert` para filas en curso se queda sin productor por D1.

**Acceptance Criteria:**
- Dado el historial vacío, cuando se abre Logros, entonces se ven **los 14** en bloqueado — no un
  estado vacío.
- Dado un historial de 42 km sin fila de `marathon_42km`, entonces la barra está al 100 % y el
  logro **sigue bloqueado**: el grid no desbloquea.
- Dado `weekly_goal` bloqueado, entonces se muestra **sin barra**, no con un 0 %.
- Dado `achievements.json` ilegible, entonces la pantalla **lo dice** y no pinta 14 bloqueados
  como si fuera un dato.
- Dado `bash Scripts/check-project-shape.sh` y su arnés, entonces verdes: ningún número visual de
  la insignia cableado fuera de `DesignTokens.swift`.
- Dada la suite completa, entonces los casos ejecutados **crecen**, contados en el `.xcresult`.

## Implementation Notes

**Dos funciones públicas en el motor, no una, y ninguna expone `AchievementMeasurement`.**
`AchievementEngine.accumulated(towards:sessions:calendar:)` devuelve **la magnitud** —metros,
sesiones o días— y `progressFraction(towards:sessions:calendar:)` devuelve la **fracción `0…1`**.
La segunda se define sobre la primera, así que **se ausentan a la vez**: no puede haber una barra
sin cifra ni una cifra sin barra, y eso lo afirma un test que recorre los 14 (*"Los 14 se reparten
en dos grupos y no hay un tercero"*). Hace falta la magnitud además de la fracción porque la
matriz congelada pide *"el acumulado frente a 42 km"*, y derivarla en la vista multiplicando la
fracción por el umbral habría mentido justo donde más duele: con la fracción capada en 1, 50 km
caminados se leerían como "42 de 42". Las dos son `Double?` y las dos hablan de números, que es
lo que el Code Map exige: `AchievementMeasurement` sigue `internal` y no aparece en ninguna firma
que salga de `Domain`.

**Siete de los catorce llevan barra, y la regla es una, no una lista.** Un logro tiene fracción
cuando su **métrica se acumula** —la caminata más larga, la distancia total, el número de
sesiones y la racha— **y** su umbral es un número positivo alcanzado **subiendo** (`gte` o `gt`).
Los otros siete no la tienen, y el `nil` es honesto en cada caso: `weekly_goal` porque su progreso
lo posee `GoalEngine` (AD-25) y una segunda fuente para el mismo número se quedaría atrás en
silencio; `rain_walker` porque una categoría no tiene fracción; `early_bird` y `night_walker`
porque una hora de inicio es un estado de una caminata, no una cuenta que suba; `hot_walker`,
`cold_walker` y `speed_walker` porque caminar a 20 °C no es "avanzar hacia" los 30, y con un
umbral `lt` la fracción saldría del revés. Los dos `switch` nuevos —el de la métrica y el de la
comparación— **no tienen `default`**, como los dos que ya había: una métrica o un comparador
nuevos obligan a decidir si su logro lleva barra en vez de heredar un `nil` mudo.

**La barra mide lo mismo que decide el desbloqueo, y eso no es una coincidencia.**
`sessionDistanceM` es la caminata **más larga**, no la suma: `first_5km` se decide sobre una sola
sesión, así que tres de 3 km dejan la barra en 0,6 y no llena (tiene test, porque sumar era el
error fácil). `consecutiveDays` es **la tirada más larga**, que es exactamente la magnitud que el
catálogo compara con 7, y se agrupa por **día local** con el `AppCalendar` de AD-19 — con test en
`America/Guayaquil`, donde dos instantes que en UTC son dos días son **uno** en local.

**El grid no desbloquea aunque la barra llegue al 100 %, y hay dos tests para que nadie lo
"arregle".** Uno en el dominio (la fracción se capa en 1 con 50 km) y otro en la insignia
(*"Con 42 km y sin fila, la barra está llena y el logro SIGUE bloqueado"*). La pantalla no llama
a `newlyUnlocked` ni a ninguna intención del store: **solo lee**. Calcular una barra no es
evaluar, y AD-17 prohíbe lo segundo.

**Un tercer estado, porque "bloqueado" sería mentira.** `AchievementStatus` tiene `unlocked`,
`locked` y **`unknown`**. Con `achievements.json` ilegible no se sabe si Paul lo ha conseguido, y
pintar los catorce en bloqueado afirmaría que no —que es justo lo que nadie sabe (AD-22, la misma
doctrina con la que el anillo se niega a pintar un 0 % sin historial)—. La insignia desconocida
enseña un interrogante en vez del emoji y VoiceOver lee *"No se pudo leer si lo has conseguido"*,
no *"Bloqueado"*; encima, el aviso lo dice con todas las letras. Los 14 siguen presentes: el
catálogo es contenido del bundle y ése sí se pudo leer.

**El progreso guardado se ignora a propósito** (decisión D1). Una fila con `progress` y sin
`unlockedAt` se trata como bloqueada y su barra se **recalcula** desde el historial. Tiene test,
y es lo que hace que borrar una caminata (CAP-15) no deje nada mintiendo: no hay caché que
invalidar porque no hay caché. La consecuencia —esa rama de `upsert` se queda sin productor— está
registrada en `deferred-work.md` con destino, como pedía la tarea.

**La insignia copia el molde del anillo, y lo que añade lo declara.** Medallón dibujado
(`Circle` relleno + `strokeBorder`), `aspectRatio(1, contentMode: .fit)` con `frame(maxWidth:)` en
vez de diámetro fijo, `@ScaledMetric(relativeTo:)` en las tres longitudes, Reduce Motion a `nil`
—no a una animación más corta—, `accessibilityElement(children: .ignore)` con etiqueta (el
nombre), valor (el estado y su progreso) y **pista** (la descripción del catálogo, que es lo que
hay que hacer para conseguirlo), y el formato en **funciones estáticas puras** que se prueban sin
renderizar. Lo que añade sobre el anillo: el emoji y los textos van `verbatim` porque son **dato
del catálogo** (AD-5), no copy de la UI, y por eso no pasan por el String Catalog.

**Ningún color nuevo y ningún número suelto.** El reborde conseguido es `Colors.accent` —el mismo
del arco— y el bloqueado es `.secondary`; la pista de la barra es `.quaternary` y el fondo de la
tarjeta `.fill.quaternary`, que son roles del sistema y no un cuarto colorset (AD-13, y la
excepción de UX-DR1 son exactamente tres). Los seis números visuales viven en `AchievementBadge`,
dentro de `DesignTokens.swift`: la sección 12 del gate los habría rechazado en la vista, que es
justo lo que la spec avisaba —`UI/Style/DesignTokens.swift` es el **único** fichero exento, y
`AchievementBadgeView.swift` no lo es—.

**Dos columnas sin escribir "dos".** `GridItem(.adaptive(minimum:))` con el mínimo en
`@ScaledMetric(relativeTo: .headline)`: con el tamaño por omisión caben dos en un iPhone (UX-DR5)
y con Dynamic Type de accesibilidad el mínimo crece y la rejilla se queda en una sola columna,
sin ninguna condición escrita a mano ni nombres recortados.

**El aviso de fichero ilegible se extrajo en vez de copiarse.** `UnreadableFileNotice`
(`UI/Components/`) es el mismo tratamiento que ya pintaba Inicio para `sessions.json` (5.1), con
dos textos distintos; `HomeView` pasa a usarlo. Copiarlo habría dejado dos sitios que se pueden
arreglar por separado, que es literalmente el hallazgo 14 de la revisión de la 3.2. Los textos
entran como `Text`, **no** como `LocalizedStringKey`, para que cada pantalla conserve su
`comment:` en el String Catalog: con una clave, el literal se extraería dentro del componente y
el traductor se quedaría sin saber de qué fichero habla.

**El calendario llega como valor, no como puerto.** `RootView` recibe `Calendar` —el
`ClockPort.calendar` de AD-19, cableado en `WalkTrackerApp`— y no el reloj: la pantalla necesita
saber qué día es un instante, no qué hora es ahora. Así el grid y el anillo no pueden dar dos
respuestas para el mismo día, y la UI no construye ningún `Calendar`. El catálogo y el store de
logros viajan igual, **por su propio camino** desde `CompositionRoot`: la sección 6 del gate
prohíbe alcanzarlos por dentro del store de sesión, y la 3.2 cerró ese atajo al añadir los dos
nombres a la regla.

**Los kilómetros salen de `DistanceFormat`.** El producto ya tenía dos criterios de redondeo de
distancia —el de la rejilla de sesión y el del anillo— y un tercero habría hecho que la misma
caminata se leyera de tres maneras. La barra usa el de `UI/Format/`, que es el que ya está
probado: "21,00 de 42,00 km".

**Dos claves del String Catalog se van y ninguna se fusiona.** `"Sin logros"` y `"Los logros que
desbloquees aparecerán aquí."` eran del `EmptyTabView` de la pestaña, que deja de existir: un
texto sin ningún sitio que lo use es deuda que el traductor paga. La clave `"Logros"` **no** hizo
falta fusionarla —su comentario ya decía *"Pestaña Logros del TabView (AD-14) y título de su
pantalla"*, así que la 3.3 aterriza sobre un comentario que ya la contemplaba—, y se comprobó que
ninguna de las nueve claves nuevas coincide con una existente. Es el hallazgo 14 de la 2.3
mirado antes de que muerda, no después.

## Spec Change Log

**2026-09-22 · El Code Map dice que los logros sin fracción son "categoría de clima, y
`weekly_goal`"; son siete, no dos. El bloque congelado NO se edita —su matriz solo nombra esos
dos como filas, y las dos filas se cumplen tal cual—; se registra aquí.**

*Qué dice.* *"Devuelve una fracción `Double?`, y `nil` cuando el logro no tiene fracción
(categoría de clima, y `weekly_goal`)"*.

*Qué falta, y por qué no es un matiz.* Con esa lista literal, los otros cinco logros que tampoco
se acumulan tendrían que llevar barra, y las tres salen mal: `early_bird` y `night_walker` la
pintarían sobre una hora de inicio (`between [5, 7]`), es decir sobre la última caminata y no
sobre un avance; `hot_walker` diría que caminar a 20 °C es un 66 % de los 30 °C que pide, que es
falso y además **fluctúa hacia abajo**; y `cold_walker` y `speed_walker`, cuyos umbrales son `lt`,
tendrían la barra **del revés** —cuanto peor lo hace Paul, más llena—. Un 0 % falso es lo que la
propia matriz prohíbe para `weekly_goal`, y aquí sería algo peor: un porcentaje inventado.

*Qué se decide.* La regla es una y no una lista: hay fracción cuando la **métrica se acumula**
(`sessionDistanceM`, `totalDistanceM`, `sessionCount`, `consecutiveDays`) **y** el umbral es un
número positivo alcanzado subiendo (`gte`, `gt`). Salen **siete con barra** —`first_km`,
`first_5km`, `first_10km`, `first_session`, `7_days_streak`, `marathon_42km`, `consistency_30`— y
siete sin ella. Las dos filas de la matriz que nombran casos sin barra (`weekly_goal` y el logro
de clima) se cumplen exactamente; las otras cinco quedan del mismo lado por la misma razón.

*Qué NO cambia.* Ninguna fila de la matriz, ningún criterio de aceptación y ningún umbral del
catálogo (AD-5). La regla vive en la doc de `AchievementEngine.accumulated(towards:sessions:calendar:)`
y su reparto está fijado por el test *"Los 14 se reparten en dos grupos y no hay un tercero"*, que
enumera los siete por su clave: si alguien mueve uno de lado, la suite lo dice.

## Review Triage Log

## Design Notes

**Por qué el grid no puede desbloquear, aunque la barra llegue al 100 %.** Es el caso que parece
un bug y no lo es: si Paul acumula 42 km y no abre la app, el logro se desbloquea en el **cierre
siguiente**, no al mirar la pantalla. AD-17 lo exige para que nada se dispare dos veces, y la
alternativa —desbloquear al pintar— pondría la celebración en manos de cuándo se abre una
pestaña. La barra al 100 % con el logro bloqueado es **correcto** y hay caso en la matriz para
que nadie lo "arregle".

**Por qué `weekly_goal` no lleva barra.** Su progreso no está en el historial: lo posee
`GoalEngine`, que lo calcula contra la meta y la semana en curso (AD-25). Derivarlo aquí sería
una segunda fuente de verdad para el mismo número, y la que se quedara atrás lo haría en
silencio. Sin barra es honesto; un 0 % sería falso.

## Verification

**Commands:**
- `bash Scripts/check-project-shape.sh` y su arnés -- esperado: verde, y el conteo no baja.
- `bash Scripts/check-spec-shape.sh` -- esperado: verde.
- `bash Scripts/verify-domain.sh` -- esperado: verde, con la línea de pendientes de AD-6 **vacía**
  como la dejó la 3.2.
- `xcodebuild test` completo -- esperado: casos ejecutados **crecen**, contados en el `.xcresult`.

**Ejecutado (2026-09-22):**
- `bash Scripts/check-project-shape.sh` -> **verde**. `bash Scripts/check-project-shape-tests.sh`
  -> **223/223**, sin cambios: esta historia no añade ni toca ninguna regla del gate. Sí lo hizo
  saltar dos veces mientras se escribía, y por lo que debe: la sección 6 trabaja **línea a línea y
  sin quitar comentarios**, así que un `store.achievements` escrito dentro de un comentario de
  `RootView` —explicando justamente que está prohibido— es una violación. Los dos comentarios se
  reescribieron nombrando la regla en vez de citando la llamada.
- `bash Scripts/check-spec-shape.sh` -> **verde**, con **63** entradas de `deferred-work.md` (61
  antes) y 11 cerradas. Las dos nuevas son las de abajo.
- `bash Scripts/verify-domain.sh` -> **verde**. **321 tests en 21 suites** (308 en 20 antes) y la
  línea de pendientes de AD-6 sigue en **`ninguna`**, como la dejó la 3.2: esta historia no porta
  vectores nuevos y no destapa ninguno —`motivation.js` **no tiene** progreso de logros en curso,
  así que no hay referencia contra la que correr una barra—. Los 109 vectores siguen pasando en
  Swift. El suite nuevo `AchievementProgressTests` entra en `DOMAIN_SUITES` en el mismo commit; sin
  eso el propio gate lo habría dicho (B-6).
- `xcodegen generate && xcodebuild test ... iPhone 16e CODE_SIGNING_ALLOWED=NO` -> **TEST
  SUCCEEDED**, **870 tests en 67 suites** (847 en 65 antes): **23 casos y 2 suites nuevos**,
  contados por nombre sobre el `.xcresult` y no por `TEST SUCCEEDED` — `AchievementEngine · el
  progreso del grid` **11** e `Insignia de logro · qué estado tiene y qué dice` **12**. Con los
  casos parametrizados desplegados, el bundle cuenta **1 326** aserciones de caso, todas `Passed`.
  Ningún suite existente cambia de tamaño: esta historia no toca conducta ya probada.

**Mutaciones (cada una aplicada, ejecutada contra `AchievementProgressTests` y
`AchievementBadgeViewTests`, y revertida):**
- **La huérfana cuenta para el progreso** (quitar el `filter(\.countsForAchievements)` de
  `accumulated`) -> falla **1 test**: "Una huérfana no cuenta para el progreso, igual que no cuenta
  para desbloquear". Es la fila de la matriz ejecutándose, y es la mitad que esta historia **sí**
  controla — la otra mitad, que el desbloqueo sí las cuenta, queda registrada como diferido.
- **La barra no se capa** (`max(0, value / threshold)` sin el `min(1, …)`) -> fallan **2 tests**:
  "La barra se capa en 1: pasarse de 42 km no pinta un 120 %" y "Las sesiones se cuentan: 3 de 30
  para la constancia, y la primera caminata va de 0 a 1", que se cae por `first_session` —una sola
  caminata sobre un umbral de 1 daría 3, no 1—.
- **Con el fichero ilegible se pinta bloqueado** (quitar el `guard !isUnreadable` de
  `AchievementStatus.of`) -> falla **1 test**: "Con el fichero ilegible no se dice 'bloqueado': no
  se sabe, y eso es otro estado". Sin él, los catorce dirían que faltan cuando lo que pasa es que
  nadie lo sabe (AD-22).
- **La fecha sin la zona del calendario** (`timeZone: .autoupdatingCurrent` en vez de
  `calendar.timeZone`, que es lo que AD-19 prohíbe) -> falla **1 test**: "La fecha de desbloqueo es
  LOCAL, con el calendario del reloj (AD-19)". Es el mismo hueco que la revisión de la 3.2 encontró
  en la costura del cierre, pinchado aquí antes de que se abriera.
- **El progreso guardado manda sobre el calculado** (usar el `progress` de la fila cuando la hay)
  -> falla **1 test**: "Una fila con progreso y SIN instante sigue bloqueada, y su progreso guardado
  se ignora". Es la decisión D1 ejecutándose: el progreso se deriva, no se lee de una caché.
- Árbol restaurado y la suite completa vuelve a **TEST SUCCEEDED** después de las cinco.

**Manual checks (iPhone, tras el build): PENDIENTES.** No se han ejecutado. Son los dos de la
spec —abrir Logros sin ninguna caminata y ver los 14 bloqueados; con VoiceOver, que un logro
bloqueado diga que lo está y lea su progreso— más lo que esta historia añade al mismo hueco: la
rejilla con Dynamic Type al máximo (debe quedarse en **una** columna, sin nombres recortados), la
barra con Reduce Motion (**sin** animación, no con una más corta) y el aviso de fichero ilegible.
**Nada de lo que se ve en pantalla lo fija ningún test**, porque XCUITest está descartado (decisión
D1 del 2026-09-20): borrar `AchievementsView(...)` de `RootView` deja la suite y los cuatro gates
en verde. Lo que **sí** queda cubierto sin renderizar es todo lo que la pantalla **decide y dice**:
el estado de cada logro, su progreso, sus tres textos y lo que VoiceOver lee de cada uno de los
cuatro casos. Está en `deferred-work.md`, junto al mismo hueco de la 2.3, la 3.1 y la 5.1.
