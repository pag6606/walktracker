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


## Medición parcial · 2026-09-15 (no cierra el gate)

> **No es la caminata del gate:** duró 19 min, no 30; hubo un desbloqueo a los 56 s y no hay lectura de Salud
> del intervalo. Queda registrada porque sus datos del registro `WTM1` son reales y responden a parte de las
> dudas. Los valores ausentes figuran como "sin datos", no se estiman. El gate sigue `pendiente`.

### Criterios

| # | Criterio | Umbral | Resultado | ¿Cumple? |
|---|---|---|---|---|
| C1 | Pasos frente a Apple Salud | ≤ 10 % | WalkTracker 2111; Salud del intervalo: **sin datos** | sin datos |
| C2 | Distancia frente a Apple Salud | ≤ 10 % | WalkTracker 1269,43 m. Salud (Paul): registros de 0,65 km a las 8:07 y 0,63 km a las 8:17, suma 1,28 km (≈ 0,9 % de diferencia) **si** ambos cubren 7:57–8:17; falta confirmar el inicio y el fin de cada registro. El "1,5 km" es el total del día | pendiente de confirmar el intervalo |
| C3 | Caída de batería en 30 min | ≤ 5 % | 23 % → 20 % (3 puntos) entre 7:53 y 8:16, unos 23 min: no es una medición de 30 min | sin datos (medición de 23 min) |
| C4 | WalkTracker en Ajustes → Batería | no destacado | no aparece destacado (Paul, 2026-09-15) | sí |
| C5 | `stepsEstimated` sin tocar la pantalla | = 0 | 0 en todo el registro, pero hubo un desbloqueo a los 56 s y el registro cierra en pausa (la finalización fue posterior, fuera del registro) | sin datos (condición no cumplida) |

### Build y condiciones

| Dato | Valor |
|---|---|
| Etiqueta del build | `v4.0.0-build.74` |
| Commit de `main` | `0ff2b5c` |
| `version` y `build` según el informe | 4.0.0 (74), coinciden |
| `sid` de la sesión | `1789477060734` |
| iOS del iPhone 14 | sin datos |
| Hora de inicio / fin | salida 7:53 (Paul); sesión iniciada 7:57:40; pausa 8:16:43; fin de la caminata 8:16 (Paul) |
| Duración | 19 min 03 s netos (informe) |
| Música (app) y auriculares | sin datos |
| iPhone desconectado del cargador | sí (Paul) |
| Modo de bajo consumo desactivado | sí (Paul) |
| Apple Watch puesto | no (Paul) |
| Teléfono en el bolsillo, pantalla bloqueada todo el rato | no: desbloqueo breve a los 56 s (7:58:36, línea `transition=active`) |
| Toques en la pantalla durante la caminata | 1 desbloqueo a los 56 s; vuelta a la app a las 8:16:39 para pausar |
| Observaciones | extracción con `sudo log collect --device --last 3h` a las 9:24. La sesión de prueba del 2026-09-14 (`sid=1789421704613`, en pausa) se cerró como huérfana al abrir el build 74: primera verificación en dispositivo de AD-18 (1.6). Paul finalizó la sesión de la caminata después de extraer el registro. |

### Informe del script (sesión de la caminata)

```text
── Sesión sid=1789477060734 (2026-09-15T12:57:40.734Z) ──
Build: 4.0.0 (74)
Finalizada: no · transiciones: start → background → active → background → active → pause → background → background → background → background
Duración neta: 19 min 03 s (1143 s) · de reloj: 26 min 39 s
Pasos: 2111 (medidos 2111 + estimados 0)
Distancia: 1269.43 m · del sistema: 1269.43 m
stepsEstimated: 0 · criterio del gate = 0: NO CUMPLE (sesión sin finalizar)
Consultas: 2 · duración máx.: 2 ms · p95: 2 ms
Desenlaces: data=2 nil=0 timeout=0 belowSeen=0 error=0
Respuestas tardías: 0
Muestras del stream: 6 · con distancia: 6 · sin distancia: 0 · alternancias: 0
Estimaciones: 0 (0 pasos) · omitidas: 0
Avisos:
  ⚠️  la sesión no está finalizada en el registro: los valores finales son los de la última transición
reconciliationTimeoutS propuesto: 1 s = max(1 s, 5 × 2 ms), redondeado hacia arriba
```

Línea a línea (`log show … category == "Medicion"`, sesión `1789477060734`): consultas a las 7:58:36 (`result=85 seen=85 ms=2 outcome=data`) y a las 8:16:39 (`result=2102 seen=2102 ms=2 outcome=data`); muestras del stream a las 7:58:36, 7:58:36, 8:02:07 (con la pantalla bloqueada), 8:16:39, 8:16:40 y 8:16:42, todas con `distance`.

### Qué responde y qué no

| Duda | Qué dice el registro | Conclusión |
|---|---|---|
| **R1** · consulta menor que lo visto | 2 consultas, las dos con `result == seen` (85/85 y 2102/2102); `belowSeen=0` | no apareció en esta caminata; 2 consultas no bastan para descartarlo |
| **R2** · el stream entrega tras una consulta degradada | ninguna consulta degradada | sin datos en esta caminata |
| **R11** · fuentes mezcladas entre tramos | un solo tramo hasta la pausa; todas las muestras con distancia | sin datos en esta caminata |
| Alternancia de la distancia (1.3) | 6 muestras con `distance`, 0 sin ella, 0 alternancias | no apareció en esta caminata |
| **R5** · el sistema terminó el stream | sin `streamEnded` | no apareció en esta caminata |
| Duración real de la consulta | máx. 2 ms (2 consultas) | la regla daría 1 s; **no se fija** con una medición parcial de 2 consultas |

## Veredicto

- **Resultado:** pasa / falla
- **Criterios que fallan:**
- **Siguiente paso:** 8.4 `done` y Epic 8 `done`, o `bmad-correct-course`.
