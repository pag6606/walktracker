---
title: 'B-3 — Una zancada que desborda la fórmula deja de estrellar la app'
type: 'bugfix'
created: '2026-09-20'
baseline_commit: '63ba220277c802eef6d797e5935a62716a4e5b55'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-retro-2026-09-20.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** una zancada enorme pero finita se guarda y **estrella la app en la siguiente
caminata**, en un `catch` que el código declara *"Inalcanzable"*.

La cadena, localizada (retro del Epic 2, hallazgo D3):

1. `AppSettings.isRepresentableStride(_:)` comprueba que **la entrada** es finita — y nada más.
   Se creó para atajar el desbordamiento del **parseo** ("400 dígitos dan `inf`"), no el del cálculo.
2. `MetricsCalculator.distanceM` valida sus tres entradas y **no valida su resultado**.
3. `rounded(_:fractionDigits:)` multiplica por 100 para redondear a dos decimales: ahí es donde
   `steps × strideM` por encima de ~1,8e306 se convierte en `inf`.
4. `paceSecPerKm` sí rechaza una distancia no finita y lanza.
5. `Session.metrics(at:)` atrapa ese lanzamiento con un `preconditionFailure` comentado como
   *"Inalcanzable: el agregado garantiza pasos ≥ 0, zancada > 0 y finita…"*. La garantía es cierta y
   **no basta**: cubre los factores, no el producto.

Con `1e307` la app se cae en **cada** caminata hasta reinstalar. Ajustes sí abre, así que "Usar el
valor por defecto" rescata — pero hay que saberlo.

**Enfoque:** cerrar la frontera de escritura con un límite **derivado, no inventado** —la zancada
mayor para la que la fórmula de distancia sigue siendo representable—, hacer que el calculador valide
su propio resultado, y que el `catch` deje de afirmar una imposibilidad que acabamos de alcanzar.

## Boundaries & Constraints

**Always:**
- **El límite superior se deriva, no se elige.** Sale de la aritmética real: el mayor `Double` finito,
  el factor 100 del redondeo a dos decimales, y el mayor número de pasos que el agregado puede
  contener. Queda escrito de dónde sale cada factor. **No es una regla de producto.**
- **Un calculador no devuelve `inf`.** `distanceM` valida su propio resultado y lanza con su campo,
  como ya hace `estimateSteps` cuando el producto no cabe.
- **El `catch` de `metrics(at:)` deja de afirmar que es inalcanzable**, porque no lo es. Si vuelve a
  alcanzarse, la app **no se cae**: degrada y lo registra.
- **La regla que Paul fijó en la 2.3 se respeta:** fuera de 0,3–1,2 m se **avisa y se guarda**. El
  rechazo duro sigue reservado a lo que no es un número, a `≤ 0` y —ahora— a lo que no cabe en la
  fórmula. Una zancada absurda pero representable (50 m) se sigue guardando con su aviso.
- El motivo de rechazo que ve Paul distingue "no cabe" de "no es mayor que cero": esos dos casos ya
  tienen resultados distintos y no se mezclan.
- Los gates y la suite siguen en verde.

**Never:**
- Inventar un máximo "razonable" de producto (10 m, 100 m): eso renegociaría la decisión de la 2.3,
  que dice avisar y no bloquear. El único techo nuevo es el de la aritmética.
- Cambiar el redondeo a dos decimales de la distancia: es equivalencia con la v3 (AD-6).
- Tocar el esquema de `settings.json` ni su versión.
- Arreglar aquí B-2 (el contraste del mensaje de error) ni lo que quedó abierto de B-1 (que nadie
  pinta el estado de lectura fallida).

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Zancada normal | `0,670` | se guarda | — |
| Absurda pero representable | `50` | **se guarda, con el aviso de rango humano** (decisión de la 2.3) | aviso, no bloqueo |
| Justo en el límite representable | el mayor valor que la fórmula soporta | se guarda | — |
| Un paso por encima del límite | el menor valor que ya no cabe | **rechazado**, con el motivo de "no cabe" | mensaje, no "guardada" |
| El caso del crash | `1e307` (308 dígitos) | **rechazado** en la frontera; ninguna caminata lo ve | mensaje |
| Ya guardada de antes | un `settings.json` con una zancada que hoy no cabría | se lee como **sin configurar** y la caminata usa el default | `log` |
| Cálculo con el límite | sesión con muchos pasos y la zancada máxima | `distanceM` devuelve un número finito, nunca `inf` | — |
| Resultado no representable | se fuerza un producto que no cabe | `distanceM` **lanza** con su campo, no devuelve `inf` | `DomainError.invalidValue` |
| `metrics(at:)` ante un lanzamiento | se fuerza el caso | **no se cae**: degrada y lo registra | — |

</frozen-after-approval>

## Code Map

- `Domain/Ports/AppSettings.swift:111-113` `isRepresentableStride(_:)` — hoy es `meters.isFinite` y
  nada más. **Aquí va el límite derivado.** Su doc (`:130-131`) ya dice que separa "no cabe" de "no es
  mayor que cero": el vocabulario existe, solo falta que "no cabe" signifique lo que dice.
- `Domain/Metrics/MetricsCalculator.swift:35-42` `distanceM` — valida las tres entradas y devuelve
  `rounded(steps * strideM, fractionDigits: 2)` **sin mirar el resultado**.
- `Domain/Metrics/MetricsCalculator.swift:72-75` `rounded` — `(value * 100).rounded() / 100`: **el
  sitio exacto del desbordamiento**, porque el ×100 desborda antes que el producto.
- `Domain/Metrics/MetricsCalculator.swift` `estimateSteps` — **el precedente a imitar**: ya lanza
  `.invalidValue(field: "steps")` cuando el producto no cabe en `Int`. Misma forma, otro campo.
- `Domain/Session/Session.swift:373-378` — el `catch` con `preconditionFailure` y el comentario
  *"Inalcanzable"* que enumera garantías sobre los **factores**, no sobre el producto.
- `Domain/Session/Session.swift:140-143` `validateStride` — `isFinite` y `> 0`. Es la frontera del
  agregado; decidir si el límite nuevo vive aquí, en `AppSettings`, o en ambos, y **escribir por qué**.
- `WalkTracker/Application/SettingsStore+Stride.swift` — ya tiene el resultado observable de rechazo
  por "no cabe" (`tooLarge` o equivalente) y su texto. Reutilizarlo.
- `WalkTracker/Adapters/Persistence/SettingsFileAdapter.swift` — la lectura ya trata una zancada
  inválida como "sin configurar" sin costar la ventana de frases. Comprobar que el límite nuevo entra
  por esa misma puerta tolerante, no por la que rechaza.
- `WalkTrackerTests/Domain/AppSettingsTests.swift` y `Application/SettingsStoreStrideTests.swift` — el
  argumento mayor que prueban hoy es `"3,0"`, que solo dispara el aviso. **Ese es el hueco** (V4).
- `Scripts/verify-domain.sh` — `AppSettingsTests` ya está en su lista; ampliarlo entra gratis. Un
  suite nuevo hay que añadirlo a mano, y **un fichero puede tener dos `@Suite`** (B-6 sigue abierto).

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Ports/AppSettings.swift` — el límite derivado en `isRepresentableStride`, con los
      factores de los que sale documentados uno a uno.
- [x] `Domain/Metrics/MetricsCalculator.swift` — `distanceM` valida su resultado y lanza con su campo,
      con la forma que ya usa `estimateSteps`.
- [x] `Domain/Session/Session.swift` — el `catch` de `metrics(at:)` deja de ser `preconditionFailure`;
      degrada y registra. Actualizar el comentario, que hoy afirma algo falso.
- [x] `WalkTrackerTests/` — la matriz entera, con **el límite exacto y su vecino** por ambos lados, y
      el caso `1e307` del crash.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` — lo que no se cierre aquí.

**Acceptance Criteria:**
- Dado `1e307` en el campo de zancada, cuando se pulsa Guardar, entonces se **rechaza** con el motivo
  de "no cabe" y ninguna caminata posterior se ve afectada.
- Dada la zancada máxima que sí cabe, cuando se completa una caminata con muchos pasos, entonces la
  distancia es un número **finito** y la app no se cae.
- Dado `50`, cuando se pulsa Guardar, entonces **se guarda con el aviso**, como decidió la 2.3.
- Dado un `settings.json` con una zancada que ya no cabe, cuando arranca la app, entonces se lee como
  sin configurar y **no se pierde la ventana de frases**.

## Implementation Notes

**El límite vive en `MetricsCalculator`, y se comprueba en dos fronteras.** La constante es
`MetricsCalculator.maxRepresentableStrideM` —no `AppSettings`— porque los factores de los que sale
son suyos: el `×100` del redondeo (`distanceFractionDigits`, que ahora lee `distanceM` en vez de un
`2` a mano, para que la derivación y el cálculo no puedan divergir) y `maxSteps`, el tope del
agregado. Ponerla en `AppSettings` habría obligado a `Session` a nombrar un tipo de `Ports/` que ya
depende de él. La derivación entera, factor a factor:

```
maxRepresentableStrideM = (Double.greatestFiniteMagnitude / 100) / 2⁶⁴ ≈ 9,745e286
```

**Se comprueba en las dos fronteras a propósito, y no es la misma pregunta dos veces.**
`AppSettings.isRepresentableStride` existe para que el **motivo** que ve Paul sea el verdadero ("no
cabe", no "no es mayor que cero") **antes** de tocar nada; `Session.validateStride` es la del
agregado, y es lo que garantiza que ninguna sesión pueda nacer con una zancada cuya distancia no se
puede calcular —ni por `start`, ni por `restore`, ni desde `formulas.json`—. Estar en
`validateStride` es además lo que hace que un `settings.json` guardado **antes** de este arreglo
entre por la puerta **tolerante** de `AppSettings` (se lee como "sin configurar", sin apartar el
fichero y sin costar la ventana de frases) y no por la que rechaza: esa fila de la matriz sale gratis
de dónde vive el tope, no de un caso especial.

**El borde es exacto, y lo que se prueba es la propiedad, no el número.** Con
`maxRepresentableStrideM` y 2⁶⁴ pasos la fórmula da un número; con su `.nextUp`, `inf`. El test lo
afirma por los dos lados, así que si la aritmética de `rounded` cambiara, el test lo dice.

**`distanceM` valida su resultado con la forma de `estimateSteps`**: `guard distance.isFinite else {
throw .invalidValue(field: "distanceM") }`, con el campo del **valor que no cabe** —como
`estimateSteps` lanza con `steps`—. Sus tres guardas de entrada no cambian: dejarlas como estaban es
lo que mantiene alcanzable —y por tanto probada— la guarda del resultado.

**La suma de `metrics(at:)` también desborda, y no la mira `distanceM`.** `systemDistanceM +
estimados` puede dar `inf` con los dos sumandos finitos y la zancada dentro del tope. Ahí hay ahora
un `guard` propio, y es exactamente el caso con el que el test fuerza la degradación: el agregado
cumple **todas** sus invariantes y aun así el cálculo es imposible, que es justo lo que el
`preconditionFailure` afirmaba que no podía pasar.

**El `catch` degrada por métrica, no en bloque.** Devuelve distancia 0, sin ritmo (AD-4: una métrica
ausente es ausente) y **la cadencia sí calculada**, porque no depende de la distancia y no hay razón
para tirar la métrica buena con la que falló. Lo marca `SessionMetrics.degraded`, un campo nuevo con
valor por omisión `false` (ninguna construcción existente cambia): es lo que distingue una
degradación de una caminata sin pasos, que tiene los mismos ceros.

**Lo que el dominio no puede hacer: registrar en `OSLog`.** `Domain/` solo importa `Foundation`
(AD-3) y el proyecto hace entrar las capacidades por un puerto (`ClockPort`, `RandomPort`), así que
un `Logger` ambiental aquí sería un precedente nuevo y una renegociación de arquitectura dentro de un
chore. El registro que el dominio sí puede llevar es el valor (`degraded`); quién lo escriba en el
log queda en `deferred-work.md` con destino **B-9**. Donde sí hay `Logger` es en el adapter, y ahí sí
se registra: `SettingsFileAdapter.decode` dice cuando el fichero traía una zancada que la frontera se
comió —la fila "ya guardada de antes" de la matriz—, sin apartar nada.

**Los dos mensajes de Ajustes no se tocaron.** `StrideRejection.tooLarge` y su texto ya existían de
la 2.3 y ya decían "ese número es demasiado grande para una zancada": lo único que cambia es que
ahora `1e307` llega a ese motivo en vez de al del cero. El orden de `saveStride` ya era el correcto
(`isRepresentableStride` **antes** de `setStrideM`), así que no hubo que reordenar nada.

**Mutación, las dos que pedía la spec.** Con `isRepresentableStride` de vuelta a `meters.isFinite`:
3 casos en rojo (`El borde es EXACTO`, `El caso del crash: 1e307…` en las dos suites, con el
`strideOutcome` cayendo a `.rejected(.notPositive)`, que es exactamente el mensaje equivocado que
esto viene a arreglar). Con el `catch` de vuelta a `preconditionFailure`:
`Domain/Session.swift:413: Fatal error: … invalidValue(field: "distanceM")` y `Restarting after
unexpected exit, crash, or test timeout` — el proceso muere, que era lo que había que demostrar.

**Cobertura, contada por nombre en el `.xcresult`:** 635 casos en 50 suites (622 antes), los **13**
nuevos ejecutados y en verde. `MetricsScenarios` y `AppSettingsTests` ya estaban en
`Scripts/verify-domain.sh`, así que los 11 de `Domain/` entran en el gate sin tocar la lista;
`SettingsStoreStrideTests` es de `Application/` y lo ejecuta la suite completa, como fijó la 2.3.

## Spec Change Log

## Review Triage Log

## Design Notes

**Por qué un límite derivado y no uno "razonable".** La 2.3 decidió que fuera del rango humano se
avisa y se guarda: es la app de Paul y su zancada. Poner un techo de producto aquí renegociaría esa
decisión por la puerta de atrás. El único techo legítimo es el que impone la aritmética: por encima de
él la fórmula no produce un número, y eso no es una preferencia.

**Por qué tres arreglos y no uno.** Cerrar solo la frontera dejaría el `catch` mintiendo y el
calculador devolviendo `inf` a quien lo llame desde otro sitio. Cerrar solo el calculador convertiría
el crash en un crash distinto, porque `metrics(at:)` atrapa y revienta. Los tres juntos son defensa en
profundidad: la frontera evita el caso, el calculador no miente, y el agregado no mata el proceso si
alguna vez nos equivocamos otra vez.

**El precedente está en casa.** `estimateSteps` ya lanza cuando el producto no cabe en `Int`, con su
campo. Este arreglo es el mismo razonamiento aplicado al producto que no cabe en `Double`.

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` — verde, y los vectores de equivalencia intactos: el redondeo a dos
  decimales no cambia.
- `bash Scripts/check-project-shape.sh` y `check-project-shape-tests.sh` — verdes.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` — TEST SUCCEEDED.
- **Mutación obligatoria:** con `isRepresentableStride` de vuelta a `meters.isFinite`, el test del
  caso `1e307` **debe fallar**. Y con el `catch` de vuelta a `preconditionFailure`, el test de la
  degradación **debe caer el proceso**.
- **Contar los casos nuevos por nombre en el `.xcresult`**, no conformarse con `TEST SUCCEEDED`.

**Manual checks:** ninguno. Se reproduce entero en test.
