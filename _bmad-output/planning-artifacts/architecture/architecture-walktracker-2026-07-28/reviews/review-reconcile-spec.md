# Reconciliation Review — SPEC-walktracker-ios vs ARCHITECTURE-SPINE

- **Date:** 2026-07-28
- **Reviewer role:** reconciliation reviewer (read-only)
- **Inputs:**
  - Spine: `../ARCHITECTURE-SPINE.md` (status: draft, 2026-07-28)
  - Spec package: `../../../../specs/spec-walktracker-ios/` — `SPEC.md`, `capabilities.md`, `domain-model.md`, `achievements.md`, `platform-matrix.md`
- **Method:** every load-bearing claim of the SPEC (capabilities CAP-1..CAP-18, constraints, quiet rules, Success signal) was checked against the spine's invariants (AD-1..AD-8 + inherited), Consistency Conventions, port contracts, Capability→Architecture Map and Deferred section. Only misses are reported in detail; landed areas get one-line confirmations.
- **Classification scale:** CRITICAL (spec requirement silently dropped) · HIGH (partially landed, rule weakened) · MEDIUM (landed but vague) · NONE.

## Verdict

**6 findings — 1 CRITICAL, 2 HIGH, 3 MEDIUM.** The spine lands the structural core of the SPEC (double channel, native edge, background reconstruction, HealthKit, distribution, privacy, licensing) faithfully, and correctly excludes the retired CAP-16. The misses concentrate on (a) one explicit portation correction the spine contradicts, (b) one capability rule the port contract cannot carry, and (c) the quiet UX/battery/music constraints that have no home in the spine.

## Findings

| # | Severity | Area | Summary |
|---|----------|------|---------|
| F1 | CRITICAL | Dominio / portación (domain-model §9, achievements.md) | Correcciones deliberadas de portación (hora local en `early_bird`/`night_walker`/rachas; `rain_walker` por código WMO, no regex localizado) ausentes del spine y contradichas por "web app intacta / domain.js sin cambios" |
| F2 | HIGH | CAP-4 (métricas, platform-matrix R8) | Regla "distancia del sistema preferida" no aterriza: el `MotionPort` del seed solo expone pasos, sin canal de distancia |
| F3 | HIGH | Constraint UX (SPEC §Constraints) | Bloque UX ausente: tono "celebrar, nunca culpar", targets ≥ 44 pt, claro/oscuro, números grandes, español, overlay motivacional 3–4 s saltable |
| F4 | MEDIUM | CAP-12 (háptica/sonido) | Regla "sin interrumpir la música" (sonidos cortos, sin ducking agresivo) no capturada; canal háptico diferido explícitamente (OK) pero sin invariante de convivencia de audio |
| F5 | MEDIUM | Constraint Batería / Success signal | El NFR de batería (60 min sin degradación notoria) existe solo como protocolo dogfood diferido + gate de TestFlight; ninguna regla de diseño lo sostiene |
| F6 | MEDIUM | CAP-5 (clima) | Sub-regla "permiso de ubicación denegado → sin re-pedir en cada sesión" no aparece; el resto de CAP-5 aterrizó |

---

### F1 — CRITICAL: las correcciones de portación de `domain-model.md` §9 no aterrizan y el spine las contradice

**Spec (load-bearing):**
- `domain-model.md` §9 (líneas 110–113): *"En iOS deben evaluarse en **hora local del dispositivo**… Se registra aquí para que la portación lo corrija deliberadamente, no por arrastre"* y *"la regla debe mapear la condición del proveedor (… código WMO) a una categoría interna (`rain`), sin depender de strings localizados"*.
- `achievements.md` líneas 26–27 repiten ambas notas como regla.

**Spine:**
- AD-1 (línea 26): *"La web app v3 (UI + Application + Domain) se sirve intacta dentro del WKWebView"*; línea 84: *"viven en la web app que se empaqueta sin cambios"*; Structural Seed línea 176: `domain.js # Domain puro (sin cambios)`.
- Ni "hora local", ni "UTC", ni "WMO", ni "regex" aparecen en ninguna parte del spine. La fila CAP-8 del mapa (línea 220) solo apunta genéricamente a `spec achievements.md`.

**Por qué es CRITICAL:** el spec contiene dos correcciones normativas ("deben") diseñadas explícitamente para que la portación las haga *deliberadamente*. El spine, leído literalmente, ordena empaquetar `domain.js` sin cambios — es decir, arrastrar el bug de UTC y el regex sobre strings localizados. No hay carve-out en invariants, convenciones, mapa de capabilities ni Deferred. Un implementador siguiendo solo el spine shipparía la evaluación de logros conocidamente incorrecta en el producto cuyo núcleo es motivacional. El puntero desnudo a `achievements.md` no salva el conflicto con el lenguaje "intacta / sin cambios".

**Fix sugerido:** añadir una regla explícita (p. ej. nota en la fila CAP-8 o convención) que abra excepción al "sin cambios" para estas dos correcciones: evaluación de logros temporales en hora local del dispositivo y mapeo de condición WMO → categoría interna `rain` en el adapter de clima.

### F2 — HIGH: la preferencia de distancia del sistema (CAP-4 / R8) no existe en el spine ni cabe en `MotionPort`

**Spec:**
- SPEC.md CAP-4 (línea 39): *"la distancia usa la del sistema cuando la provee y, si no, pasos × zancada configurada"*.
- `capabilities.md` CAP-4 (línea 33): *"Distancia: la del sistema (CMPedometer distance) cuando está disponible; si no, `(stepsMeasured + stepsEstimated) × strideM`"*.
- `platform-matrix.md` R8 (línea 14): *"Distancia estimada por el sistema disponible; zancada queda como fallback y calibración opcional"* — es una de las 10 resoluciones de plataforma que justifican el producto.

**Spine:**
- Fila CAP-4 (línea 216): `MetricsCalculator (web)` gobernado por *"AD-4/5 heredados (v3)"* — es decir, solo la regla de fallback por zancada.
- Contrato `MotionPort` (líneas 193–196): `start → stream onSteps(cumulativeCount)`, `query(fromMs, toMs) → steps | null`. **No hay canal de distancia** ni en el stream ni en la query, aunque CMPedometer la provee en ambos.
- Ningún invariante menciona la preferencia de fuente de distancia.

**Por qué es HIGH:** la capability está mapeada y el camino de fallback aterriza, pero la regla que define su valor en nativo (preferir la distancia del sistema, volviendo la calibración opcional) está silenciosamente ausente; peor, el contrato de puerto semilla no la puede transportar. Un build conforme al spine produciría distancia siempre por zancada. Roza CRITICAL porque el requisito queda de facto dropeado del sustrato arquitectónico.

**Fix sugerido:** extender el seed de `MotionPort` (`onSteps(cumulativeCount, distanceM?)`, `query → { steps, distanceM } | null`) y citar la regla de preferencia en la fila CAP-4 o en una convención.

### F3 — HIGH: el bloque de constraints UX no aterrizó (incluido el tono "celebrar, nunca culpar")

**Spec (SPEC.md línea 91, repetido en `capabilities.md` línea 151 y `platform-matrix.md` línea 35):** *"targets táctiles ≥ 44 pt, claro/oscuro, dirección 'celebrar, nunca culpar', números grandes, momento motivacional de 3–4 s saltable; UI en español"* — listado como **Constraint** del contrato, no como detalle de story.

**Spine:** ninguna de estas reglas aparece. Ni "44 pt", ni "claro/oscuro", ni "español", ni "números grandes", ni el tono "celebrar, nunca culpar", ni el overlay de 3–4 s saltable (la fila CAP-6, línea 218, solo hereda AD-18: banco en bundle + no-repetición de 20). El spine sí creó fila de convención para Privacy (línea 150) — demuestra que el vehículo existía y el bloque UX simplemente no se cargó.

**Por qué es HIGH (no CRITICAL):** la parte de selección de frases aterrizó vía AD-18, y `capabilities.md` anuncia un UX pass posterior ("el UX pass de Sally decide la forma final") — pero ese pass decide *forma*, mientras estas son *invariantes que cruzan plataforma* según el propio spec. El tono es la quiet constraint más fácil de perder entre capas y la que más daño hace si se pierde (copy de celebraciones, empty states, logros).

**Fix sugerido:** añadir una fila `UX` en Consistency Conventions con las seis reglas verbatim del spec.

### F4 — MEDIUM: CAP-12 sin la regla de convivencia con música

**Spec:** SPEC.md línea 63 — *"sin interrumpir la música en reproducción"*; `capabilities.md` línea 101 — *"sonidos cortos, sin ducking agresivo"*. La música sonando es además el escenario del Success signal.

**Spine:** fila CAP-12 (línea 224) + Deferred (línea 236) difieren el canal háptico a story — deferral explícito y aceptable. Pero la regla de convivencia de audio (sesión de audio ambient, sin ducking) no está en ningún invariante ni convención, y la lista de eventos (inicio, km, meta, logro) tampoco se nombra. Landed pero vago: queda a criterio de la story tanto el canal como el comportamiento de audio.

### F5 — MEDIUM: batería / validación de performance solo como deferral

**Spec:** constraint Batería (línea 90) y Success signal (línea 108): *"una sesión completa de 60 min con conteo en background sin degradación de performance ni de batería notoria"*; la viabilidad misma de Capacitor queda condicionada a ello (línea 83).

**Spine:** AD-5 (línea 123) usa la prueba de performance como gate de TestFlight ✓, y Deferred (línea 235) baja el protocolo dogfood a epic/story — explícito, no silencioso. Pero el constraint no se traduce en ninguna regla de diseño (p. ej. política de actualización de la Live Activity, adquisición de keep-awake acotada a foreground) ni se re-enuncia como invariante. AD-6 mitiga el riesgo principal (WebView suspendido) de forma implícita. Landed pero vago.

### F6 — MEDIUM: CAP-5, sub-regla "no re-pedir ubicación" ausente

**Spec:** `capabilities.md` línea 47 — *"Permiso de ubicación denegado → sesión sin clima, sin re-pedir en cada sesión"*. Es una quiet degradación rule (evita spam de prompts en cada inicio de sesión).

**Spine:** degradación limpia del clima ✓ (AD-14 heredado, línea 94), coords a 2 dp ✓ (AD-17, línea 95), pre-pantallas de permiso ✓ (AD-8, línea 138). La regla específica de no re-pedir tras denegación no aparece. Menor, pero es exactamente el tipo de regla silenciosa que se pierde en implementación.

---

## Confirmations — what landed (one line per area)

- **CAP-1** (cronómetro wall-clock, pausa explícita, recuperación silenciosa): landed — fila línea 213 + AD-6/AD-8 heredados (líneas 91, 93).
- **CAP-2** (pasos 24/7 por coprocesador, pantalla MotionDenied): landed — AD-2 + fila línea 214 + MotionDenied en capa UI (línea 30).
- **CAP-3** (reconstrucción exacta por query; GapEstimator solo degradación con muestra ≥120 s, "~", descartable): landed verbatim — AD-4 (líneas 115–118).
- **CAP-5** (clima Open-Meteo, timeout 3 s, degradación limpia, coords 2 dp): landed — AD-14/17 heredados (líneas 94–95) + fila línea 217 (salvo F6).
- **CAP-6** (100 frases en bundle, sin repetición en 20): landed — AD-18 heredado (línea 96) (timing del overlay: ver F3).
- **CAP-7** (meta semanal ISO, anillo): landed por referencia — fila línea 219 → domain-model §5.
- **CAP-8** (14 logros, evaluación al cierre, no re-disparo): landed por referencia — fila línea 220 → achievements.md (salvo F1).
- **CAP-9** (storage garantizado en sandbox, preferences tras StoragePort): landed — fila línea 221 + AD-7.
- **CAP-10 / CAP-13 / CAP-14 / CAP-15** (historial, recalibración con zancada congelada, export/import, eliminar): landed heredado — filas líneas 222, 225–227; RF-17 correctamente no resucitado.
- **CAP-11** (workout a Salud una vez al cierre, con dato inmutable completo; pre-pantalla): landed — AD-8 (línea 138) + AD-2.
- **CAP-12**: parcial — ver F4.
- **CAP-16 (retirada):** verificado — el spine **no** la cubre: ausente de `binds` (línea 11) y del mapa; ID reservada y reactivación futura anotada en Deferred (línea 238). Conforme a SPEC línea 103 y capabilities líneas 126–128. NONE.
- **CAP-17** (recordatorios locales, reprogramación idempotente cancel→schedule, permiso con pre-pantalla): landed — AD-8 (línea 138) + fila línea 228.
- **CAP-18** (Live Activity alimentada por nativo; WebView solo estado mayor; null = degradación): landed — AD-6 (líneas 125–128) + contrato `LiveActivityPort → activityId | null`. Nota: el spine desvía deliberadamente del "bridge desde el WebView" del spec (capabilities línea 157) hacia callbacks nativos — fortalecimiento justificado y coherente con los criterios de CAP-18; no es un miss.
- **Constraint Capacitor (OQ-1):** landed — AD-1 + gate de viabilidad en AD-5.
- **Constraint No-backend:** landed — AD-7 (línea 133) + "Sin backend, sin CI de servidor" (línea 207).
- **Constraint Privacidad (sin analítica, única red clima, 2 dp, HealthKit solo escritura):** landed verbatim — convención Privacy (línea 150).
- **Constraint Dominio preservado:** landed — tabla Inherited Invariants (líneas 86–96) cubre los 7 invariantes citados por el spec.
- **Constraint Hexagonal:** landed — AD-1 + tabla de capas + regla de flechas (línea 80).
- **Constraint Licencias (solo Apache-2.0/MIT):** landed — Stack con licencia por dependencia (líneas 160–164) + "verificados (MIT)" en AD-2.
- **Constraint Batería / UX:** ver F5 / F3.
- **Constraint Usuario único:** landed por omisión (nada multi-cuenta en el spine).
- **Non-goals:** respetados — App Store fuera de scope (línea 123), HealthKit solo escritura (línea 150), GPS solo one-shot de clima (AD-17), sin control de música.
- **Distribución (TestFlight duradero, builds locales, PWA por GitFlow, mismo commit):** landed — AD-5 + convención "Version sync de canales" (línea 149).
- **Success signal:** parcial — referenciado como gate de TestFlight (línea 123) y protocolo diferido (línea 235); escenario de música/bloqueo cubierto por diseño (AD-4 + AD-6 + AD-8); ver F5 para la parte de batería.
