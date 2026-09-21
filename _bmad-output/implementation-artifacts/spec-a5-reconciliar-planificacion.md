---
title: 'A-5 — Los documentos de planificación dejan de afirmar lo que no es'
type: 'chore'
created: '2026-09-20'
baseline_commit: 'b73b0c9d7b8c3400359fc1c0dac3b4b372478d33'
status: 'done'
route: 'dispatch'
review_loop_iteration: 2
context:
  - '{project-root}/_bmad-output/implementation-artifacts/decisiones-2026-09-20.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-retro-2026-09-14.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-retro-2026-09-20.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** `epics.md` y `ARCHITECTURE-SPINE.md` describen conductas que el producto ya no tiene.
No es cosmético: **el contexto de cada épica se compila de esos documentos**, así que lo desfasado
viaja a las historias que aún no se han escrito. Ya ocurrió en el Epic 2 — al recompilar su contexto
salió una advertencia falsa (la atribución de Open-Meteo dada por pendiente cuando estaba
implementada) precisamente porque el compilador solo lee planificación.

**Y el Epic 3 es el siguiente.** Dos afirmaciones falsas apuntan directamente a sus historias:
`epics.md:427` dice que la semana ISO va en **UTC** cuando AD-19 la resuelve *"a favor de la hora
local"*; y `epics.md:467` escribe las franjas de los logros como **05:00–07:00 / 21:00–23:00** cuando
el catálogo usa `between` **inclusiva** y el spine dice **05:00–07:59 / 21:00–23:59**.

**Enfoque:** reconciliar los siete puntos del action item más las divergencias del mismo tipo que se
han acumulado desde que se escribió (R1, tokens de estilo, B-2, B-3, y las decisiones del 2026-09-20).
Cada línea que cambie se apoya en una fuente verificable.

## Boundaries & Constraints

**Always:**
- **Cada cambio cita su fuente:** el código (`fichero:línea`), la spec que lo decidió, o la retro que
  lo registró. Una afirmación que no se pueda señalar no entra.
- **Se distingue "el documento miente" de "el documento calla".** Lo primero se corrige; lo segundo se
  añade solo donde la ausencia induce a error a quien escriba la siguiente historia.
- **Lo que está abierto se dice abierto.** Donde una decisión sigue pendiente, el documento pasa a
  decir que está pendiente y quién la tiene — **nunca** se decide aquí por conveniencia.
- **El tono y la estructura de cada documento se respetan:** los criterios de `epics.md` siguen siendo
  Given/When/Then con su `[fuente: …]`; las decisiones del spine mantienen su formato
  Binds/Prevents/Rule.
- **Nada de código.** Este chore no toca `Domain/`, `WalkTracker/`, `Scripts/` ni tests.

**Never:**
- Decidir el `WakeLockPort`: `epics.md:896` afirma que sobrevive como puerto del Epic 1 y es falso
  —el Epic 1 cerró sin él y el conjunto de AD-10 tiene 9 de 11—, pero **qué debe pasar con él es la
  pregunta abierta Q-3 de la retro del Epic 1**. Aquí solo se corrige la falsedad y se marca abierta.
- Hacer el trabajo de **B-9**: la atribución de Open-Meteo fuera de "Ajustes → Acerca de" y la
  `DegradationPolicy` que no existe tienen su propio action item con owner Dev. Aquí los documentos
  dejan de afirmar que están resueltos, y nada más.
- Reescribir historias que no estén desfasadas, ni "mejorar" redacción por gusto.
- Tocar `DEROGACIONES.md` más allá de lo que este chore nombra.

## I/O & Edge-Case Matrix

| # | Documento | Dice hoy | Es cierto | Fuente |
|---|---|---|---|---|
| 1 | `epics.md:274`, `:302` | los estimados vuelven a 0 **"para ese gap"** | el descarte es **global**: un solo contador, y se permite en `paused` | `Session.swift:205-218`; retro E1 S2 |
| 2 | `epics.md:292-294` | "Sesión recuperada" tras force-quit **o background** | **solo al relanzar**; volver de background no lo enciende | `SessionStore.swift:138-141`, `+Recovery:110`; spec-1-6 |
| 3 | `SPINE:176`, `epics.md:618`, `:620` | autosave **cada 10 s** | por **evento y por muestras**, nunca con temporizador; 10 s es espaciado mínimo | `SessionStore.swift:29-32`, `+StepCounting:90`; AD-21 |
| 4 | `SPINE:146`, `:150-151` | `SessionStatus` incluye **`idle`**; el flag es `reconciling` | tres estados; "antes de iniciar" es `session == nil`; el campo es **`isReconciling`** | `SessionStatus.swift:8-12`, `SessionStore.swift:135` |
| 5 | `SPINE:266` | los dos modos de conteo **"no se combinan"** | no se **suman**; sí conviven, y el store se queda con el máximo | `+Reconciliation:18-20`, `+StepCounting:76-79`; retro E1 R10 |
| 6 | `epics.md:598-620` | *(calla)* la 5.1 se describe como si el puerto no existiera | `StoragePort` ya cubre 2 de los 4 ficheros, con 6 métodos, y hay sustrato reutilizable | `StoragePort.swift:32-65`, `JSONFileStore.swift` |
| 7 | `SPINE`, `epics.md` | *(calla)* no hay criterio de qué va a `formulas.json` | **calibraciones medibles sí**; hechos del sistema, reglas de producto, límites derivados y cadencias de AD-21, no | `formulas.json`; retro E1 A5 y su A-5 |
| 8 | `SPINE:146` | un tramo de más de 7 días **"se degrada a estimación"** | con el tope de R1 **no se estima nada**; y cualquier respuesta no nula es dato | `+Reconciliation:60-95`, `GapEstimator.swift:102`; spec-r1 |
| 9 | `epics.md:266`, `:280` | se estima cuando el puerto devuelve `null` **o vacío** | solo **sin respuesta**; con las tres defensas y el tope | spec-r1 |
| 10 | `SPINE:217`, `epics.md:92`, `:100` | *(calla)* la excepción a UX-DR1 no está en el spine | **tres** colorsets propios con contraste medido | `DEROG:59-82`; `DesignTokens.swift`; spec-b2 |
| 11 | `DEROG:62`, `:78-80` | *"exactamente **dos** colores"*; el gate veta `.orange` | son **tres**; el gate veta la **familia cromática** desde B-2 | `ErrorMessage.colorset`; spec-b2 |
| 12 | `epics.md:385` | zancada *"> 0 y finito"* | tres reglas: rechazo duro, **tope derivado**, aviso de rango, y override opcional | `AppSettings.swift:95-130`; spec-2-3, spec-b3 |
| 13 | `epics.md:427` | semana ISO **"lunes 00:00 UTC"** | **hora local**: AD-19 resuelve la contradicción a favor de §9 | `SPINE:249-253` |
| 14 | `epics.md:467` | franjas **05:00–07:00 / 21:00–23:00** | `between` **inclusiva**: 05:00–**07:59** / 21:00–**23:59** | `achievements.json:13-14`; `SPINE:100-104` |
| 15 | `epics.md:1036`, `SPINE:386` | la 8.4 reemplaza el timeout **y el umbral de huérfana** por medidos | el timeout se midió (1 s); el umbral **no**: es valor decidido | `8-4-medicion-referencia.md:104-105, 189` |
| 16 | `SPINE:304`, `:391` | XCUITest **diferido** | **descartado** (2026-09-20): lógica de presentación a tipos probables | `decisiones-2026-09-20.md` D1 |
| 17 | `SPINE:175` | `settings.json` = *"zancada, meta, toggles"* | hoy: `recentQuoteIds` y `strideM` opcional; meta y toggles no existen | `AppSettings.swift:29-52` |
| 18 | `epics.md:21` | *"app **Capacitor** instalable"*, dominio *"intacto"* | falso desde AD-1; es la **primera frase** del documento | `SPINE:59`, `DEROG §1` |
| 19 | `epics.md:738`, `:752` | `CapacitorHealthKitAdapter`, `@capacitor/local-notifications` | AR-2 derogado → `HealthPort` y `NotificationPort` | `epics.md:67`, `DEROG §5` |
| 20 | `SPINE:400`, `epics.md:78` | toolchain *"Xcode 26.6 / Swift 6.3.3"* | la máquina tiene **Swift 6.2.4 / Xcode 26.3 (17C529)**, como dice `SPINE:311-312` | verificado con `swift --version` y `xcodebuild -version` |
| 21 | `SPINE:287`, `:196`, `:340` | la atribución está en Ajustes; existe una `DegradationPolicy` | las dos son falsas | **no se arreglan aquí**: se marcan abiertas con dueño **B-9** |
| 22 | `epics.md:896` | el wake lock *"sobrevive como `WakeLockPort` en Epic 1"* | falso: el Epic 1 cerró sin él, 9 de 11 puertos existen | **no se decide aquí**: se marca abierta, pregunta **Q-3** |

</frozen-after-approval>

## Code Map

- `_bmad-output/planning-artifacts/epics.md` — 12 de los 22 puntos. Los criterios son Given/When/Then
  con `[fuente: …]`; mantener esa forma. Los puntos 13 y 14 son los urgentes: van a las historias 3.1
  y 3.2, que son las siguientes en escribirse.
- `_bmad-output/planning-artifacts/architecture/.../ARCHITECTURE-SPINE.md` — 9 puntos. Las decisiones
  llevan Binds / Prevents / Rule; el punto 7 es una **fila nueva** en la tabla de Consistency
  Conventions, no una decisión nueva. Su frontmatter sigue en `updated: '2026-09-12'` y debe moverse.
- `.../DEROGACIONES.md` — solo el punto 11: el recuento de colores y la condición del gate.
- **Fuentes para contrastar**, ya verificadas al investigar: `Domain/Session/Session.swift`,
  `SessionStatus.swift`, `Domain/Ports/StoragePort.swift`, `AppSettings.swift`,
  `Domain/Metrics/MetricsCalculator.swift`, `WalkTracker/Application/SessionStore*.swift`,
  `WalkTracker/Resources/{formulas,achievements}.json`, `WalkTracker/UI/Style/DesignTokens.swift`,
  y las specs `spec-1-6`, `spec-2-3`, `spec-r1`, `spec-b2`, `spec-b3`.
- `_bmad-output/implementation-artifacts/epic-2-context.md` — **el precedente que justifica el chore**:
  se recompiló el 2026-09-19 y produjo una advertencia falsa por leer solo planificación.

## Tasks & Acceptance

**Execution:**
- [x] `epics.md` — los 12 puntos que le tocan, **empezando por 13 y 14**, que son los que viajan al
      Epic 3.
- [x] `ARCHITECTURE-SPINE.md` — sus 9 puntos, incluida la fila nueva de Constantes y el `updated:`.
- [x] `DEROGACIONES.md` — el recuento de colores y la condición del gate.
- [x] Los puntos 21 y 22 — **marcar abiertas**, con su dueño (`B-9`) y su pregunta (`Q-3`). No
      resolverlas.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` — lo que se descubra y no quepa aquí.
- [x] **Ampliación acordada con Paul (2026-09-20):** el paquete `specs/spec-walktracker-ios/`
      —`SPEC.md`, `capabilities.md`, `domain-model.md`, `achievements.md`— arrastraba el mismo
      desfase un nivel más arriba, y el compilador de contexto de épica también lo lee. Queda
      reconciliado y registrado en `deferred-work.md`. *(Esto extiende la frontera de "los tres
      documentos" de la Intent congelada; se hizo con permiso explícito, no por cuenta propia.)*
- [x] **Segunda pasada de revisión (2026-09-20)** — los 19 hallazgos de las dos revisiones sobre el
      diff, en el Review Triage Log de abajo. Incluye un **error de hecho propio** (punto 1) y cuatro
      restos en código que se **registran, no se arreglan**.

**Acceptance Criteria:**
- Dado cualquiera de los 22 puntos, cuando se lee la línea cambiada, entonces coincide con la fuente
  que la matriz nombra.
- Dado el contexto del Epic 3 compilado **después** de este chore, cuando se busca la semana ISO y las
  franjas de los logros, entonces dicen **hora local** y **05:00–07:59 / 21:00–23:59**. Esta es la
  comprobación que de verdad importa: es el mecanismo por el que lo desfasado viajaba.
- Dados los puntos 21 y 22, cuando se leen, entonces el documento **dice que están abiertos** y quién
  los tiene, en vez de afirmar algo falso o inventar una respuesta.
- Dado `git diff`, cuando se mira, entonces **no hay cambios fuera de los tres documentos** nombrados
  (más `deferred-work.md` si procede).

## Implementation Notes

**Lo que se tocó, y solo eso.** Cinco documentos: `epics.md`, `ARCHITECTURE-SPINE.md`,
`DEROGACIONES.md`, el paquete `specs/spec-walktracker-ios/` (ampliación acordada) y
`deferred-work.md`, más esta spec. **Cero ficheros de código**, que es lo que la Intent congelada
exige y lo que `git diff --stat` confirma.

**La forma de cada enmienda.** Una línea desfasada no se borra: se corrige y **se deja dicho qué
decía antes y por qué dejó de ser cierto**, con fecha y fuente. El motivo es el que este chore existe
para defender — quien lea el documento dentro de tres meses tiene que poder distinguir "esto siempre
fue así" de "esto se corrigió, y esto es lo que se creía". Por eso hay notas `⛔` / `⚠️` / `ℹ️` /
`📍` en vez de ediciones silenciosas.

**Duplicación: se eligió una fuente, no se sincronizaron tres.** La tabla de los tres colores propios
estaba en AD-13, en `DEROGACIONES.md §4` y en dos notas de `epics.md`, y ya había divergido (AD-13
había perdido los ratios en oscuro de `ErrorMessage`). §4 queda como **fuente única**, los otros dos
remiten. Es el mismo argumento que el diff usaba contra duplicar el `0,655` de la zancada, aplicado a
sí mismo.

**Lo abierto se dejó abierto, y ahora también en `deferred-work.md`.** El `WakeLockPort` (Q-3), la
`DegradationPolicy` y la atribución de Open-Meteo (B-9), la guarda inferior de `speed_walker` (3.2) y
el texto de `early_bird` (3.2) están marcados como pendientes **con dueño**, no resueltos. La lección
L2 dice que un traspaso que vive solo en planificación se pierde; por eso cada uno tiene además su
entrada en `deferred-work.md`, que es lo que la historia siguiente sí lee.

**Los restos en código se registraron, no se arreglaron** (puntos 11–14 de la segunda revisión): la
redacción ambigua de `MotionPort.swift:5-6`, los dos recuentos de "dos colores" en
`DesignTokens.swift` y `check-project-shape.sh:497`, y el texto de `early_bird` en
`achievements.json`. Los tres primeros son comentarios sin conducta; el cuarto **necesita una
decisión de Paul**, porque el catálogo está declarado contenido congelado y cambiar su texto choca
con esa restricción. Arreglar cualquiera de ellos habría roto el "nada de código" de la Intent.

## Spec Change Log

**1 · Corregido un error de hecho de la propia matriz congelada — fila 8 (2026-09-20).**

La fila 8 de la I/O & Edge-Case Matrix dice que, con el tope de R1, un tramo de más de 7 días **"no se
estima nada"**. **Es falso**, y la enmienda que escribí en AD-8 apoyándome en ella heredó el error,
llegando a afirmar además que *"el registro dice que cortó el tope"*. El texto que sustituía —*"se
degrada a estimación"*— estaba **más cerca de la verdad** que su reemplazo.

Lo que dice el código:
- la condición de los 7 días mira **el tramo**: `end.timeIntervalSince(start) <= queryableHistoryS`
  con `start = segmentStart` (`SessionStore+Reconciliation.swift:46`);
- la estimación se hace sobre **el gap**: `[backgroundedAt, end]` (`:74`);
- y el propio log lo dice al tomar ese camino (`:61`): *"Tramo de más de 7 días: no se consulta; **se
  estima solo si el gap cabe en el tope**"*.

Un tramo viejo con un gap corto **sí estima**. Y si `backgroundedAt` es `nil`, el `guard` de `:74`
sale **sin estimar y sin escribir nada** en el registro, así que "el registro dice que cortó el tope"
tampoco era universal. AD-8 y `epics.md` quedan reescritos con la distinción tramo/gap explícita.

**El bloque congelado no se edita** —la Intent es propiedad humana—, así que queda dicho aquí: **la
fila 8 de la matriz es incorrecta en su columna "Es cierto"**, y quien la use como fuente debe leer en
su lugar AD-8 tal como queda tras este chore. El error lo introdujo el autor de esta spec al
investigar, no el documento que se estaba corrigiendo.

**2 · Dos citas más de la matriz congelada están desplazadas.** La fila 5 cita
`+Reconciliation:18-20` y `+StepCounting:76-79`; en el árbol de hoy la regla R1 está en
`SessionStore+Reconciliation.swift:23-26`, la convivencia tramo/stream en `:19-21`, y el máximo de
`highestCumulativeSteps` en `SessionStore+StepCounting.swift:71-73`. **Las citas de los documentos
enmendados usan las líneas correctas**; la matriz congelada conserva las suyas y esta entrada explica
la diferencia.

**3 · "Las tres defensas" tenía dos significados.** La fila 9 de la matriz —y la primera redacción de
AD-8 y de `epics.md:267`— hablaban de *"las tres defensas **y** el tope"*, y `epics.md` incluía
además `active` y los 120 s en el recuento. **El código llama "tres defensas"** a: stream no
avanzado, cadencia tomada en el inicio del gap, y **el tope** `maxEstimableGapS`
(`SessionStore+Reconciliation.swift:29-31`; spec-r1, Boundaries). `active` es una **precondición** y
el mínimo de **120 s es anterior a R1** —`GapEstimator.swift:18-20` lo atribuye a `domain-model.md
§4`—. Unificado al vocabulario del código en los dos documentos, con la atribución corregida.

## Review Triage Log

**Pasada 1 (2026-09-20) — revisión del alcance.** Un hallazgo, aceptado: el paquete
`specs/spec-walktracker-ios/` arrastraba el mismo desfase que los tres documentos del chore y el
compilador de contexto de épica también lo lee, así que el criterio de cierre ("el contexto del Epic 3
sale con hora local y franjas inclusivas") no se cumplía sin tocarlo. Ampliación **acordada con
Paul**, no asumida. Registrada en `deferred-work.md`.

**Pasada 2 (2026-09-20) — dos revisiones sobre el diff de reconciliación: 19 hallazgos.**

| # | Hallazgo | Veredicto | Qué se hizo |
|---|---|---|---|
| 1 | AD-8 afirma algo falso del tramo > 7 días; el texto sustituido estaba más cerca de la verdad | **aceptado — error de hecho propio** | AD-8 y `epics.md` reescritos con la distinción **tramo** (`:46`) / **gap** (`:74`) y el log de `:61`; registrado arriba en el Change Log, señalando la fila 8 congelada como su origen |
| 2 | "Las tres defensas" significa cosas distintas en el código y en `epics.md` | aceptado | Unificado al vocabulario del código en AD-8 y `epics.md`; los 120 s dejan de atribuirse a R1 (`GapEstimator.swift:18-20` → `domain-model.md §4`) |
| 3 | Dos citas desplazadas | aceptado | `+StepCounting:76-79` → **`:71-73`**; `+Reconciliation:18-20` → **`:23-26`** para R1 y **`:19-21`** para la convivencia tramo/stream |
| 4 | La fila de Constantes contradice a otras dos líneas del mismo diff sobre `orphanSessionThresholdS` | aceptado | El criterio se mantiene —es **medible en principio**—; la fila ahora dice que salir de `provisional` tiene **dos caminos**, medir o decidir, y que lo que no puede perderse es cuál de los dos fijó el valor [`8-4-medicion-referencia.md:104-105`, `:189`] |
| 5 | El punto 15 se aplicó en 2 de 5 sitios | aceptado | Reconciliados `epics.md:287`, `:319` y `:901`: hoy `"provisional": []` y las cuatro constantes fijadas; cada sitio dice además **cómo** se fijó la suya |
| 6 | `DEROGACIONES.md:20` sigue con "ABSORBIDO → AD-10 (`WakeLockPort`)" | aceptado | Fila marcada `⚠️` y nota nueva: la absorción está **declarada, no cumplida**; remite a **Q-3** sin decidir nada |
| 7 | El frontmatter de `epics.md` declara como entrada el spine **derogado** de 2026-07-28 | aceptado | Apuntado a `architecture-walktracker-2026-09-12/` y añadido su companion vinculante `DEROGACIONES.md`. **Comprobadas las demás**: las cinco del paquete SPEC están vigentes y reconciliadas; `DESIGN.md`/`EXPERIENCE.md` de 2026-07-04 **no** están superados, sino parcialmente derogados por §4 — se dejan y se dice por qué |
| 8 | Ocho diferidos se apoyan en "XCUITest diferido" / "no hay arnés de vista" / "A-4 abierto", salidas que D1 eliminó | aceptado | Reconciliadas las cinco del Epic 1 (1.1, 1.2, 1.4, 1.5, 1.6) y las tres que citaban "A-4, abierto" (2.2, 2.3, B-2) más la del `minimumScaleFactor`. Cada una se parte en **lo que cierra el arnés de tipos probables** y **lo que solo se ve renderizando**, que pasa a **verificación manual** — el matiz que la propia D1 deja escrito. La de la 2.2 (el overlay tapando la sesión) es el caso literal de solape entre capas y va **entera** a manual |
| 9 | La tabla de colores está en tres documentos y ya diverge | aceptado | `DEROGACIONES.md §4` queda como **fuente única** y lo dice; AD-13 y las dos notas de `epics.md` remiten a ella y dejan de repetir los datos |
| 10 | `EstimatedSteps` en oscuro no tiene ratio medido en ninguno de los tres sitios | aceptado | Recuperados de `DesignTokensTests.swift` + colorset, **no inventados**: `#FF9F0A` da **10,22:1** sobre negro y **8,87:1** sobre el fondo del aviso (mismo color al 12 %). Reproducida la fórmula del arnés y verificada contra los seis ratios ya publicados, que salen idénticos |
| 11 | `MotionPort.swift:5-6` conserva la redacción ambigua que R10 nombraba en **dos** sitios | **registrado, no arreglado** | Entrada nueva en `deferred-work.md` con destino: la historia o el chore que toque `MotionPort`. "Nada de código" |
| 12 | La cabecera de `DesignTokens.swift` dice "los **dos** colorsets" y su `enum Colors` declara tres | **registrado, no arreglado** | Mismo diferido que el 13 |
| 13 | `check-project-shape.sh:497` describe la sección 12 como "los **dos** colores propios" | **registrado, no arreglado** | Diferido único para los dos recuentos, con la nota de que §4 es ahora la fuente única a la que deberían remitir |
| 14 | `achievements.json` describe `early_bird` como "antes de las 7:00" y la franja llega a **07:59** | **registrado como decisión pendiente** | Es el único desfase que ve un usuario, **y cambiarlo choca con el catálogo declarado contenido congelado**. Se registra diciendo exactamente eso, con las tres salidas posibles y sin elegir. Owner: **Paul**; destino: la 3.2 |
| 15 | El Structural Seed anotó solo `DegradationPolicy.swift` y dejó el resto sin anotar | aceptado | Encabezado que declara el árbol como **objetivo**, `⏳` en todo lo que aún no existe (`Adapters/Notifications/`, `Adapters/WakeLock/`, `HistoryStore`, `AchievementsStore`, `UI/Summary|History|Achievements|Components`, los engines de Goal y Achievement) y `⚠️` reservado al único caso distinto: lo que el documento y el código dan por existente sin estarlo |
| 16 | `DEROGACIONES.md` conserva `fecha: 2026-09-12` habiendo reescrito §4 | aceptado | Añadido `actualizado: 2026-09-20` y una nota que explica qué significa cada marca; queda alineado con el `updated:` del spine |
| 17 | El Overview dice que las dos divergencias que eran defectos "se suman" a las vigentes | aceptado | Reescrito: la tabla de AD-6 tiene **dos filas, no cuatro** — las dos que eran defectos **salieron**, y `DEROGACIONES.md §6` se cita literal |
| 18 | La spec está sin cerrar | aceptado | `status: done`, casillas de Execution, Implementation Notes, este log y el Change Log con la corrección del punto 1 |
| 19 | Verification prescribe recompilar el contexto del Epic 3, criterio que **contradecía el alcance del propio chore** | aceptado | Sección reescrita para decir la verdad de cómo se verificó; el razonamiento, abajo |

**Ninguno rechazado.** Los cuatro "registrados, no arreglados" (11–14) no son rechazos: son hallazgos
válidos cuyo arreglo la Intent congelada pone fuera de alcance, y quedan en `deferred-work.md` con
destino explícito, que es lo que la regla D4 exige.

## Design Notes

**Por qué esto no es cosmético.** El contexto de cada épica se compila de estos documentos, y ese
contexto es lo que lee quien escribe cada historia. Una frase desfasada en `epics.md` no se queda en
`epics.md`: entra en la spec, y de ahí en el código. El Epic 3 tiene cuatro historias esperando y dos
de sus afirmaciones ya son falsas.

**Por qué se marca lo abierto en vez de cerrarlo.** Tres puntos (21 y 22) son decisiones pendientes,
no redacción desfasada. Resolverlas aquí sería tomar una decisión por la puerta de atrás, que es
exactamente lo que la retro del Epic 2 señaló cuando una "Decisión de Paul" congelada se resolvió en
contra sin registrarlo. Un documento que dice "esto está abierto y lo tiene B-9" es correcto; uno que
inventa la respuesta, no.

**El punto 20 se resolvió midiendo, no eligiendo:** el spine se contradice a sí mismo sobre el
toolchain, y la máquina responde `Swift 6.2.4` y `Xcode 26.3 (17C529)` — que es lo que ya dice
`SPINE:311-312`. La línea 400 es la que está mal.

## Verification

**Commands:**
- `git diff --stat` — esperado: `epics.md`, `ARCHITECTURE-SPINE.md`, `DEROGACIONES.md`, el paquete
  `specs/spec-walktracker-ios/` (ampliación acordada), `deferred-work.md` y esta spec. **Cero
  ficheros de código.**
- `bash Scripts/check-project-shape.sh` y `bash Scripts/verify-domain.sh` — verdes y sin cambios: este
  chore no toca código, y que sigan verdes lo confirma.

**Manual checks:** releer cada línea cambiada contra la fuente que la nombra —el fichero de código y
su línea, la spec que lo decidió, o la retro que lo registró—. Es trabajo de lectura, no de ejecución,
y así se declara. La segunda pasada de revisión lo demostró: encontró **una cita corregida con un
número de línea desplazado** y **una afirmación que el propio código desmiente en su log**, y las dos
aparecieron abriendo el fichero, no ejecutando nada.

**Por qué ya no se recompila el contexto del Epic 3, que era el criterio de cierre original.**

Dos razones, y las dos salieron durante la ejecución:

1. **Contradecía el alcance de este mismo chore.** `epic-3-context.md` no existe, así que "recompilar"
   habría significado **crearlo** — un fichero fuera de los tres documentos que la Intent congelada
   acota ("no hay cambios fuera de los tres documentos nombrados"), y además un artefacto de
   implementación que pertenece a quien arranque el Epic 3, no a un chore de reconciliación. El
   criterio pedía violar la restricción que la misma spec declara.
2. **La premisa cambió.** El criterio existía porque el compilador de contexto **solo lee
   planificación**, y eso era lo que hacía viajar lo desfasado. Al ampliar el chore al paquete SPEC
   —lo que el compilador lee además de `epics.md` y el spine—, **ya no queda un nivel sin
   reconciliar** del que pudiera salir la advertencia falsa. Recompilar habría comprobado una fuente
   que acaba de corregirse línea a línea contra el código.

**Lo que se verificó en su lugar, y es lo que de verdad importaba.** Las dos afirmaciones que
viajaban al Epic 3 se comprobaron **en todos los sitios de los que el contexto se compila**, no en su
salida:

- **Semana ISO en hora local** — `epics.md:457` (era "lunes 00:00 UTC"), `ARCHITECTURE-SPINE.md`
  AD-19 y la nota fechada de `domain-model.md §5`, que es la que `AD-19` cita como sitio de la
  contradicción. Fuente: `SPINE:249-253`, `AppCalendar` con `timeZone` del dispositivo.
- **Franjas inclusivas 05:00–07:59 / 21:00–23:59** — `epics.md:497`, `achievements.md#27` y el
  esquema de AD-5. Fuente: `WalkTracker/Resources/achievements.json:13-14`, `between` inclusiva en
  los dos extremos. *(Y de ahí salió el punto 14: el propio catálogo describe `early_bird` como
  "antes de las 7:00". Registrado como decisión pendiente, no arreglado.)*

Quien arranque el Epic 3 compilará su contexto por primera vez y será entonces cuando esa salida se
lea — con las fuentes ya reconciliadas, que es lo que este chore podía garantizar.
