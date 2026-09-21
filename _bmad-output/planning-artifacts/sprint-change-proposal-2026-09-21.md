# Sprint Change Proposal — La Summary Screen no tiene historia dueña

**Fecha:** 2026-09-21 · **Autor:** Dev (con Paul) · **Disparador:** entrada de `deferred-work.md`
registrada por la 1.4 el 2026-09-13, reabierta al cerrar el A-7 y al ir a arrancar el Epic 3.

---

## 1. Resumen del problema

`epics.md` pide la **Summary Screen** en dos sitios y **ninguna historia la entrega**:

- **UX-DR4** la lista entre los componentes visuales (`epics.md:109`).
- **UX-DR5** la lista entre las 9 superficies de la arquitectura de información, con una
  restricción propia —*"finished (Summary **forward-only**)"*— que hoy no vive en ninguna
  historia (`epics.md:110`).

Lo que existe hoy en el producto es el **resumen mínimo de la 1.4**:
`WalkTracker/UI/Session/SessionSummaryView.swift` (117 líneas) con título
("Caminata completada" / "Caminata recuperada"), las métricas, el aviso de sesión huérfana,
el aviso de "no se pudo guardar" que añadió la 5.1, y "Volver al inicio". La 1.4 nunca pretendió
más: su alcance eran los controles.

### La causa raíz, que no es un olvido

**No existe ningún FR para el resumen.** El FR Coverage Map tiene 17 entradas (`epics.md:122-141`)
y ninguna dice "resumen tras finalizar". La Summary Screen existe **solo como requisito de UX**.
Las historias de este proyecto se derivan de FRs, así que no había de dónde colgarla: no se cayó
de una historia, es que nunca tuvo una de la que caerse.

### La deuda ya está cobrando intereses

La **historia 6.1** (Salud) ya escribió un criterio de aceptación **contra una pantalla que nadie
construye** (`epics.md:772`):

> **And** si HealthKit está denegado o la escritura falla, **la sesión se guarda local igual** y
> **el resumen muestra "no sincronizado"** — nunca un error.

Es la única mención al resumen en las 1.099 líneas de `epics.md` fuera de los bloques UX-DR. Una
historia del Epic 6 depende de una superficie sin dueño, y si nada cambia, la 6.1 se encontrará
con que tiene que inventarse la mitad de una pantalla para poder poner su fila.

---

## 2. Análisis de impacto

**Impacto en epics.** Solo el Epic 3 en el orden; ningún epic cambia de alcance. Las piezas que
llenarían el resumen ya están repartidas y **casi todas existirán al terminar el Epic 3**:

| Pieza del resumen | Quién la trae | Estado |
|---|---|---|
| Métricas (distancia, tiempo, ritmo, cadencia, pasos) | 1.4 | ✅ hecho |
| Clima del inicio | 2.1 | ✅ hecho (en `review`) |
| Marca de caminata recuperada / huérfana | 1.6 + AD-18 | ✅ hecho |
| Estado de persistencia ("no se pudo guardar") | 5.1 | ✅ hecho |
| Progreso de la meta semanal tras esta caminata | 3.1 | pendiente |
| Logros desbloqueados en este cierre | 3.2 | pendiente |
| Celebración no bloqueante | 3.4 | pendiente |
| Estado de sincronización con Salud | **6.1** | **pendiente, Epic 6** |

**Impacto en historias.** Ninguna historia existente cambia de alcance. La 6.1 gana un sitio
concreto donde aterrizar su fila en vez de tener que inventárselo.

**Conflictos de artefactos.** `epics.md` (historia nueva + mapa de cobertura), `sprint-status.yaml`
(clave nueva), `deferred-work.md` (la entrada que disparó esto se cierra apuntando aquí). El
**PRD no se toca**: no se inventa un FR-18 a posteriori para justificar una pantalla que la UX
ya pedía; se declara explícitamente que esta historia **la gobierna la UX**, y eso queda escrito.

**Impacto técnico.** Ninguno inmediato: `SessionSummaryView.swift` existe y el punto de
composición también. La historia nueva es de UI y composición, no de dominio.

---

## 3. Enfoque recomendado

**Ajuste directo** — añadir **una historia nueva, la 3.5**, al final del Epic 3.

Y la decisión de diseño que importa: **la 3.5 es dueña de la PANTALLA, no de todo su contenido.**
Es dueña de la composición, el orden, el estado vacío de cada sección, la restricción
*forward-only* de UX-DR5, la accesibilidad (VoiceOver sobre cada fila, Reduce Motion) y —lo que de
verdad cierra el agujero— **del contrato por el que una historia posterior añade su fila**.

**Por qué así y no de las otras dos formas que caben:**

- *Repartir las filas entre las historias que las traen, sin historia de pantalla.* Es exactamente
  lo que se ha hecho hasta hoy, y el resultado es este documento. Sin un dueño de la composición,
  cada historia añade su trozo y nadie responde del conjunto: ni del orden, ni de qué pasa cuando
  faltan tres de las ocho piezas, ni del recorrido de VoiceOver.
- *Una 3.5 dueña de TODO el contenido.* No puede cumplirse: la fila de Salud llega en el Epic 6.
  Una historia que promete una pantalla "completa" cuando una octava parte no existe es una
  historia que nace incumplida — el patrón que llevamos toda la semana quitando de en medio.

**Colocación: al final del Epic 3, después de la 3.4.** En ese punto existen siete de las ocho
piezas. La octava (Salud) entra por el contrato, en la 6.1, sin reabrir la 3.5.

**Riesgo asumido y declarado:** al terminar la 3.5 el resumen **todavía no estará completo** —le
faltará la fila de Salud hasta el Epic 6. Eso es correcto y queda escrito en la propia historia,
en vez de fingir lo contrario.

---

## 4. Cambios propuestos

### 4.1 `epics.md` — historia nueva 3.5

Se inserta tras la Story 3.4, al final del Epic 3:

```markdown
### Story 3.5: Summary Screen — la pantalla de cierre y su contrato de filas

As a caminante (usuario único),
I want ver al terminar una caminata todo lo que esa caminata significó —sus métricas, el clima
con el que salí, lo que sumó a mi meta y lo que desbloqueó—,
So que el cierre de la sesión me devuelva algo y no solo un botón para volver.

**Dueña de la pantalla, no de todo su contenido.** Esta historia es dueña de la COMPOSICIÓN:
qué secciones hay, en qué orden, qué pasa cuando una falta, el recorrido de VoiceOver y la
restricción forward-only de UX-DR5. El CONTENIDO lo aportan las historias que traen cada pieza,
a través del contrato que esta historia define. Al cerrarse, la pantalla NO estará completa:
le faltará la fila de Salud hasta la 6.1, y eso es deliberado.

**Origen:** UX-DR4 (componente "Summary Screen") y UX-DR5 (superficie "Summary", estado
"finished (Summary forward-only)"). **No cubre ningún FR**: el resumen nunca tuvo uno — ver el
FR Coverage Map. Es una historia gobernada por la UX, y se declara como tal en vez de inventarle
un FR a posteriori. [sprint-change-proposal-2026-09-21.md]

**Acceptance Criteria:**

**Given** una caminata recién finalizada
**When** se presenta el resumen
**Then** muestra, en orden fijo y declarado: métricas de la caminata, clima del inicio si se
capturó, lo que suma a la meta semanal, los logros desbloqueados en este cierre, y el estado de
guardado — y "Volver al inicio" como única salida [fuente: UX-DR4, UX-DR5]

**Given** una sección cuya pieza no se capturó (sin clima, sin logros nuevos, sin meta fijada)
**When** se presenta el resumen
**Then** esa sección **se omite entera**, sin hueco ni texto de relleno — y la pantalla sigue
teniendo sentido leída de arriba abajo con VoiceOver [fuente: UX-DR6]

**Given** el resumen presentado
**When** intento volver a la sesión que acabo de cerrar
**Then** no puedo: el resumen es **forward-only**, la única salida es a Inicio, y una sesión
finalizada es inmutable [fuente: UX-DR5, domain-model.md#13]

**Given** una caminata recuperada o cerrada como huérfana (AD-18)
**When** se presenta el resumen
**Then** lo dice, y **no** muestra sección de logros: una huérfana no cuenta para logros
[fuente: AD-18, `SessionRecord.countsForAchievements`]

**Given** que la caminata no se pudo persistir
**When** se presenta el resumen
**Then** se conserva el aviso que ya entregó la 5.1 — el resumen no se convierte en el sitio
donde se pierde esa señal

**Given** una historia posterior que aporta una fila nueva (la 6.1 con el estado de Salud)
**When** la añade
**Then** le basta con declararla en el contrato de secciones: **no** tiene que tocar la
composición, ni el orden, ni el recorrido de accesibilidad [fuente: la nota de la 6.1 en
`epics.md:772`, que ya escribía contra esta pantalla antes de que existiera]
```

### 4.2 `epics.md` — FR Coverage Map

Se añade, tras la última línea del mapa, una nota que deja constancia de la causa raíz:

```markdown
> **Nota (2026-09-21):** este mapa cubre los 17 FRs y **no cubre la Summary Screen**, que la UX
> pide en UX-DR4 y UX-DR5 sin que exista un FR detrás. Ésa es la razón de que pasara año y medio
> sin historia dueña: las historias se derivan de FRs. La **3.5** la reclama citando la UX como
> origen. No se inventa un FR-18 a posteriori. [`sprint-change-proposal-2026-09-21.md`]
```

### 4.3 `epics.md` — Epic 3, cabecera

A la línea `**UX:**` del Epic 3 se le añade la nota de que ahora incluye la superficie Summary.

### 4.4 `sprint-status.yaml`

Clave nueva bajo `epic-3`, tras `3-4-…`:

```yaml
  3-5-summary-screen-la-pantalla-de-cierre-y-su-contrato-de-filas: backlog
```

### 4.5 `deferred-work.md`

La entrada de la línea 25 (origen `spec-1-4`) pasa a `**CERRADO el 2026-09-21 — …**`: ya tiene
historia dueña, que era exactamente lo que pedía.

---

## 5. Handoff

**Clasificación: Moderada.** No es un replan: ningún epic cambia de alcance, ningún FR se toca y
no hay rollback. Es reorganización de backlog —una historia nueva y cuatro artefactos
reconciliados— más una decisión de producto que ya está tomada (la pantalla tiene dueño y el
dueño es la composición, no el contenido).

**Destinatario:** Dev, para aplicar los cambios de la sección 4.

**Criterios de éxito:**

1. `epics.md` contiene la Story 3.5 y la nota del FR Coverage Map.
2. `sprint-status.yaml` tiene la clave `3-5-…` en `backlog`.
3. La entrada de `deferred-work.md` queda cerrada apuntando a la 3.5, y
   `bash Scripts/check-spec-shape.sh` sigue **verde** — el gate del A-7 exige que una entrada
   cerrada lleve `**CERRADO el <fecha>` y ninguna abierta se quede sin `Destino:`.
4. La 3.1 puede arrancar sin tocar nada de esto.
