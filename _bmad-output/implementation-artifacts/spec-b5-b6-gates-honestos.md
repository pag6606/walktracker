---
title: 'B-5 y B-6 — Los gates comprueban lo que dicen comprobar'
type: 'chore'
created: '2026-09-20'
baseline_commit: '4c0f3a6d17ce01660964bb166f8289b194ed9891'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-retro-2026-09-20.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** cuatro comprobaciones afirman cubrir algo que no cubren. No es un fallo de una regla
concreta: es que **una regla léxica se ha hecho pasar por un invariante**, y el proyecto ha empezado
a apoyarse en ellas.

- **Sección 6.** Dice impedir que una vista llame a `save()` del store de ajustes. Lo que comprueba es
  que **el receptor acabe en `store`/`Store`**. `settings.save()` en una vista pasa en verde, y lo
  único que sostiene el invariante es un comentario en producción pidiendo no renombrar la variable:
  un *rename* en Xcode lo desarma.
- **Sección 12c.** Busca la clave del acento sobre **todo `project.yml`**, sin anclarla a un target.
  Moverla al target de la extensión sale verde con la app sin acento.
- **Sección 12b.** Si un `Info.plist` no existe, `[ -f "$plist" ] || continue` **se lo salta en
  silencio**: verde por no haber mirado.
- **`verify-domain.sh` (B-6).** Su lista de `-only-testing:` es **explícita y a mano**, y el propio
  script lo confiesa. Un suite nuevo que nadie añada no se ejecuta y nadie se entera. **Ya mordió:**
  durante la retro del Epic 2 se ejecutó un fichero con dos `@Suite`, corrió solo el primero y
  devolvió `TEST SUCCEEDED` sin haber ejecutado el test que se estaba investigando.

**Enfoque:** que cada una compruebe el invariante y no su sombra. Donde una regla léxica no pueda
alcanzar el invariante, que **falle en vez de pasar** — y que lo que no compruebe deje de anunciarse.

## Boundaries & Constraints

**Always:**
- **Ningún gate pasa por no haber mirado.** Un fichero o target que falte es un fallo explícito, no un
  `continue` silencioso. Es la regla que la sección 12 ya aplica bien y que las demás deben adoptar.
- **Cada regla nueva o ampliada llega con su caso rojo y su caso verde** en el arnés, incluidos los
  verdes de lo que debe seguir pasando. Es la convención desde A-6 y no se relaja.
- **Lo que un gate no pueda comprobar deja de anunciarse.** Si una regla léxica no alcanza el
  invariante, el comentario lo dice y —si procede— se registra el límite. Un gate honesto que cubre
  menos es mejor que uno que promete de más.
- **Falsos positivos, cero.** El árbol actual pasa sin cambios de código de producto. Si una regla
  nueva obligara a cambiar código para pasar, es que está mal calibrada.
- **B-6 se resuelve por derivación**: la lista de suites del gate de dominio sale del árbol, o el gate
  falla nombrando el suite no listado. Nunca se queda en una lista a mano que hay que recordar.
- El alcance de `verify-domain.sh` **no cambia**: sigue siendo dominio y vectores. Esto es sobre cómo
  se entera de qué ejecutar, no sobre qué debe ejecutar.

**Never:**
- Ampliar lo que un gate prohíbe aprovechando el viaje: esto es hacer honestas las reglas que hay, no
  añadir reglas nuevas.
- Cambiar código de producto para que un gate pase. Si hace falta, la regla está mal.
- Renombrar `SettingsStore.save()` ni volverlo `private` para esquivar el problema de la sección 6: el
  invariante es "la vista no escribe el estado", no "la variable se llama de cierta forma".
- Tocar lo que ya funciona de las secciones 9, 9b y 12.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Sección 6 · receptor renombrado | una vista escribe `settings.save()` | **falla**, nombrando fichero y línea | hoy pasa en verde |
| Sección 6 · intención legítima | una vista llama a `settingsStore.saveStride(…)` | **pasa**: es una intención, no un paso interno | — |
| Sección 6 · lectura legítima | una vista lee `store.metrics` o `settingsStore.strideM` | **pasa** | — |
| 12c · clave en otro target | la clave del acento se mueve al target de la extensión | **falla**: el acento de la app no queda fijado | hoy pasa |
| 12c · clave ausente | se borra del manifiesto | falla, como hoy | — |
| 12c · colorset borrado | la clave está pero `AccentColor.colorset` no existe | **falla**: la clave apunta a nada | hoy pasa |
| 12b · plist ausente | se borra un `Info.plist` declarado en el manifiesto | **falla**: no se puede declarar verde lo que no se miró | hoy se salta en silencio |
| B-6 · suite nuevo sin listar | se añade un `@Suite` en `Domain/` o `Vectors/` y no se lista | **falla**, nombrando el suite | hoy no se ejecuta y nadie se entera |
| B-6 · dos suites en un fichero | un fichero ya listado gana un segundo `@Suite` | **falla** si el segundo no entra | es el caso que mordió en la retro |
| B-6 · suite fuera del alcance | se añade un `@Suite` en `Application/` o `UI/` | **pasa**: el gate es de dominio, y eso no cambia | — |
| Árbol actual | todo como está hoy | los dos gates **verdes**, sin tocar código de producto | — |

</frozen-after-approval>

## Code Map

- `Scripts/check-project-shape.sh:222-232` — la sección 6. `store_write` y `store_internal` exigen que
  el receptor acabe en `store`/`Store`. El comentario de `:223` lo declara como definición
  (*"'Del store' es cualquier receptor que acabe en `store`/`Store`"*), así que el arreglo es tanto de
  regla como de redacción. **Pista:** los dos stores son tipos conocidos (`SessionStore`,
  `SettingsStore`) y sus intenciones son enumerables; el nombre de la variable no tiene por qué ser el
  criterio.
- `Scripts/check-project-shape.sh:602-608` — la 12c. `grep -qE '^…ASSETCATALOG…'` sobre `$MANIFEST`
  entero. `project.yml` declara los targets con su indentación; hay que anclar al de la app.
- `Scripts/check-project-shape.sh:579-600` — la 12b. La derivación desde `INFOPLIST_FILE` ya está bien
  (se arregló al cerrar B-2); lo que queda es el `[ -f "$plist" ] || continue` de `:594`. Ojo con el
  respaldo de `:588-591`: el arnés monta árboles mínimos sin manifiesto y eso debe seguir funcionando.
- `Scripts/check-project-shape.sh:497` y la cabecera — el índice de secciones describe lo que cada una
  hace; si una regla cambia, su descripción también.
- `Scripts/check-project-shape-tests.sh` — el arnés. Cada regla lleva rojo y verde; mira cómo montan
  los fixtures las secciones 9 y 12, que son las mejor hechas.
- `Scripts/verify-domain.sh` — la lista de `-only-testing:` y el comentario de `:26-27` que confiesa el
  defecto. Hay **16 `@Suite`** en `WalkTrackerTests/{Domain,Vectors,Scenarios}`; comprueba si la lista
  los cubre todos, porque la respuesta a eso ya es un hallazgo.
- `Scripts/vectors/check-inventory.js` — precedente de derivación del árbol dentro de este mismo gate:
  recorre los ficheros y compara con el inventario en vez de fiarse de una lista.
- `WalkTracker/UI/Settings/SettingsView.swift:26-28` — el comentario que hoy sostiene el invariante de
  la sección 6 pidiendo no renombrar la variable. Cuando la regla deje de depender del nombre, ese
  comentario **sobra y hay que quitarlo**: dejarlo sería documentación que miente.

## Tasks & Acceptance

**Execution:**
- [x] `Scripts/check-project-shape.sh` — sección 6: que el criterio sea el invariante y no el nombre
      del receptor. Actualizar su comentario, que hoy define la regla por el nombre.
- [x] `Scripts/check-project-shape.sh` — 12c anclada al target de la app, y comprobando que el
      colorset al que apunta existe.
- [x] `Scripts/check-project-shape.sh` — 12b sin salto silencioso, conservando el respaldo del arnés.
- [x] `Scripts/check-project-shape.sh` — el índice de secciones y las cabeceras, alineados con lo que
      las reglas hacen ahora.
- [x] `Scripts/verify-domain.sh` — la lista de suites sale del árbol, o el gate falla nombrando el que
      falte. Quitar el comentario que confiesa el defecto, ya sin defecto que confesar.
- [x] `Scripts/check-project-shape-tests.sh` — rojo y verde de cada regla tocada.
- [x] `Scripts/verify-domain-tests.sh` — **nuevo**: el camino rojo del inventario de suites, que
      `verify-domain.sh` no tenía arnés propio donde alojar. Lo ejecuta el propio gate, como el
      camino rojo del arnés JS.
- [x] `WalkTracker/UI/Settings/SettingsView.swift` — quitar el comentario que pide no renombrar la
      variable, cuando deje de ser cierto que eso importa.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` — los límites que queden, con destino.

**Acceptance Criteria:**
- Dado `settings.save()` escrito en una vista, cuando corre el gate, entonces **falla** — y hoy pasa.
- Dada la clave del acento movida al target de la extensión, cuando corre el gate, entonces **falla**.
- Dado un `Info.plist` declarado en el manifiesto pero ausente, cuando corre el gate, entonces
  **falla** en vez de saltárselo.
- Dado un `@Suite` nuevo en `Domain/` o `Vectors/` sin añadir a mano, cuando corre `verify-domain.sh`,
  entonces **falla nombrándolo** — y hoy se ignora en silencio.
- Dado el árbol actual sin tocar código de producto, cuando corren los dos gates, entonces **verdes**.

## Implementation Notes

**Sección 6 — el criterio pasa a ser el tipo, y el nombre se queda de respaldo declarado.** De cada
fichero de `UI/` y `App/` se derivan los identificadores declarados como `SessionStore` o
`SettingsStore` (`let settingsStore: SettingsStore`, `init(store: SessionStore, …)`,
`func f(_ settings: SettingsStore)`, `let s = SessionStore(…)`), y esos son los receptores de ese
fichero. Los tipos ANIDADOS quedan fuera (`SettingsStore.StrideOutcome`, `SessionStore.MotionBlock`,
`SessionStore.ScenePhase` son valores, no stores), o la pantalla real de Ajustes habría dejado de
pasar. **La lista de lo prohibido no cambia** —las mismas asignaciones y los mismos pasos internos
de siempre—: lo que cambia es a quién se le aplica, que es lo que pedía la Intent ("hacer honestas
las reglas que hay, no añadir reglas nuevas").

El sufijo `store`/`Store` **se conserva como respaldo**, y no por inercia: un receptor al que se
llega a través de otro objeto (`root.sessionStore.isReconciling`, que el arnés ya cubría) no se
declara en el fichero que lo usa, así que su tipo no es derivable línea a línea. Un receptor tipado
se caza siempre; uno encadenado, solo si además se llama como se llama. Está escrito así en el
comentario de la sección y registrado en `deferred-work.md`: es justo lo que la Intent pide cuando
una regla léxica no alcanza el invariante.

**12c — el target sale del manifiesto, no de una constante.** Se añadió `parse_target_settings`
(hermana de `parse_sources`), que emite `target⇥clave⇥valor` de todo lo que cuelga de un target. El
target de la app se identifica por `type: application`, no por llamarse `WalkTracker`: un target de
app renombrado no deja la comprobación colgando. Sin ningún `type: application` el gate **falla**,
en vez de no tener a quién preguntar.

**12b — los dos orígenes de la lista son estrictos.** Si el manifiesto declara un `INFOPLIST_FILE`,
tiene que existir; si no declara ninguno y entra el respaldo, los dos del producto tienen que
existir, porque si no tampoco se miró nada. El respaldo se conserva (el arnés monta árboles mínimos
sin manifiesto), y el fixture pasa a traer **los dos** `Info.plist`, como el árbol real.

**B-6 — el hallazgo que la Code Map pedía comprobar.** Hay **16** `@Suite` en
`WalkTrackerTests/{Domain,Vectors,Scenarios}` y la lista tenía **15**: `WorkoutRecordTests`
(`Domain/WorkoutRecordTests.swift`) **llevaba sin ejecutarse en el gate desde que existe**. Al
derivar la lista, el gate lo nombró solo. Entra en `DOMAIN_SUITES`, así que el conteo de la suite de
dominio **sube**, no baja.

La derivación va **antes** del `xcodegen`/`xcodebuild` a propósito: un suite sin listar se ve en
segundos, no tras un build entero. `--suites-only [raíz]` ejecuta solo el inventario, y es lo que
usa su arnés.

**Por qué un arnés nuevo.** `verify-domain.sh` no tenía camino rojo propio; el que invocaba
(`Scripts/vectors/red-path-tests.sh`) es del arnés JS de los vectores. `Scripts/verify-domain-tests.sh`
sigue la convención del repo (`X.sh` / `X-tests.sh`) y **lo ejecuta el propio gate**, para que no
acabe siendo otro script que nadie recuerda correr — que es el defecto que este chore cierra.

**Fuera de la lista de tareas, por rendimiento:** la búsqueda del colorset usa `-prune` y no
`-not -path`. Con `-not -path`, `find` descendía en `node_modules/` (324 MB) en cada build. Medido
en caliente sobre el árbol real: gate anterior 5,1 s, gate nuevo 4,8 s.

## Spec Change Log

## Review Triage Log

## Design Notes

**Por qué los cuatro juntos.** Son el mismo defecto con cuatro caras: una comprobación léxica que se
presenta como invariante. Arreglarlas por separado repetiría el diagnóstico cuatro veces, y el arnés
que las prueba es el mismo.

**El caso de la sección 6 es el que más enseña.** El invariante es *"la vista no escribe el estado del
store"*. La regla comprueba *"el receptor se llama algo acabado en Store"*. Entre las dos frases cabe
un rename, y lo único que hoy lo impide es un comentario pidiendo por favor que no se haga. Un
comentario no es un gate.

**Y B-6 ya cobró su pieza.** Durante la retro del Epic 2 se ejecutó un fichero con dos `@Suite`, corrió
solo el primero y devolvió `TEST SUCCEEDED` sin haber ejecutado el test que se estaba investigando.
El fallo no fue de quien lo invocó: fue de un mecanismo que selecciona por suite y depende de que
alguien se acuerde.

**Lo que este chore no promete.** Un gate de una línea a la vez sigue teniendo límites —una expresión
partida en dos líneas lo esquiva, y eso ya está registrado—. La diferencia no es que pase a ser
infalible, es que **deje de afirmar que lo es**.

## Verification

**Commands:**
- `bash Scripts/check-project-shape.sh` y `check-project-shape-tests.sh` — verdes, con los casos nuevos.
- `bash Scripts/verify-domain.sh` — verde, y ejecutando **todos** los suites de dominio y vectores.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` — TEST SUCCEEDED, y el
  conteo **no baja**: si baja, el gate de dominio estaba ejecutando menos de lo que creía.
- **Mutación obligatoria, una por regla:** `settings.save()` en una vista; la clave del acento movida
  al target de la extensión; un `Info.plist` declarado y borrado; y un `@Suite` nuevo sin listar. Las
  cuatro deben fallar, y **hoy las cuatro pasan**. Revertir cada una.

**Manual checks:** ninguno.
