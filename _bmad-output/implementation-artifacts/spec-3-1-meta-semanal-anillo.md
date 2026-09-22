---
title: '3.1 — Meta semanal configurable con anillo de progreso'
type: 'feature'
created: '2026-09-21'
status: 'in-review'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '8492df94ed0c1b7309639be6363c73a3a40d3f9e'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-3-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-5-1-persistencia-sesiones.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-2-3-recalibracion-zancada.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Paul no puede fijar una meta semanal ni ver cómo va hacia ella. La 5.1 dejó por
primera vez caminatas persistidas (`sessions.json`, `HistoryStore.records`) y nadie las suma
todavía: `HistoryStore` solo sabe responder `contains(startedAt:)` — **no existe ninguna consulta
por rango de fechas**, ni agregados, ni totales. `Domain/Engines/` está **vacío**.

**Approach:** Tres piezas y su cableado. (1) Un campo `weeklyGoalKm` en `AppSettings`, con su
intención en `SettingsStore+Goal.swift`, siguiendo el molde exacto que estrenó la 2.3 con la
zancada. (2) Un cálculo puro en `Domain/` que suma la semana ISO en **hora local** y que ejecuta
los **15 vectores de equivalencia de `weeklyProgress` que llevan escritos desde la 8.7 sin
runtime contra el que correr**. (3) El anillo en Inicio: la **primera** de las tres piezas
dibujadas a mano que AD-13 autoriza — hoy no existe ninguna en el árbol.

## Boundaries & Constraints

**Always:**
- El calendario es **uno solo y ya existe**: `ClockPort.calendar` (`identifier = .iso8601`,
  `firstWeekday = 2`, `timeZone = .current`). **Esta historia es su primer consumidor**: hoy
  nadie lo lee. `Calendar.current` está prohibido y el gate lo impide en `Domain/`.
- La suma es **en metros**, no en kilómetros. Sumar km fraccionarios acumula error y una meta
  exacta repartida en varias sesiones quedaba en 9,999999… km. Está escrito en el JS de
  referencia y hay vector para ello.
- `isComplete` se decide sobre los **metros sin redondear**: 9.995 m redondean a 10,00 km y **no**
  cumplen una meta de 10 km. Decisión de Paul en la 8.7, con su vector.
- Ventana semiabierta `[lunes 00:00 local, lunes+7 00:00 local)`.
- Una caminata **recuperada u huérfana sí suma en el anillo**. Lo dice la documentación de
  `SessionRecord.countsForAchievements` explícitamente: `countsForAchievements` es `false` para
  una huérfana, y aun así **suma en el anillo semanal**. Son dos preguntas distintas.
- El anillo lleva **etiqueta de accesibilidad explícita**: una forma dibujada no la trae. Y
  respeta Reduce Motion, con el patrón que ya usa `SessionView.swift:70`.
- Todo número visual nuevo (grosor de trazo, diámetro, color de la pista) **entra en
  `DesignTokens.swift`**. La sección 12 del gate rechaza un número cableado en una vista, y hoy
  no existe ninguno de esos tokens.
- La sección "Acerca de" de Ajustes **se queda la última y entera**: carga la obligación de
  licencia CC BY 4.0 de AD-24. `AboutSection.items` es una constante escrita a mano a propósito.

**Never:**
- No se sube `schemaVersion` de `settings.json`. El campo entra **opcional** con valor por
  omisión, que es el patrón documentado del adapter: subirlo haría que un build anterior leyera
  "un esquema del futuro" y perdiera la ventana de frases y la zancada.
- No se toca el catálogo de logros. `weekly_goal` es la entrada #5 congelada por AD-5
  (`metric: weeklyGoalMet`, `threshold: 1`, `comparison: eq`) y **no se declara en Swift**.
- No se implementa el `AchievementEngine` general: es de la 3.2. Esta historia solo toca
  `weekly_goal`, que el spine declara **excepción evaluada por `GoalEngine`**, no por el cierre
  de sesión.
- No se porta `checkStreak` (8 vectores). Su destino es la 3.2.
- No se toca `SessionStore`, ni el flujo de sesión, ni el resumen. La 3.5 es dueña del resumen.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Salida esperada | Error |
|---|---|---|---|
| Sin meta configurada | `weeklyGoalKm == nil` | el anillo usa **10 km** | N/A |
| Meta válida | "15" en el campo | se guarda; el anillo pasa a 15 km | N/A |
| Meta ≤ 0 o no numérica | "0", "-3", "abc" | se rechaza **con mensaje**, no se escribe | rechazo en frontera |
| Meta por debajo del mínimo | "0,5" (enmienda del 2026-09-21, ver Spec Change Log) | se rechaza **diciendo el mínimo**; 1 km exacto se acepta | rechazo en frontera |
| Meta no finita | `inf`, `NaN` | se rechaza | rechazo en frontera |
| Sin sesiones | historial vacío | 0 km, 0 %, no cumple | N/A |
| Sesiones de la semana | 3 sesiones, 12 km, meta 10 | 12 km, 100 % (capado), cumple | N/A |
| Semana anterior | sesión del lunes pasado | **no** suma | N/A |
| Frontera de semana | domingo 23:59:59 local vs lunes 00:00 local | el domingo entra en la semana vieja; el lunes abre la nueva | N/A |
| Semana ISO que cruza el año | sesiones a caballo de enero | suman en su semana ISO | N/A |
| Meta exacta | 10.000 m en 6 sesiones, meta 10 | cumple | N/A |
| Casi la meta | 9.995 m, meta 10 | muestra 10,00 km y **NO** cumple | N/A |
| Meta ≤ 0 al calcular | `goalKm` 0 por un fichero manipulado | porcentaje **0**, sin división por cero | tolerado |
| Huérfana en la semana | registro con `recovered == true` | **sí** suma en el anillo | N/A |
| Historial ilegible | `HistoryStore.readOutcome == .unreadable` | el anillo no miente: no pinta 0 % como si fuera un dato | se conserva el aviso de la 5.1 |


## Decisiones de Paul (2026-09-21)

**D1 — H-08 cerrado: el logro y la celebración son dos cosas distintas, y solo celebra el anillo.**
`weekly_goal` **sigue siendo un desbloqueo de por vida e irrevocable** — AD-5 congela el catálogo
y el spine ya lo declara excepción evaluada por `GoalEngine`, así que no hay alternativa. La
celebración semanal es **otro evento, con estado propio**: `lastGoalCelebratedWeek` en
`settings.json`, dueño `SettingsStore`, campo **opcional y sin subir `schemaVersion`**. Y la mitad
que resuelve el solape que la revisión describía: **`weekly_goal` no produce celebración propia**
— quien celebra es siempre el anillo, una vez por semana. Así la primera semana no celebra dos
veces. **Esta regla la heredan la 3.2 y la 3.4**, y por eso no se queda solo en esta spec: se
registra como **AD-25** en `ARCHITECTURE-SPINE.md`, que es lo que la revisión pedía al decir
*"o lo contrario. Pero escrito"*.

**D2 — Al cumplir la meta, en esta historia solo se ve el anillo al 100 %.** La 3.1 deja el estado
y la señal listos; la celebración visible (toast, háptica, sonido) llega con la 3.4 enchufándose a
esa señal. No se entrega una celebración provisional: en este proyecto lo provisional se queda y
después nadie sabe si era el diseño final.

</frozen-after-approval>

## Code Map

**Campos compartidos de `SessionStore` que toca este cambio** (lección L3, regla (b) del A-7):
**ninguno**. `HomeView` ya recibe `store: SessionStore` y esta historia **no lee ni escribe ningún
campo suyo**: el anillo se alimenta de `HistoryStore.records` y de `SettingsStore`. Lo único que
comparte con la sesión es la pantalla. Si la implementación acaba necesitando un campo de
`SessionStore`, eso es señal de que el diseño se torció, no un detalle a resolver sobre la marcha.

**El molde de campo nuevo — copiar, no inventar**
- `Domain/Ports/AppSettings.swift` — hoy dos campos: `recentQuoteIds: [Int]` (L36) y
  `strideM: Double?` (L51). Puerta que **rechaza** en la frontera: `setStrideM(_:) throws` (L71-74).
  Puerta **tolerante** para leer del fichero: `tolerated(_:)` (L179-187). Parser de texto con coma
  y punto: `strideMeters(fromText:)` (L149-166). El `init` (L53-56) normaliza: **no existe un
  `AppSettings` inválido**. La meta necesita sus tres equivalentes.
- `WalkTracker/Adapters/Persistence/SettingsFileAdapter.swift` — `supportedSchemaVersion = 1`
  (L47), `readableSchemaVersions = 1...1` (L49), `private struct File: Codable` (L102-131) con
  `strideM: Double?` opcional, `init(from:)` a mano (L125-130) con
  `try? container.decodeIfPresent` para tolerar un tipo erróneo sin tirar el fichero. El doc
  L11-19 explica cómo entra un campo nuevo. **Ojo:** ya existe un test que usa el nombre
  `weeklyGoalKm` — `WalkTrackerTests/Adapters/SettingsFileAdapterTests.swift:91-100`.
- `WalkTracker/Application/SettingsStore+Stride.swift` — **el molde entero**: `enum StrideOutcome`
  (L25-55), `enum StrideRejection` (L60-70), `saveStride(fromText:)` (L84), `clearStride()` (L127),
  `strideEditingDidChange()` (L138), `strideScreenDidDisappear()` (L149). La meta repite esta
  forma en `SettingsStore+Goal.swift`.
- `WalkTracker/Application/SettingsStore.swift` — `save(applying:) -> Bool` (L193-205): **relee
  antes de bloquear**, el `change` debe ser idempotente. `strideOutcome` está almacenado en el
  store (L56) porque una extensión no puede almacenar; la meta necesitará lo mismo.

**La pantalla de Ajustes**
- `WalkTracker/UI/Settings/SettingsView.swift` — `body` L58-101: sección "Zancada" (L61-74) y
  `aboutSection` (L76) **último**. La sección de meta entra **entre las dos**.
- `AboutSection.swift` — `items` es constante escrita a mano (L67) a propósito; si pasa a ser
  función del estado, `AboutSectionTests` **deja de compilar**. No tocar.

**El historial, que aún no sabe sumar**
- `WalkTracker/Application/HistoryStore.swift` — `records: [SessionRecord]` (L39, orden del
  fichero, más antigua primero), `readOutcome` (L42), `showsUnreadableNotice` (L52),
  `contains(startedAt:)` (L102-104). **Eso es todo**: no hay consulta por rango ni agregados.
- `Domain/Ports/SessionRecord.swift` — los campos que importan aquí: `startedAt` (L36) y
  `distanceM` (L50), que son literalmente lo que consumen los vectores. `countsForAchievements`
  (L134) con su doc L129-133: una huérfana **no** cuenta para logros y **sí** suma en el anillo.

**El calendario, ya resuelto y sin estrenar**
- `Domain/Ports/ClockPort.swift:6-12` — `var calendar: Calendar` (L11).
  `WalkTracker/Adapters/Clock/SystemClock.swift:15-20` lo construye ISO-8601 con `firstWeekday = 2`
  y `TimeZone.current`; `WalkTrackerTests/Support/ClockStub.swift:19` igual. **Nadie lo consume**:
  `grep -rn "\.calendar"` no devuelve un solo uso. Este es el `AppCalendar` único de AD-19 — el
  tipo con ese nombre no existe y no hace falta inventarlo.

**Los 15 vectores que llevan esperando desde la 8.7**
- `WalkTrackerTests/Vectors/weeklyProgress.json` — 15 vectores, `reference: motivation.js:195`.
  Entrada `{ sessions: [{startedAt, distanceM}], weeklyGoalKm, now }`, salida
  `{ completedKm, goalKm, percentage, isComplete }`. **Tres son divergentes declarados**
  (`divergence: "localTime"`) y traen `expected` (hora local, el nuestro) **y** `expectedJs` (UTC,
  el de la v3): `domingo-noche-local-no-entra`, `ahora-domingo-noche-local`, `ahora-lunes-00-00-local`.
- `WalkTrackerTests/Vectors/VectorHarness.swift:178` los lista en `knownFunctions` y
  `swiftDomain` (L188-196) **no los registra**, así que hoy salen `.pending`. Registrarlos es
  parte de esta historia: `verify-domain.sh` exige ver la línea de pendientes y la va a cambiar.
- `motivation.js:195-232` (`getWeeklyProgress`) — el algoritmo de referencia. Usa semana ISO en
  **UTC**, y ésa es exactamente la divergencia declarada: nosotros la calculamos en local.

**El anillo, que no tiene precedente**
- **Ninguna de las tres piezas dibujadas de AD-13 existe.** Cero `Canvas`, `Path(`, `: Shape`,
  `trim(from:`, `.stroke` en todo `WalkTracker/`. Esta historia escribe la primera, y con ella el
  patrón que copiarán el gráfico de tendencia y la insignia.
- `WalkTracker/UI/Home/HomeView.swift` — `home` (L51-87): aviso de historial ilegible (L53-55),
  `Spacer`, el `Image(systemName: "figure.walk")` de L57-61 —**el hueco dominante actual**—, el CTA
  (L62-71), `Spacer`, diagnósticos en DEBUG.
- `WalkTracker/UI/Style/DesignTokens.swift` — su cabecera **ya nombra "anillo de meta (3.1)"** como
  destinatario (L7-8). Hoy tiene `Spacing` (4/8/12/16/24), `LayoutMetrics` (margin 16,
  touchTargetMin 44, heroSize 88), `Radius.card = 20`, `Surface`, `Typography`, `Colors`
  (`accent`/`estimated`/`error`). **No tiene** grosor de trazo, diámetro, color de pista ni
  duración de animación.
- `WalkTracker/UI/Session/SessionView.swift:70` — único precedente de Reduce Motion:
  `@Environment(\.accessibilityReduceMotion)`, aplicado en L148-206 con el patrón
  `reduceMotion ? .easeInOut(duration: 0.2) : .default`.

**Los logros, listos desde la 5.1**
- `WalkTracker/Application/AchievementsStore.swift` — `unlocks` (L37), `readOutcome` (L40),
  `unlock(forKey:)` (L81), `save(applying:)` (L95). La maquinaria para escribir el desbloqueo de
  `weekly_goal` **ya existe**; el motor general es de la 3.2.
- `Domain/Achievements/AchievementMetric.swift:24` — `case weeklyGoalMet`, con doc que dice que la
  evalúa `GoalEngine`.
- `Domain/Engines/` — **vacío**.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Ports/AppSettings.swift` -- campo `weeklyGoalKm: Double?` con su puerta que rechaza,
  su puerta tolerante y su parser de texto, a imagen de la zancada -- no puede existir un
  `AppSettings` con meta inválida.
- [x] `Domain/Engines/WeeklyProgress.swift` -- cálculo puro `(records, goalKm, now, calendar) ->
  (completedKm, goalKm, percentage, isComplete)`, suma en metros, ventana semiabierta local,
  `isComplete` sobre metros sin redondear -- es lo que ejecutan los vectores.
- [x] `WalkTrackerTests/Vectors/VectorHarness.swift` -- registrar `weeklyProgress` en
  `swiftDomain` -- sin esto los 15 vectores siguen `.pending` y el gate lo dice.
- [x] `WalkTracker/Adapters/Persistence/SettingsFileAdapter.swift` -- clave opcional nueva en
  `File`, `schemaVersion` **se queda en 1** -- compatible en las dos direcciones.
- [x] `WalkTracker/Application/SettingsStore+Goal.swift` -- la intención, con su `GoalOutcome` y su
  `GoalRejection` -- el molde de la 2.3.
- [x] `WalkTracker/UI/Settings/SettingsView.swift` -- sección "Meta semanal" **entre** Zancada y
  Acerca de -- Acerca de sigue siendo la última y entera.
- [x] `WalkTracker/UI/Style/DesignTokens.swift` -- tokens del anillo (grosor, diámetro relativo,
  color de pista) -- la sección 12 del gate rechaza cablearlos en la vista.
- [x] `WalkTracker/UI/Home/GoalRingView.swift` -- el anillo, con etiqueta de accesibilidad
  explícita y Reduce Motion -- primera pieza dibujada de AD-13.
- [x] `WalkTracker/UI/Home/HomeView.swift` -- el anillo sustituye al `figure.walk` como pieza
  dominante -- el CTA no se mueve de sitio.
- [x] `WalkTracker/Application/SettingsStore+Goal.swift` -- `lastGoalCelebratedWeek` y el
  desbloqueo de `weekly_goal` vía `AchievementsStore` (D1) -- el logro es de por vida; la
  celebración es semanal y **solo la dispara el anillo**.
- [x] `_bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-09-12/ARCHITECTURE-SPINE.md`
  -- **AD-25** registrando el cierre de H-08 -- la revisión pidió "pero escrito", y una decisión
  que heredan la 3.2 y la 3.4 no puede vivir solo en la spec de la 3.1.

**Acceptance Criteria:**
- Dado `bash Scripts/verify-domain.sh`, entonces la línea de pendientes de AD-6 **ya no nombra
  `weeklyProgress (15)`**, y los 15 vectores pasan — los 3 divergentes contra su `expected` local,
  no contra `expectedJs`.
- Dado un divergente ejecutado contra `expectedJs`, entonces **falla**: la divergencia es
  declarada, no una tolerancia.
- Dado `bash Scripts/check-project-shape.sh`, entonces verde: ningún número visual del anillo
  cableado fuera de `DesignTokens.swift`.
- Dado VoiceOver sobre el anillo, entonces anuncia meta, completado y porcentaje — no una forma
  muda.
- Dado `bash Scripts/check-spec-shape.sh`, entonces verde.

## Implementation Notes

**Dos tipos en `Domain/Engines/WeeklyProgress.swift`, y por qué no uno.** `WeeklyProgress` es el
valor —`completedKm`, `goalKm`, `percentage`, `isComplete`, exactamente las cuatro claves que
fijan los vectores— y `GoalEngine` es el motor que lo produce. El fichero se llama como el valor
porque es lo que viaja; el motor se llama como lo llaman AD-17, AD-5 y el spine. `Domain/Engines/`
deja de estar vacío con uno de los dos motores que el Epic 3 estrena; el otro es de la 3.2.

**La divergencia de hora local, ejecutada de verdad por primera vez.** `ClockPort.calendar`
existía desde la reconciliación y **nadie lo leía**: esta historia es su primer consumidor. El
motor recibe el calendario como parámetro (AD-3: ni reloj ni `Calendar.current` en `Domain/`) y la
ventana sale de `calendar.dateInterval(of: .weekOfYear, for:)`, no de sumar 7 × 24 h — en la
semana del cambio de hora eso dejaría el lunes siguiente a las 23:00 del domingo, y hay test.

**Lo que los vectores dejaron abierto a propósito, y qué salió.** El vector
`nueve-995-km-no-cumplen-10` solo fija `isComplete`, con la nota *"completedKm y percentage
dependen de cómo redondee cada runtime"*. Resuelto: **9 995 m se muestran como `9,99`, no como
`10,00`**. La matriz congelada dice "muestra 10,00 km y NO cumple", y eso es lo que da la
aritmética decimal, pero no lo que da ningún runtime: `9995 / 1000` en coma flotante binaria es
`9,99499999…`, así que el `toFixed(2)` de la referencia da `9,99` y este dominio da lo mismo. **Se
eligió ser fiel a la referencia**, y además es lo que quiere la historia: el anillo y la cifra que
lleva dentro dicen la misma verdad, en vez de enseñar "10,00" junto a un arco sin cerrar — que es
justo la confusión que la fila de la matriz describe. La mitad **bold** de esa fila (NO cumple) se
cumple exactamente. Como con 9 995 m el mutante "decidir sobre los km redondeados" **no se ve**
—su cifra redondeada también se queda corta—, hay un caso propio con 9 999,6 m, que sí redondea a
`10,00` y sigue sin cumplir: ése es el que mata al mutante.

**Una meta que no es meta no se cumple, y ahí sí se diverge de la referencia.** Con `goalKm ≤ 0`
—solo alcanzable con un `settings.json` manipulado, porque la frontera lo rechaza y la puerta
tolerante lo lee como "sin configurar"— el porcentaje es `0` (como la referencia, que ya lo
previó) y `isComplete` es **`false`**, donde `motivation.js` diría `true` (`0 >= 0`). No hay
vector que lo fije, así que no es una divergencia declarada de AD-6: es la segunda puerta de un
caso que la primera ya cierra, y celebrar por no tener meta era el peor de los dos errores.

**El molde de la 2.3, copiado entero y con dos diferencias.** `AppSettings.weeklyGoalKm` con sus
dos puertas —`setWeeklyGoalKm(_:)` rechaza, el `init` tolera—, `SettingsStore+Goal.swift` con
`GoalOutcome` / `GoalRejection`, botón Guardar explícito, vuelta atrás aparte ("Usar los 10 km por
defecto") y mensaje que se apaga al escribir y al salir. El parser **no se duplicó**:
`strideMeters(fromText:)` y `weeklyGoalKm(fromText:)` delegan en el mismo `decimalNumber(fromText:)`
—la regla de lectura es la misma y lo que cambia es la validación—. Las dos diferencias: la meta **no tiene rango de aviso**
—3 km y 80 km son igual de suyos, así que `GoalOutcome` tiene cuatro casos y no cinco— y sí tiene
**suelo duro**, `AppSettings.minimumWeeklyGoalKm = 1` (decisión de Paul, ver Spec Change Log), que
es la única regla de producto de esta historia que bloquea en vez de avisar: una zancada mala se
corrige guardando otra, y un `weekly_goal` desbloqueado con una meta de 10 metros no se corrige con
nada. El default de 10 km vive en `AppSettings.defaultWeeklyGoalKm` y **no** en
`formulas.json`, que es para calibraciones medibles.

**`schemaVersion` sigue en 1 con dos campos más, y hay test que lo ata.** `weeklyGoalKm` y
`lastGoalCelebratedWeek` entran opcionales y con decodificación tolerante (`try? decodeIfPresent`),
como la zancada: un `weeklyGoalKm: "abc"` se lee como "sin fijar" y **no** cuesta ni la zancada ni
la ventana de frases. Subirlo a 2 haría que un build anterior leyera los ajustes como del futuro.

**AD-25, que es la decisión D1 escrita donde se hereda.** El desbloqueo de `weekly_goal` vive en
`AchievementsStore+Goal.swift` (`unlockWeeklyGoal(at:)`, idempotente, de por vida) y la
celebración semanal en `SettingsStore+Goal.swift` (`goalRingDidUpdate()`, que devuelve `true` **la
primera vez de cada semana**). El catálogo no se toca: lo único que se escribe en Swift es la
**clave** `weekly_goal`, con un test que la ata al catálogo del bundle por su métrica
(`weeklyGoalMet`), su comparación (`eq`) y su umbral (`1`) — si la entrada #5 cambiara, la suite lo
dice. La regla queda en `ARCHITECTURE-SPINE.md` como **AD-25**, porque la heredan la 3.2 y la 3.4.

**`SettingsStore` gana tres colaboradores, y el primer intento estaba mal.** Recibe `HistoryStore`,
`AchievementsStore` y `ClockPort`: la meta semanal no se responde solo con `settings.json`, y
`lastGoalCelebratedWeek` es de este fichero, así que la decisión vive con su estado. Nacieron con
**valor por omisión** construido sobre el mismo `storage` —para no cablear medio producto en los
treinta tests que no miran la meta— y eso creaba un **segundo lector** de `sessions.json`: leer un
historial ilegible lo **aparta**, así que el segundo dueño encontraba "no hay fichero" y el aviso
de la 5.1 desaparecía. Lo cazó `HistoryStorePersistenceTests` en la primera pasada de la suite. Los
tres son ahora **obligatorios** —un fichero, un dueño, **y una sola instancia**— y los tests que no
miran la meta usan `SettingsStoreFixture`, que lo dice en su doc. El nombre `SettingsStore` para
quien lleva la lógica del anillo se ha quedado corto, y eso está en `deferred-work.md` con destino
la 3.4.

**El anillo: la primera pieza dibujada de AD-13, con sus tres condiciones.** `GoalRingView` son dos
`Circle().stroke(...)` —pista y arco con `trim(from:to:)`— y no había en todo el árbol ni un
`Canvas`, ni un `Path`, ni un `trim`. Las tres condiciones que AD-13 le pone, resueltas: (1)
**etiqueta explícita**, porque una forma dibujada no la trae — es un solo elemento con
`accessibilityLabel` ("Meta semanal") y `accessibilityValue` con la magnitud entera; (2) **nada de
diámetros fijos** — `aspectRatio(1, contentMode: .fit)` con `GoalRing.maxDiameter` como **tope**, y
el grosor en `@ScaledMetric(relativeTo: .title)` para que engorde con la cifra que lleva dentro; (3)
**Reduce Motion**, con el patrón de `SessionView`: el arco aparece **sin animación**, no con una más
corta. Los **cinco** números nuevos están en `GoalRing`, en `DesignTokens.swift`. **No hay ningún color
nuevo**: el arco es `Colors.accent` y la pista es `.primary` a `GoalRing.trackOpacity` — un rol del
sistema, no un cuarto colorset, que la excepción de UX-DR1 son exactamente tres.

**El arco no sale del porcentaje, y eso no es un detalle.** `percentage` se redondea a un decimal
sobre unos kilómetros ya redondeados a dos —lo fija el vector—, así que con 9 999,6 m vale `100`:
un arco derivado de él se pintaría **entero mientras `isComplete` es `false`**, es decir, lleno y
sin celebrar. `WeeklyProgress.fraction` divide la magnitud cruda, de modo que **el anillo se cierra
si y solo si la meta está cumplida**. Ningún vector fija `fraction`: es una magnitud de esta app,
no de la v3. Y la **meta** llega al anillo por su propio parámetro, no dentro del progreso: con el
historial ilegible el progreso es `nil` pero la meta se sabe igual, porque vive en otro fichero.

**Sin dato el anillo no pinta un cero.** Con `sessions.json` ilegible `weeklyProgress` es `nil`, la
cifra es un guion y VoiceOver dice *"Sin progreso: no se pudo leer tu historial"*. Un 0 % afirmaría
que Paul no ha caminado esta semana, que es exactamente lo que nadie sabe (AD-22). El aviso de la
5.1 sigue donde estaba, encima.

**En Ajustes, "Acerca de" sigue siendo la última y entera.** La sección "Meta semanal" se **inserta**
entre Zancada y Acerca de; `AboutSection.items` no se tocó. La fila del mensaje en línea se compartió
entre los dos ajustes (`outcomeMessage(_:symbol:style:)`) en vez de duplicarla, y los seis mensajes de
la meta son distintos entre sí **y distintos de los cinco de la zancada**, con test que lo afirma: las
dos secciones están en la misma pantalla y dos textos iguales no se distinguirían al leerlos.

**Una cadena compartida, dicha en voz alta.** `"km"` ya existía en el String Catalog con el comentario
de la pantalla de sesión, y la sección de meta la reusa. El catálogo guarda **un** comentario por
clave, así que los dos sitios llevan ahora el **mismo** `comment:`, que nombra los dos usos — es el
hallazgo 14 de la 2.3 (deriva entre el comentario del código y el del catálogo) aplicado al caso en
que la clave tiene dos dueños.

## Spec Change Log

**2026-09-21 · Decisión nueva de Paul: la meta semanal tiene un mínimo de 1 km.** Enmienda un
criterio del bloque congelado, así que se registra aquí y **el bloque no se edita**; la única
edición en él es la fila nueva de la matriz, que es donde la matriz vive.

*Qué decía.* "Meta ≤ 0 o no numérica se rechaza"; es decir, la regla era **"> 0 y finita"**.

*Qué faltaba, y por qué no es cosmético.* Con esa regla, `0,01` km es una meta válida: caminar
**diez metros** la cumple, y cumplirla **desbloquea `weekly_goal`**, que es un logro **de por vida
e irrevocable** (AD-5 congela el catálogo; AD-17 y AD-25 lo hacen irrevocable). Una meta de broma
—o un dedazo con la coma— ensucia el grid de logros de la 3.3 **para siempre**, y no hay forma de
deshacerlo: ni borrando la caminata, ni bajando la meta, ni reinstalando salvo que se pierda todo.

*Qué se decide.* `AppSettings.minimumWeeklyGoalKm = 1`, **inclusivo**, y `validateWeeklyGoalKm`
rechaza por debajo. Es la **única** regla de producto de esta historia que bloquea en vez de
avisar, y la asimetría con la zancada es deliberada: el rango humano de la zancada avisa porque
una zancada mala se corrige guardando otra, y esto no se corrige guardando nada. Por arriba **no**
hay tope: 80 km son suyos y no desbloquean nada que no se haya caminado.

*Dónde vive.* `AppSettings.minimumWeeklyGoalKm` y `isTooSmallGoalKm(_:)` en el dominio; el caso
`GoalRejection.belowMinimum(Double)` en el store —caso propio y no `.notPositive`, porque el
mensaje tiene que **decir cuál es el mínimo**: "0,5" no es "menor o igual que cero"—; su texto en
el String Catalog, con el mínimo interpolado desde donde se decide; y el pie de la sección lo dice
antes de que Paul se equivoque.

*Qué NO cambia.* La puerta **tolerante** sigue tolerando: un `weeklyGoalKm: 0.01` en disco
—guardado por un build anterior al mínimo— se lee como "sin configurar" y el anillo usa los 10 km,
sin apartar el fichero ni costar la zancada. Es la misma asimetría de B-3 con la zancada.

*Fila nueva en la matriz.* "Meta por debajo del mínimo | "0,5" | se rechaza **diciendo el
mínimo**; 1 km exacto se acepta | rechazo en frontera".

**2026-09-21 · La fila "Casi la meta" de la matriz congelada dice una cifra que ningún runtime
produce. El bloque congelado NO se edita; se registra aquí.**

*Qué dice la matriz.* `| Casi la meta | 9.995 m, meta 10 | muestra 10,00 km y **NO** cumple |`.

*Qué pasa de verdad.* La mitad en negrita —**no cumple**— es exacta y tiene su vector y su
mutación. La otra mitad no: `9995 / 1000` no es `9,995` en coma flotante binaria sino
`9,99499999…`, así que el redondeo a dos decimales da **`9,99`**, y eso es lo que da también la
referencia (`(9.995).toFixed(2) === "9.99"`). El propio vector lo había previsto: su nota dice que
**solo fija `isComplete`** porque *"completedKm y percentage dependen de cómo redondee cada
runtime"*.

*Qué se decidió, y por qué no se "arregla" para que salga 10,00.* Ser fiel a la referencia. Forzar
`10,00` exigiría un segundo criterio de redondeo sin vector que lo respalde, y además sería peor
para Paul: enseñaría "10,00 km" junto a un anillo sin cerrar, que es exactamente la confusión que
la fila describe. Con `9,99` el arco y su cifra dicen lo mismo.

*Qué NO cambia.* La decisión de Paul de la 8.7 —`isComplete` se decide sobre los metros sin
redondear— se cumple entera. Para que sea **comprobable** hizo falta un caso que la matriz no
trae: **9 999,6 m**, que sí redondea a `10,00` y sigue sin cumplir la meta. Con los 9 995 m de la
matriz, cambiar `isComplete` a los kilómetros redondeados no rompe nada, porque `9,99 < 10`.

*Dónde vive.* `GoalEngineTests`, "La cifra redondeada llega a 10,00 y la meta SIGUE sin cumplirse".

## Review Triage Log

**2026-09-21 · Revisión de la implementación de la 3.1.** 19 hallazgos más una decisión nueva de
Paul (fila 1). Veredicto: **20 aplicados**, 1 rechazado con evidencia, 1 diferido re-verificado.
Una fila por hallazgo, sin agrupar: la primera versión de esta tabla metió los tres menores en una
sola fila y **eso es exactamente cómo un hallazgo desaparece sin dejar rastro**.

### A · Decisión nueva de Paul (aplicada)

| # | Hallazgo | Veredicto |
|---|---|---|
| 1 | La meta admitía `0,01` km: caminar diez metros la cumplía y desbloqueaba `weekly_goal`, que es **de por vida e irrevocable**, ensuciando el grid de la 3.3 para siempre | **Aplicado.** `AppSettings.minimumWeeklyGoalKm = 1` (inclusivo), `isTooSmallGoalKm(_:)`, `GoalRejection.belowMinimum(Double)` con su texto —el mensaje dice **cuál** es el mínimo, que es la razón de que sea un caso propio y no `.notPositive`— y el pie de la sección lo anuncia antes del error. La puerta tolerante **sigue tolerando**: un `0,01` en disco se lee como "sin configurar". Registrado en el Spec Change Log con fila nueva en la matriz |

### B · El anillo mentía (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 2 | `fraction` salía del `percentage` **ya redondeado**: con 9 999,6 m daba `100` y el anillo se pintaba **entero sin celebrar ni desbloquear**, porque `isComplete` mira los metros crudos | **Aplicado.** `fraction` pasa a ser una magnitud propia del valor, derivada de los metros sin redondear, de modo que **`fraction == 1` si y solo si `isComplete`**. No toca AD-6: ningún vector la fija (los 15 fijan `completedKm`, `goalKm`, `percentage` e `isComplete`). Con test del caso 9 999,6 —"casi lleno pero no completo"— y otro que recorre exacto / pasado / mitad |
| 3 | `GoalRingView` sacaba la meta de `progress?.goalKm`, así que con el historial ilegible el pie decía **"de 10 km" a quien tuviera 15 guardados**: deshacía el `nil` deliberado de AD-22 | **Aplicado.** La meta entra por su propio parámetro (`goalKm`), que `HomeView` toma de `settingsStore.resolvedWeeklyGoalKm`. Son dos preguntas con dos respuestas: el progreso no se sabe, la meta sí — vive en otro fichero |
| 4 | El doc de `GoalRingView.kilometers` afirmaba que "9 995 m se muestran como `10`", **y es falso**: se muestran como `9,99`, como registra el Spec Change Log de esta misma historia | **Aplicado.** El comentario usa el caso que sí vale (9 999,6 m) y enlaza con la razón por la que el arco no sale del porcentaje. Una afirmación falsa en un comentario es exactamente lo que este proyecto lleva semanas quitando, y se coló en el cambio que documentaba la corrección |

### C · Huecos de verificación (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 5 | Cambiar `history: historyStore` por `history: HistoryStore(storage: storage)` en `CompositionRoot` **compila**, y deja dos lectores de `sessions.json`: el anillo no se movería tras una caminata y, con el historial ilegible, diría **0 km / 0 %** en vez de "no se pudo leer". Quitar `clock: clock` también compila | **Aplicado.** Tres casos nuevos en `CompositionRootTests`, al molde de `storeGetsQuotesRandomAndSettings`: el reloj del root (una caminata que solo cae en la semana del `ClockStub`), la **única** instancia de historial (`append` por `root.historyStore` y el anillo se mueve) y el historial ilegible llegando al anillo como `nil` |
| 6 | Los fixtures seguían construyendo un **segundo dueño** de `sessions.json` por el valor por omisión | **Aplicado.** `MeasurementLogTests` y `SessionStoreTestSupport` cablean el historial una vez y lo comparten; el `sessionStore(...)` de `SettingsStorePersistenceTests` toma por omisión **el del propio store de ajustes** (`settings.history`) en vez de fabricar otro |
| 7 | `goalRingDidUpdate()` descartaba el `Bool` de `save { … }` y de `unlockWeeklyGoal(at:)`, y el comentario afirmaba la conducta de recuperación **sin test** | **Aplicado.** Los dos fallos se registran en el log, y hay dos casos nuevos: con el disco caído **se celebra igual** y —porque `save(applying:)` aplica en memoria— no se repite en esta ejecución, solo al relanzar (el comentario decía lo contrario y ahora dice lo que pasa); y con `achievements.json` ilegible la celebración **no se cancela**, porque son dos cosas distintas (AD-25) |
| 8 | Faltaba test de que **cambiar la meta** complete la semana: la celebración solo se ejercitaba por cambios del historial, nunca por lo único que esa pantalla deja hacer | **Aplicado.** Dos casos: bajar la meta (12 km con meta 15 → "usar los 10 por defecto") celebra **ahora**, y subirla por encima de lo caminado **no "descelebra"** la semana ya celebrada |

### D · Falsos verdes y silencios (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 9 | `save(applying: { _ = try? $0.setWeeklyGoalKm(kilometers) })` se tragaba el `throw`: si la revalidación cambiara, escribiría `settings.json` **sin** la meta reportando `.saved` | **Aplicado.** El `change` lleva testigo: si la frontera rechazara al aplicar, se registra un `error` y el resultado es un rechazo, nunca "guardada" |
| 10 | El log nuevo de `SettingsFileAdapter` no saltaba cuando `weeklyGoalKm` o `lastGoalCelebratedWeek` venían con el tipo equivocado: el valor se perdía en silencio | **Aplicado.** `unreadableEditableKeys(in:)`, **pura y estática** como `decode`/`encode`, nombra las claves editables ilegibles y `decode` las registra. Con test de ocho casos, incluidos los que **no** cuentan (`null`, un número fuera de rango) y el booleano, que `JSONSerialization` da como `NSNumber` y `JSONDecoder` tira |
| 11 | **Clave duplicada `"Meta semanal"` con dos `comment:` en conflicto**: etiqueta de VoiceOver del anillo y encabezado de la sección de Ajustes. El catálogo se quedó **solo con el del anillo**, así que el del encabezado se perdió y quien lo acortara reescribiría de paso lo que VoiceOver lee | **Aplicado, y era un olvido, no una discusión**: en este mismo diff la clave `"km"` sí estaba resuelta con un comentario fusionado. Ahora los dos sitios llevan **el mismo** `comment:`, que nombra los dos usos y avisa de que acortar el encabezado acorta la etiqueta hablada. Se eligió fusionar y no partir la clave porque partirla obligaría a **cambiar el texto** del anillo, y "Meta semanal" es exactamente lo que VoiceOver debe decir: la copia no la decide el formato del catálogo. Verificado además que no queda ninguna otra clave del árbol con dos comentarios distintos |
| 12 | `WeeklyProgress` tenía un `init` público por miembros **sin invariante**, al revés que todo valor de dominio del proyecto: `(completedKm: -5, goalKm: 0, percentage: 900, isComplete: true)` compilaba | **Aplicado.** El `init` pasa a ser `(completedM:goalKm:)` —los metros crudos y la meta— y **deriva** los cuatro campos, así que no pueden contradecirse. Normaliza en vez de lanzar, como `AppSettings`: esto no es una frontera de escritura, es el resultado de un cálculo. Con test parametrizado de seis entradas imposibles |
| 13 | La rama `guard let interval … else { return now..<now }` de `GoalEngine.week` no tenía test y su propio comentario decía "no ocurre": una ventana vacía da 0 % en silencio | **Aplicado.** Se extrae `week(from:containing:)`, que es donde vive el suelo y **sí** se puede ejecutar, con test de los tres casos (sin intervalo, intervalo vacío, intervalo bueno) |

### E · La semana que cambia debajo (aplicado, con residuo registrado)

| # | Hallazgo | Veredicto |
|---|---|---|
| 14 | `clock.now` no es estado observable, así que cruzando el lunes con la app abierta el anillo **seguía mostrando la semana pasada** y la celebración de la nueva no se disparaba nunca | **Aplicado.** `SettingsStore.weekMayHaveChanged()` mueve `goalRefreshToken` —que la vista lee, y por eso repinta— y vuelve a mirar si toca celebrar; lo llama `RootView` en cada cambio de fase de escena, que es como se cruza el lunes casi siempre. Con test (`clock.set(...)` al lunes siguiente → semana nueva celebrada). **El residuo —la app en primer plano cruzando la medianoche sin cambio de fase— está en `deferred-work.md` con `Destino:` la 3.4 o la 6.2**, con las tres salidas posibles escritas |

### F · Accesibilidad, invariantes y ruido (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 15 | Con Dynamic Type al máximo y el aviso de historial ilegible, el anillo o el **botón de iniciar caminata** podían recortarse | **Aplicado.** `GeometryReader` + `ScrollView` con `minHeight: proxy.size.height`, el mismo patrón que la pantalla de sesión: los dos `Spacer` siguen repartiendo el aire cuando sobra, y cuando falta toma el relevo el scroll |
| 16 | `minimumScale = 0.5` era un quinto número visual en la vista, y la spec afirmaba que los cuatro nuevos estaban en `GoalRing` | **Aplicado.** Sube a `GoalRing.minimumValueScale`, por la vía "normativo" de la regla de admisión del fichero de tokens: recortar un número es peor que encogerlo, porque un `1` recortado de un `10` se lee como otro número |
| 17 | El mensaje de la sección 9b del gate seguía diciendo que las intenciones de `achievements` son "las que estrene la 3.2" | **Aplicado.** Nombra `unlockWeeklyGoal` (3.1). La regla no cambia; el mensaje sí |
| 18 | `thenextWeekCelebratesAgain` | **Aplicado.** `theNextWeekCelebratesAgain` |
| 19 | El reloj por omisión de `SettingsStoreFixture` era un literal (`1_783_512_000`) sin decir qué fecha es | **Aplicado.** `SettingsStoreFixture.defaultNow`, con su fecha y su semana escritas: miércoles 8 de julio de 2026, 12:00 UTC → `2026-W28`, la misma que usan los tests de la meta semanal |
| 20 | La Verification de la spec decía `GoalEngineTests 12` cuando el suite define más | **Aplicado.** Los números se recontaron por nombre sobre el `.xcresult` después de esta pasada, no a ojo |

### Rechazado con evidencia

| # | Hallazgo | Veredicto |
|---|---|---|
| — | "La entrada diferida de *los ajustes no se pudieron leer* se queda sin re-apuntar" | **Rechazado: es falso.** El diff **sí** la actualiza — dice que la 3.1 tocó Ajustes y **no** la cerró (su bloque congelado acota el alcance, y el aviso pide además decidir si hay reintento o "empezar de cero"), deja escrito que la 3.1 **empeoró el silencio a la mitad** —ahora son dos ajustes los que se muestran por omisión con el fichero ilegible— y re-apunta `Destino:` a la **4.2**, o a la retro del Epic 3 si cae antes. Comprobado sobre `deferred-work.md` |

### Diferido, re-verificado (registrado, no arreglado)

- **Que nada pruebe que `HomeView` pinta el anillo ni que dispara `goalRingDidUpdate()`.** XCUITest
  está descartado (decisión D1 del 2026-09-20), no diferido. La entrada ya existía y se ha
  **ampliado** con lo que la revisión pide dejar dicho: de ese `.task` cuelga **la celebración
  entera** —el desbloqueo de por vida de `weekly_goal` y la marca de semana celebrada—, nadie más
  lo llama salvo el `weekMayHaveChanged()` del cambio de fase, y borrarlo no deja un solo test en
  rojo mientras la meta deja de celebrarse **para siempre**, en silencio. Es el hueco más caro que
  esta historia deja abierto, y así queda escrito.

## Design Notes

**Por qué el cálculo va en `Domain/` y no en el store.** Porque los 15 vectores lo ejecutan, y
los vectores no pueden importar `WalkTracker`. Es además lo que AD-3 pide. El store se queda con
lo que no es cálculo: leer el historial, leer la meta y decidir si toca celebrar.

**Por qué la huérfana suma en el anillo y no cuenta para logros.** Son dos preguntas distintas y
el código ya las separó: `countsForAchievements` es `false` porque un logro premia una caminata
que Paul hizo deliberadamente, y el anillo mide **distancia recorrida**, que la hizo igual. Está
escrito en la doc del campo desde la 5.1; esta historia lo respeta en vez de redescubrirlo.

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` -- esperado: verde, con `weeklyProgress` **fuera** de la línea
  de pendientes y los 15 vectores en verde.
- `bash Scripts/check-project-shape.sh` y su arnés -- esperado: verde, 220/220.
- `bash Scripts/check-spec-shape.sh` -- esperado: verde.
- `xcodebuild test` completo -- esperado: el número de tests ejecutados **crece**, contado en el
  `.xcresult`, no leído del `TEST SUCCEEDED`.

**Ejecutado (2026-09-21):**
- `bash Scripts/verify-domain.sh` -> **verde**. 279 tests en 19 suites (255 en 18 antes). La línea
  de pendientes de AD-6 pasa a `achievementCatalog (1), checkStreak (8), checkTimeOfDay (5),
  evaluateAchievements (51)`: **`weeklyProgress (15)` ya no está**, y los vectores que pasan suben
  de 29 a **44**. El suite nuevo `GoalEngineTests` entra en `DOMAIN_SUITES` en el mismo commit —sin
  eso el propio gate lo habría dicho, que es lo que B-6 dejó hecho—.
- `xcodegen generate && xcodebuild test ... iPhone 16e CODE_SIGNING_ALLOWED=NO` -> **TEST
  SUCCEEDED**, **781 tests en 62 suites** (723 en 59 antes): **58 casos y 3 suites nuevos**,
  contados por nombre sobre el `.xcresult` y no por `TEST SUCCEEDED` — `GoalEngine · la semana, en
  hora local` **13**, `SettingsStore · la meta semanal y el anillo` **19**, `AchievementsStore · el
  logro de la meta semanal` **5**, más los ampliados: `AppSettings · la ventana no se puede
  construir mal` pasa a 37, `Arnés de vectores` a 22, y `SettingsFileAdapter` y `SettingsView`
  suman los suyos. Con los casos parametrizados desplegados, el bundle cuenta **1 206 aserciones
  de caso**, todas `Passed`. Sin errores ni warnings propios nuevos: los tres de `SettingsViewTests`
  (`decimalText` / `humanRangeBounds` llamados desde un contexto no aislado) son los de antes, y
  los tests nuevos de esa suite llevan `@MainActor` para no añadir más.
- `bash Scripts/check-project-shape.sh` -> verde. `bash Scripts/check-project-shape-tests.sh` ->
  **220/220**, sin reglas nuevas: ni el anillo ni la sección de meta las necesitan.
- `bash Scripts/check-spec-shape.sh` -> verde, con 59 entradas de `deferred-work.md` (57 antes).

**Mutaciones, las cuatro comprobadas y revertidas:**
- **La semana en UTC** (forzar `timeZone = UTC` en `GoalEngine.week`, que es literalmente lo que
  hace `motivation.js`) -> **los tres vectores divergentes fallan**, el test de `expectedJs` falla
  en sus tres casos (Swift pasa a dar el valor de la v3) y caen 2 tests de `GoalEngineTests`, entre
  ellos el del cambio de hora. Es la comprobación de que AD-19 está **ejecutándose**, no escrito.
- **`isComplete` sobre los km redondeados** -> falla "La cifra redondeada llega a 10,00 y la meta
  SIGUE sin cumplirse". Los 15 vectores **no** lo cazan, y por eso ese caso existe.
- **Celebrar en cada pintado** (quitar la guarda de `lastGoalCelebratedWeek`) -> fallan 2 tests:
  "UNA vez por semana" y "Relanzar la app en la misma semana NO vuelve a celebrar".
- **Que la huérfana no sume en el anillo** (`&& record.countsForAchievements`) -> fallan los 2
  tests que afirman lo contrario, uno en el dominio y otro en el store.
- Árbol restaurado y suite completa en verde después de las cuatro.

**Manual checks (iPhone 14, tras el build): PENDIENTES.** No se han ejecutado. Son los tres de la
spec —fijar meta 15 y reabrir la app; "0" y "abc" rechazados sin tocar el fichero; VoiceOver sobre
el anillo— más el aspecto del anillo con Dynamic Type al máximo y con Reduce Motion. Lo que sí
queda cubierto sin renderizar: que la meta sobreviva al relanzar (`SettingsStoreGoalTests`, con un
store nuevo sobre el mismo `storage`), que un valor inválido no escriba (`storage.settingsSaved`
vacío) y **qué dice** VoiceOver (`SettingsViewTests` sobre `GoalRingView.spokenValue`). Lo que
falta está en `deferred-work.md` con su destino.
