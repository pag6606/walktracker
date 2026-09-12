---
type: rubric-review
target: ../ARCHITECTURE-SPINE.md
reviewer: rubric-walker
date: 2026-07-28
verdict: APPROVE WITH CHANGES
---

# Review por rúbrica — Architecture Spine WalkTracker iOS (Capacitor)

**Veredicto global: APPROVE WITH CHANGES.** El spine es sólido en lo esencial (cobertura completa de CAPs, stack verificado en fuente el mismo día, sobre operativo presente, decisiones trazables al memlog), pero tiene dos hallazgos HIGH que conviene corregir antes de generar epics/stories: la omisión del camino de pasos/wake del canal web en las tablas de capas y puertos, y la colisión de identificadores AD nuevos vs heredados.

---

## 1. ¿Fija los puntos de divergencia reales para epics/stories?

**Veredicto: MAYORMENTE SÍ, con dos lagunas.**

Cubierto bien: frontera nativa única (AD-2), detección de plataforma (AD-3), estrategia de pasos en background (AD-4), alimentación nativa de la Live Activity (AD-6), distribución (AD-5), permisos/escritura HealthKit (AD-8), bundle local (AD-7). Son exactamente los puntos donde dos builders divergerían.

**Laguna A (HIGH):** el camino de pasos del **canal web/PWA** no está representado. El seed de `MotionPort` (líneas 193-196) tiene forma nativa (`onSteps(cumulativeCount)`); la v3 definía `MotionPort.onSample(callback)` a 60 Hz alimentando `StepDetector` (v3 AD-12). El spine no dice si el adapter web implementa el puerto nuevo (¿adaptando StepDetector → cumulative?), si coexisten dos contratos, ni si v3 AD-12 sigue vigente en la PWA. Dos stories (motion nativa vs preservación PWA) pueden divergir incompatiblemente sobre qué es `MotionPort`.

**Laguna B (MEDIUM):** `KeepAwakePort` (línea 204) solo nombra `CapacitorKeepAwakeAdapter`. El canal web necesita un adapter (hoy `createWakeLockPort` en `runtime.js:27`); el spine no lo nombra ni hereda v3 AD-16. El composition root de AD-3 no tiene regla de qué registrar en web para keep-awake.

## 2. ¿Toda Rule es enforceable y previene su divergencia declarada?

**Veredicto: SÍ salvo AD-5 (parcial) y una cláusula de AD-3.**

| AD | Enforceable | Evidencia |
| --- | --- | --- |
| AD-1 | Sí | Grepeable: imports de Capacitor fuera de `Capacitor*Adapter`/composition root. Previene el acoplamiento declarado. |
| AD-2 | Sí | Estructural: un solo paquete `./walktracker-kit`; los 3 adapters JS hablan solo con él. Revisable en PR. |
| AD-3 | Casi | Detección en composition root: chequeable. La cláusula final "toda feature nueva nace con su camino de degradación web definido" es **aspiracional** (proceso, no verificable). LOW. |
| AD-4 | Sí | `query` primario, `GapEstimator` solo si null/vacío: revisable en código; umbrales heredados (≥120 s, "~") son testeables. |
| AD-5 | **Parcial (MEDIUM)** | La regla de promoción a TestFlight depende de "pasar la prueba de performance" cuyo protocolo está en **Deferred**. Tal cual, el único mecanismo de enforcement de la Rule es indefinido: dos hitos podrían interpretar distinto cuándo "pasa". El criterio existe en el spec (Success signal: 60 min, ≤10 % vs Salud) pero el spine lo difiere sin fijar el mínimo. |
| AD-6 | Sí | Verificable: la Activity se actualiza desde callbacks CMPedometer del plugin, sin round-trip JS. |
| AD-7 | Sí | Inspeccionable: `capacitor.config.json` sin `server.url` en producción; única red = Open-Meteo. |
| AD-8 | Sí | Un solo call-site de `writeWorkout` al finalizar; cancel-then-schedule idempotente: revisable y testeable. |

## 3. ¿Algo en Deferred permite divergencia incompatible entre unidades?

**Veredicto: dos riesgos.**

- **Canal háptico (MEDIUM):** se difiere "CoreHaptics dentro de walktracker-kit vs API vía WebView" sin fijar zona de aterrizaje ni puerto. Si cae en CoreHaptics, la superficie de `walktracker-kit` (fijada por AD-2 como CMPedometer + HKWorkout + ActivityKit) crece sin AD que lo ampare; una story podría crear `HapticsPort` y otra llamar al plugin directo. Deferred legítimo, pero debería declarar "se resuelve como adapter tras un puerto, nunca llamada directa".
- **Protocolo de performance (MEDIUM):** deferred a epic, pero AD-5 lo referencia como gate. Cross-dependencia Deferred↔Rule (ver §2).
- Sin riesgo: contenido de la Live Activity (componente único), sync PWA↔app (fuera de scope explícito, CAP-16 retirada), cache-busting del SW (problema heredado declarado), calibración interactiva (producto futuro).

## 4. ¿La tecnología nombrada está verificada como vigente?

**Veredicto: SÍ — spot-check completo superado el 2026-07-28.**

| Claim | Verificación | Resultado |
| --- | --- | --- |
| @capacitor/core 8.4.2, MIT | `npm view` | 8.4.2, MIT ✓ |
| @capacitor/cli 8.4.2, Node ≥22 | `npm view` | 8.4.2, `engines.node >=22.0.0` ✓ |
| @capacitor/ios 8.4.2 | `npm view` | 8.4.2 ✓ |
| @capacitor/local-notifications 8.2.1, MIT | `npm view` | 8.2.1, MIT ✓ |
| @capacitor-community/keep-awake 8.0.1, MIT | `npm view` | 8.0.1, MIT ✓ |
| Xcode 26.0+ requerido por Capacitor 8 | capacitorjs.com/docs/ios | "iOS 15+ is supported. Xcode 26.0+ is required" ✓ |
| Deployment target 16.1 = piso ActivityKit | coherente con Apple (Live Activities iOS 16.1+) y spec A-2 (dispositivo iOS 17+) ✓ |

**Nit (LOW):** `@capacitor/preferences` se nombra en la fila CAP-9 ("si hiciera falta") pero no figura en la tabla Stack verificada (existe en npm, 8.0.1). Trazabilidad incompleta, no obsolescencia.

## 5. ¿Ratifica el brownfield en vez de contradecirlo?

**Veredicto: CONTRADICE en las tablas de capas (HIGH).**

Ratifica: el Structural Seed lista exactamente los archivos del repo (`index.html`, `domain.js`, `motivation.js`, `climate.js`, `storage.js`, `runtime.js`, `migration.js`, `quotes.json`, `sw.js`, `manifest.webmanifest`, `icons/`, `test/`, `e2e/`); AD-1 declara la web app "empaquetada intacta", lo cual es cierto y verificable.

Contradice: la tabla de capas (línea 32) enumera el Domain **sin `StepDetector`**, y los adapters JS **sin `DeviceMotionAdapter` ni `WakeLockAdapter`**. Pero el código que "se sirve intacta" los contiene y los usa: `domain.js:401` (`createStepDetector`, v3 AD-12), `index.html:535` (instancia StepDetector con `devicemotion` listener), `runtime.js:27` (`createWakeLockPort`, v3 AD-16). Un builder que lea solo el spine concluiría que StepDetector fue eliminado del dominio; otro que lea el código lo mantendrá. Divergencia garantizada a nivel de story.

## 6. ¿Cubre las 17 capabilities activas del spec?

**Veredicto: SÍ, completo.**

El front-matter `binds` y el Capability → Architecture Map cubren CAP-1..CAP-15, CAP-17 y CAP-18 — las 17 activas. Contrastado con `capabilities.md`: CAP-16 está "❌ RETIRADA (OQ-3)" y correctamente ausente. Cada fila tiene Lives-in + Governed-by. Los nombres coinciden con el spec.

## 7. ¿Algún AD nuevo debilita o contradice un invariante heredado?

**Veredicto: ninguna contradicción semántica; pero colisión de IDs (HIGH) y herencia incompleta (MEDIUM).**

- Semántica limpia: AD-4 nuevo acota `GapEstimator` a degradación **solo en nativo** preservando el camino web explícitamente — estrecha, no contradice v3 AD-13. AD-1 nuevo refuerza el AD-1 heredado. AD-8 nuevo es consistente con el aggregate inmutable heredado (AD-4 v3). AD-6/AD-7 nuevos no tocan invariantes v3.
- **Colisión de IDs (HIGH):** los AD nuevos reusan AD-1..AD-8, que ya existen como heredados del spine v3 (AD-1..AD-18). El propio Capability Map mezcla ambos espacios: "AD-4" (nuevo, query background) en la fila CAP-3 vs "AD-4/5 heredados (v3)" en CAP-4/CAP-13; "AD-3" (nuevo, doble canal) en la fila Doble canal vs "AD-3 heredado (v3)" (storage) en CAP-9/CAP-15. Toda cita "AD-n" en una story será ambigua salvo que se califique; el spine debería renumerar (p. ej. AD-C1..AD-C8 o continuar AD-19+).
- **Herencia incompleta (MEDIUM):** la tabla Inherited omite v3 AD-2 (vanilla sin build), AD-9 (AudioContext unlock), AD-10 (SW offline), AD-11 (Pages paths relativos), AD-12 (StepDetector), AD-13 (GapEstimator) y AD-16 (WakeLock) — pese a que el Map cita "AD-3/AD-15 heredados" (tampoco listados), AD-4 nuevo restatea las reglas de AD-13 ("muestra ≥120 s, desglosado, '~', descartable"), y la PWA sigue dependiendo de AD-10/11/12/16. Lo citado en el Map debería estar en la tabla, o marcarse explícitamente como superseded.

## 8. ¿Toda dimensión estructural de esta altitud está decidida, diferida o como open question?

**Veredicto: SÍ — el sobre operativo/ambiental NO está silente.**

Deployment & environments: decidido (AD-5 + "Entornos / sobre operativo", línea 207: dev = builds locales Xcode en iPhone físico + `http://localhost`; prod = TestFlight + GitHub Pages). Infra/provider: decidido por negativa explícita ("sin backend, sin CI de servidor"; única red = Open-Meteo). Operations: distribución archive → App Store Connect → TestFlight (AD-5), convención de version-sync de canales (mismo merge a `main`), entitlements/Info.plist fijados en Consistency Conventions. Sin dimensiones mudas detectadas.

Delgadeces aceptables (LOW): sin esquema de versionado/build numbers de TestFlight (nivel story); gestión de certificados/firma delegada a Xcode sin convención (aceptable para un desarrollador único, pero una línea la cerraría).

---

## Hallazgos (clasificados)

| # | Severidad | Hallazgo | Ítem |
| --- | --- | --- | --- |
| F1 | **HIGH** | Canal web sin representación: Domain sin `StepDetector`, adapters sin `DeviceMotionAdapter`/`WakeLockAdapter`, `MotionPort` seed solo en forma nativa, v3 AD-12/AD-16 ni heredados ni superseded — contradice el brownfield (`domain.js:401`, `runtime.js:27`, `index.html:535`) y deja a dos stories divergir sobre qué es MotionPort en la PWA. | 1, 5, 7 |
| F2 | **HIGH** | Colisión de identificadores AD: nuevos AD-1..AD-8 reusam IDs de los heredados v3 (AD-1..AD-18); el Capability Map cita ambos espacios ("AD-4" vs "AD-4 heredado (v3)"). Trazabilidad ambigua garantizada en epics/stories. | 1, 7 |
| F3 | **MEDIUM** | AD-5 inenforceable tal cual: su gate de TestFlight depende del protocolo de performance que está en Deferred; una Rule no debería colgar de un ítem indeciso (fijar al menos el mínimo del Success signal: 60 min background, ≤10 % vs Salud). | 2, 3 |
| F4 | **MEDIUM** | Tabla Inherited incompleta: el Map y los ADs citan/implican v3 AD-2, AD-3, AD-9, AD-10, AD-11, AD-12, AD-13, AD-15, AD-16 que no figuran como heredados ni como superseded. | 7 |
| F5 | **MEDIUM** | Canal háptico diferido sin zona de aterrizaje ni puerto: puede expandir la superficie de `walktracker-kit` (AD-2) o colarse como llamada directa sin adapter. | 3 |
| F6 | **LOW** | AD-3 cierra con cláusula aspiracional ("toda feature nueva nace con su camino de degradación web definido") no verificable mecánicamente. | 2 |
| F7 | **LOW** | `@capacitor/preferences` nombrado en CAP-9 sin entrar en la tabla Stack verificada (existe: 8.0.1). | 4 |
| F8 | **LOW** | Sin esquema de versionado/build number de TestFlight ni convención de firma; aceptable a esta altitud, una línea en Conventions lo cerraría. | 8 |

## Lo que está bien (para no tocar)

- Cobertura íntegra de las 17 CAPs activas con Lives-in + Governed-by (ítem 6).
- Stack 100 % verificado en npm registry y capacitorjs.com el mismo día (ítem 4); todas las licencias MIT, conforme a AGENTS.md.
- AD-6 (Live Activity alimentada por nativo) es la decisión correcta y bien razonada — el JS del WebView se suspende en background; documentado en memlog DECISION 6.
- Sobre operativo completo y explícito, incluyendo "sin backend, sin CI" por negativa (ítem 8).
- AD-4 nuevo estrecha GapEstimator sin contradecir la herencia; scoping por canal explícito.

## Acciones requeridas antes de epics

1. (F1) Añadir a las tablas: `StepDetector` en Domain (canal web), adapter de movimiento web y `WakeLockAdapter` web para `KeepAwakePort`; declarar si v3 AD-12/AD-16 se heredan (scope PWA) o se superseden, y cómo el `MotionPort` web satisface el contrato seeded.
2. (F2) Renumerar los AD nuevos para no colisionar con los heredados (p. ej. AD-C1..C8 o AD-19..AD-26) y actualizar el Capability Map.
3. (F3) Fijar en AD-5 el criterio mínimo del gate (referencia directa al Success signal del spec) o mover el gate al Deferred.
4. (F4) Completar la tabla Inherited con los v3 ADs citados o marcarlos superseded explícitamente.
5. (F5) Acotar el Deferred háptico: "se resuelve como adapter tras puerto; si es CoreHaptics, entra en walktracker-kit previa actualización de AD-2".
