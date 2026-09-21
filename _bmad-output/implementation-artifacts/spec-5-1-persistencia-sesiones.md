---
title: '5.1 — Las caminatas terminadas sobreviven al cierre de la app'
type: 'feature'
created: '2026-09-21'
baseline_commit: '4d014a5db375d73ece3bd2e6a0f8b18220d9bb74'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-5-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-b1-ajustes-no-se-pisan.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** una caminata terminada **no se guarda en ninguna parte**. `confirmFinish()` acaba en
`clearSnapshot()`, que borra el fichero de la sesión viva, y lo único que queda es un `FinishedWalk`
en un `@State` de `SessionView` — una proyección de vista sin `id`, sin `startedAt` y sin zancada,
que muere al salir del resumen. Todo lo que Paul ha caminado en once builds se ha perdido.

**Por eso esta historia se adelanta** (decisión de Paul, 2026-09-21). El Epic 3 no puede empezar sin
ella: la 3.1 suma las caminatas de la semana para el anillo y la 3.2 necesita acumulados y rachas.
Son además **79 vectores de equivalencia** los que esperan a leer este registro.

**Enfoque:** el registro inmutable de una caminata cerrada, por el mismo `StoragePort` y sobre el
mismo sustrato de disco que ya existe. La historia **añade dos ficheros con sus dueños, no el
mecanismo**.

## Boundaries & Constraints

**Decisiones de Paul (2026-09-21):**
- **Un historial ilegible se aparta, la app sigue con historial vacío, y se avisa.** Hereda la
  doctrina de B-1 —el fichero no se destruye— y añade lo que los ajustes no necesitaban: **un aviso
  visible**. No es simétrico con `settings.json`: allí se pierde la configuración; aquí, el historial
  entero, que **no es reproducible** y que CAP-9 promete garantizado. Perderlo en silencio es lo peor
  de las salidas posibles.
- **La sesión huérfana entra en el historial con su marca**, y **no cuenta para logros** (AD-18 dice
  que se archiva y no dispara celebración). El contrato de datos gana una columna para distinguirla.
- **Se guarda primero y solo se borra el snapshot si el guardado fue bien.** Si falla, el snapshot
  sigue ahí y la caminata se recupera al relanzar. Hay que impedir que en esa ventana se restaure
  como huérfana.
- **La escritura sigue siendo síncrona**, como el resto del puerto: ~1.500 caminatas en diez años son
  unos cientos de KB y el momento es uno solo. **Se anota el umbral** a partir del cual dejaría de
  valer, con su número.

**Decisiones del implementador, registradas:**
- **La huérfana sí suma al anillo y a la distancia.** Sus pasos son reales: los contó el
  coprocesador. Lo que AD-18 prohíbe es que dispare logros, no que exista.
- **Una métrica degradada no se guarda como verdad.** `metrics(at:)` devuelve `distanceM: 0` con
  `degraded: true` cuando algo no cuadra; un 0 en disco es indistinguible de una caminata sin pasos,
  y el registro es **inmutable**. La marca viaja con el registro, por la misma razón que `recovered`.

**Always:**
- **El mecanismo no se reinventa:** `JSONFileStore` (escritura atómica, apartado con nombre único,
  derivación de nombres) se reutiliza **tal cual**, y `FileStorageAdapter` gana dos campos.
- **Un fichero, un dueño** (AD-16), declarado en la sección 9 del gate. Si un store nuevo se inyecta
  en otro, hace falta su regla equivalente a la 9b — que existe porque ya pasó con los ajustes.
- **`nil` no es un error de lectura.** "No hay nada" deja escribir; "hay algo que no pude leer", no.
- **Un esquema del futuro no es corrupción:** se deja intacto y la lectura lanza.
- Los timestamps del registro van en **ISO-8601** (contrato de datos), no en milisegundos como el
  snapshot. Las dos serializaciones conviven en el mismo directorio y no se mezclan.
- La zancada de una sesión cerrada queda **congelada**: recalibrar nunca reescribe historial. Esto
  cierra el test que la 2.3 dejó pendiente por no haber historial contra el que probarlo.

**Never:**
- Crear un puerto nuevo: AD-10 fija un conjunto cerrado de 11 y "persistencia local" ya es uno.
- Tocar el catálogo de logros de `Resources/`, que es contenido congelado y tiene el **mismo nombre**
  que el store de desbloqueos. Son dos ficheros distintos.
- Adelantar la 5.2 (lista, totales, tendencia), la 5.3 (export) ni la 5.4 (borrado).
- Evaluar logros: eso es la 3.2. Esta historia **fija el punto donde se enchufará**, y lo dice.
- Reescribir el resumen que dejó la 1.4 más allá del aviso de fallo de guardado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Caminata normal | se finaliza con pasos y distancia | queda un registro inmutable con sus campos materializados | — |
| Sobrevive al relanzar | se cierra la app y se reabre | el registro sigue ahí, íntegro | — |
| Primera vez | no hay `sessions.json` | se crea al guardar la primera | — |
| Historial ilegible | JSON roto o campos de otro tipo | **se aparta**, la app sigue con historial vacío, **y se avisa** | aviso visible, no silencio |
| Historial del futuro | `schemaVersion` mayor | **se deja intacto**, no se escribe encima, y se avisa | — |
| Fallo al guardar | el disco falla al cerrar | **el snapshot NO se borra**: la caminata se recupera al relanzar | se avisa antes de salir del resumen |
| Ventana de duplicado | entre guardar y borrar el snapshot | al relanzar **no** se restaura como huérfana una caminata ya guardada | — |
| Sesión huérfana | se cierra sola tras el umbral | entra en el historial **con su marca**; suma distancia, **no dispara logros** | — |
| Métrica degradada | el cálculo no cuadra al cerrar | la marca viaja con el registro; un 0 no se guarda como verdad | — |
| Zancada congelada | se cierra con 0,655 y se recalibra a 0,670 | el registro **sigue en 0,655** | — |
| Clima y frase | caminata con clima y frase | los dos viajan al registro; sin ellos, ausentes | — |
| Pasos estimados | caminata con estimados | medidos y estimados **siempre desglosados** | — |
| Dos ficheros, un nombre | store de desbloqueos y catálogo | no se pisan; el gate del catálogo sigue verde | — |

</frozen-after-approval>

## Code Map

**Lo que se reutiliza sin tocar**
- `WalkTracker/Adapters/Persistence/JSONFileStore.swift` — `read`/`write` (temp + `rename(2)`),
  `remove`, `setAside` (`<base>.corrupt.<marca>.json` con `RENAME_EXCL`), y los nombres derivados de
  un solo `base`. **Entero, sin cambios.**
- `WalkTracker/Adapters/Persistence/FileStorageAdapter.swift` — compositor puro, una línea de reparto
  por método. Aquí se enchufan los adapters nuevos.

**El molde de adapter, idéntico en los dos que existen**
- `ActiveSessionFileAdapter.swift` y `SettingsFileAdapter.swift`: `supportedSchemaVersion` /
  `readableSchemaVersions`, `base`, `private struct File: Codable` con los campos nuevos
  **opcionales**, `VersionProbe`, `decode`/`encode` **puros y estáticos**, `sortedKeys`, y el `load`
  que aparta y **propaga el error original** aunque el apartado falle.
- **Divergencia a decidir conscientemente:** `SettingsFileAdapter` intercepta el esquema del futuro
  **antes** del `catch` que aparta; `ActiveSessionFileAdapter` **no**, y aparta cualquier versión
  fuera de rango. El registro nuevo sigue al primero.

**El molde de dueño único**
- `WalkTracker/Application/SettingsStore.swift` — init que lee una vez ("no hay un `load()` que
  alguien pueda olvidarse de llamar"), `ReadOutcome` (`loaded`/`absent`/`unreadable`) con
  `allowsWriting`, `save(applying:)` que recibe **una función** para poder reaplicar el cambio sobre
  lo que traiga el reintento, y `reloadBeforeWriting()`.

**El gate**
- `Scripts/check-project-shape.sh` sección 9: `storage_owner_rule NOMBRES DUEÑO EXPLICACIÓN` es
  **el único punto de declaración** de quién escribe qué. Un dueño nuevo es una línea más. La
  exención es por forma del nombre (`DUEÑO.swift`, `DUEÑO+Algo.swift`).
- Sección 9b: existe porque `SessionStore` guarda el `SettingsStore` en una propiedad llamada
  `settings` y eso compilaba. Si un store nuevo se inyecta igual, hace falta su equivalente.

**El dominio**
- `Domain/Session/Session.swift` — el mapeo campo a campo está en el contrato de datos. Ojo:
  `distanceM`, `paceSecPerKm` y `cadenceSpm` **son derivadas**, salen de `metrics(at:)` y hay que
  **materializarlas** al cerrar; `recovered` existe en el agregado y **no** está en el contrato;
  `status` y `pausedAt` no aplican a un registro cerrado.
- `Domain/Ports/ActiveSessionSnapshot.swift` — el molde de DTO de frontera: struct público, `let`s,
  init por miembros, doc que cita el contrato.
- `Domain/Ports/WorkoutRecord.swift` — **no encaja** (es el DTO de salida a Salud, sin `id`, sin
  zancada, sin clima), pero sus tests son el **molde de validación en frontera** a copiar.

**El punto de escritura**
- `SessionStore.confirmFinish()` — el hueco es **entre materializar las métricas y borrar el
  snapshot**: el único instante donde coexisten la sesión finalizada y sus métricas congeladas. AD-17
  obliga a que la 3.2 evalúe logros **en esa misma transacción**, así que la forma que se le dé aquí
  la condiciona.
- `SessionStore+Recovery.swift` — `closeOrphan(_:at:)` es el **segundo** sitio que cierra una sesión
  y también llama a `clearSnapshot()`. Fácil de olvidar.
- `SessionView.swift` — el `@State` con la caminata terminada; la restauración al relanzar es lo que
  hay que impedir que resucite un registro ya guardado.

**Los vectores que esperan**
- `WalkTrackerTests/Vectors/` — `weeklyProgress` (15) y `checkStreak` (8) consumen literalmente
  `{startedAt, distanceM}`; `evaluateAchievements` (51) necesita el historial y la sesión que cierra.
  `verify-domain.sh` exige ver la línea de pendientes de AD-6 o declara el gate no ejecutado.
  **Portarlos o traspasarlos con destino, pero no dejarlos sin decir.**

**Deriva a reconciliar**
- `sprint-status.yaml` y `epics.md` siguen con la 5.1 **detrás** del Epic 3. Si esto se implementa sin
  reconciliar el orden, se repite exactamente lo que A-5 vino a cerrar.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/` — el tipo del registro de sesión cerrada, con validación en frontera al molde de
      `WorkoutRecord`, y las columnas de huérfana y de métrica degradada.
- [x] `Domain/Ports/StoragePort.swift` — los métodos del historial y del store de desbloqueos,
      agrupados por dueño, con la doctrina de `nil` frente a error.
- [x] `WalkTracker/Adapters/Persistence/` — los adapters nuevos sobre `JSONFileStore`, y
      `FileStorageAdapter` repartiendo.
- [x] `WalkTracker/Application/` — los stores dueños, al molde de `SettingsStore`.
- [x] `WalkTracker/Application/SessionStore*.swift` — guardar al cerrar **y al cerrar una huérfana**,
      con el orden decidido y sin resucitar lo ya guardado.
- [x] El aviso: historial ilegible, y fallo de guardado antes de salir del resumen.
- [x] `Scripts/check-project-shape.sh` — los dueños nuevos declarados, más su regla equivalente a la
      9b si se inyectan. Casos rojo y verde en el arnés.
- [x] Tests de la matriz, **incluido el de la zancada congelada** que la 2.3 dejó pendiente.
- [x] `sprint-status.yaml` y `epics.md` — el orden nuevo, con su razón.
- [x] `deferred-work.md` — el umbral de tamaño con su número, los vectores que no se porten, y la
      transacción de AD-17 que cruza dos ficheros con dos dueños.

**Acceptance Criteria:**
- Dada una caminata terminada, cuando se cierra la app y se reabre, entonces **el registro sigue ahí**
  — y hoy no queda nada.
- Dado un `sessions.json` ilegible, cuando arranca la app, entonces se **aparta**, la app funciona con
  historial vacío y **Paul se entera**.
- Dado un fallo al guardar, cuando se cierra la caminata, entonces **el snapshot no se borra** y la
  caminata se recupera al relanzar.
- Dada una caminata cerrada con 0,655 y una recalibración posterior a 0,670, cuando se lee el
  registro, entonces **sigue en 0,655**.
- Dada una sesión huérfana, cuando se archiva, entonces está en el historial **marcada como tal**.

## Implementation Notes

**Dos ficheros, dos dueños, y el mecanismo intacto.** `JSONFileStore` no se ha tocado: los dos
adapters nuevos —`SessionHistoryFileAdapter` (`sessions.json`) y `AchievementsFileAdapter`
(`achievements.json` **del sandbox**)— lo usan tal cual, con su `base`, y `FileStorageAdapter` gana
cuatro líneas de reparto. Los dueños son `HistoryStore` y `AchievementsStore`, al molde de
`SettingsStore`: init que lee una vez, `ReadOutcome`, `save(applying:)` con reintento. `StoragePort`
pasa de 6 a 10 métodos y **sigue siendo un puerto** (AD-10).

**Dos tipos de dominio, no uno.** `SessionRecord` es el registro inmutable de la caminata cerrada,
con validación en frontera al molde de `WorkoutRecord`; `AchievementUnlock` es el `{key, unlockedAt,
progress}` del fichero de logros. Los dos son DTO de frontera (`Domain/Ports/`), como
`ActiveSessionSnapshot`.

**Lo que `SessionRecord` añade sobre el contrato de datos, y por qué.** `recovered` y `degraded`.
La primera existe en el agregado y **no** estaba en el contrato: sin ella una huérfana es
indistinguible de una caminata que Paul cerró. La segunda no existe en ningún sitio: `metrics(at:)`
devuelve `distanceM: 0` con `degraded: true` cuando el cálculo no cuadra (B-3), y un 0 en disco es
indistinguible de una caminata sin pasos — con el registro **inmutable**, no hay una segunda
oportunidad de decirlo. Las dos viajan con el registro por la misma razón.

**`countsForAchievements`, y por qué existe ya.** Es `!recovered`, una línea, y es **el punto donde
la 3.2 se enchufa**: AD-18 dice que una huérfana se archiva y no dispara celebración, y decidirlo
aquí evita que el evaluador vuelva a razonarlo. Lo que AD-18 prohíbe es la celebración, **no la
existencia**: la distancia de una huérfana es real y suma en el anillo (3.1) y en los totales (5.2).
Es además lo que hace comprobable la mutación "dejar que la huérfana dispare logros", que sin este
predicado no tendría nada que mutar.

**Una fila que el dominio rechaza hace ilegible el fichero, y no se salta.** Decisión del
implementador, registrada: un historial al que le falta una caminata **sin que nada lo diga** es
peor que uno apartado entero, porque apartarlo conserva los bytes (`sessions.corrupt.<marca>.json`)
y además avisa. La única excepción es el clima, como en el snapshot: un clima con la forma bien y
los rangos mal se lee como sin clima (AD-11).

**La divergencia de molde, decidida a la vista.** `SettingsFileAdapter` intercepta el esquema del
futuro **antes** del `catch` que aparta; `ActiveSessionFileAdapter` no. Los dos adapters nuevos
siguen al primero, y la razón es asimétrica: un snapshot apartado cuesta una caminata a medias; un
historial apartado por haber instalado un build anterior costaría meses de caminatas que no se
pueden reconstruir.

**El orden al cerrar, en un solo sitio.** `SessionStore+History.swift` tiene `saveFinishedWalk` y lo
llaman los **dos** puntos que cierran una sesión: `confirmFinish()` y `closeOrphan(_:at:)`. Cada uno
borra el snapshot **solo si** el guardado devolvió `true`. Tener un punto es lo que impide que el
segundo se olvide, que es exactamente lo que pasaba antes: los dos acababan en `clearSnapshot()` y
ninguno guardaba nada.

**La ventana de duplicado se cierra con la clave natural.** Entre guardar y borrar el snapshot la
caminata existe en los dos ficheros. `restoreOnLaunch()` pregunta `history.contains(startedAt:)`
antes de restaurar o archivar: si ya está, termina de borrar el snapshot y se va. `startedAt` es la
clave porque no puede haber dos caminatas que empiecen en el mismo instante. **Vale también pasado
el umbral de huérfana**, que era el caso peor: sin la guarda, la caminata guardada volvía a entrar
en el historial marcada como recuperada.

**Un reintento más, y por qué no bastaba con el snapshot.** Si el guardado falla, el snapshot sigue
en disco y la caminata vuelve al relanzar — pero solo hasta que Paul empiece otra caminata en esa
misma ejecución, porque el primer `persist()` de la nueva lo sobrescribe. Por eso
`leaveSummary()` reintenta el guardado con `unsavedFinishedRecord` antes de soltar la sesión: acota
la pérdida a "el disco falló dos veces".

**Dónde diverge `HistoryStore` de `SettingsStore`, a propósito.** Con la escritura bloqueada,
`SettingsStore.save(applying:)` **sí** aplica el cambio en memoria —la ventana de frases de esta
ejecución no debe repetir aunque el disco falle— y `HistoryStore.save(applying:)` **no**: un
registro en memoria que no está en disco haría que `contains(startedAt:)` diera por salvada una
caminata cuya única copia es el snapshot que se iba a borrar.

**El aviso, y dónde vive cada mitad.** El de historial ilegible es
`HistoryStore.showsUnreadableNotice` y lo pinta **Inicio**, no la pestaña Historial: la decisión
dice que Paul *se entera*, no que pueda enterarse si va a buscarlo, y la pestaña sigue siendo un
marcador de posición hasta la 5.2. El de fallo de guardado es
`SessionStore.finishedWalkNotPersisted` → `FinishedWalk.notPersisted` → una nota en
`SessionSummaryView`, **antes de dejar salir del resumen**; el resto del resumen de la 1.4 no se
toca. Los dos usan `Colors.error`, el rol medido de B-2, no un `.red` a mano.

**El gate.** Sección 9: dos `storage_owner_rule` más, una por dueño. Sección 9b: pasa de ser una
regla escrita a mano para `settings` a `injected_owner_rule PROPIEDAD DUEÑO INTENCIONES`, llamada
tres veces (`settings`, `history`, `achievements`) — hacía falta porque `SessionStore` guarda el
store del historial en una propiedad `history`, igual que guardaba el de ajustes en `settings`, y
eso compila. Sección 6: `HistoryStore` y `AchievementsStore` entran en los tipos de receptor y
`history` en la lista de pasos internos. El arnés pasa de 208 a **220 casos**, con rojo y verde para
cada regla nueva, incluidos los dos sentidos de la separación (el dueño del historial tampoco puede
tocar el snapshot) y el subdirectorio que empieza igual que el dueño.

**`ISO8601Timestamp`, y por qué no es `ISO8601DateFormatter`.** Los ficheros nuevos van en ISO-8601
(contrato de datos) y el snapshot sigue en milisegundos (domain-model.md §8): conviven en el mismo
directorio y no se mezclan, porque las claves ni siquiera se llaman igual (`startedAtMs` frente a
`startedAt`). Se escribe con milisegundos —viaje de ida y vuelta estable— y se lee con y sin
fracción. Es `Date.ISO8601FormatStyle` porque es un tipo de valor `Sendable` y puede ser una
constante estática bajo concurrencia estricta (AD-12); el formateador de clase habría obligado a
construir uno por llamada o a esconder un `nonisolated(unsafe)`.

**`StoredFileReadOutcome`.** El vocabulario de B-1 sale de dentro de `SettingsStore` para que los
dos dueños nuevos no lo vuelvan a razonar cada uno por su cuenta. `SettingsStore` conserva de
momento su tipo anidado: migrarlo toca sus tests y es parte de B-10, y está en `deferred-work.md`.

**Lo que esta historia NO hizo, con su destino escrito.** Los 79 vectores que esperaban al historial
**no se portan**: `weeklyProgress` (15) y `checkStreak` (8) necesitan el `AppCalendar` de AD-19, que
crea la 3.1; `evaluateAchievements` (51) y `checkTimeOfDay` (5) necesitan el evaluador de la 3.2.
La línea de pendientes de AD-6 sigue **idéntica**, y eso es lo esperado. Tampoco se evalúa ningún
logro, ni se adelanta nada de la 5.2, la 5.3 ni la 5.4.

## Spec Change Log

## Review Triage Log

## Design Notes

**Por qué el aviso, y por qué solo aquí.** B-1 resolvió que un fichero ilegible se aparta y no se
sobrescribe, y eso vale igual para el historial. Lo que cambia es la consecuencia: perder los ajustes
es perder una zancada y una ventana de frases —molesto y rehacible—; perder el historial es perder
meses de caminatas que **no se pueden reconstruir**. Un silencio proporcionado allí es
desproporcionado aquí.

**El orden al cerrar crea una ventana, y hay que cerrarla.** Guardar antes de borrar el snapshot es lo
correcto —un fallo no pierde la caminata— pero durante un instante la sesión existe en los dos
ficheros. Si en ese instante muere la app, al relanzar la recuperación la vería como una sesión viva
y podría archivarla otra vez. Resolverlo es parte de la historia, no un detalle.

**La transacción que esta historia no puede cerrar.** AD-17 pide que la 3.2 evalúe logros dentro de la
misma transacción que persiste la sesión; AD-16 pide un fichero, un dueño; y la escritura es atómica
**por fichero**. No hay atomicidad conjunta entre dos ficheros con dos dueños. **El problema se crea
aquí aunque se manifieste en la 3.2**, así que se nombra y se registra en vez de descubrirlo entonces.

**Lo que el puerto síncrono aguanta, con su número.** Su documentación justifica la sincronía en que
"los dos ficheros ocupan unos cientos de bytes", y eso deja de ser cierto. Con ~1.500 caminatas en
diez años el fichero ronda unos cientos de KB y se reescribe entero en el hilo principal **una vez por
caminata**: milisegundos. Se queda síncrono, y se anota a partir de qué tamaño habría que revisarlo.

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` — verde. La línea de pendientes de AD-6 debe reflejar lo que se
  porte; si no se porta nada, debe seguir igual y estar dicho por qué.
- `bash Scripts/check-project-shape.sh` y `check-project-shape-tests.sh` — verdes, con los dueños
  nuevos declarados y sus casos rojo y verde.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` — TEST SUCCEEDED, y el
  conteo **sube**.
- **Mutaciones obligatorias**, todas las que hoy pasarían: borrar el snapshot antes de guardar; no
  apartar un historial ilegible; escribir encima de un historial del futuro; y dejar que la huérfana
  dispare logros.
- **Contar los casos nuevos por nombre en el `.xcresult`**, no conformarse con `TEST SUCCEEDED`.

**Manual checks (iPhone):** caminar, terminar, **cerrar la app del todo y reabrir** — la caminata
sigue. Recalibrar la zancada después y comprobar que el registro no cambia.

**Ejecutado (2026-09-21):**
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` → **TEST SUCCEEDED**,
  **723 tests en 59 suites** (656 en 51 antes: los 8 suites y 67 casos nuevos son todos de ficheros nuevos, ninguno se ha añadido a un suite existente), sin errores ni warnings propios nuevos.
- `bash Scripts/verify-domain.sh` → **verde** (255 tests en 18 suites; 245 en 16 antes). La línea de
  pendientes de AD-6 es **la misma**: `achievementCatalog (1), checkStreak (8), checkTimeOfDay (5),
  evaluateAchievements (51), weeklyProgress (15)`. No se ha portado ningún vector y el porqué, con
  su destino por historia (3.1 y 3.2), está en `deferred-work.md`. Los suites nuevos que SÍ entran
  en el alcance son los dos de `Domain/`: `SessionRecordTests` y `AchievementUnlockTests`, añadidos
  a `DOMAIN_SUITES`; los de `Application/` y `Adapters/` quedan fuera por el criterio de AD-6 fijado
  desde la 1.1.
- `bash Scripts/check-project-shape.sh` → verde. `bash Scripts/check-project-shape-tests.sh` →
  **220/220** (208 antes): 12 casos nuevos, rojo y verde, para los dos dueños nuevos de la sección 9
  y para la regla 9b generalizada.
- **Los tests nuevos se ejecutan de verdad**, contados por nombre sobre el `.xcresult` y no por
  `TEST SUCCEEDED`: `SessionStore · la caminata cerrada se guarda` **15**,
  `SessionHistoryFileAdapter · historial de caminatas` **15**,
  `AchievementsFileAdapter · estado de los logros` **10**, `HistoryStore · dueño de sessions.json`
  **9**, `SessionRecord · validación` **7**, `HistoryStore · el ciclo completo sobre sessions.json`
  **5**, `AchievementUnlock · validación` **3**, `AchievementsStore · dueño de achievements.json`
  **3** — **67 casos**, todos `Passed`.

**Mutaciones (obligatorias), las cuatro, más una:**
- **Borrar el snapshot antes de guardar** (`clearSnapshot()` antes de `saveFinishedWalk`) → **4
  tests fallan**, entre ellos "Si el guardado falla, el snapshot NO se borra y el resumen lo dice"
  (`storage.snapshot → nil` y `clearCount → 1`) y "Y la caminata se recupera al relanzar", que deja
  de recuperar nada.
- **No apartar un historial ilegible** (quitar el `file.setAside()` del `catch`) → **2 tests
  fallan**, el del adapter y el del ciclo completo sobre bytes reales.
- **Escribir encima de un historial del futuro** (`save(applying:)` sin la guarda de `allowsWriting`)
  → **3 tests fallan**, incluido el que compara los **bytes crudos** del fichero del futuro antes y
  después de una caminata.
- **Dejar que la huérfana dispare logros** (`countsForAchievements` → `true`) → **2 tests fallan**,
  el del dominio y el de la huérfana archivada.
- **(Extra) Quitar la guarda de la ventana de duplicado** (`history.contains(startedAt:)`) → **2
  tests fallan**: la caminata ya guardada vuelve como sesión viva y, pasado el umbral, se archiva
  otra vez marcada como recuperada.
- Árbol restaurado y suite completa en verde después de las cinco.

**Manual checks (iPhone): PENDIENTES.** No se han ejecutado. Son los dos de arriba —caminar,
terminar, cerrar la app del todo, reabrir y ver la caminata; recalibrar después y ver que el
registro no cambia— más los dos avisos, que solo se ven renderizando (`deferred-work.md`). El caso
del relanzamiento y el de la zancada congelada **sí** están cubiertos en test sobre ficheros reales
(`HistoryStore · el ciclo completo sobre sessions.json`); lo que falta del dispositivo es el
force-quit de verdad y el aspecto de los avisos.

