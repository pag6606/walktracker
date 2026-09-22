---
title: 'early_bird — el texto deja de mentir, con su divergencia declarada'
type: 'chore'
created: '2026-09-21'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: 'e9f873ac5d592fb4043a21e8bd0e13a01bb4cb36'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-a5-reconciliar-planificacion.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `WalkTracker/Resources/achievements.json:13` describe `early_bird` como *"Camina antes
de las 7:00"*, pero su regla es `{ "metric": "startHourLocal", "threshold": [5, 7], "comparison":
"between" }` y **`between` es inclusiva en los dos extremos**: la franja llega hasta las **07:59**.
El texto que Paul lee contradice la regla que desbloquea el logro, y por debajo: quien camine a
las 07:30 lo desbloquea creyendo que no debía. Es **el único desfase del producto que ve un
usuario**. Paul decidió el 2026-09-20 corregir **el texto, no la regla**; al aplicarlo,
`verify-domain.sh` se puso en rojo con `achievements.json#early_bird: description 'Camina antes de
las 8:00' ≠ referencia 'Camina antes de las 7:00'`, y el cambio se revirtió. El contenido
congelado de AD-5 no es una convención: es una regla mecánica, comparada contra la referencia de
la v3 en `Scripts/vectors/run-js.js`.

**Approach:** Aplicar el texto **declarando la divergencia**, por el mismo principio con el que el
gate ya lista como esperadas las divergencias de hora local y de categoría WMO: una lista
explícita, con fecha y razón, que el gate **imprime al correr**. La divergencia se registra
además en la tabla de AD-6 del spine, que es su fuente.

## Boundaries & Constraints

**Always:**
- La divergencia es **una lista declarada dentro del gate**, con clave, campo, fecha y razón, y se
  **imprime en cada ejecución** junto a las divergencias de vector que ya se imprimen. Lo que
  está exento se ve.
- La excepción es **por logro y por campo** (`early_bird` · `description`). No exime el campo
  `description` de los otros trece, ni los campos `name`/`icon` de `early_bird`.
- Camino rojo obligatorio en `Scripts/vectors/red-path-tests.sh`, y con **dos** casos, no uno:
  (a) con la divergencia declarada, el texto nuevo **pasa**; (b) **otro** cambio de texto —otro
  logro, u otro campo del mismo— **sigue rompiendo**. Sin (b) la excepción sería un cheque en
  blanco.
- La regla del logro **no se toca**: `threshold` sigue siendo `[5, 7]` y `comparison` sigue siendo
  `between`. El logro se desbloquea exactamente igual que antes; solo deja de mentir.

**Never:**
- **No se mete en el enum `VectorDivergence`** (`WalkTrackerTests/Vectors/VectorHarness.swift:65-68`)
  ni en `DIVERGENCE_FAMILIES` (`Scripts/vectors/lib.js:23-31`). Esas dos son divergencias de
  **conducta de vector**, con funciones y logros afectados; ésta es de **texto de catálogo** y no
  tiene función ni vector. Mezclarlas ensucia los dos mecanismos y haría que un lector creyera
  que `early_bird` diverge en su evaluación por partida doble.
- No se toca `night_walker`: *"Camina después de las 21:00"* **sí** es fiel a `[21, 23]`.
- No se cambia el motor de logros ni se porta ningún vector: eso es la 3.2.
- No se edita `motivation.js` ni el catálogo de la referencia v3. La referencia es la referencia;
  lo que se declara es que nos apartamos de ella a propósito.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Salida esperada | Error |
|---|---|---|---|
| El texto decidido | `early_bird.description = "Camina antes de las 8:00"` | el gate **pasa** y **imprime** la divergencia | N/A |
| Otro logro | `first_5km.description` cambiada | **rompe** — la excepción es por logro | exit ≠ 0 |
| Otro campo | `early_bird.name` cambiado | **rompe** — la excepción es por campo | exit ≠ 0 |
| Revertido al texto viejo | `early_bird.description = "Camina antes de las 7:00"` | **rompe**: hay una divergencia declarada que ya no se cumple, igual que una exención sobrante | exit ≠ 0 |
| Divergencia sin razón | entrada en la lista sin fecha o sin motivo | **rompe** | exit ≠ 0 |

</frozen-after-approval>

## Code Map

**Dónde se compara el catálogo contra la v3**
- `Scripts/vectors/run-js.js:252-269` — lee `achievements.json`, obtiene
  `Motivation.getAchievementsCatalog()` y compara, en orden: las **claves** (línea 257), y para
  cada logro `name` (:263), `icon` (:264) y `description` (:265) con `squash()` que quita espacios
  —está ahí porque `achievements.md` escribe "30 °C" y la v3 "30°C"—. Aquí entra la excepción.
- `Scripts/vectors/run-js.js:271+` — el veredicto ya imprime un bloque
  `"Divergencias esperadas (domain.js falla a propósito; el vector lleva el valor de Swift)"`.
  La divergencia de catálogo se imprime **junto a él y distinguida**, no dentro: no es el mismo
  tipo de cosa.

**Lo que NO es el mecanismo adecuado, y por qué**
- `Scripts/vectors/lib.js:22-31` — `DIVERGENCE_FAMILIES` con exactamente dos entradas, cada una
  con `functions` y `achievements`. Su comentario dice *"Las únicas dos familias de divergencia
  declaradas (AD-6)"*. Esa frase **se queda verdadera**: sigue habiendo dos familias de
  divergencia **de vector**. La nueva no lo es. Si se añadiera aquí, `early_bird` aparecería con
  dos divergencias y la segunda no afecta a ningún vector.
- `WalkTrackerTests/Vectors/VectorHarness.swift:62-68` — `enum VectorDivergence { case localTime,
  wmoCategory }`, con la regla de que en Swift **el vector divergente debe pasar**. Un texto de
  catálogo no tiene vector que pase o falle.

**El camino rojo a extender**
- `Scripts/vectors/red-path-tests.sh:165-175` — el molde exacto: `fresh_copy`, copiar
  `achievements.json`, `mutate` con una expresión JS sobre `d.achievements.find(...)`, y
  `assert_run "<nombre>" nonzero "<needle>" -- "$RUN_JS" --vectors … --catalog <copia>`. Ya hay
  casos para `name` e `icon` cambiados. Se añaden los de la matriz, **incluido el caso verde**,
  que hoy ese arnés no tiene para el catálogo.

**El dato de producción**
- `WalkTracker/Resources/achievements.json:13` — la línea a cambiar. `schemaVersion` **no se
  toca**: no cambia la forma, solo un texto.
- `_bmad-output/specs/spec-walktracker-ios/achievements.md:29-30` — ya dice que `[5, 7]` es
  05:00–07:59, con la enmienda del 2026-09-20. El texto nuevo lo hace coherente, no lo contradice.

**La fuente de la declaración**
- `ARCHITECTURE-SPINE.md` AD-6 (tabla de categorías en las líneas 113-117) — donde vive la
  declaración de qué se aparta de la v3 y por qué. La divergencia de catálogo entra ahí; el gate
  es el que la hace cumplir.

**Deriva de documentación que se arregla de paso**
- `_bmad-output/implementation-artifacts/sprint-status.yaml:80` — la 3.1 está en `review`, que es
  **deliberado** (sus checks manuales en el iPhone no se han ejecutado), pero **sin comentario que
  lo diga**, al revés que la 2.1, que sí lo tiene en las líneas 68-69. Sin él se lee como deriva:
  el compilador de contexto del Epic 3 lo señaló como incoherencia el 2026-09-21. Se añade el
  comentario, con el mismo formato que el de la 2.1.

## Tasks & Acceptance

**Execution:**
- [x] `WalkTracker/Resources/achievements.json` -- `early_bird.description` →
  `"Camina antes de las 8:00"` -- la decisión de Paul del 2026-09-20.
- [x] `Scripts/vectors/run-js.js` -- lista declarada de divergencias de texto de catálogo (clave,
  campo, fecha, razón), aplicada en la comparación y **impresa en cada ejecución**, distinguida
  del bloque de divergencias de vector -- una exención invisible es una mentira.
- [x] `Scripts/vectors/run-js.js` -- que una divergencia declarada **que ya no se cumple** rompa,
  pidiendo que se borre -- el mismo criterio bidireccional que B-6 aplica al inventario de suites
  y el A-7 a sus exenciones.
- [x] `Scripts/vectors/red-path-tests.sh` -- los cinco casos de la matriz, incluido el **verde**
  del texto decidido -- el arnés del catálogo hoy solo tiene rojos.
- [x] `ARCHITECTURE-SPINE.md` -- registrar la divergencia en AD-6, nombrando logro, campo, fecha y
  razón -- el gate la hace cumplir; el spine es donde se lee por qué existe.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` -- cerrar la entrada de la línea 127
  con `**CERRADO el <fecha>` -- es exactamente lo que pedía.
- [x] `_bmad-output/implementation-artifacts/sprint-status.yaml` -- comentario que explique por qué
  la 3.1 está en `review`, con el formato del de la 2.1 -- que no se lea como deriva.

**Acceptance Criteria:**
- Dado el texto nuevo **sin** declarar la divergencia, cuando se corre `verify-domain.sh`,
  entonces **rompe** con el mensaje de `description ≠ referencia`. Se comprueba **antes** de
  declararla: si no rompe, el gate no comprueba lo que dice y el chore no tiene sentido.
- Dado el texto nuevo **con** la divergencia declarada, entonces `verify-domain.sh` sale
  **verde** y su salida **nombra** la divergencia de `early_bird` · `description`.
- Dado `bash Scripts/vectors/red-path-tests.sh`, entonces todos los casos pasan y el conteo
  **crece** respecto al actual.
- Dado que se revierte `achievements.json` al texto viejo dejando la divergencia declarada,
  entonces el gate **rompe** pidiendo que se borre la declaración.
- Dado `bash Scripts/check-spec-shape.sh`, entonces verde.

## Implementation Notes

**El rojo se comprobó primero, y es lo que da sentido al chore.** Con el texto nuevo puesto y sin
declarar nada, `run-js.js` —el paso 2 de `verify-domain.sh`— salió en rojo con el mensaje exacto que
la Intent predecía: `achievements.json#early_bird: description 'Camina antes de las 8:00' ≠
referencia 'Camina antes de las 7:00'`, `exit 1`, 109 vectores. Sin esa comprobación previa, el
verde de después no demostraría nada.

**La tercera clase se llama `CATALOG_TEXT_DIVERGENCES` y vive en `run-js.js`, no en `lib.js`.** Está
a propósito **fuera** de `lib.js`: `DIVERGENCE_FAMILIES` se exporta desde allí porque la consumen dos
scripts y describe conducta de vector; esta lista solo la usa la comparación del catálogo, que vive
entera en `run-js.js`. Dejarla junto a lo que la aplica evita exactamente la confusión que las
Boundaries prohíben —que un lector la tome por una tercera familia de vector—, y el doc comment de la
constante lo dice por escrito, con el argumento de por qué no se mezcla.

**La comparación se reescribió como una tabla de campos, no como tres `if`.** Antes eran tres líneas
sueltas (`name`, `icon`, `description`, esta última con `squash()`); ahora `CATALOG_TEXT_FIELDS`
declara los tres con su accesor a la referencia y si se comparan con espacios o sin ellos, y el bucle
busca la exención **por logro y por campo**. El mensaje de rojo de los campos no exentos es
**literalmente el mismo de antes** —lo confirman los dos casos rojos de `name` e `icon` que ya
existían en el arnés, que pasan sin tocarles el needle—, así que ningún rojo cambió de forma.

**Lo que se imprime, y por qué siempre.** El bloque va **después** del de divergencias de vector y
**fuera** de su guarda `!args.quiet || failures.length`: se imprime en cada ejecución, también en
verde y también con `--quiet`. La razón es la de la Intent —una exención invisible es una mentira—,
y `--quiet` hoy no lo usa nadie (ningún script del repo lo pasa), así que no se pierde nada. La marca
es `≠` frente al `≈` de las divergencias de vector: mismo sitio, distinta cosa. La línea final del
veredicto también lo dice (`Catálogo: igual a la referencia salvo 1 divergencia(s) de texto
declarada(s)`).

**Bidireccional, con el mensaje que pide el borrado.** Si el catálogo vuelve a coincidir con la
referencia en un campo declarado, la entrada pasa a estado `sobrante`, se imprime con `✗` y el gate
falla pidiendo que se borre de `CATALOG_TEXT_DIVERGENCES` **y de la tabla de AD-6** — los dos sitios,
porque son los dos que mentirían. Es el criterio de B-6 con el inventario de suites y el del A-7 con
sus exenciones, aplicado aquí.

**Dos casos rojos más de los cinco de la matriz, por el mismo precio.** La fila "divergencia sin
razón" de la matriz dice *"sin fecha o sin motivo"*, y el arnés cubre **las dos mitades**: son dos
mutaciones distintas y cuestan una línea cada una. El arnés pasa de **19 a 25 casos**.

**Cómo se prueba en rojo una lista que vive dentro del gate.** Las otras cuatro filas de la matriz se
mutan por `--catalog`, que ya existía. Ésta no: la lista es código del propio script. Se resuelve
copiando `run-js.js` y `lib.js` a un temporal, mutando **la copia** con un `node -e` que **falla
ruidosamente si el patrón no casa** —un caso rojo que se vuelve no-op sin avisar no prueba nada— y
pasándole `--root "$ROOT"` para que la copia siga encontrando la referencia v3 del árbol real. El
árbol real solo se lee, y el `fingerprint` del final del arnés lo confirma como siempre.

**Límite conocido, declarado en vez de anunciado como cubierto (B-5).** La exención es por logro y por
campo, que es lo que la Intent pide, pero **no fija el valor**: con la divergencia declarada,
`early_bird.description` podría pasar a `"Camina antes de las 9:00"` y el gate saldría verde
nombrándolo. Lo comprobado y probado es lo que la Intent acota —otro logro u otro campo siguen
rompiendo, y revertir al texto de la v3 también—; pinchar el valor exacto habría añadido un quinto
campo a la lista que las Tasks no enumeran (*"clave, campo, fecha y razón"*). Queda dicho aquí, y lo
que sí cubre el rojo es que el cambio **se vea**: cualquier texto distinto se imprime con su valor en
cada ejecución.

**La regla no se tocó, y eso se lee en el diff.** `WalkTracker/Resources/achievements.json` cambia
**una línea y un campo**: `description`. `threshold: [5, 7]`, `comparison: "between"`, `metric`,
`name`, `icon` y `schemaVersion` quedan idénticos. `motivation.js` y el catálogo de la referencia no
se tocan, y `night_walker` tampoco.

**Deriva que este chore CREA y no arregla: registrada, no resuelta.** Cambiar el texto deja
desfasadas tres afirmaciones del paquete `specs/spec-walktracker-ios/`: la assumption **A-3** de
`SPEC.md:119` y la cabecera de `achievements.md:3` dicen que el catálogo se reutiliza *"íntegro, sin
cambios de contenido"*, y la **columna de descripción** de `achievements.md:18` sigue leyendo *"Camina
antes de las 7:00"* (su columna de regla y su nota del 2026-09-20 ya dicen 05:00–07:59, así que la
fila se contradice a sí misma). Las Tasks de este chore enumeran siete ficheros y ninguno es del
paquete SPEC; ampliarlo por cuenta propia es exactamente lo que A-5 tuvo que pedirle permiso a Paul
para hacer. Y no es cosmético: el compilador de contexto de épica lee ese paquete. Queda con entrada
propia y destino en `deferred-work.md` (la 3.2, o un chore de reconciliación del paquete SPEC), que
es la regla D4 y la lección L2.

## Spec Change Log

**1 · Sin cambios sobre el bloque congelado.** Las cinco filas de la I/O & Edge-Case Matrix se
implementaron tal cual y las cinco tienen su caso en `red-path-tests.sh`. Las únicas dos adiciones
sobre lo escrito son **ampliaciones, no desvíos**: la fila 5 se probó en sus **dos** mitades (sin
fecha y sin razón, un caso cada una) y se declara arriba el límite de que la exención no fija el
valor del campo. Nada de la Intent se renegoció.

**2 · Un incidente de entorno durante la verificación, sin efecto en el resultado.** A mitad del
chore, `CATALOG_TEXT_DIVERGENCES` apareció en disco como `[]` —la lista vaciada, el resto del fichero
intacto— por un cambio **externo** a la ejecución (no hay hooks en `.claude/`, y el arnés solo escribe
en copias temporales, como confirma su `fingerprint`). El estado fue transitorio y el fichero volvió
solo a su contenido correcto. Se anota porque **sirvió de comprobación independiente del rojo**: con
la lista vacía y el texto nuevo puesto, `run-js.js` falla con el mensaje de `description ≠
referencia`, que es la primera fila de los Acceptance Criteria. Todas las órdenes de verificación de
abajo se repitieron **después**, sobre el árbol ya estable.

## Review Triage Log

## Design Notes

**Por qué una tercera clase de divergencia y no un caso más del enum.** Las dos que existen
responden a la pregunta *"¿qué vector falla en `domain.js` a propósito?"* y tienen funciones y
logros afectados. Esta responde a otra: *"¿en qué se aparta el contenido del catálogo del de la
referencia?"*. No tiene vector, no tiene función, y `domain.js` no falla por ella. Meterla en
`DIVERGENCE_FAMILIES` haría que `early_bird` figurara con dos divergencias cuando su **conducta**
solo diverge en una: la hora local. Un lector que buscara por qué `early_bird` diverge encontraría
dos razones y una sería falsa.

**Por qué el texto y no la regla.** Estrechar el `threshold` a `[5, 6]` haría el texto verdadero,
pero **cambiaría qué desbloquea el logro**: alguien que hoy lo tiene desbloqueado por una caminata
a las 06:30 seguiría teniéndolo —los desbloqueos son irrevocables—, pero la misma caminata de
mañana ya no lo daría. Cambiar la regla de un logro irrevocable por un problema de redacción es
desproporcionado. Decisión de Paul del 2026-09-20.

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` -- esperado: **rojo antes** de declarar la divergencia con el
  texto nuevo puesto; **verde después**, nombrando la divergencia.
- `bash Scripts/vectors/red-path-tests.sh` -- esperado: todos verdes, conteo creciente.
- `bash Scripts/check-project-shape.sh` -- esperado: sigue verde, sin tocar.
- `bash Scripts/check-spec-shape.sh` -- esperado: verde.

**Manual checks:**
- Mutación propia: borrar la entrada de la lista de divergencias y comprobar que el gate vuelve a
  romper por `early_bird`. Restaurar y confirmar con `git status`.
