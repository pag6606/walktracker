---
title: 'A-7 — El gate que hace verificable la lección de specs'
type: 'chore'
created: '2026-09-21'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: 'eb124a41139092278d53291fba31f063236df82a'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-b5-b6-gates-honestos.md'
  - '{project-root}/_bmad/custom/bmad-build.toml'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** El action item A-7 de la retro del Epic 1 decidió que las dos reglas de specs
fueran **verificables, no convención**, y el check nunca se escribió: viven como
`persistent_facts` en `_bmad/custom/bmad-build.toml` y se aplican a mano. Medido hoy sobre el
árbol, las dos llevan incumpliéndose desde el principio. Regla **(b)** —"una spec que toque
`SessionStore` lista en su Code Map los campos compartidos y sus invariantes"—: **18 specs**
tocan `SessionStore` en su Code Map y solo **4** listan los campos (2.1, R1, retro-E1-A1,
retro-E1-A2); **14 en rojo**, la 5.1 de ayer incluida. No falló "una vez en la 2.2": no se ha
cumplido nunca de forma comprobable. Regla **(a)** —"todo traspaso va a `deferred-work.md` con
destino explícito"—: de **54 entradas**, **22 no lo declaran de forma reconocible a máquina**, y
las que sí usan **al menos tres redacciones** (`Destino:` ×25, `Destino explícito:` ×2,
`Encaja al` ×1). Leídas por una persona, solo **17** carecen de destino por completo —3 de ellas
ya marcadas `**CERRADO`—: las 5 de diferencia lo declaran en prosa (`encaja con la historia 4.2`,
`→ historia 3.1`, `se manifiesta en la 3.2, que es su dueña`). **Esa brecha de 5 es el coste
exacto de la prosa**, y es el argumento de la forma canónica.

**Approach:** Un gate propio, `Scripts/check-spec-shape.sh`, con su camino rojo
`Scripts/check-spec-shape-tests.sh`, siguiendo el molde ya probado de `verify-domain.sh` /
`verify-domain-tests.sh` (B-6): raíz por argumento, salida `fichero:línea: error:`, y **un caso
rojo y uno verde por regla**. Vive **fuera del build** y se engancha al `On Complete` del
workflow de `bmad-build` desde `_bmad/custom/bmad-build.toml`, que es el punto de extensión
creado en A-8.

## Boundaries & Constraints

**Always:**
- El gate acepta la raíz por argumento (`check-spec-shape.sh [raíz]`), como los otros dos, para
  que el arnés lo apunte a un árbol temporal y **nunca** al repositorio.
- Formato de error `fichero:línea: error: …`, y el conteo de fallos decide el código de salida.
- **Toda regla tiene caso rojo Y caso verde** en `check-spec-shape-tests.sh`. Un gate sin camino
  rojo probado no es un gate (B-5/B-6).
- **Toda exención es una línea declarada dentro del propio script**, con fecha y razón, y el
  gate la imprime al correr. Lo que está exento se ve; no hay exenciones implícitas.
- El gate nombra el fichero **y la línea** del incumplimiento, no solo el fichero.

**Never:**
- No se engancha a `preBuildScript`. Una spec a medio escribir **no puede tumbar el build de la
  app**: estas reglas son sobre documentos, no sobre el árbol de código.
- No se toca `check-project-shape.sh` ni `verify-domain.sh` ni sus arneses.
- **No se infiere "esta spec difiere trabajo" del texto en prosa.** Está medido y es ruido: la
  8-3 dispara la señal y no tiene entrada; la R1 no dispara ninguna y sí tiene entrada. El gate
  no adivina intención; comprueba forma.
- No se edita ningún bloque `<frozen-after-approval>` de una spec cerrada. Si una spec `done`
  tiene que cumplir la regla (b), se rellena su **Code Map**, que no está congelado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Salida esperada | Manejo de error |
|---|---|---|---|
| (b) verde | Spec cuyo `## Code Map` menciona `SessionStore` y contiene una línea `**Campos compartidos…` | sin error | N/A |
| (b) rojo | Spec cuyo `## Code Map` menciona `SessionStore` y **no** contiene esa línea | `spec:LÍNEA_DEL_CODE_MAP: error:` nombrando la spec y la regla | exit ≠ 0 |
| (b) no aplica | Spec sin `SessionStore` en el Code Map (aunque lo mencione en Intent o Tasks, como la 1.1) | sin error | N/A |
| (b) sin Code Map | Fichero `spec-*.md` sin `## Code Map` | error: una spec sin Code Map no es comprobable | exit ≠ 0 |
| (a) verde | Entrada de `deferred-work.md` con destino en la forma canónica | sin error | N/A |
| (a) rojo | Entrada sin destino declarado | `deferred-work.md:LÍNEA: error:` con el arranque del `summary` | exit ≠ 0 |
| (a) campos | Entrada a la que le falta `summary` o `evidence` | error nombrando el campo ausente | exit ≠ 0 |
| (a) integridad | `source_spec` que apunta a un fichero que **no existe** en el árbol | error: entrada huérfana | exit ≠ 0 |
| Corpus vacío | Raíz sin ningún `spec-*.md` | error: el gate no encontró nada que comprobar (no un verde silencioso) | exit ≠ 0 |

## Decisiones de Paul (2026-09-21)

**D1 — La regla (b) corre sobre todo el corpus con una exención declarada y fechada.** Las 14
specs que hoy tocan `SessionStore` en su Code Map sin listar los campos compartidos se nombran
**una a una dentro del script**, con la fecha del A-7 y la razón. El gate las imprime al correr.
Cualquier spec nueva —o cualquier exenta que alguien rellene— entra en rojo automáticamente.
*Razón:* la regla (b) solo tiene valor prospectivo; enumerar los campos compartidos evita que la
**siguiente** historia los pise, y sobre una spec cerrada el valor es cero y el riesgo de
inventar contenido retroactivo, real. Es el mismo patrón que las divergencias declaradas de AD-6
y la excepción de tres colorsets de AD-13.

**D2 — La regla (a) sí se pone en verde a mano, porque ahí el trabajo sigue vivo.** Al revés que
en la (b): una entrada diferida sin destino es trabajo comprometido que nadie ha asignado, y es
exactamente el defecto que la regla existe para evitar. Se rellenan las **14** sin destino y se
reescriben las **5** que lo dicen en prosa. Las **3** marcadas `**CERRADO` quedan exentas por esa
marca, que es la convención real del fichero y no necesita campo nuevo. **Los 14 destinos se
proponen a Paul y él los confirma o corrige antes de escribir nada en `deferred-work.md`.**

**D3 — La forma canónica es `Destino:` literal.** Sin ambigüedad y trivial de comprobar. Obliga a
reescribir una frase en 8 entradas: las 3 con otro marcador y las 5 de prosa. El
`persistent_facts` del A-7 en `_bmad/custom/bmad-build.toml` se amplía para que el workflow lo
escriba así desde el principio — necesario porque la plantilla `defer` de la propia skill
(`step-04-review.md`) escribe los diferidos **sin destino**, y ése es el origen de las 22.

</frozen-after-approval>

## Code Map

**El molde a copiar — no inventar otro**
- `Scripts/verify-domain-tests.sh` — el arnés de camino rojo de B-6. `assert_gate nombre raíz
  exit_esperado [needle]` afirma **el código de salida Y que la salida menciona el texto
  correcto**, para no dar por buena una violación detectada por la razón equivocada.
  `report_pass`/`report_fail` con contadores. Monta un árbol temporal con `mktemp -d`; **no toca
  el repositorio**. Copiar esta forma entera.
- `Scripts/verify-domain.sh:44-56` — cabecera que explica *qué defecto cierra* y `section()` para
  el formato de salida. El gate nuevo abre igual.
- `Scripts/check-project-shape.sh:79-91` — `ROOT="${1:-…}"`, `err()` con formato
  `fichero:línea: error:` y `fail_count`. Ese es el contrato de salida.

**Lo que hay que parsear**
- `_bmad-output/implementation-artifacts/spec-*.md` — 26 ficheros. Estructura **uniforme y
  verificada**: las 26 tienen `## Code Map`, `## Intent`, `## Boundaries & Constraints`,
  `## I/O & Edge-Case Matrix`, `## Tasks & Acceptance`, `## Implementation Notes` y
  `## Verification`, con el encabezado exacto `## Code Map` sin variantes. El frontmatter tiene
  siempre los 8 mismos campos, `status` entre ellos.
- Delimitar el Code Map: desde `^## Code Map` hasta el siguiente `^## `. Es lo que distingue el
  caso real del falso positivo — la 1-1 menciona `SessionStore` 9 veces y **ninguna** en su Code
  Map.
- La marca de cumplimiento de (b) es una línea en negrita que empieza por `**Campos compartidos`
  — verificado: aparece en 4 specs, las 4 dentro del Code Map, en 3 redacciones
  (`**Campos compartidos del store**` ×2, `**Campos compartidos entre las fronteras**`,
  ``**Campos compartidos de `SessionStore` que toca este cambio (lección L3 de la retro):**``).
- `_bmad-output/implementation-artifacts/deferred-work.md` — 164 líneas: un `# Deferred Work` y
  **54 entradas de exactamente 3 líneas cada una** (`^- source_spec:`, `^  summary:`,
  `^  evidence:`), verificado — las 53 distancias entre `source_spec` consecutivos son 3, y hay
  54 `summary` y 54 `evidence`. El parser es trivial y **no hace falta YAML**. Los valores de
  `summary` y `evidence` son **párrafos largos de una sola línea** con markdown dentro; no se
  pueden partir por comas ni por puntos.
- Estado de cierre: **no hay campo**. Se marca en el texto libre del `summary`, con `**CERRADO el
  <fecha>` al principio. Hay 3 así. Una entrada cerrada no debe exigir destino.
- Integridad referencial: los `source_spec` toman **21 valores distintos y los 21 ficheros
  existen** (verificado). La regla nace en verde: es una guardia para el futuro, y su camino rojo
  se demuestra en el arnés, no en el corpus.

**Dónde se engancha**
- `_bmad/custom/bmad-build.toml` — punto de extensión del proyecto (A-8). Ya lleva los dos
  `persistent_facts` con las reglas. La clave `on_complete` del `[workflow]` se renderiza en el
  `## On Complete` al final de `step-05-present.md`; hoy está vacía.
- **Ojo:** el `defer` de `step-04-review.md` escribe entradas con **solo** `source_spec`,
  `summary` y `evidence` — sin destino. Ese es el motivo de que 22 entradas no lo tengan: la
  plantilla de la skill no lo pide. El `persistent_facts` es el único sitio donde se puede
  obligar, y el gate es quien lo caza cuando se olvida.

**Lo que NO se toca**
- `check-project-shape.sh`, `verify-domain.sh` y sus dos arneses. `project.yml`. Nada de
  `WalkTracker/`, `Domain/` ni `WalkTrackerTests/`: este chore no toca una línea de Swift.
- **Campos compartidos de `SessionStore` que toca este cambio (regla (b), aplicada a esta
  misma spec):** **ninguno**, y el invariante es ése: este chore no toca Swift.
  `SessionStore` aparece en este Code Map solo como el literal que la regla (b) busca, así
  que no hay campo del store que la siguiente historia pueda pisar por culpa del A-7. Se
  escribe porque la regla corre sobre **todo** el corpus y esta spec entra en él: la
  alternativa era exentarse a sí misma, y una spec viva no tiene la razón que justifica las
  14 exenciones de D1 (valor cero sobre una spec cerrada, riesgo real de inventar contenido
  retroactivo). Aquí el valor es cero por otro motivo —no hay campos— y decirlo cuesta una
  línea comprobable.

## Tasks & Acceptance

**Execution:**
- [x] `Scripts/check-spec-shape.sh` -- gate nuevo con las reglas (a) y (b), raíz por argumento,
  cabecera que explica qué defecto cierra y qué está exento -- es el entregable.
- [x] `Scripts/check-spec-shape-tests.sh` -- camino rojo y verde de **cada** regla sobre árbol
  temporal, con `assert_gate` copiado de `verify-domain-tests.sh` -- sin esto el gate no está
  probado.
- [x] `_bmad/custom/bmad-build.toml` -- `on_complete` que invoca el gate, y ampliar el
  `persistent_facts` de A-7 con la **forma canónica** que el gate exige -- que la convención y
  el check digan lo mismo.
- [x] `Scripts/check-spec-shape.sh` (segunda pasada) -- añadir la lista de exención de D1 con las
  **14 specs nombradas una a una**, fecha y razón, **solo después** de haber corrido el gate sin
  ella y comprobado que nombra exactamente esas 14 -- el orden importa: la lista se escribe
  desde lo que el gate encontró, no desde lo que yo creía que iba a encontrar.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` -- rellenar las 14 entradas sin
  destino y reescribir las 5 de prosa a `Destino:` (D2, D3) -- **previa confirmación de Paul de
  los 14 destinos propuestos**; nada se escribe antes de esa confirmación.

**Acceptance Criteria:**
- Dado el gate **sin** su lista de exención, cuando se corre sobre el árbol real, entonces sale
  rojo nombrando **exactamente 14** specs para la regla (b) y **27** entradas para la (a). Si los
  números no salen, el gate no comprueba lo que dice y se rechaza.
  *(Corregido el 2026-09-21: decía **22**. El 22 se midió con la familia laxa
  `Destino|Encaja`, antes de que D3 fijara `Destino:` literal como forma canónica; con la forma
  que el gate exige son 27, verificado a mano —54 entradas, 25 con `Destino:` literal, 29 sin
  él, 2 de esas marcadas `**CERRADO` → 27. La Intent congelada conserva el 22 y no se toca; el
  número que manda es éste.)*
- Dado el gate **con** la lista de exención y el `deferred-work.md` ya arreglado, cuando se
  corre, entonces sale verde y **imprime las 14 exenciones vigentes**. Un verde que no las
  enumere se rechaza: una exención invisible es una mentira.
- Dado que se añade una spec nueva que toca `SessionStore` sin listar campos compartidos, cuando
  corre el gate, entonces sale rojo — la exención cubre a las 14 nombradas, no a la regla.
- Dado `bash Scripts/check-spec-shape-tests.sh`, entonces todos los casos pasan y el conteo de
  casos ejecutados **crece** respecto a cero, imprimiéndose explícitamente.
- Dado que se borra la línea `**Campos compartidos…` de una spec del árbol temporal, cuando
  corre el arnés, entonces ese caso sale rojo mencionando esa spec — y no otra.

## Implementation Notes

**Los números medidos por el gate NO son los de la Intent, y el que manda es el del gate.** El
criterio de aceptación pedía **14** specs y **22** entradas al correr sin lista de exención.
Corrido sobre el árbol real (`27` specs, `54` entradas) el gate nombró **15 specs** y
**27 entradas**:

- **Regla (b) — 15, no 14.** Las 14 de D1, **más esta misma spec**, cuyo Code Map menciona
  `SessionStore` al citar la regla. La medida de la Intent se tomó sobre los 26 ficheros
  versionados; hoy hay 27 porque el A-7 ya está en el árbol. Resuelto rellenando el Code Map de
  esta spec con la respuesta verdadera (ningún campo compartido: no toca Swift), no exentándola
  — ver el Spec Change Log. Con eso, el gate sin exenciones nombra **exactamente las 14** de D1,
  y con ellas sale **verde imprimiendo las 14**.
- **Regla (a) — 27, no 22.** Es un error de medida de la Intent, no del gate, y se puede
  reproducir: `grep -c '^- source_spec:'` da **54**; entradas que contienen el literal
  `Destino:`, **25**; luego **29** no lo declaran de forma canónica. De esas 29, las marcadas
  `**CERRADO` son **2** (una tercera entrada cerrada ya traía `Destino:`), así que quedan
  **27** en rojo. Las cuentas de la Intent no cierran entre sí: 22 ≠ 54 − 28 (los tres
  marcadores que cita suman 28 entradas), y 17 + 5 = 22 exige 26 entradas sin marcador, no 22.
  **Los 27 incluyen los 3 de marcador alternativo y los 5 de prosa que D3 manda reescribir**, así
  que el trabajo que D2 describe es el mismo: solo que las que hay que rellenar son **19**, no 14.

**La tarea de `deferred-work.md` esperó a Paul, como D2 manda** (*"nada se escribe antes de
esa confirmación"*). Paul confirmó la propuesta el 2026-09-21 con cuatro precisiones, y las 27
entradas ya están escritas: el `Destino:` va **al final del `summary`**, que es donde lo ponen
las 25 que ya lo tenían; las entradas siguen ocupando **exactamente tres líneas** (el fichero
sigue en 164); y los dos marcadores alternativos que quedaban —`Destino explícito:` ×2 y
`Encaja al` ×1— han desaparecido del fichero. Con eso **el gate sale verde sobre el árbol real**
e imprime sus 14 exenciones. Las precisiones de Paul: **L10** y **L148** no eran trabajo
pendiente sino rastro, y se marcan `**CERRADO el 2026-09-21` en vez de recibir destino
(las cerradas pasan de 3 a **5**); **L94** apuntaba a la 5.1, ya cerrada y mergeada en `eb124a4`,
y se redestina a un chore de test inmediato porque `sessions.json` y `SessionRecord` ya existen;
**L25** va al `bmad-correct-course` del 2026-09-21; y las tres mediciones de CoreMotion
(**L22**, **L28**, **L37**) apuntan a la **caminata instrumentada de B-8**, no a una historia,
porque eso no lo zanja una historia sino una medición.

**Los destinos escritos (27 entradas).** `L` es la línea del `summary` en `deferred-work.md`.
Las marcadas ⟲ ya decían un destino en prosa o con otro marcador y se reescribieron a
`Destino:` sin perder lo que daban; las marcadas ✱ no lo decían en ningún sitio.

| L | Entrada (gist) | `Destino:` propuesto |
|---|---|---|
| 4 ✱ | Borrar `NativeLayerDiagnosticsView` y su cableado | un chore de limpieza propio; **ya es exigible**: la UI de sesión existe desde la 1.4 |
| 7 ⟲ | `FeedbackAdapter.fire` y el sonido | la historia 4.2, dueña de la preferencia de sonido |
| 10 ⟲ | Portar los escenarios AD-6 de `session-v3-tests.js` | sin `Destino:`, **marcada `**CERRADO el 2026-09-21`**: su destino eran las historias 1.1–1.6 y las seis cerraron |
| 13 ⟲ | Arranque con `achievements.json` inválido | la primera historia del Epic 3 que lea el catálogo (3.2) |
| 22 ✱ | ¿CoreMotion alterna muestras con y sin `distance`? | la **caminata instrumentada de B-8**: esto no lo zanja una historia, lo zanja una medición |
| 25 ⟲ | La Summary Screen de UX-DR4 no tiene historia dueña | el `bmad-correct-course` de 2026-09-21, que le asigna historia en `epics.md` |
| 28 ✱ | Reconciliar distancia entre tramos de pausa | la caminata instrumentada de B-8, con L22: misma causa y mismas muestras |
| 37 ✱ | Stream tras consulta de reconciliación sin dato | la caminata instrumentada de B-8, con L22 y L28 |
| 43 ⟲ | Retirar el registro de medición `WTM1` | el chore A-2 |
| 46 ✱ | Tests del informe del gate 8.4 (`estimate` con 0, p95≠máx) | el chore A-2, con L43 |
| 49 ✱ | Sección 4 del gate no ve `@preconcurrency import` | el siguiente chore de gates de la familia A-6/B-5/B-6 |
| 55 ✱ | Camino real de `LocationAdapter` con costura | el chore que introduzca la costura sobre `CLLocationManager` |
| 61 ⟲ | `PendingGap` en vez de la pareja de campos | el chore A-1 |
| 67 ⟲ | Reduce Motion en las cuatro vistas que no lo leen | la historia 3.3, la primera que anima |
| 76 ✱ | Límite: color partido en dos líneas esquiva la sección 12 | el chore que reescriba la sección 12 sobre líneas lógicas; **hoy sin dueño** |
| 91 ✱ | Contrato vista↔store de Ajustes | el chore que extraiga la presentación a tipos probables (con los diferidos de la 1.1 y la 1.2) |
| 94 ⟲ | Recalibrar no cambia el historial | **un chore de test inmediato**: decía "la 5.1", cerrada y mergeada en `eb124a4`, así que el test ya se puede escribir |
| 100 ✱ | Los dos suites de `settings.json` fuera del gate de dominio | el chore que decida si existe un gate del seam adapter↔store |
| 103 ⟲ | Nadie registra ni pinta `SessionMetrics.degraded` | el chore **B-10** para el registro, y **la decisión de producto de Paul** para si la pantalla lo dice |
| 106 ✱ | `maxRepresentableStrideM` se rederiva si cambia la base | la historia 3.1, la primera que suma sobre el historial |
| 112 ⟲ | `WakeLockPort` no tiene historia dueña | la pregunta abierta Q-3 de la retro del Epic 1 |
| 133 ✱ | `SUITE_DIRS` sigue siendo una lista a mano | el siguiente chore de gates, con L49 |
| 148 ✱ | Dónde quedó registrado el dueño del "Acerca de" | sin `Destino:`, **marcada `**CERRADO el 2026-09-21`**: es un registro, no trabajo pendiente |
| 151 ✱ | Umbral de ~5.000 registros para la escritura síncrona | la historia que haga `StoragePort` asíncrono; **hoy sin epic** |
| 154 ⟲ | La transacción de AD-17 cruza dos ficheros | la historia 3.2, que es su dueña |
| 157 ⟲ | Los 79 vectores que esperaban al historial | las historias 3.1 (`weeklyProgress`, `checkStreak`) y 3.2 (`evaluateAchievements`, `checkTimeOfDay`) |
| 160 ⟲ | Converger los tres `ReadOutcome` | el chore B-10 |

**Lo que el gate comprueba de más que la matriz, y por qué.** Además de los ocho escenarios de
la matriz, una entrada cuyas líneas no sean exactamente los tres campos conocidos es un fallo.
Sin eso, una línea envuelta o un campo inventado haría que el parser leyera otra entrada y el
error saliera contra la línea equivocada: sería volver a "verde por no haber mirado". Y una
exención que **ya no hace falta** —la spec exenta ahora lista sus campos— también deja el gate
en rojo pidiendo que se borre su línea, que es la lectura literal de D1 (*"o cualquier exenta
que alguien rellene entra en rojo automáticamente"*). Una exención que sobra esconde a las que no.

**Y el criterio NO es bidireccional del todo, al revés que el de B-6: se dice, no se maquilla.**
El inventario de suites de `verify-domain.sh` falla en los dos sentidos —un suite sin listar y un
listado que ya no está—. Aquí solo falla uno: una exenta que ya lista sus campos deja el gate en
rojo (`✗`), pero una exención cuya spec **no está en el árbol** se marca `?`, se imprime y **no
falla**. No es un descuido: los árboles temporales del arnés no contienen casi ninguna de las 14,
así que hacerlo rojo convertiría el caso normal del arnés en un fallo permanente. El gate lo dice
en su propia salida y hay un caso que fija ese comportamiento, para que nadie lo "arregle" sin
ver lo que rompe.

**Hueco de verificación encontrado al verificar, y cerrado (2026-09-21).** El caso del arnés
"mencionar `SessionStore` fuera del Code Map NO dispara la regla" **no ejercitaba lo que decía
ejercitar**. Mutación propia: quitar el corte del bloque —`NR > start { if ($0 ~ /^## /) exit;
print }` → `NR > start { print }`, o sea leer hasta el final del fichero en vez de parar en el
siguiente `## `— dejaba el arnés en **19/19 verde**, mientras el gate mutado marcaba en falso a
`spec-1-1` sobre el árbol real (menciona `SessionStore` en las líneas 91–146 con su `## Code Map`
en la 68). La causa: el fixture `store-fuera` ponía sus menciones en `## Intent`, es decir
**antes** del Code Map, donde leer de más no las alcanza; en el corpus real caen **después**.
Arreglado añadiendo al fixture un `## Implementation Notes` con menciones posteriores al Code
Map. Con el fixture corregido la misma mutación produce **4 casos rojos**, y el árbol restaurado
vuelve a 19/19. Es el mismo defecto de siempre —un caso que dice comprobar más de lo que
comprueba—, esta vez dentro del propio arnés que existe para evitarlo.

**Un 33/34 observado una vez y NO reproducido (2026-09-21).** La implementación reportó una
ejecución del arnés en 33/34 con tres procesos solapados, sin el nombre del caso (se perdió en un
`tail -3`). Intentos de reproducción por mi parte: **5 ejecuciones en serie** y **3 concurrentes**,
las 8 en 34/34. Además el arnés no tiene ninguna ruta temporal fija —cada fixture monta su propio
`mktemp -d`—, así que la vía obvia de interferencia entre procesos no existe. Queda escrito aquí
sin causa conocida: si vuelve a aparecer, hay constancia de que ya se vio una vez y de qué se
descartó. No se declara benigno.

**Límite declarado, para no prometer de más.** La regla (b) comprueba que la línea **existe**,
no lo que dice: una spec puede escribir `**Campos compartidos**: los de siempre` y pasar. El
gate caza el olvido, no la desgana. Está escrito en la cabecera del script, como pide B-5.

## Spec Change Log

**2026-09-21 · Code Map — esta spec cumple la regla (b) en vez de exentarse.** Al correr el
gate sin lista de exención sobre el árbol real nombró **15** specs, no 14: las 14 de D1 más
**esta misma**, cuyo `## Code Map` menciona `SessionStore` al citar la regla. La medida de la
Intent se tomó sobre 26 ficheros y hoy hay 27, porque esta spec ya está en el árbol. Se
resuelve por el camino que las Boundaries ya autorizan —"se rellena su Code Map, que no está
congelado"— con la respuesta verdadera: **ningún campo compartido**, porque este chore no
toca Swift. Así la lista de exención se queda en las **14** que D1 nombra y el criterio de
aceptación ("exactamente 14") se comprueba tal cual está escrito. No se tocó nada dentro de
`<frozen-after-approval>`.

## Review Triage Log

Revisión del 2026-09-21. Todos los hallazgos llegaron reproducidos por el revisor y se
verificaron antes de tocar nada; ninguno se rechazó.

| # | Hallazgo | Verdicto | Resolución |
|---|---|---|---|
| 1 | Nada ejecuta `check-spec-shape-tests.sh`, al revés que `verify-domain.sh:205`, que es el molde que la Code Map manda copiar | high | El gate ejecuta su arnés cuando se invoca **sin raíz** (`[ $# -eq 0 ]`); el arnés siempre pasa raíz, así que no hay recursión ni flag nuevo. Si el arnés falla, rojo **antes** de mirar el corpus |
| 2 | Falta el caso verde de un `Destino:` que vive solo en el `evidence`: 11 de 54 entradas reales son así, y estrechar la búsqueda a `$summary_text` dejaba el arnés en 19/19 con 10 entradas legítimas en rojo | high | Caso 14 añadido. Mutación reproducida: con la búsqueda estrechada, ese caso —y solo ése— se pone rojo |
| 3 | El caso de la exención solo afirmaba la **primera** (`head -n 1`): un `break` en el bucle de impresión dejaba el arnés verde imprimiendo 1 de 14 | high | Se cuentan las líneas impresas contra `exempt_names \| wc -l`. Mutación reproducida: con el `break`, el caso falla diciendo "imprime 1 y declara 14" |
| 4 | Un `deferred-work.md` vacío (solo encabezado) salía verde: la regla (b) guardaba el corpus vacío y la (a) no | medium | Simetría con su caso rojo (15) |
| 5 | `Destino:` sin nada detrás pasaba | medium | Exige `[^[:space:]]` detrás, con caso rojo (16) |
| 6 | `**CERRADO` sin fecha eximía del destino | medium | Exige `[0-9]{4}-[0-9]{2}-[0-9]{2}`, con caso rojo (17). Las 5 entradas cerradas reales ya la traen |
| 7 | Lo anterior a la primera entrada era invisible al parser | medium | Solo encabezado y líneas en blanco; caso rojo (18) |
| 8 | Dos entradas fundidas se absorbían y la falta de destino de la segunda se volvía invisible | medium | Exactamente un `summary` y un `evidence` por bloque; caso rojo (19) |
| 9 | `wc -l` daba rojo falso en un fichero sin salto de línea final | medium | `awk 'END{print NR}'`, con caso verde (20) |
| 10 | `## Code Map (actualizado)` daba rojo falso, y un Code Map repetido no se señalaba | medium | Encabezado con texto detrás aceptado; repetido, rojo. Casos 6c |
| 11 | Tres `err` sin número de línea contradecían las Boundaries ("nombra el fichero **y la línea**") | low | Los tres pasan a `:1` |
| 12 | `entradas con fallo` contaba violaciones, no entradas | low | Un flag por entrada (`entry_bad`); el rótulo ya mide lo que dice |
| 13 | `mktemp -d` fallido dejaría `root` vacío y el gate correría contra el repositorio real | medium | `make_fixture` falla explícito y `assert_gate` —el único punto por el que pasan todos los casos— se niega a correr sin árbol temporal |
| 14 | Las grafías proscritas por D3 (`Destino explícito:`, `Encaja al`, `destino:`) no tenían caso que fijara que fallan | medium | Tres casos rojos (21). Sin ellos, ensanchar el patrón restauraba en silencio la ambigüedad que D3 quitó |
| 15 | La viñeta opcional del marcador de (b) no la ejercitaba nada | low | Caso verde 6b con el marcador sin viñeta |
| 16 | Las Implementation Notes reclamaban "el mismo criterio bidireccional que B-6", y la exención `ausente` nunca falla | medium | **No se hizo rojo a propósito** (rompería los árboles del arnés): se corrigió la afirmación, el gate lo dice en su salida y hay un caso que fija el comportamiento |
| 17 | `Destino: por decidir, hoy sin dueño` pasa — y dos de los destinos recién escritos dicen eso | medium | Límite declarado en la cabecera del gate y registrado en `deferred-work.md` con destino. No se endurece: obligaría a escribir un destino falso |
| 18 | La ejecución del gate sigue siendo un prompt, no un mecanismo, y la Intent pedía "verificables, no convención" | medium | Dicho con todas las letras en Design Notes, en el `README` y en la cabecera del script (límite 3), más su entrada diferida |
| 19 | El chore no registró un solo "Límite conocido", siendo el que hace cumplir esa regla (B-5/B-6 registraron 4) | high | Tres entradas nuevas en `deferred-work.md`, con `Destino:` canónico: contenido de (b), destino vacío de (a), y que nada comprueba que el gate llegue a ejecutarse |
| 20 | El `README` no nombraba el par gate+arnés, y no había decisión sobre las precondiciones de release | medium | Sección nueva en `## Los gates`, con la obligación de correr el camino rojo y la decisión explícita: **no** entra en el release, con su razón |
| 21 | El action item A-7 seguía `open` en `sprint-status.yaml` | low | A `done`, como hizo B-9 en `6fa1a45` |
| 22 | La tabla de destinos de la spec divergía de lo escrito en L103 | low | La fila dice ahora lo mismo que el fichero |

## Design Notes

**Por qué (a) se comprueba por forma y no por intención.** La mitad valiosa de la regla (a) es
"una spec que difiere trabajo **tiene** su entrada". Se intentó medir y no es mecanizable
honestamente: buscando en las 26 specs las señales de prosa (`diferid`, `traspas`, `queda para
la`, `Destino:`), la 8-3 da señal con **0** entradas y la R1 da **0** señales con 1 entrada. Un
gate construido sobre eso produciría rojos falsos y verdes falsos, que es exactamente el defecto
que B-5 y B-6 cerraron. Lo que sí es sólido es la dirección contraria —**integridad
referencial**: toda entrada apunta a un `source_spec` que existe— y la forma de la entrada. La
mitad de intención se queda donde único puede vivir: en el `persistent_facts` que el agente lee
al escribir la spec, con el gate cazando la forma cuando se olvida.

**Por qué el gate no va en el build.** `check-project-shape.sh` lo invoca la `preBuildScript` de
los dos targets. Meter ahí una regla sobre documentos haría que una spec en `draft` impidiera
compilar la app. La consecuencia previsible es que alguien la desactive, y un gate desactivado
es peor que ninguno porque sigue pareciendo que protege.

**Y ése es el precio, dicho con todas las letras: la EJECUCIÓN sigue siendo un prompt, no un
mecanismo.** La Intent congelada pedía que las dos reglas fueran "verificables, no convención", y
eso se cumple **a medias**. El **check** es mecánico: corre solo, falla por sí mismo, tiene camino
rojo probado y su propio gate lo ejecuta antes de gatear nada. La **ejecución** no: a
`check-project-shape.sh` lo invoca cada build y a éste solo lo invoca una frase de
`workflow.on_complete` que un agente puede saltarse, que una actualización de la skill puede dejar
sin renderizar, y que nadie ejecuta si el trabajo no pasa por `bmad-build`. La diferencia con la
convención anterior es real —antes no existía nada que se pudiera correr— pero no es la misma
garantía que tienen los otros dos gates, y decir lo contrario sería exactamente el defecto que B-5
cerró: un gate que promete más de lo que cubre. Está declarado en la cabecera del script (límite 3),
en el `README` y registrado en `deferred-work.md` con destino, que es lo único que este chore puede
hacer hoy sin meter documentos en el build.

## Verification

**Commands:**
- `bash Scripts/check-spec-shape.sh` -- esperado: **rojo antes** del arreglo del corpus
  (nombrando specs y entradas), **verde después**.
- `bash Scripts/check-spec-shape-tests.sh` -- esperado: todos los casos verdes, con el conteo
  impreso; al menos un caso rojo y uno verde por regla.
- `bash Scripts/check-project-shape.sh` -- esperado: sigue en 220/220, sin tocar.
- `bash Scripts/verify-domain.sh` -- esperado: sigue verde, con su línea de pendientes de AD-6
  byte a byte idéntica.
- `uv run --no-cache _bmad/scripts/render_skill.py --project-root . --skill .claude/skills/bmad-build`
  -- esperado: resuelve, y el `## On Complete` de `step-05-present.md` deja de estar vacío.

**Manual checks:**
- Mutación propia: quitar una regla del gate y comprobar que el arnés se pone rojo señalando esa
  regla. Restaurar el árbol y confirmarlo con `git status`.
