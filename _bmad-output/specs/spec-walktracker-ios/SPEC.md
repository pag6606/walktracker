---
id: SPEC-walktracker-ios
companions:
  - capabilities.md
  - domain-model.md
  - achievements.md
  - platform-matrix.md
  - ../../../quotes.json
  - ../../planning-artifacts/architecture/architecture-walktracker-2026-09-12/ARCHITECTURE-SPINE.md
  - ../../planning-artifacts/architecture/architecture-walktracker-2026-09-12/DEROGACIONES.md
  - ../../planning-artifacts/architecture/architecture-walktracker-2026-09-12/REESTIMACION-EPICS.md
sources:
  - ../../../input/SPEC_WalkTracker_v3_PWA.md
  - ../../planning-artifacts/prds/prd-walktracker-v3-2026-07-07/prd.md
  - ../../planning-artifacts/architecture/architecture-walktracker-v3-2026-07-07/ARCHITECTURE-SPINE-v3.md
  - ../../../domain.js
  - ../../../motivation.js
  - ../../../climate.js
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability only — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# SPEC — WalkTracker iOS (nativa)

## Why

Dolor + oportunidad. Paul —usuario único— camina para superar el sobrepeso y quiere ver su progreso reconocido sin fricción. La PWA v3 (producto puente) ya validó en producción el dominio motivacional completo: metas semanales, 14 logros, 100 frases, clima, historial con totales. Pero la plataforma web en iOS impone tres límites estructurales documentados: los pasos solo se cuentan en foreground con pantalla activa (caminar con música degrada a pasos estimados "~"), no hay escritura en Apple Salud, y el storage es evictable (exige respaldos manuales). La app iOS nativa elimina esos tres límites —conteo 24/7 por coprocesador de movimiento, HealthKit, storage garantizado— reutilizando el dominio ya validado: es un cambio de adaptadores, no de modelo. Es el producto objetivo "v2" que la v3 anticipó, y el momento es ahora: el dominio está probado y lo único que falta es la plataforma que lo libere.

## Capabilities

- **CAP-1**
  - **intent:** El usuario puede iniciar, pausar y finalizar una sesión de caminata con cronómetro wall-clock; la pausa es solo explícita y cambiar de app no pausa.
  - **success:** Sesión de 10 min con 5 min en otra app: al volver, el tiempo transcurrido es exacto (wall-clock) y la pausa solo descuenta lo pausado explícitamente.
- **CAP-2**
  - **intent:** El usuario cuenta sus pasos automáticamente de forma continua —foreground, background y pantalla bloqueada— mediante el coprocesador de movimiento del sistema, con el teléfono en el bolsillo.
  - **success:** Caminata de 10 min con pantalla bloqueada y música sonando: pasos con error ≤10 % respecto a la app Salud.
- **CAP-3**
  - **intent:** El sistema reconstruye con datos exactos los intervalos en que la app estuvo en background, sin estimar; la estimación por cadencia queda como degradación excepcional, siempre marcada y descartable.
  - **success:** Gap de 5 min con música: los pasos del intervalo provienen de la consulta al sistema; 0 pasos estimados marcados "~".
- **CAP-4**
  - **intent:** El usuario ve métricas en vivo durante la sesión: pasos, distancia, tiempo, ritmo y cadencia; la distancia usa la del sistema cuando la provee y, si no, pasos × zancada configurada.
  - **success:** Las métricas mostradas cuadran con las fórmulas de dominio (`domain-model.md`); el ritmo solo aparece con distancia ≥ 100 m.
- **CAP-5**
  - **intent:** El usuario ve un snapshot de clima congelado al inicio de la sesión (temperatura, sensación, condición, humedad, UV, viento); sin red o sin permiso de ubicación, la sesión inicia sin clima.
  - **success:** Con red: snapshot visible en la sesión. En modo avión: la sesión funciona completa sin clima, sin bloqueos.
- **CAP-6**
  - **intent:** El usuario recibe una frase motivacional al iniciar cada sesión, de un banco de 100, sin repetición en las últimas 20, en un overlay de 3–4 s saltable con un tap.
  - **success:** 20 sesiones consecutivas sin frase repetida; el overlay se descarta con un tap antes de los 4 s.
- **CAP-7**
  - **intent:** El usuario configura una meta semanal de km (default 10) y ve su progreso en un anillo calculado sobre la semana ISO, con celebración al cumplirla.
  - **success:** El anillo refleja exactamente la suma de distancias de la semana ISO (lunes–domingo) ÷ meta; al cruzar el 100 % hay celebración.
- **CAP-8**
  - **intent:** El usuario desbloquea logros de un catálogo de 14 (`achievements.md`), evaluados al cierre de cada sesión, con celebración visual + sonora + háptica.
  - **success:** Al completar el primer kilómetro se desbloquea "Tu primer kilómetro" con celebración; los logros ya desbloqueados no se re-disparan.
- **CAP-9**
  - **intent:** El usuario tiene persistencia local garantizada y no evictable: sesiones, logros y configuración sobreviven reinicios del dispositivo sin respaldos manuales.
  - **success:** Reinicio del iPhone → historial, logros y configuración íntegros, sin haber exportado nada.
- **CAP-10**
  - **intent:** El usuario consulta su historial en lista descendente con totales de semana/mes y un gráfico de tendencia; las sesiones con pasos estimados aparecen marcadas.
  - **success:** Con 5 sesiones registradas, los totales cuadran con la suma exacta; con historial vacío se muestra empty state.
- **CAP-11**
  - **intent:** El usuario ve cada sesión finalizada escrita automáticamente en Apple Salud como workout de caminata con distancia y pasos.
  - **success:** Tras finalizar una sesión, el workout aparece en la app Salud con distancia y pasos correctos.
- **CAP-12**
  - **intent:** El usuario recibe feedback háptico y sonoro en los eventos clave (inicio de sesión, cada km, meta cumplida, logro desbloqueado), sin interrumpir la música en reproducción.
  - **success:** En dispositivo físico, cada evento produce su háptica/sonido mientras la música sigue sonando.
- **CAP-13**
  - **intent:** El usuario recalibra su zancada in-app; las sesiones ya cerradas conservan congelada la zancada con que se registraron.
  - **success:** Tras recalibrar, el historial no cambia; la siguiente sesión usa la nueva zancada.
- **CAP-14**
  - **intent:** El usuario exporta su historial en CSV/JSON compartible y puede re-importar el JSON para restaurarlo.
  - **success:** Export JSON → borrar datos → import → historial restaurado íntegro; el CSV abre en Numbers/Excel.
- **CAP-15**
  - **intent:** El usuario elimina sesiones individuales del historial.
  - **success:** La sesión eliminada desaparece de la lista y deja de contar en totales, meta y logros no desbloqueados aún.
- **CAP-17**
  - **intent:** El usuario recibe notificaciones locales de recordatorio de su meta semanal.
  - **success:** Con la notificación programada, el recordatorio llega en el momento configurado con la app cerrada.
- **CAP-18**
  - **intent:** El usuario ve las métricas de su sesión en vivo (pasos, distancia, tiempo) en la pantalla de bloqueo mediante una Live Activity, y en la Dynamic Island cuando el hardware la tiene, sin desbloquear el teléfono.
  - **success:** Con sesión activa y teléfono bloqueado, la Live Activity muestra las métricas actualizándose en vivo; al finalizar la sesión, la Live Activity se cierra. En iPhone sin isla, la Live Activity de pantalla de bloqueo funciona igual.

## Constraints

- **SwiftUI nativo (decisión Paul, OQ-1 reabierta y resuelta de nuevo el 2026-09-12):** app iOS nativa contra el SDK de iOS 26, sin WebView y sin capa híbrida. El dominio de la v3 se porta a Swift idiomático; las capacidades del sistema se acceden por adapters detrás de puertos. Descarta Capacitor, Flutter y cualquier sustrato híbrido. Deroga `PLAN-CAPACITOR-v2.md` — el inventario de lo anulado y lo absorbido está en el companion `DEROGACIONES.md`, que es vinculante. Los invariantes de construcción están en el companion `ARCHITECTURE-SPINE.md` como `AD-1`…`AD-24`, IDs estables y citables.
- **Suelo de despliegue iOS 26.0:** el dispositivo es un iPhone 14 con iOS 26 y es el único universo de instalación. Descarta compatibilidad hacia atrás: `if #available` hacia versiones anteriores está prohibido.
- **No-backend (invariante permanente):** todo on-device; la única llamada de red permitida es el clima. Descarta autenticación, cuentas, sincronización cloud y servidor propio.
- **Usuario único:** producto estrictamente personal (Paul). Descarta multi-cuenta, perfiles y cualquier UX de identidad.
- **Privacidad:** datos en el dispositivo; sin analítica ni telemetría de terceros; si el clima sale por red, las coordenadas se redondean a 2 decimales antes de enviarse.
- **Dominio preservado — los invariantes, no los defectos:** se reutilizan los invariantes validados en v3 —cronómetro wall-clock, pausa explícita única, sesión finalizada inmutable, zancada congelada al cierre, validación en la frontera, cadencia calculada solo sobre tramos medidos, pasos estimados siempre desglosados y marcados—. Descarta reescribir el modelo de dominio (`domain-model.md`). **Cuatro divergencias son obligatorias** respecto al código v3, declaradas en `ARCHITECTURE-SPINE.md` AD-6: logros temporales y rachas en hora local y no UTC; lluvia por código WMO y no por regex sobre string localizado; las pausas se restan una sola vez (`domain.js:349-352` las resta dos: cadencia 84,4 donde debe ser 80,3, ritmo 1.085 donde debe ser 1.140); y las rachas se comparan como fechas (`motivation.js:156-159` ordena lexicográficamente sin relleno de ceros y rompe una racha real del 25-sep al 1-oct).
- **Arquitectura hexagonal:** dominio puro sin frameworks de plataforma ni UI; puertos definidos en el dominio, adapters en el borde. Descarta lógica de dominio en views/controllers.
- **Licencias:** en **código**, solo dependencias Apache-2.0 / MIT; copyleft fuerte (GPL/AGPL) es bloqueante. En **fuentes de datos** se admite CC-BY 4.0 con atribución visible — Open-Meteo lo es, y su atribución va en Ajustes → Acerca de.
- **Batería:** una sesión de 30 min con conteo continuo no degrada la batería de forma notoria: la caída total en esos 30 min no supera el 5 %, y Ajustes → Batería confirma que WalkTracker no es un consumidor destacado de ese periodo.
  > ⚠️ **ENMENDADO el 2026-09-13** (decisión de Paul): antes 60 min. La precisión no depende de la duración y la batería se mide con la atribución por app de iOS, no solo con el porcentaje. [`sprint-change-proposal-2026-09-13.md`]
- **UX:** targets táctiles ≥ 44 pt, claro/oscuro, dirección "celebrar, nunca culpar", números grandes, momento motivacional de 3–4 s saltable; UI en español.

## Non-goals

- Backend, autenticación, multi-usuario, sincronización cloud (invariante permanente del producto).
- GPS de ruta ni mapas.
- Conteo manual de vueltas (superado desde v3; no regresa).
- Android, watchOS, iPad.
- Lectura de datos de Apple Salud (solo escritura de workouts propios).
- Funciones sociales: retos, leaderboards, compartir progreso.
- Control de la reproducción de música.
- Publicación en App Store como requisito de éxito (instalación por build local o TestFlight es suficiente).
- Importación del historial de la PWA (decisión Paul, OQ-3: arranque limpio; CAP-16 retirada y su ID reservada por si se reactiva en una versión futura).
- Capacitor, WebView y cualquier sustrato híbrido (decisión Paul, OQ-1 reabierta el 2026-09-12).

## Success signal

Paul sale a caminar con el iPhone en el bolsillo, auriculares con música y pantalla bloqueada; al terminar, la app muestra pasos, distancia y tiempo exactos (≤10 % vs Salud), el workout ya está escrito en Apple Salud y la app celebra el km recorrido y su progreso semanal — sin que Paul haya tocado la pantalla durante toda la caminata. A los 30 días: historial íntegro sin ningún respaldo manual y Paul reporta sentirse reconocido. El gate en su iPhone 14 físico se conserva y cambia de significado: una sesión completa de **30 min** con conteo en background sin degradación de batería notoria (≤ 5 % de caída y WalkTracker no destacado en Ajustes → Batería) y con precisión ≤ 10 % vs Salud *(enmendado el 2026-09-13; antes 60 min)*. Ya no valida si un WebView aguanta —ese riesgo desaparece con el sustrato nativo—, valida NFR-8.

## Assumptions

- **A-1:** Paul dispone o dispondrá de Mac + Xcode + cuenta Apple Developer de pago — barrera documentada desde v3 como la razón de ser del producto puente PWA.
- **A-2 [verificada, ya no es supuesto]:** el dispositivo es un **iPhone 14** (A15, sin Dynamic Island) con **iOS 26**. Consecuencia: CAP-18 se valida solo en el layout de pantalla de bloqueo; la Dynamic Island se limita a compilar.
- **A-3:** El banco de 100 frases (`quotes.json`) y el catálogo de 14 logros se reutilizan íntegros, sin cambios de contenido.

## Open Questions

*(Ninguna abierta.)*

**OQ-5 RESUELTA (Paul, 2026-09-12):** el iPhone 14 de validación **se congela en iOS 26** y no se actualiza a iOS 27 hasta terminar el desarrollo. El toolchain se queda en Xcode 26.6 / Swift 6.3.3. Consecuencias aceptadas, registradas aquí porque vinculan:

- Las actualizaciones automáticas de iOS deben quedar **desactivadas** en el dispositivo; las Respuestas de Seguridad pueden seguir activas.
- iOS 26.6.2 es la última del ciclo y **no trae parches de seguridad** — los siguientes van en iOS 27. El dispositivo queda sin parches nuevos durante el desarrollo. Riesgo aceptado: dispositivo personal, app sin backend, sin datos de terceros.
- La app se construirá y validará **solo contra iOS 26**. El día que Paul actualice a iOS 27 será la primera vez que corra ahí: la primera sesión post-actualización es una **revalidación obligatoria** de CAP-2 y CAP-3, no un trámite.

*(OQ-3 y OQ-4 resueltas por Paul el 2026-07-28. OQ-2 resuelta el mismo día: Live Activity en scope como CAP-18. **OQ-1 reabierta y resuelta de nuevo el 2026-09-12: SwiftUI nativo, superseding Capacitor.**)*
