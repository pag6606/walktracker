# Sprint Change Proposal — 2026-09-13

**Proyecto:** WalkTracker iOS (SwiftUI) · **Autor:** corrección de rumbo con Paul · **Modo:** incremental
**Estado:** **APROBADA por Paul el 2026-09-13** — 8 ediciones aprobadas una a una y aprobación global

## 1. Resumen del problema

**Disparador:** la historia **8.4 — Gate del Success signal** no se puede ejecutar en su posición
actual, la última del Epic 8 antes de cualquier otro epic.

**Cómo se descubrió.** Al cerrar la 8.3, Paul instaló `v4.0.0-build.38` desde TestFlight y la app
solo mostraba la vista raíz provisional. Al preparar la 8.4 se vio que sus criterios miden una sesión
que todavía no existe.

**Evidencia:**
- La 8.4 exige una sesión registrada completa con `stepsEstimated = 0`, reconstrucción del background
  por consulta al sistema (AD-8) y las tres cadencias de AD-21: conteo continuo, UI a 1 Hz y Live
  Activity por evento. Eso lo construyen las historias **1.1–1.6** y la **7.2**.
- **Dependencia circular:** la 8.4 *fija* el timeout de reconciliación y el umbral de sesión huérfana
  que el Epic 1 *usa* (AD-8, AD-18, spine §Deferred).
- **Contradicción de planificación:** `epics.md` dice que el Epic 8 "sigue corriendo PRIMERO", y
  `epic-8-context.md` que "el epic entero bloquea a los demás", mientras su gate final depende del
  Epic 1.
- **Restricción nueva de Paul:** no dispone de 60 minutos para la caminata de prueba.

## 2. Análisis de impacto

**Epics**
- **Epic 8:** se completa sin la 8.4. El gate se reubica tras el Epic 1 y el epic sigue `in-progress`
  hasta entonces.
- **Epic 1:** 1.5 y 1.6 introducen el timeout de reconciliación y el umbral de sesión huérfana con
  valores provisionales.
- **Epic 7:** la 7.2 recomprueba la batería con la Live Activity activa.
- **Epics 2–6:** sin cambios. Ningún epic queda obsoleto ni hace falta uno nuevo.

**Artefactos**
- **`SPEC.md`:** restricción de *Batería* y frase del gate en *Success signal*; enmienda de 60 a 30 min
  con un umbral verificable. El resto del Success signal no cambia.
- **`ARCHITECTURE-SPINE.md`:** AD-21 (*Prevents* y último punto de *Rule*) y la fila de *Deferred*.
- **`epics.md`:** NFR-8, cabecera y orden del Epic 8, historia 8.4 y añadidos en 1.5, 1.6 y 7.2.
- **`epic-8-context.md`:** se recompila desde las fuentes.
- **`sprint-status.yaml`:** solo comentarios; ninguna clave ni estado cambia.
- **UX:** sin impacto. **No se toca** `REESTIMACION-EPICS.md`: es registro histórico, no contrato.

**Técnico:** ninguno sobre el código existente. Sin rollback.

## 3. Enfoque recomendado

**Ajuste directo** (opción 1), con una enmienda menor del criterio de éxito.

| Opción | Viable | Esfuerzo | Riesgo | Motivo |
|---|---|---|---|---|
| 1. Ajuste directo | ✅ | Bajo | Bajo | Reordenar y precisar historias existentes resuelve todo |
| 2. Rollback | ❌ | — | — | No hay trabajo hecho que estorbe |
| 3. Revisión del MVP | ❌ | — | — | El MVP no cambia; solo cómo se mide su criterio de batería |

**Duración del gate: 30 min** (decisión de Paul, opción "d"). La precisión (±10 % frente a Salud y cero
pasos estimados) no depende de la duración: 30 minutos dan de sobra y ejercitan varias suspensiones de
la app. La batería se mide con un umbral verificable, **≤ 5 % de caída en los 30 min**, más la
atribución por app de **Ajustes → Batería**. Con solo el porcentaje global no se distinguiría el gasto
de la app del de la música.

**Impacto en el calendario:** positivo. El gate se puede ejecutar de verdad, y cuesta 30 minutos de
caminata en lugar de 60.

## 4. Ediciones detalladas (aprobadas)

### E1 · `SPEC.md` — Constraints · Batería, y Success signal
- **Batería:** "sesión de 60 min" → "sesión de **30 min** … caída total ≤ 5 % y WalkTracker no
  destacado en Ajustes → Batería", con marcador **ENMENDADO el 2026-09-13**.
- **Success signal:** "sesión completa de 60 min" → "sesión completa de **30 min** … (≤ 5 % de caída y
  WalkTracker no destacado)", con nota de enmienda.

### E2 · `epics.md` — NFR-8
- "sesión de 60 min" → "sesión de 30 min", con subviñeta **ENMENDADO el 2026-09-13** y el umbral
  verificable.

### E3 · `epics.md` — Story 8.4
- Nota de reubicación (después del Epic 1) y de enmienda de duración.
- "caminata completa de 60 minutos" → "caminata de 30 minutos".
- AC 1: precondición **historias 1.1–1.6 en `done`** y app instalada por TestFlight; caminata de
  **30 min**.
- AC 2 (batería): **≤ 5 %** en 30 min y WalkTracker no destacado en Ajustes → Batería.
- AC 3 (`stepsEstimated = 0`): sin cambios de fondo.
- AC 4: mide las cadencias que existen al terminar el Epic 1 (**conteo continuo y UI a 1 Hz**) y
  **reemplaza los valores provisionales** de `formulas.json`.
- Nuevo **And:** la cadencia de la Live Activity no se mide aquí; la recomprueba la 7.2.
- AC final: si falla, se revisa **antes de seguir con los epics 2–7**.

### E4 · `epics.md` — Epic 8, cabecera y orden de ejecución
- **Cabecera:** "sigue corriendo PRIMERO" → "…PRIMERO, **salvo su gate final (8.4), que mide una
  sesión real y corre después del Epic 1**".
- **Orden:** `8.5 → 8.6 → 8.7 → 8.3 → 8.4` → `8.5 → 8.6 → 8.7 → 8.3`, y después
  **Epic 1 (1.1–1.6) → 8.4**, antes de los epics 2–7. Se añade un párrafo con el porqué y cómo se rompe
  la dependencia circular.

### E5 · `epics.md` — Stories 1.5, 1.6 y 7.2
- **1.5**, nuevo **And:** timeout de reconciliación (AD-8) en `formulas.json` con **valor
  provisional** marcado; la 8.4 lo reemplaza.
- **1.6**, nuevo **And:** umbral de sesión huérfana (AD-18) en `formulas.json` con **valor
  provisional**; por encima del umbral, cierre recortado, `recovered: true`, sin logros ni
  celebración; la 8.4 lo reemplaza.
- **7.2**, nuevo **Given/When/Then:** con la Live Activity por evento en una caminata de 30 min, la
  batería sigue **≤ 5 %** y WalkTracker no destacado.

### E6 · `ARCHITECTURE-SPINE.md` — AD-21 y Deferred
- **AD-21 · Prevents:** "60 min sin degradación notoria" → "30 min sin degradación notoria (≤ 5 % de
  caída) … enmendado el 2026-09-13".
- **AD-21 · Rule, último punto:** "La medición de 60 min … gate de la historia final" → "La medición de
  30 min … gate de la historia 8.4, que corre al terminar el Epic 1 y antes de los epics 2–7 … Mide
  conteo y UI; la Live Activity la recomprueba la 7.2", con nota de reubicación.
- **Deferred:** la fila del timeout y del umbral dice que 1.5 y 1.6 los introducen con valores
  provisionales y que la 8.4 los reemplaza.

### E7 · `epic-8-context.md` — recompilación
- Se recompila desde las fuentes ya editadas. Debe reflejar el gate de 30 min con su umbral, que el
  sustrato (8.5, 8.6, 8.7, 8.3) bloquea a los demás epics mientras la 8.4 corre tras el Epic 1, y las
  constantes provisionales.

### E8 · `sprint-status.yaml` — comentarios
- Tras `1-6-…`: comentario "Al terminar 1-6 → gate 8-4 (caminata de 30 min) ANTES de epic-2..epic-7",
  con referencia a esta propuesta.
- Antes de `8-4-…`: comentario "Se ejecuta DESPUÉS de epic-1 (1-1..1-6). epic-8 sigue in-progress hasta
  entonces". Claves y estados sin cambios.

## 5. Traspaso para la implementación

**Alcance: Moderado.** Reorganiza el backlog (orden del gate, criterios en cuatro historias) y enmienda
un criterio de éxito de la SPEC, sin replanificación de fondo ni cambios de arquitectura estructurales.

| Rol | Responsabilidad |
|---|---|
| Paul (Product Owner) | Aprobar esta propuesta y firmar la enmienda del Success signal (E1) |
| Agente de desarrollo (esta sesión) | Aplicar E1–E8 en una rama, recompilar el contexto, abrir PR |
| Historias futuras (1.5, 1.6, 7.2, 8.4) | Heredar los criterios nuevos al generar sus specs |

**Criterios de éxito de la implementación**
- Ningún artefacto vigente dice ya "60 min" para el gate. Única excepción: `REESTIMACION-EPICS.md`,
  histórico.
- La 8.4 exige 1.1–1.6 en `done`, y el orden del Epic 8 lo dice explícitamente.
- 1.5 y 1.6 nombran sus constantes provisionales, y la 7.2 recomprueba la batería.
- `epic-8-context.md` recompilado sin la contradicción "el epic entero bloquea a los demás".
- `sprint-status.yaml` sin cambios de clave ni de estado.
