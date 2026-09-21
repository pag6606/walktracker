# Capabilities — detalle y criterios de aceptación

Companion de `SPEC.md`. Una sección por capability: prioridad (MoSCoW heredado del PRD v3), trazabilidad al RF de la PWA v3 que origina, notas normativas y criterios de aceptación testables. Fórmulas e invariantes de dominio viven en `domain-model.md`; el catálogo completo de logros en `achievements.md`.

## CAP-1 — Control de sesión con cronómetro wall-clock · Must
- **Hereda:** RF-01 v3, ADR-05.
- Cronómetro wall-clock: `elapsedS = (now − startedAt) − totalPausesS`; ningún timer es fuente de verdad.
- Pausa solo explícita (botón). Cambiar de app no pausa. Sin auto-pausa por inactividad.
- **Criterios:**
  - Sesión de 10 min con 5 min en otra app → al volver, elapsed exacto por wall-clock.
  - Pausar 2 min y reanudar → esos 2 min no cuentan en elapsed.
  - Force-quit de la app con sesión activa → al reabrir, la sesión se recupera con el tiempo correcto recomputado desde `startedAt` (recuperación silenciosa, indicador "Sesión recuperada" 3 s).

## CAP-2 — Conteo automático de pasos 24/7 · Must
- **Hereda:** RF-02 v3; resuelve la restricción R1 de la matriz PWA (`platform-matrix.md`).
- Fuente de pasos: coprocesador de movimiento del sistema (CMPedometer), no pipeline de acelerómetro propio. El `StepDetector` de dominio de la PWA queda retirado en nativo (la detección la hace el SO).
- Debe contar con pantalla bloqueada, app en background y teléfono en bolsillo.
- **Criterios:**
  - Caminata de 10 min, pantalla bloqueada, música sonando → pasos con error ≤10 % vs app Salud.
  - Permiso de movimiento denegado → pantalla explicativa (equivalente a Motion Denied de la PWA); la app no puede operar su núcleo sin él.

## CAP-3 — Reconstrucción exacta de background · Must
- **Hereda:** RF-05 v3; resuelve R2.
- Al volver a foreground (o al finalizar), los pasos de intervalos en background se obtienen por consulta histórica al sistema (query CMPedometer por rango). No se extrapola por cadencia como en la PWA.
- La estimación por cadencia (`GapEstimator`) sobrevive en el dominio solo como degradación excepcional, y **solo cuando el sistema no responde** —`nil`, error, timeout, o un tramo que empieza hace más de 7 días, que `queryPedometerData` no cubre—. Ojo a que la condición de los 7 días mira el **tramo** (lo que se consulta) y la estimación se hace sobre el **hueco** (el tiempo en background): un tramo viejo con un hueco corto **sí estima**, porque lo que decide ahí es `maxEstimableGapS`, no la antigüedad del tramo. **Cualquier respuesta no nula es dato y corta la estimación**, aunque traiga menos pasos de los ya vistos: el sistema consolida su histórico con retraso y la consulta va por detrás del stream (R1, medido en el iPhone 14 el 2026-09-17).
- Aun sin respuesta, `GapEstimator.outcome` decide con **cuatro guardas** y con cualquiera de ellas la estimación es 0: la **precondición** de sesión `active` (`notActive` en otro caso) y **las tres defensas** —así las nombra el código— que son no estimar si el stream ya trajo los pasos del hueco (`streamAdvanced`), tomar la cadencia en el **inicio del hueco** y nunca la de ahora (y por debajo de 120 s de sesión en ese instante no hay cadencia representable, `noPriorSample`), y no estimar por encima de `maxEstimableGapS` (**20 min**, decisión de Paul 2026-09-17; `gapAboveCap`). *(Enmendado el 2026-09-20: decía "tres defensas y un tope", dejando el tope fuera del recuento y metiendo `notActive` dentro, al revés que el código. El mínimo de 120 s tampoco es de R1: es anterior, `domain-model.md §4`.)*
- Lo estimado va siempre desglosado, marcado "~" y es descartable. **El descarte es global** —todos los estimados de la sesión vuelven a 0 y distancia y ritmo se recalculan sin ellos—, no por hueco, y se permite también con la sesión en pausa, porque el aviso de estimados también se ve en pausa.
- **Criterios:**
  - Gap de 5 min con música → pasos exactos del sistema; `stepsEstimated` permanece en 0.
  - Consulta que responde **menos** pasos de los ya vistos → se aplica como dato; `stepsEstimated` permanece en 0.
  - El sistema **no responde** (nil, error o timeout) y ninguna defensa lo impide → estimación marcada "~", descartable.
  - Hueco sin respuesta por encima de los 20 min → **0 pasos estimados**, no una estimación mayor.
  - Al descartar → **todos** los estimados de la sesión vuelven a 0, en activa o en pausa; esos pasos dejan de contar en distancia y ritmo.

  *(Enmendado el 2026-09-20: estas reglas decían que la estimación entraba "p. ej. [cuando el] dato del sistema no [está] disponible" y que el descarte quitaba "esos pasos". R1 restringió la entrada a la ausencia de respuesta y añadió el tope y las defensas; el descarte siempre fue global.)* [`WalkTracker/Application/SessionStore+Reconciliation.swift:58-95`, `Domain/Session/GapEstimator.swift:20, 45-58, 95-102`, `Domain/Session/Session.swift:213-219`, `WalkTracker/Resources/formulas.json`; `ARCHITECTURE-SPINE.md` AD-8; spec-r1]

## CAP-4 — Métricas en vivo · Must
- **Hereda:** RF-03, RF-04 v3; resuelve R8.
- Métricas: pasos, distancia, tiempo, ritmo (min/km), cadencia (spm).
- Distancia: la del sistema (CMPedometer distance) cuando está disponible; si no, `(stepsMeasured + stepsEstimated) × strideM` con zancada configurada (default 0,655 m — validada en campo en v1).
- Ritmo solo si `distanceM ≥ 100`. Cadencia solo sobre tramos medidos (regla de dominio).
- **Criterios:**
  - Con distancia del sistema disponible, la UI la prefiere y la marca igual que el resto (sin distinción visible de fuente; la fuente es decisión interna).
  - Con <100 m recorridos, ritmo muestra "—".

## CAP-5 — Clima snapshot al inicio · Must
- **Hereda:** RF-06 v3; resuelve R3.
- Snapshot congelado al iniciar: `tempC, feelsLikeC, condition, humidityPct, uvIndex, windKmh, capturedAt`.
- Proveedor primario: Open-Meteo sin key, consumido por `WeatherAdapter` detrás de `WeatherPort`; WeatherKit se difiere (cambio de adapter, aislado). Coordenadas redondeadas a 2 decimales **en `LocationPort`**, el único punto donde la restricción de Privacidad es verificable. Open-Meteo es CC-BY 4.0: exige atribución visible.
- Timeout 3 s y degradación limpia: sin red/permiso → la sesión inicia sin clima, no bloqueante.
- **Criterios:**
  - Con red → snapshot visible asociado a la sesión.
  - Modo avión → sesión completa sin clima.
  - Permiso de ubicación denegado → sesión sin clima, sin re-pedir en cada sesión.

## CAP-6 — Frase motivacional al iniciar · Must
- **Hereda:** RF-07 v3, ADR-11/AD-18.
- Banco de 100 frases en `quotes.json` (companion adoptado; se empaqueta como asset local en el bundle).
- Selección aleatoria excluyendo `recentQuoteIds` (últimas 20); si todas están excluidas, se ignora el filtro (regla implementada en la PWA, se conserva).
- Overlay de 3–4 s, saltable con tap.
- **Criterios:**
  - 20 sesiones consecutivas sin repetición.
  - Tap sobre el overlay lo descarta antes de los 4 s y la sesión ya está corriendo.

## CAP-7 — Meta semanal de km · Must
- **Hereda:** RF-10 v3.
- Configurable (default 10 km, >0 validado en frontera). Anillo de progreso sobre semana ISO (lunes 00:00 → domingo) **en la hora local del dispositivo**: el único `AppCalendar` de AD-19, nunca `Calendar.current`. Regla en `domain-model.md` §5. *(Enmendado el 2026-09-20: decía "lunes 00:00 **UTC**"; AD-19 resuelve la contradicción a favor de la hora local.)*
- Celebración al cumplir (toast no bloqueante + sonido/háptica).
- **Criterios:**
  - Anillo correcto sobre semana ISO con sesiones distribuidas en distintos días.
  - Cruzar el 100 % dispara celebración una sola vez por semana.

## CAP-8 — Logros (catálogo de 14) · Must
- **Hereda:** RF-11 v3. Catálogo y reglas de evaluación: `achievements.md`.
- Evaluación al cierre de sesión (excepto `weekly_goal`, evaluado por el GoalEngine al cumplirse la meta).
- Celebración visual + sonora + háptica. Logros ya desbloqueados no se re-disparan.
- **Criterios:**
  - Primer km → "Tu primer kilómetro" con celebración.
  - Grid de logros muestra locked/unlocked con progreso.

## CAP-9 — Persistencia local garantizada · Must
- **Hereda:** RNF-02 v3; resuelve R6.
- El storage vive en el sandbox de la app instalada: ficheros JSON `Codable` en Application Support con escritura atómica, detrás de `StoragePort`. La evicción de iOS era específica de la PWA en pantalla de inicio; una app instalada no la sufre. SwiftData se descartó: ~1.500 sesiones en diez años no justifican un segundo modelo y su capa de mapeo.
- Sesiones finalizadas inmutables (invariante de dominio). Config y snapshot de sesión activa en storage de preferencias.
- **Criterios:**
  - Reinicio del iPhone → historial, logros y config íntegros.
  - Force-quit con sesión activa → recuperación silenciosa desde snapshot (ver CAP-1).

## CAP-10 — Historial con totales y tendencia · Must
- **Hereda:** RF-09 v3.
- Lista descendente (más reciente primero): fecha, distancia, duración, ritmo; sesiones con pasos estimados marcadas "~".
- Totales de semana y mes; gráfico de tendencia simple.
- **Criterios:**
  - 5 sesiones → totales cuadran exactamente.
  - Historial vacío → empty state ("Aún no hay sesiones registradas").

## CAP-11 — Escritura de workouts en Apple Salud · Must
- **Hereda:** R4 de la matriz (en PWA era out-of-scope); reemplaza el flujo manual CSV + Shortcuts.
- Al finalizar sesión: workout tipo caminata con distancia, pasos y duración. Solo escritura; la app no lee datos de Salud (non-goal).
- Permiso HealthKit solicitado con pantalla explicativa previa (pre-permission), no en frío.
- **Criterios:**
  - Sesión finalizada → workout visible en Salud con distancia/pasos/duración correctos.
  - Permiso denegado → la sesión se guarda local igual; la app sigue funcionando.

## CAP-12 — Feedback háptico + sonoro · Must
- **Hereda:** RF-12 v3; resuelve R5.
- Eventos: inicio de sesión, cruce de cada km, meta cumplida, logro desbloqueado. Háptica (CoreHaptics) como canal primario nuevo; sonido conservado de la PWA.
- Respetuoso con música: sonidos cortos, sin ducking agresivo. Sonido desactivable en Ajustes (`soundEnabled`).
- **Criterios:**
  - En dispositivo físico, cada evento produce háptica (+ sonido si habilitado) mientras la música continúa.

## CAP-13 — Recalibración de zancada · Must
- **Hereda:** RF-14 v3, ADR-03 heredado.
- `strideM` es la única medida cruda editable, y es un **override opcional**: solo se guarda si Paul lo toca. Sin configurar (`nil`), la sesión nace con `defaultStrideM` de `formulas.json` (0,655 m), que queda como el **único** sitio donde vive ese número. "Usar el valor por defecto" es la vuelta atrás explícita —vaciar el campo se rechaza, así que sin ella un dedazo guardado dejaba a Paul sin forma de recuperar el valor bueno— (decisión de Paul, 2026-09-19).
- **Rechazo duro en la frontera de escritura**, con mensaje y sin persistir: ≤ 0, no finita, no numérica, o **mayor que el tope representable** de `domain-model.md` §4 (B-3). Los dos motivos se distinguen: "no cabe" y "no es mayor que cero" no se corrigen igual.
- **Aviso que no bloquea:** fuera del rango humano **0,3–1,2 m** (cerrado: en el borde exacto no hay aviso) se **guarda igual** y se dice que está fuera de lo humano, por si fue un dedazo (0,067 por 0,67). Es regla de producto, no del dominio — el agregado acepta 0,001 m y 50 m, y bloquear aquí inventaría un límite que el modelo no tiene.
- La puerta de **lectura** del fichero es la tolerante, no la que rechaza: un valor corrupto se lee como "sin configurar" y no cuesta el resto de los ajustes.
- La zancada nueva se aplica a la **siguiente sesión sin relanzar la app**: se resuelve al abrir la sesión, no al construir el store.
- Sesiones cerradas conservan su `strideM` congelado: recalibrar nunca reescribe historial.
- **Criterios:**
  - Recalibrar → historial inmutado; la siguiente sesión usa la nueva zancada, sin relanzar.
  - Valores ≤ 0, no numéricos o no representables → rechazados en frontera con mensaje, y no se persisten.
  - Valor fuera de 0,3–1,2 m → **se guarda**, con aviso de que está fuera de lo humano; no es un rechazo.
  - "Usar el valor por defecto" → vuelve a "sin configurar" y la siguiente sesión usa el 0,655 de `formulas.json`.

  *(Enmendado el 2026-09-20: esta sección decía solo ">0, finito, validado en frontera; default 0,655 m" y un criterio de rechazo de "≤0 o no numéricos". Faltaban el tope derivado de B-3, el aviso de rango que no bloquea y el carácter opcional del override.)* [`Domain/Ports/AppSettings.swift:51, 71-84, 101-128`, `Domain/Session/Session.swift:158-162`, `WalkTracker/Resources/formulas.json`; spec-2-3, spec-b3]

## CAP-14 — Export CSV/JSON + re-import · Should
- **Hereda:** RF-15 v3. En nativo baja de "mitigación de evicción" a respaldo voluntario (CAP-9 garantiza storage).
- Export vía share sheet. El JSON exportado es re-importable y restaura el historial (prueba respaldo/restauración).
- **No preservado (deliberado):** RF-17 v3 (aviso de respaldo si >30 días sin export) existía solo como mitigación de la evicción de storage en PWA (R6). Con storage garantizado pierde su razón de ser; se retira del producto.
- **Criterios:**
  - Export JSON → borrar datos → import → historial restaurado íntegro.
  - CSV abre en Numbers/Excel.

## CAP-15 — Eliminar sesiones individuales · Should
- **Hereda:** RF-16 v3.
- **Criterios:**
  - Eliminar remueve la sesión de lista, totales, anillo semanal y acumulados de logros no desbloqueados aún; los logros ya desbloqueados no se revocan.

## CAP-16 — Importación de historial desde la PWA v3 · ❌ RETIRADA (OQ-3, decisión Paul 2026-07-28)
- **Decisión:** arranque limpio — el historial de la PWA no se importa. La capability queda retirada y su ID reservada (nunca se reasigna); si Paul cambia de opinión en una versión futura, se reactiva con este mismo ID.
- Las reglas de importación diseñadas quedan archivadas en `domain-model.md` §7 como referencia para esa eventual reactivación.

## CAP-17 — Notificaciones locales de recordatorio de meta · Should (OQ-4 resuelta: en scope)
- **Hereda:** RF-18 v3 (Web Push) convertido a notificaciones locales nativas — no requiere servidor push, coherente con no-backend.
- **Condición de Paul:** entra a scope solo si el esfuerzo es bajo → re-verificada tras el pivot (2026-09-12): `UNUserNotificationCenter` nativo es igual o más simple que el plugin que sostenía la premisa original, y sin dependencia. La premisa se sustituye; la capability no cambia.
- Recordatorio semanal del estado de la meta (p. ej. domingo por la tarde: "Te faltan 2 km esta semana").
- **Criterios:**
  - Recordatorio programado llega con la app cerrada; se respeta el permiso de notificaciones.
  - Permiso denegado → la app funciona completa sin recordatorios.

## Superficie de UI heredada (referencia para el UX pass iOS)

Cómo funciona hoy la PWA v3 — las 8 pantallas que el usuario conoce. La app iOS las reinterpreta en patrones nativos (el UX pass de Sally decide la forma final; esta lista es el inventario funcional a cubrir):

1. **Home** — anillo de meta semanal (300 px) + "Iniciar caminata".
2. **Sesión** — pasos (con "~" si hay estimados), distancia, tiempo, ritmo, cadencia, clima; controles Pausar/Reanudar/Finalizar; banner de pasos estimados descartable. (El botón "+1 vuelta" de v1 ya no existe desde v3.)
3. **Momento motivacional** — overlay 3–4 s con la frase, saltable con tap (CAP-6).
4. **Summary** — stats finales al cerrar + celebraciones de logros/meta; en nativo añade confirmación de workout escrito en Salud (CAP-11).
5. **Historial** — lista descendente + totales semana/mes + tendencia (CAP-10); eliminar sesiones (CAP-15).
6. **Logros** — grid 2 columnas locked/unlocked con progreso (CAP-8).
7. **Ajustes** — zancada, meta semanal, sonido, exportar (con fecha de último respaldo), borrar datos; en nativo añade permisos (Salud, notificaciones).
8. **Motion Denied** — pantalla explicativa si el permiso de movimiento está denegado (CAP-2).

Invariantes de UX que cruzan plataforma (constraint UX): números grandes, celebrar nunca culpar, momento motivacional saltable, targets ≥ 44 pt, claro/oscuro, español.

## CAP-18 — Live Activity / Dynamic Island · Must (OQ-2, decisión explícita de Paul 2026-07-28)
- **Nuevo** (R7 de la matriz; en PWA no tenía equivalente). Paul la quiere en v1 por encima de la recomendación de diferir.
- Muestra en la pantalla de bloqueo (y en la Dynamic Island en hardware que la tenga) las métricas vivas de la sesión: pasos, distancia, tiempo. Mismo contenido que la pantalla Sesión, en formato glanceable.
- Se crea al iniciar la sesión, se actualiza durante, y se cierra al finalizar/pausar de forma terminal. Si la extension falla o el SO la rechaza, la app funciona completa sin ella (degradación limpia, coherente con el resto del producto).
- **Costo:** requiere un **Widget Extension con ActivityKit** y un target `Shared` para el tipo de `ContentState`. No requiere App Group — el estado viaja por `request`/`update` con tope de 4 KB. Requiere `NSSupportsLiveActivities` en `Info.plist`. La extensión solo renderiza: no calcula, no lee ficheros, no importa el dominio. En el iPhone 14 se valida el layout de pantalla de bloqueo; la Dynamic Island se limita a compilar.
- **Orden de construcción:** capa aditiva al final — primero se valida el core (conteo background + HealthKit + performance, Success signal), luego se monta la Live Activity sobre las mismas métricas.
- **Criterios:**
  - Sesión activa + teléfono bloqueado → métricas actualizándose en la Live Activity.
  - Finalizar sesión → Live Activity se cierra; pausar → estado visible de pausa.
  - iPhone sin isla → Live Activity de lock screen funciona igual.
  - Sin la extension disponible → sesión y conteo funcionan al 100 %.

## Wrapper-only content (registro de descarte)

Contenido de las fuentes que es ceremonial o de proceso y NO se preserva por no ser load-bearing para este contrato:
- Roadmap de epics E0–E5 del PRD v3 y su tabla de dependencias (planning de la PWA, ya ejecutado; la descomposición iOS se hará en su propio ciclo de epics).
- §13 "Dependencias y riesgos" del PRD v3 (estado de aprobación de artefactos PWA, ya cumplido).
- §15 "Release criteria" del PRD v3 (proceso de release PWA; la iOS tendrá los suyos).
- Estrategias PWA de la matriz R1–R10 (columna "Estrategia v3"): eran workarounds de plataforma web; quedan superadas — se preserva la *capacidad objetivo* en `platform-matrix.md`.
- Deferred items del spine v3 (cache-busting de sw.js, push service worker): específicos de plataforma web.
