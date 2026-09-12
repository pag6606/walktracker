---
title: 'Revisión adversaria — ARCHITECTURE-SPINE WalkTracker iOS'
target: ../ARCHITECTURE-SPINE.md
context:
  - ../../../../specs/spec-walktracker-ios/SPEC.md
  - ../../../../specs/spec-walktracker-ios/capabilities.md
  - ../../../../specs/spec-walktracker-ios/domain-model.md
  - ../../../../specs/spec-walktracker-ios/achievements.md
reviewer: 'revisor adversario'
date: '2026-09-12'
method: 'pares de unidades un nivel por debajo que obedecen todos los AD y aun así son incompatibles'
---

# Revisión adversaria — ARCHITECTURE-SPINE (WalkTracker iOS)

## Veredicto

El spine decide bien **el sustrato, las capas y el escritor de la sesión viva**, y cierra de raíz el incidente Dart (AD-5) y la divergencia de serializadores (AD-9). Pero está escrito casi entero alrededor de **una sola entidad — la sesión activa — y de un solo eje de riesgo — la concurrencia**. Todo lo que vive *después* del `finish()` (logros, meta semanal, borrado, historial, export, Live Activity, muerte de la app) queda gobernado por ADs que hablan de **formato y de capas, nunca de propiedad ni de momento**. Resultado: **14 pares de unidades que obedecen los 15 AD al pie de la letra y no pueden coexistir**, cinco de ellos con conflicto de build o de fichero, no solo de comportamiento.

Las tres ausencias estructurales que generan casi todo lo demás:

1. **AD-9 define el formato de los ficheros pero no su dueño.** "Un fichero por preocupación" no dice *quién escribe cada fichero*. AD-7 protege un agregado en memoria, no un fichero en disco. Con escritura atómica temp+rename, **dos escritores del mismo fichero no corrompen: se pisan en silencio**, que es peor.
2. **Nadie posee "cuándo".** El spine dice dónde vive cada cálculo (`Capability → Architecture Map`) y nunca en qué momento del ciclo se dispara. "Evaluado al cierre de sesión" está en el SPEC, no en un AD, y por tanto no gobierna a la historia que decida re-evaluar al pintar el grid.
3. **Nadie posee "el calendario".** La convención de fechas fija `firstWeekday` y olvida `timeZone`, mientras `domain-model.md §5` dice **UTC** y `achievements.md` dice explícitamente **hora local**. Los dos son contrato heredado y se contradicen dentro del mismo producto.

---

## Los pares incompatibles

### H-01 — `achievements.json`: ¿reglas en datos o metadatos en datos? · CRÍTICO · conflicto de recurso

**Unidad A — Historia «Motor de logros» (`Domain/Engines/Achievement`).**
Lee AD-5 literal: *"Ningún logro se declara en Swift"*. Concluye que **la regla también es dato** y diseña `achievements.json` como mini-DSL:
`{"key":"first_km","rule":{"scope":"session","field":"distanceM","op":">=","value":1000},"progress":{"kind":"ratio","of":"distanceM","target":1000}}`.
Escribe un intérprete de reglas en Swift. Cumple AD-3, AD-4, AD-5, AD-6.

**Unidad B — Historia «Grid de Logros» (`UI/Achievements` + `AchievementsStore`).**
Lee AD-5 igual de literal, pero entiende que lo prohibido es el **catálogo** hardcodeado (que es lo que produjo el incidente Dart), no la regla. Diseña `achievements.json` como metadatos:
`{"key":"first_km","name":"Tu primer kilómetro","desc":"…","icon":"🏅","threshold":1000}`
y mantiene en Swift un `switch key { case "first_km": session.distanceM >= 1000 … }` de 14 ramas. Cumple AD-5 tal como lo valida el propio arranque, que según AD-5 sólo comprueba **"14 entradas, claves únicas, todas las del catálogo"** — nunca la forma de la regla.

**Por qué el spine permite ambas:** AD-5 no dice qué esquema tiene el fichero, y su propia cláusula de validación (contar entradas y claves) es compatible con los dos esquemas. El *Structural Seed* lista `Resources/achievements.json` sin contrato.

**Cómo se rompe:** las dos historias producen el **mismo fichero con dos esquemas mutuamente ilegibles**. La segunda en mergear rompe el arranque, que por AD-5 **falla ruidosamente** — es decir, la app no arranca. Y el fallo aparece en la historia que no cambió nada.

**Cierre propuesto (AD-5 endurecido):** el spine debe **publicar el esquema de `achievements.json` y de `formulas.json` como parte del propio AD** (campos exactos, tipos, si la regla es dato interpretado o clave con implementación fija), y decir que el validador de arranque comprueba **el esquema completo**, no solo el conteo. Sin eso, AD-5 previene el incidente Dart y abre uno nuevo.

---

### H-02 — Dos momentos de evaluación de logros y dos escritores de `achievements.json` · CRÍTICO

**Unidad A — Historia «Finalizar sesión + Summary» (CAP-8).**
`SessionStore.finish()` llama a `AchievementEngine.evaluate(session, allSessions, unlocked)`, escribe `achievements.json` y pasa los recién desbloqueados a la pantalla Summary para la celebración visual+sonora+háptica. Cumple AD-7 (AD-7 hace a `SessionStore` escritor único **de la sesión**; los logros no son la sesión), AD-3, AD-5, AD-9.

**Unidad B — Historia «Grid de Logros con progreso» (CAP-8).**
`AchievementsStore` recalcula `progress: 0.0..1.0` de los 14 logros a partir de `HistoryStore.sessions` cada vez que se abre la pestaña — porque el progreso y el desbloqueo **salen de la misma regla**, y calcular uno sin el otro es duplicar la regla (justo lo que AD-5 prohíbe). Si un umbral está cruzado, lo marca desbloqueado y persiste. Cumple exactamente los mismos AD.

**Por qué el spine permite ambas:** ningún AD asigna el **momento** de la evaluación ni el **dueño** de `achievements.json`. El `Capability → Architecture Map` sitúa CAP-8 en `Domain/Engines/Achievement` — un motor puro, que por definición no decide cuándo se le llama. `AchievementsStore` existe en el *Structural Seed* sin un solo AD que lo gobierne.

**Cómo se rompe, concreto:** Paul cierra una sesión de 1,2 km. A desbloquea `first_km` y celebra. Paul abre la pestaña Logros: B recalcula, ve el umbral cruzado, y como su copia en memoria de `achievements.json` se cargó antes de que A escribiera, **reescribe el fichero con `unlockedAt` = ahora** (AD-9: temp+rename, último escritor gana, sin corrupción y sin aviso). El logro queda fechado el día que Paul abrió una pestaña. Si el orden se invierte, el logro se desbloquea **sin celebración** — y CAP-8 exige celebración.

**Cierre propuesto (AD nuevo, "AD-16 · Un fichero, un dueño"):** cada fichero de AD-9 tiene **exactamente un store escritor**; los demás leen por ese store, nunca del disco. Y **"AD-17 · La evaluación de logros tiene un único disparador"**: `AchievementEngine` se ejecuta **solo** en la transición a `finished` y en el borrado (H-03). Cualquier otra pantalla **renderiza estado persistido**; el grid nunca evalúa.

---

### H-03 — CAP-15: borrar sesión, ¿recalcula logros, y puede revocar? · CRÍTICO

**Unidad A — Historia «Eliminar sesión del historial».**
`HistoryStore.delete(id)` reescribe **solo** `sessions.json`. Razona con AD-9 en la mano: *"un fichero por preocupación… prevents: que guardar un ajuste reescriba el histórico completo"*; los logros son otra preocupación, con otro fichero y otro store. Cumple AD-9 y el mapa de capabilities, que asigna CAP-15 a `HistoryStore` gobernado **únicamente por AD-9**.

**Unidad B — Historia «Coherencia de acumulados tras borrado».**
Lee el criterio de CAP-15 (*"deja de contar en totales, meta y logros no desbloqueados aún"*) y, al borrar, **recalcula el catálogo entero desde cero** sobre las sesiones supervivientes. Cumple los mismos AD.

**Por qué el spine permite ambas:** AD-9 es un AD de **formato**, y es el único que gobierna CAP-15. Nada dice si borrar propaga.

**Cómo se rompe, y peor:** B recalcula desde cero → un logro **ya desbloqueado** cuya sesión se borró vuelve a `unlockedAt: null`. `achievements.md` lo prohíbe explícitamente (*"no se re-disparan ni se revocan, incluido si se elimina la sesión que los originó"*) — pero esa prohibición vive en el companion del SPEC, **no en ningún AD**, así que no gobierna la implementación. Y A deja el bug simétrico: `marathon_42km` en 41,8 km después de borrar una sesión de 5 km, es decir el progreso miente y el logro se disparará 5 km antes de tiempo.

Peor aún, el par se cruza con H-02: si A y B conviven, borrar una sesión deja `sessions.json` y `achievements.json` en estados que **discrepan según qué pantalla se abrió antes**.

**Cierre propuesto:** el AD-17 propuesto debe decir que el borrado dispara **una recomputación monótona**: el conjunto de `unlockedAt != null` es **append-only y nunca se recalcula**; solo se recalcula `progress` y solo los logros aún bloqueados. Y que esa recomputación es **una sola transacción de dos ficheros** — lo que obliga a decidir algo que AD-9 tampoco cubre: **no hay escritura atómica multi-fichero con temp+rename**, así que hace falta un orden de escritura y una regla de recuperación si el proceso muere entre los dos renames.

---

### H-04 — El snapshot de sesión activa no existe en AD-9 (y su forma contradice las convenciones) · CRÍTICO

**Unidad A — Historia «Recuperación silenciosa» (CAP-1/CAP-9).**
Implementa `domain-model.md §8` tal cual: un cuarto fichero `activeSession.json` con la forma heredada de la PWA — `{startedAtMs, totalPausesMs, pausedAtMs, paused, stepsMeasured, stepsEstimated, strideM, weather, quoteId}` — autosave cada 10 s y al ir a background. Cumple AD-9 (JSON `Codable`, escritura atómica) y AD-7.

**Unidad B — Historia «Persistencia garantizada» (CAP-9).**
Lee AD-9 literal: los ficheros son **tres** (`sessions.json`, `achievements.json`, `settings.json`), *"un fichero por preocupación"*, y "sesiones" es una sola preocupación. Persiste la sesión viva como una entrada de `sessions.json` con `endedAt: null`. Y aplica la convención de fechas del spine — **ISO-8601 con fracción y zona** — y la de unidades — **metros y segundos, siempre**. Cumple AD-9 y la tabla de *Consistency Conventions* mejor que A.

**Por qué el spine permite ambas:** AD-9 enumera tres ficheros y el snapshot activo no está entre ellos; el *Structural Seed* tampoco lo nombra. Y `domain-model.md §8` — que **sí** define el snapshot — lo hace en **milisegundos**, en contradicción directa con la convención de unidades del spine, sin que ningún AD arbitre cuál gana.

**Cómo se rompe, concreto:**
- Si conviven, `totalPausesMs = 120000` leído por un consumidor que espera segundos son **33 horas de pausa**. Cronómetro destruido, y en silencio, porque ambos son `Int` válidos.
- Con la opción B, CAP-10 lista la sesión viva en el historial, CAP-14 la **exporta con `endedAt: null` y `distanceM` sin cachear**, y CAP-15 permite **borrar la sesión que se está caminando**. Todo ello obedeciendo AD-9 al pie de la letra.
- Y el snapshot no tiene `schemaVersion` mandatado, porque AD-9 sólo lo exige a los tres ficheros que enumera.

**Cierre propuesto (AD-9 endurecido):** enumerar **cuatro** ficheros, declarar el snapshot activo como **fichero propio, con `schemaVersion`, en segundos e ISO-8601**, y declarar explícitamente que **la convención de unidades del spine deroga la forma en milisegundos de `domain-model.md §8`** (o al revés, pero por escrito). Y prohibir que `sessions.json` contenga sesiones no finalizadas: `sessions.json` es, por definición, el archivo de lo inmutable.

---

### H-05 — Sesión huérfana: ¿quién decide que está viva, finalizada o descartada? · CRÍTICO

**Unidad A — Historia «Recuperación silenciosa» (CAP-1).**
Al arrancar con snapshot presente, restaura a `active` y recomputa `elapsedS = now − startedAt` (contrato heredado, wall-clock, *"cambiar de app no pausa"*, *"sin auto-pausa"*). Muestra el indicador "Sesión recuperada" 3 s. Cumple el *Contrato heredado del SPEC* al pie de la letra: **el spine prohíbe explícitamente cualquier auto-pausa**, así que A no puede hacer otra cosa.

**Unidad B — Historia «Higiene de arranque» / «Historial» (CAP-9/CAP-10).**
Decide que un snapshot cuyo `startedAt` es de hace 3 días es basura: lo auto-finaliza con `endedAt = lastAutosaveAt` y lo empuja al historial (o lo descarta). Cumple todos los AD — **ninguno menciona la palabra "huérfana"**.

**Por qué el spine permite ambas:** AD-8 modela el retorno a foreground **de un proceso vivo**. El diagrama de estados va de `Idle` a `Finished` sin un solo arco que salga de "el proceso murió". El *Deferred* no lista este caso; el spine simplemente no lo vio.

**Cómo se rompe, concreto:** Paul deja el móvil en la mesa el viernes con sesión activa y lo recoge el lunes.
- Con A: la app abre en modo sesión (`fullScreenCover`, AD-14 — **no se puede navegar fuera**), cronómetro en 72:14:03, y CMPedometer, consultado por rango desde `startedAt` (CAP-3), devuelve **todos los pasos del fin de semana**. Al finalizar: 41.000 pasos, 26 km, `paceSecPerKm` de 9.900 s/km. `first_10km` y `marathon_42km` desbloqueados por una mesa.
- Con B: la sesión aparece sola en el historial el lunes por la mañana, **y B tiene que decidir si dispara la evaluación de logros** — con lo que H-02 se multiplica: ahora hay un tercer momento de evaluación, en el arranque.
- Y las dos historias tomadas juntas: A restaura, B ya la había archivado → **la misma sesión existe dos veces**, una viva y una finalizada, con el mismo `id` en dos ficheros.

**Cierre propuesto (AD nuevo, "AD-18 · Ciclo de vida de la sesión huérfana"):** definir el arco que falta en el diagrama de AD-8 — `Orphaned` — con **un dueño único** (el composition root, antes de que ninguna UI se monte), un **criterio explícito de antigüedad** (con número, no diferido — este sí bloquea historias), qué `endedAt` se le pone, si dispara evaluación de logros, si escribe en Salud, y si el usuario decide o el sistema decide. El contrato de "wall-clock, sin auto-pausa" gobierna una sesión **observada**; una sesión huérfana de 72 h no es un caso de wall-clock, es un caso de recuperación, y el spine los confunde.

---

### H-06 — `ContentState`: dos formas del mismo tipo, en el mismo target compartido · CRÍTICO · conflicto de build

**Unidad A — Historia «Live Activity de pantalla de bloqueo» (CAP-18).**
Para que el cronómetro avance en la pantalla de bloqueo sin gastar presupuesto de actualizaciones, usa `Text(timerInterval:pauseTime:)`, que es el patrón nativo. Por tanto `ContentState = {startedAt: Date, pausedSince: Date?, totalPauses: TimeInterval, steps: Int, distanceM: Double}` y **la extensión deriva el tiempo mostrado**. Cumple AD-15 en su lectura razonable: la extensión **renderiza**, no calcula dominio, no lee ficheros, no importa `Domain`.

**Unidad B — Historia «Puente de métricas a la Live Activity» (CAP-18).**
Lee AD-15 literal: *"solo renderiza… **no calcula**"*. Por tanto `SessionStore` empuja `ContentState = {elapsedLabel: "12:04", stepsLabel: "1.482", distanceLabel: "1,2 km"}` cada N segundos. Cumple AD-15 literalmente y AD-7 (el store es la única fuente).

**Por qué el spine permite ambas:** AD-15 dice qué **no** hace la extensión y nunca **qué contiene el `ContentState`** ni **quién avanza el reloj**. `Shared/` aparece en el *Structural Seed* como "ContentState de la Live Activity" — un nombre, no un contrato.

**Cómo se rompe:** `ContentState` es **un solo tipo, en un solo target compartido por App Group**. Las dos historias no pueden compilar juntas: es un conflicto duro, no de comportamiento. Y cada una arrastra un defecto propio:
- **B se congela.** ActivityKit limita las actualizaciones frecuentes; una sesión de 60 min a 1 Hz supera el presupuesto y el sistema **descarta actualizaciones sin avisar**. La pantalla de bloqueo se queda en un número viejo mientras la app muestra el correcto: exactamente el fallo de "dos caminos calculando lo mismo" que AD-15 dice prevenir — **causado por AD-15**.
- **B duplica el formateador.** Las convenciones dicen que *"la conversión a km y a `mm:ss` ocurre solo en la capa de formato de UI"*, y `UI/Format/` vive en el target de la app, que **AD-15 prohíbe importar a la extensión** (`Shared` únicamente). Así que o B formatea en la app y manda `String` (y entonces `ContentState` no tiene datos, tiene pixeles), o alguien escribe un segundo formateador. El spine prohíbe el único sitio donde el formato puede vivir legalmente y no ofrece otro.

**Cierre propuesto (AD-15 endurecido + AD nuevo):** (a) **publicar el `ContentState` campo a campo en el propio spine** — es un contrato entre dos targets, exactamente lo que un spine existe para fijar; (b) decidir por escrito que **el tiempo se deriva en el render con `timerInterval`** y que eso **no** cuenta como "calcular" (o lo contrario, asumiendo el coste); (c) mover `Format/` a `Shared/` — o declarar que la extensión recibe valores ya formateados y que el formateador es **uno solo**, en `Shared/`, importado por app y extensión.

---

### H-07 — Semana ISO: UTC contra hora local, con tres consumidores · CRÍTICO

**Unidad A — Historia «Anillo de meta semanal» (CAP-7, `GoalEngine`).**
Implementa `domain-model.md §5` textual: *"lunes 00:00 **UTC** de la semana corriente hasta +7 días"*. Cumple AD-6 (los vectores dorados vienen de la PWA, que calculaba en UTC → **el vector le da la razón**) y la convención del spine, que sólo le exige fijar `firstWeekday`.

**Unidad B — Historia «Recordatorio de meta» (CAP-17) y/o «Totales semana/mes» (CAP-10).**
Programa la notificación del domingo por la tarde **en hora local** (no tiene otra opción: `UNCalendarNotificationTrigger` es local) y calcula "te faltan N km esta semana" con un `Calendar` con `firstWeekday = 2` y `timeZone = .current`, siguiendo la nota de `achievements.md`: *"en iOS se evalúan en **hora local** del dispositivo"*. Cumple la convención del spine igual de bien.

**Por qué el spine permite ambas:** la tabla de convenciones dice *"Semana ISO (lunes–domingo) siempre con un `Calendar` configurado explícitamente — nunca `Calendar.current` sin fijar `firstWeekday`"*. **Fija el primer día de la semana y olvida la zona horaria**, que es la mitad que importa. Y el contrato heredado se contradice consigo mismo: §5 dice UTC para la meta, §9 y `achievements.md` dicen local para rachas y horarios. Ningún AD arbitra.

**Cómo se rompe, concreto (Madrid, UTC+2):** Paul camina 2,5 km el domingo a las 23:30 hora local = lunes 21:30 UTC.
- El anillo (A, UTC) mete esos 2,5 km en la **semana siguiente**; Paul ve el domingo por la noche que le faltaban 2,5 km y que su caminata **no movió el anillo**.
- El total "esta semana" del Historial (B, local) sí los cuenta → **dos pantallas, dos números para la misma semana**.
- El recordatorio del domingo 20:00 (B) dice "te faltan 2,5 km" y el logro `weekly_goal` (evaluado por A) no se desbloquea nunca esa semana.
- Y `7_days_streak` (local, por `achievements.md`) considera esa caminata del **domingo**, mientras el `GoalEngine` la considera del **lunes**: la misma sesión pertenece a dos días distintos dentro de la misma app.

**Cierre propuesto (AD nuevo, "AD-19 · Un solo calendario"):** un único `AppCalendar` en `Domain/`, **inyectado por puerto** junto al `ClockPort`, con `identifier`, `firstWeekday` **y `timeZone` fijados en un solo sitio**; todo cálculo de semana, día y hora del producto pasa por él; **la zona es la local del dispositivo** y el AD debe **derogar explícitamente el "UTC" de `domain-model.md §5`** — y anotar que los vectores dorados de AD-6 para el `GoalEngine` **deben regenerarse**, porque los actuales codifican el bug de la PWA. Este es el punto donde AD-6 deja de ser un suelo y pasa a ser un ancla: **un vector heredado bloqueará el merge de la implementación correcta**.

---

### H-08 — `weekly_goal`: logro de por vida contra celebración semanal · ALTO

**Unidad A — Historia «Celebración de meta» (CAP-7).**
Criterio de CAP-7: *"cruzar el 100 % dispara celebración **una sola vez por semana**"*. Necesita recordar la semana ya celebrada; añade `lastGoalCelebratedWeek` a `settings.json` y sube `schemaVersion`. Cumple AD-9.

**Unidad B — Historia «Catálogo de 14 logros» (CAP-8).**
`weekly_goal` es la entrada #5 del catálogo. Su almacenamiento es `{key, unlockedAt, progress}` — **un desbloqueo de por vida**. Y AD-5 obliga: son 14 entradas y **ninguna se declara en Swift**, así que `weekly_goal` no puede tratarse aparte. Cumple AD-5 al pie de la letra.

**Por qué el spine permite ambas:** el estado "meta ya celebrada esta semana" **no existe en ninguna forma de almacenamiento** (`domain-model.md §8` no lo tiene y el spine no lo añade), y ningún AD dice quién lo posee. `achievements.md` dice que `weekly_goal` *"se evalúa externamente vía GoalEngine"* — externamente **a qué store**, no lo dice nadie.

**Cómo se rompe:** semana 1, Paul cumple la meta → **doble celebración** (A por el anillo, B por el logro), doble háptica, dos toasts. Semana 2, la cumple otra vez → A celebra, B no (ya desbloqueado) → el grid muestra `weekly_goal` desbloqueado para siempre mientras el anillo celebra cada semana. Ninguna de las dos está mal; simplemente son dos productos distintos.
Y se cruza con CAP-15: borrar una sesión te deja al 85 % después de haber celebrado. A no vuelve a celebrar esa semana (recuerda que ya celebró); B mantiene el logro desbloqueado por la regla de no-revocación. Coherente por separado, incoherente junto.

**Cierre propuesto:** declarar por AD que `weekly_goal` es **un logro de por vida** y que la celebración semanal del anillo es **un evento distinto con estado propio**, con dueño nombrado (`SettingsStore` o `GoalStore`) y clave en el esquema; o lo contrario. Pero escrito.

---

### H-09 — Cadencia: quién posee "minutos con sensor activo" · ALTO

**Unidad A — Historia «Métricas en vivo» (CAP-4).**
`cadenceSpm = stepsMeasured / minutosConSensorActivo`. En nativo el coprocesador **siempre** está activo (es la razón de ser de CAP-2), así que `minutosConSensorActivo = (elapsedS − pausas)/60`. Cumple el contrato (*"cadencia solo sobre tramos medidos"*: todos los tramos son medidos).

**Unidad B — Historia «Reconstrucción de gap» (CAP-3, `GapEstimator`).**
Necesita la cadencia **previa al gap** para extrapolar, y hereda de la PWA que "sensor activo" significaba foreground con pantalla encendida. Excluye los intervalos de background de la ventana. Cumple el contrato con la misma frase.

**Por qué el spine permite ambas:** `minutosConSensorActivo` **no es un campo del agregado** (`domain-model.md §2` no lo lista), no tiene dueño en el mapa de capabilities, y AD-4 ("Swift idiomático") invita explícitamente a no copiar la implementación JS. Peor: **AD-6 arbitra a favor de B**, porque los 168 vectores se extraen de una implementación donde "activo" era foreground — así que la historia que implemente la semántica **correcta para nativo** verá un vector rojo y su merge bloqueado.

**Cómo se rompe:** dos `cadenceSpm` para la misma sesión según qué módulo la calcule; y como la cadencia alimenta la estimación del gap (§4), **el error se propaga a `stepsEstimated`**, es decir a un número que el usuario ve marcado "~" y puede descartar.

**Cierre propuesto:** hacer de **la ventana medida un dato explícito del agregado** (p. ej. `measuredWindowS`), con un dueño único (`SessionStore`, que es quien ve las transiciones de ciclo de vida), y **anotar en AD-6 los vectores que codifican semántica de plataforma web** — hace falta una lista de vectores derogados, o AD-6 congela los bugs de la PWA en la app nativa.

---

### H-10 — El timeout de AD-8: diferido significa "cada historia elige el suyo" · ALTO

**Unidad A — Historia «Reconciliación al volver a foreground» (CAP-3).**
AD-8 exige un timeout y el spine lo difiere, así que A pone `private let reconcileTimeout: Duration = .seconds(3)` en `SessionStore` (por analogía con los 3 s de Open-Meteo de la tabla de *Stack*). Cumple AD-8.

**Unidad B — Historia «Live Activity durante la reconciliación» (CAP-18).**
Necesita saber cuánto puede durar el estado "reconciliando" para elegir el `staleDate` del `ContentState`. Pone 10 s. Cumple AD-8 y AD-15.

**Por qué el spine permite ambas:** AD-8 dice *que existe* un timeout, no dónde vive el número. Y **AD-5 no lo cubre**: AD-5 ata las constantes a `AchievementEngine` y `GoalEngine`, y AD-8 dice expresamente que la reconciliación *"vive fuera del dominio"*, así que el timeout no es una constante de fórmula. Queda en tierra de nadie, y el *Deferred* lo bendice.

**Cómo se rompe:** en el segundo 4 la app ya degradó a estimación "~" y liberó los comandos; la pantalla de bloqueo sigue diciendo "reconciliando" seis segundos más, o se marca *stale* y muestra un número congelado. Dos relojes para una operación que AD-8 define como **atómica**.

**Segundo eje del mismo agujero — qué significa "rechazar un comando":**
- A lanza un `DomainError`; la convención de errores obliga entonces a *"una única traducción a mensaje de usuario"* → Paul pulsa Finalizar y ve un mensaje de error, en un producto cuya dirección es **"celebrar, nunca culpar"**.
- B no lanza nada: los botones están `disabled` (AD-8 dice *"la UI los deshabilita"*) y el comando se descarta en silencio.
- Y **AD-8 sólo contempla superficies con botones deshabilitables**. Una Live Activity con botones de App Intent (patrón estándar en iOS 26) puede disparar `finish()` **desde la pantalla de bloqueo, en mitad de la reconciliación**, por un camino que AD-8 no modela y que AD-15 no prohíbe porque un App Intent no es "calcular".

**Cierre propuesto:** sacar el timeout del *Deferred* — no es un número de microcopy, es un **contrato entre dos historias**. Ponerlo en `formulas.json` (o donde sea, pero **en un sitio**), extender AD-5 para cubrir constantes de aplicación, definir **desde qué instante se mide**, y añadir a AD-8 que **rechazar no es un error de dominio** sino un no-op observable, y que **toda superficie de comando** (UI, App Intent, Live Activity, atajo) pasa por el mismo guardián.

---

### H-11 — CSV: el serializador propio que AD-9 no cubre · ALTO

**Unidad A — Historia «Exportar historial» (CAP-14), camino CSV.**
El export sale de la UI de Ajustes; aplica la convención *"la conversión a km y a `mm:ss` ocurre solo en la capa de formato de UI"* y emite `fecha;1,20 km;12:04;7:32 /km` con formato español.

**Unidad B — Historia «Export/Import JSON» (CAP-14).**
Aplica AD-9: el JSON en disco **es** el formato de intercambio, metros y segundos, ISO-8601.

**Por qué el spine permite ambas:** AD-9 dice *"el export de CAP-14 no tiene serializador propio: emite el mismo formato"* — y eso **sólo puede referirse al JSON**. El CSV, que CAP-14 exige igualmente, **no tiene forma definida en ningún sitio**: ni columnas, ni separador, ni unidades, ni si es re-importable. Es exactamente el segundo serializador que AD-9 fue escrito para prevenir, y AD-9 lo deja pasar por la puerta de al lado.

**Cómo se rompe:** con decimal español (`1,20`) y separador coma, el fichero **se abre roto en Numbers** — que es el criterio de aceptación literal de CAP-14. Y si mañana alguien quiere re-importar el CSV, no hay contrato que se lo permita.

**Cierre propuesto:** AD-9 debe declarar el CSV como **una proyección de sólo lectura, derivada del mismo modelo**, con columnas y unidades fijadas en el AD (unidades de dominio, separador `;`, punto decimal, o lo que se decida), y declarar explícitamente que **el CSV no es un camino de import**.

---

### H-12 — Import: ¿reemplaza o fusiona? ¿y qué hace con `source`? · ALTO

**Unidad A — Historia «Importar respaldo» (CAP-14).**
Criterio literal: *"export → borrar datos → import → historial restaurado íntegro"*. Implementa **reemplazo**: el fichero importado sustituye `sessions.json`.

**Unidad B — Historia «Importar respaldo»** (otro sprint, misma capability).
Implementa **merge idempotente por `id`**, siguiendo la regla archivada de `domain-model.md §7` (*"idempotente por id: re-importar el mismo archivo no duplica"*).

**Por qué el spine permite ambas:** AD-9 fija el **formato** del import y **ni una palabra sobre su semántica**. Las reglas de §7 están marcadas "archivadas — no aplican en v1", así que B las está resucitando y A las está ignorando; ninguna incumple nada.

**Cómo se rompe:** con A, importar un respaldo de hace un mes **borra las sesiones del mes** sin aviso — pérdida de datos en la capability cuyo propósito es no perder datos. Y ninguna de las dos define qué pasa con los **logros** al importar (¿el fichero los trae? ¿se recalculan? → H-02 otra vez), ni con un registro cuyo `source` sea `"v3"` (§7 dice que no alimenta cadencia — una regla que **ninguna historia de v1 implementa** porque CAP-16 está retirada, y que un fichero editado a mano puede activar).

**Cierre propuesto:** un AD que fije **merge idempotente por `id`**, la **validación de frontera del fichero importado** (rechazar, no corregir — es contrato heredado), el trato de `source` desconocido, y si el import dispara evaluación de logros y escritura en Salud (ver H-13).

---

### H-13 — HealthKit: quién dispara la escritura, y qué la re-dispara · ALTO

**Unidad A — Historia «Sync automático a Salud» (CAP-11).**
`SessionStore.finish()` espera el `await healthPort.write(workout)` antes de persistir, para que el Summary pueda mostrar "sincronizado". Cumple AD-7, AD-10, AD-11.

**Unidad B — Historia «Pantalla Summary».**
Dispara la escritura al aparecer la vista, vía `HealthPort` (legal: no importa HealthKit, usa el puerto — AD-10 cumplido). Así la sesión se guarda instantáneamente y Salud no bloquea el cierre, que es justo lo que pide AD-11 (*"la sesión se guarda local igual"*).

**Por qué el spine permite ambas:** el mapa sitúa CAP-11 en `Adapters/Health` gobernado por AD-10 y AD-11 — **dónde vive y qué hacer si falla**. Nunca **quién lo llama ni cuándo**.

**Cómo se rompe:** con B, un force-quit antes de que el Summary aparezca deja el workout sin escribir **para siempre** — no hay reintento, porque nadie posee la cola. Con A, un HealthKit lento retrasa el cierre de una sesión que el contrato declara inmutable en el instante del cierre. Y con las dos: **doble workout en Salud**. Súmese el import (H-12): si escribir en Salud es efecto de *persistir* y no de *finalizar*, importar un respaldo escribe 200 workouts duplicados.

**Cierre propuesto:** declarar por AD que la escritura en Salud es **un efecto de la transición a `finished`, nunca de la persistencia ni del render**, con **idempotencia por `session.id`** (metadato en el `HKWorkout`) y una **cola de reintento con dueño nombrado** — porque AD-11 promete degradación limpia y sin cola no hay degradación, hay pérdida.

---

### H-14 — `recentQuoteIds`: `SessionStore` escribe en el fichero de `SettingsStore` · MEDIO-ALTO

**Unidad A — Historia «Momento motivacional» (CAP-6).**
La frase se elige al iniciar la sesión (`SessionStore`), y `recentQuoteIds` vive en `config` → `settings.json`, cuyo dueño natural es `SettingsStore`. A la mete en el snapshot de sesión activa y la vuelca a `settings.json` al finalizar.

**Unidad B — Historia «Ajustes».**
`SettingsStore` mantiene su copia en memoria de `settings.json` y la reescribe entera cuando Paul cambia el sonido o la meta.

**Por qué el spine permite ambas:** AD-7 protege **la sesión**, no los ficheros. AD-9 define **el formato**, no el dueño. Nada impide dos escritores de `settings.json`.

**Cómo se rompe:** Paul inicia una caminata (A registra la frase #47), y durante la sesión entra en Ajustes y sube la meta a 12 km (B reescribe `settings.json` desde su copia, **sin la frase #47**, con temp+rename: sin conflicto, sin error, sin log). La frase #47 vuelve al bombo y CAP-6 falla en su único criterio de aceptación: *"20 sesiones consecutivas sin repetición"*. Un fallo probabilístico, invisible en test, reproducible sólo en producción.

**Cierre propuesto:** el mismo AD-16 de H-02 ("un fichero, un dueño") lo cierra: `SessionStore` no escribe `settings.json`, se lo pide a `SettingsStore`.

---

## Hallazgos menores (no generan un par, pero dejan una decisión sin dueño)

- **¿Cuándo se congela la zancada?** `domain-model.md §2` dice *"congelado al cierre"*; §8 pone `strideM` **dentro del snapshot de inicio**. Una historia que recalibre a mitad de sesión reescribe retroactivamente la distancia de toda la caminata; otra no. El spine cita el invariante ("zancada congelada al cierre") sin resolver la contradicción de su propio companion.
- **¿El anillo cuenta la sesión en curso?** CAP-12 exige háptica de "meta cumplida" — un evento que sólo puede ocurrir **durante** la caminata, luego el anillo debe ser vivo. Pero `GoalEngine` suma "sesiones", y una sesión activa no está en `sessions.json`. Dos historias, dos anillos.
- **`progress: 0.0..1.0` para logros booleanos** (`rain_walker`, `early_bird`, `first_session`): la forma de almacenamiento lo exige para los 14 y ninguna regla lo define para los no acumulativos. Sub-caso de H-01.
- **`ClockPort` no llega a la extensión.** AD-10 dice *"el dominio nunca llama a `Date()`"*, pero la extensión no puede importar `Domain` (AD-15) y usará el reloj del sistema. Con un cambio de hora o un salto de DST a las 03:00 durante una caminata madrugadora, app y pantalla de bloqueo muestran una hora de diferencia — y `early_bird`, evaluado en local, cambia de respuesta según el instante en que se evalúe.
- **No hay atomicidad multi-fichero.** AD-9 da temp+rename **por fichero**. Cerrar una sesión toca `sessions.json`, `achievements.json`, `settings.json` y borra el snapshot activo: **cuatro renames**. Morir entre el segundo y el tercero es un estado que ningún AD define ni ninguna historia sabe reparar.

---

## Resumen de agujeros y cierres propuestos

| # | Agujero | Severidad | Tipo de fallo | Cierre |
|---|---|---|---|---|
| H-01 | Esquema de `achievements.json` sin definir (reglas vs metadatos) | Crítico | Build / arranque | AD-5 endurecido: publicar el esquema y validarlo entero |
| H-02 | Dos momentos de evaluación y dos escritores de logros | Crítico | Datos | **AD-16** un fichero un dueño · **AD-17** disparador único |
| H-03 | CAP-15 borrado: sin propagación definida; posible revocación | Crítico | Datos / contrato | AD-17: recomputación monótona, desbloqueos append-only |
| H-04 | Snapshot activo fuera de AD-9 y en ms contra la convención | Crítico | Datos / unidades | AD-9 endurecido: 4º fichero, segundos, ISO-8601, `schemaVersion` |
| H-05 | Sesión huérfana sin dueño ni criterio | Crítico | Ciclo de vida | **AD-18** estado `Orphaned` con dueño, umbral y efectos |
| H-06 | `ContentState` sin contrato; quién avanza el reloj; formateador duplicado | Crítico | Build | AD-15 endurecido: publicar `ContentState`; `Format/` a `Shared/` |
| H-07 | Semana ISO en UTC contra hora local | Crítico | Datos / UX | **AD-19** un solo `AppCalendar`; derogar el UTC de §5 |
| H-08 | `weekly_goal` de por vida contra celebración semanal | Alto | Comportamiento | Separar logro y celebración; dueño y clave de estado |
| H-09 | Ventana "con sensor activo" sin dueño; AD-6 arbitra a favor del bug | Alto | Datos | Campo explícito en el agregado + lista de vectores derogados |
| H-10 | Timeout de reconciliación diferido; "rechazar" indefinido; App Intents | Alto | Comportamiento | Sacar del *Deferred*; guardián único de comandos |
| H-11 | CSV sin contrato — el segundo serializador que AD-9 no vio | Alto | Datos | AD-9: CSV como proyección de sólo lectura, columnas fijadas |
| H-12 | Import: reemplazo contra merge; `source` desconocido | Alto | Pérdida de datos | AD de semántica de import: merge idempotente por `id` |
| H-13 | Escritura en Salud sin disparador ni idempotencia ni cola | Alto | Integración | Efecto de `finished`, idempotente por `id`, con cola |
| H-14 | Dos escritores de `settings.json` pierden `recentQuoteIds` | Medio-alto | Datos | Cubierto por AD-16 |

**Cinco ADs nuevos y cuatro endurecimientos** cierran los catorce. Los cinco nuevos, en orden de urgencia:

- **AD-16 · Un fichero, un dueño.** Cada fichero de AD-9 tiene un único store escritor; los demás leen a través de él. Cierra H-02, H-03, H-14 y la mitad de H-04.
- **AD-17 · La evaluación de logros tiene un disparador único.** Sólo en `finished` y en el borrado; el desbloqueo es append-only; ninguna pantalla evalúa al pintar.
- **AD-18 · Ciclo de vida de la sesión huérfana.** El arco que falta en el diagrama de AD-8.
- **AD-19 · Un solo calendario.** `AppCalendar` por puerto, con zona fijada; deroga el UTC de `domain-model.md §5` y marca los vectores dorados a regenerar.
- **AD-20 · Contrato de superficies de comando.** Todo comando (UI, App Intent, Live Activity) pasa por el mismo guardián de AD-8; rechazar es un no-op observable, no un error de dominio.

## Lo que el spine sí cierra bien (para que el endurecimiento no lo estropee)

AD-5 y AD-6 son la mejor pareja del documento: sacan la verdad del código y la ponen en datos que las dos implementaciones ejecutan. AD-7 elige bien el riesgo que quiere correr y lo dice. AD-8 es el único AD del documento que **se pone a sí mismo un límite** ("atómico sin timeout es un bloqueo con buenos modales") — el patrón que le falta a los otros catorce. Y AD-2 y AD-13 ahorran trabajo real. El problema no es que el spine decida mal: es que **decidió una entidad y se olvidó de las otras cuatro**.
