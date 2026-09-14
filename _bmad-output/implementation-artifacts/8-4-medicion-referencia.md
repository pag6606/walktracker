---
title: '8.4 — Medición de referencia: caminata de 30 min en el iPhone 14'
story: '8.4'
spec: 'spec-8-4-gate-success-signal.md'
status: 'pendiente'   # pendiente | pasa | falla
fecha: ''             # AAAA-MM-DD de la caminata
---

# Medición de referencia · gate 8.4

> **Plantilla.** Se rellena tras la caminata, con el protocolo de `README.md` → "Gate 8.4". Ningún valor de
> esta página se escribe de memoria ni se estima: cada uno sale de Salud, de Ajustes → Batería, del resumen
> de WalkTracker o del informe de `Scripts/walk-report.sh`.

## Criterios del gate

[fuente: epics.md Story 8.4; SPEC Success signal; NFR-8; CAP-3]

| # | Criterio | Umbral | Resultado | ¿Cumple? |
|---|---|---|---|---|
| C1 | Pasos frente a Apple Salud | ≤ 10 % | | |
| C2 | Distancia frente a Apple Salud | ≤ 10 % | | |
| C3 | Caída de batería en 30 min | ≤ 5 % | | |
| C4 | WalkTracker en Ajustes → Batería | no destacado | | |
| C5 | `stepsEstimated` sin tocar la pantalla | = 0 | | |

Diferencia relativa = |WalkTracker − Salud| / Salud × 100.

**Si falla un criterio, se para:** se registra aquí y se revisa con `bmad-correct-course` antes de los
epics 2–7, sin tocar el umbral.

## Build y condiciones

| Dato | Valor |
|---|---|
| Etiqueta del build (`v4.0.0-build.N`) | |
| Commit de `main` | |
| `version` y `build` según el informe (deben coincidir con la etiqueta) | |
| `sid` de la sesión de la caminata en el informe | |
| iOS del iPhone 14 | |
| Hora de inicio / fin | |
| Duración de reloj | |
| Música (app) y auriculares | |
| iPhone desconectado del cargador durante la caminata | sí / no |
| Modo de bajo consumo desactivado | sí / no |
| Apple Watch puesto (si sí: Salud leído solo con la fuente iPhone) | sí / no |
| Teléfono en el bolsillo, pantalla bloqueada todo el rato | sí / no |
| Toques en la pantalla durante la caminata | |
| Otras apps abiertas / observaciones | |

## Valores

Salud: «Mostrar todos los datos», sumando solo las entradas entre la hora de inicio y la de fin, y solo
las de la fuente iPhone si hubo otra.

| Métrica | WalkTracker (resumen) | Apple Salud (mismo intervalo, fuente iPhone) | Diferencia |
|---|---|---|---|
| Pasos | | | |
| Distancia (m) | | | |
| Duración | | — | — |

## Batería

| Dato | Valor |
|---|---|
| Batería al empezar (%) | |
| Batería al terminar (%) | |
| Caída (puntos) | |
| Uso de WalkTracker en Ajustes → Batería (últimas 24 h) | |
| Apps que más consumen en el periodo | |
| ¿WalkTracker destaca? | |

## Informe del script

Comando: `sudo log collect --device --last 2h --output ~/caminata-8-4.logarchive` y después
`bash Scripts/walk-report.sh ~/caminata-8-4.logarchive`.

```text
(pegar aquí la salida completa del informe)
```

## Decisiones con los datos

Cada decisión cita la línea o el dato del informe que la sostiene. Hallazgos de
`epic-1-retro-2026-09-14.md`.

| Duda | Qué dice el registro | Decisión | Sigue en |
|---|---|---|---|
| **R1** · ¿la consulta puede dar menos que lo ya visto? (`belowSeen`) | | | Q-5 |
| **R2** · ¿el stream entrega después de una consulta degradada el acumulado del gap? | | | |
| **R11** · distancia con fuentes mezcladas entre tramos | | | deferred-work 1.4 |
| Alternancia de la distancia entre muestras con y sin `distance` (1.3) | | | deferred-work 1.3 |
| ¿El sistema terminó el stream durante la sesión? (`streamEnded`, R5) | | | Q-6 |

> Con la pantalla bloqueada todo el rato solo hay consultas al volver y al finalizar: R2 solo aparece si
> alguna degrada. Si no hay datos para una duda, se escribe "sin datos en esta caminata", no una conclusión.

## Constantes fijadas

Regla de las Decisiones de Paul (2026-09-14), en `spec-8-4-gate-success-signal.md`:

| Constante | Antes | Dato medido | Regla | Valor fijado |
|---|---|---|---|---|
| `reconciliationTimeoutS` | 3 (provisional) | duración máx. real de la consulta en la sesión `sid` de la caminata: ___ ms (p95: ___ ms; timeouts sin `queryLate`: ___) | max(1 s, 5 × duración máx.), redondeado hacia arriba al segundo; sin valor si hay timeouts sin `queryLate` | |
| `orphanSessionThresholdS` | 21600 (provisional) | — (no medible en esta caminata) | se queda en 6 h como **valor decidido, no medido** | 21600 |

Tras fijarlas: `formulas.json` sin ninguna de las dos en `provisional`, `FormulasTests` actualizado, y
`verify-domain.sh` y la suite completa en verde.

## Veredicto

- **Resultado:** pasa / falla
- **Criterios que fallan:**
- **Siguiente paso:** 8.4 `done` y Epic 8 `done`, o `bmad-correct-course`.
