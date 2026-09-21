# Decisiones de Paul — 2026-09-20

Cierre de los action items de owner Paul que arrastraban las retrospectivas de los épicos 1 y 2.
Eran **cinco decisiones, no seis**: `B-7` decía literalmente *"Decidir A-4"*, así que el Epic 2 había
reabierto la misma pregunta con su coste ya medido.

---

## D1 · Arné de verificación de vistas — `A-4` / `B-7`

**Decisión: extraer la lógica de presentación a tipos probables.** Sin target de XCUITest.

Cada vista expone **qué pinta y con qué estado** en un tipo sin SwiftUI, y eso se prueba con la suite
que ya existe. Rápido, sin target nuevo, sin fragilidad, y sin romper la regla de cero dependencias
de terceros del spine —que es lo que descartaba ViewInspector de antemano—.

**Lo que cierra:** la mayoría de los 9 diferidos que dependían de esto, y en concreto el reparto de
resultado→texto→color que hoy no cubre ni el gate ni la suite (`B-2` lo dejó escrito como el único
criterio sin respaldo automático).

**Lo que explícitamente NO cierra, y queda dicho:** los solapes entre capas. Que la frase motivacional
tape la pre-pantalla de ubicación (`B-4`) solo se ve renderizando. Ese diferido **no se cierra con
esta decisión** y hay que re-apuntarlo a verificación manual, no dejarlo esperando un arnés que no va
a llegar.

> Consecuencia aceptada: 2 de los 3 defectos de la retro del Epic 2 eran de interfaz, y de esos dos,
> este arnés habría cazado **uno**. El otro necesitaba renderizar.

## D2 · La 2.1 — `B-8`

**Decisión: se cierra ejecutando sus checks en la próxima caminata.** No se declara cerrada a ciegas.

Los cuatro —clima con red, en modo avión, con ubicación denegada, y force-quit con clima— caben en la
misma salida que la validación de R1, pendiente desde el build 88. Hasta entonces la 2.1 **sigue en
`review`**, que es lo que dice la verdad.

## D3 · Umbral de tamaño de spec — `A-8`

**Decisión: subir el umbral a 4.000 tokens y dejar de avisar en cada historia.**

Las 7 specs escritas superaron el umbral estándar de 1.600 y las 7 salieron bien. Lo que las engorda
es el inventario de código real —rutas, líneas, conteos verificados—, que es justamente lo que evita
que la implementación se invente el contexto.

**Lo que no cambia:** el criterio de objetivo único. Trocear una historia se sigue justificando porque
tenga **dos entregables independientes**, nunca por tamaño de spec.

Aplicado en `_bmad/custom/bmad-build.toml` como hecho permanente —y no editando la skill, que una
actualización sobrescribiría—. Verificado: la skill lo resuelve.

## D4 · Lección de specs — `A-7`

**Decisión: convertirla en regla verificable.** Las dos mitades:

- todo traspaso de trabajo a otra historia va a `deferred-work.md` **con destino explícito**;
- una spec que toque `SessionStore` lista en su Code Map **los campos compartidos y sus invariantes**.

La primera se cumple por costumbre. La segunda solo se hizo en la 2.1 y se olvidó en la 2.2, que
tocaba `SessionStore+Motivation`. El argumento que decidió esto está en la propia retro: **lo que no
tiene gate se erosiona** — A-1 quitó los `sleep` fijos de los tests y la 2.1 reintrodujo cinco.

Mientras el check no exista, las dos reglas se aplican a mano; el hecho permanente ya lo dice.

## D5 · Reconciliar `epics.md` y el spine — `A-5`

**Decisión: los siete puntos, ahora, antes de empezar el Epic 3.**

Descarte global · aviso solo al relanzar · autosave por muestras · sin idle · que no se combinan ·
el `StoragePort` de partida para la 5.1 · el criterio de constantes en `formulas.json`.

El motivo es concreto: **el contexto de cada épica se compila de esos documentos**. Ya se vio en el
Epic 2 — al recompilar su contexto salió una advertencia falsa (la atribución de Open-Meteo dada por
pendiente cuando estaba implementada) precisamente porque el compilador solo lee planificación. Si el
Epic 3 se compila de documentos desfasados, lo desfasado viaja a sus cuatro historias.

---

## Qué queda en manos de quién

| Item | Estado tras la decisión | Dueño |
|---|---|---|
| `A-4` · decidir el arnés | **cerrado**: la decisión era el item | — |
| `B-7` · decidir A-4 | **cerrado**: duplicado de A-4 | — |
| `A-8` · umbral de spec | **cerrado**: aplicado y verificado | — |
| `A-5` · reconciliar los siete puntos | abierto → **chore de Dev**, antes del Epic 3 | Dev |
| `A-7` · regla verificable | abierto → **chore de Dev** (el check) | Dev |
| `B-8` · cerrar la 2.1 | abierto → **una caminata** | Paul |

Con esto, **lo único que sigue esperando a Paul es andar**.
