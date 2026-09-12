---
id: DEROGACIONES-swiftui
fecha: 2026-09-12
companion_de: ARCHITECTURE-SPINE.md
estado: vinculante
---

# Derogaciones y absorciones — pivot a SwiftUI

Inventario de lo que el spine SwiftUI anula, lo que absorbe con heredero, y lo que otro ciclo debe enmendar.
Una derogación sin heredero explícito es una pérdida silenciosa: esta tabla existe para que no las haya.

## 1. `PLAN-CAPACITOR-v2.md` — DEROGADO ENTERO

| Contenido | Destino |
| --- | --- |
| Líneas 27, 62, 179 — *"reutiliza el 90 % del código actual"*, *"el dominio y la UI no se tocan"* | **Anulado.** Falso desde AD-1 |
| Comparativa que descartó SwiftUI *"por effort"* | **Anulada.** Recosteada en `OPCIONES-SUSTRATO.md` |
| **AD-IOS-01** — appId `com.walktracker.app`, inmutable post-distribución | **ABSORBIDO → AD-1** |
| Wake lock como limitación fundacional | **ABSORBIDO → AD-10** (`WakeLockPort`) |
| Entitlements y usage strings | **ABSORBIDO → envoltura operativa del spine** |
| Cuenta Apple Developer de pago | **ABSORBIDO → envoltura operativa** (sigue siendo A-1 del SPEC) |
| Licencias Apache-2.0 / MIT | **Vigente**, con la enmienda de AD-24 (CC-BY admisible en fuentes de datos) |
| Plugin `walktracker-kit`, adapters `Capacitor*`, `server.url`, `webDir` | **Anulados.** Sin heredero: no hay WebView |

## 2. `SPEC.md` — requiere enmienda (ciclo `bmad-spec` aparte)

| Dice hoy | Debe decir |
| --- | --- |
| Constraints: *"Capacitor como capa nativa (decisión Paul, OQ-1)"* | SwiftUI nativo. **OQ-1 reabierta y resuelta de nuevo** el 2026-09-12 |
| Non-goals: *"Reescritura SwiftUI total"* | Retirado del listado |
| A-2: *"El iPhone de Paul corre iOS 17+"* | iPhone 14 con iOS 26; suelo de despliegue 26.0 (AD-2) |
| Constraint de Licencias: solo Apache-2.0 / MIT | Admite CC-BY 4.0 en **fuentes de datos**, no en código (AD-24) |
| Companion `PLAN-CAPACITOR-v2.md` | Sustituido por `ARCHITECTURE-SPINE.md` + este documento |

**Nota sobre CAP-17.** Entró en scope porque `@capacitor/local-notifications` la hacía barata. Esa premisa
desaparece con Capacitor. Re-verificada: `UNUserNotificationCenter` nativo es igual o más simple, sin
dependencia. **CAP-17 se mantiene en scope**; la premisa se sustituye, no se pierde.

## 3. `platform-matrix.md` — OBSOLETO EN SU COLUMNA DE RESOLUCIÓN

Las filas R1–R10 siguen siendo evidencia válida del *Why* (los límites de la PWA son reales). La columna
"iOS nativa (resolución)" está escrita en clave Capacitor y hay que reescribirla: R3 (adapter web
reutilizado), R6 (storage del WebView + `@capacitor/preferences`) y R7 (bridge al WebView) ya no describen
nada que vaya a existir. Va en el mismo ciclo de `bmad-spec`.

## 4. Requisitos UX derogados por patrón nativo

| Requisito | Decía | Deroga | Por qué |
| --- | --- | --- | --- |
| **UX-DR5** | *"navegación iconos top-right (⚙📋🏆) sin tab bar"* | **AD-14** | Describía una PWA de reemplazo de pantalla. En iOS el tab bar es el patrón, y es donde Liquid Glass trabaja |
| **UX-DR7** | *"prohibidos: swipe-to-delete"* | **AD-20** | Restricción de la web. En iOS el swipe **es** el gesto de borrado; el icono embebido es el antipatrón (B-11 de la validación) |
| **UX-DR1** | Design tokens Volt (`#CCFF00`, `#1A1A1A`…) | **AD-13** | Colores del sistema y Liquid Glass heredado. Cablear hexadecimales pelea con el SDK |
| **UX-DR2** | Tipografía en `px` con `clamp()` | **AD-13** + convención de accesibilidad | Dynamic Type nativo; `px` y `clamp()` son conceptos de CSS |

`UX-DR3`, `UX-DR4`, `UX-DR6` y `UX-DR8` siguen vigentes: espaciado, catálogo de componentes,
accesibilidad WCAG AA y los seis flujos no dependen del sustrato.

## 5. Requisitos adicionales de los epics (`AR-*`)

**Derogados:** AR-1 (Capacitor + web intacta), AR-2 (plugin `walktracker-kit`), AR-4 en su mecanismo
(`pnpm cap run ios`), AR-5 (Live Activity alimentada desde el WebView), AR-6 (bundle local / `server.url`),
AR-8 (stack Capacitor completo, target 16.1), AR-9 (structural seed Capacitor), AR-10 en su forma
(los contratos de puerto se redefinen en AD-10).

**Conservados con heredero:** AR-3 → AD-8 · AR-7 → AD-11 + AD-17 · AR-11 → envoltura operativa ·
AR-12 (invariantes v3 heredados) → sigue vigente, ahora verificable por AD-6 · AR-13 → sección Deferred.

**Excepción de AR-1 que se promueve:** las "2 correcciones de portación" que AR-1 autorizaba —logros
temporales en hora local y mapeo WMO— dejan de ser excepciones toleradas y pasan a ser **divergencias
declaradas y obligatorias** en AD-6 y AD-19.

## 6. Bugs de la v3 — CORREGIDOS EN LA REFERENCIA (2026-09-12)

Descubiertos al verificar la suite JS contra `domain-model.md`. Estaban vivos en producción.
**Decisión de Paul: arreglarlos en la v3 antes de portar**, en contra del argumento de eficiencia
("se arreglan solos al portar"). Fue la decisión correcta y por una razón que la mesa no vio:
arreglar la referencia **antes** de escribir el port hace que `domain.js` y el dominio Swift
converjan en vez de divergir, y permite **validar el mecanismo de vectores dorados contra un
runtime que ya existe**, antes de apostar el port a él.

| Bug | Dónde | Efecto real | Estado |
| --- | --- | --- | --- |
| Pausas restadas dos veces | `domain.js:216`, `:351-352` + `index.html` (ritmo en vivo) | Cadencia 84,4 spm donde debe ser 80,3; ritmo 1.085 s/km donde debe ser 1.140. `elapsedS` ya devuelve neto y `pace`/`activeMin` volvían a restar. Además la cadencia **cambiaba al pulsar Finalizar**: la vista en vivo usaba `calculateCadence` (correcta) y el cierre su propio cálculo | ✅ **Corregido.** Tres sitios; `finishV3` ahora reutiliza `calculateCadence`, una sola implementación |
| Rachas comparadas lexicográficamente | `motivation.js:155-158` | Claves sin relleno de ceros: `"2026-9-25"` ordena después de `"2026-10-1"`. Una racha real del 25-sep al 1-oct devolvía `false` | ✅ **Corregido.** Claves `YYYY-MM-DD` y parseo explícito en UTC |
| Ritmo y cadencia con pausas sin assertar | `session-v3-tests.js`, `domain-tests.js` | Los valores correctos estaban escritos **en comentarios**, no en aserciones. La suite pasaba al 100 % porque codificaba el bug | ✅ **Corregido.** La aserción de 84,4 pasa a 80,3, y se añaden 3 regresiones: cadencia viva == cadencia al cerrar, ritmo sin doble resta, y racha cruzando fin de mes con su control negativo |
| `Date.now()` dentro del dominio | `domain.js:249`, `:392` | Viola el `ClockPort`; hace esas funciones invectorizables | ⏳ **Pendiente en el port.** Cambiar la firma en la v3 rompería a sus llamantes sin beneficio; en Swift entra por `ClockPort` (AD-10) desde el día uno |
| `checkTimeOfDay` y rachas en UTC | `motivation.js` | `early_bird` y `night_walker` evalúan la hora en UTC, no local. Según el desfase horario de Paul, un logro puede dispararse a la hora equivocada | ⏳ **Deliberadamente no tocado.** `domain-model.md §9` lo ordena corregir **en iOS**; cambiarlo en la v3 es una decisión de producto, no un arreglo. Sigue siendo divergencia declarada de AD-6 |

**Consecuencia para AD-6:** la tabla de divergencias declaradas pasa de **cuatro filas a dos**.
`domain.js` ya no falla los vectores de ritmo, cadencia y racha — los pasa. Solo quedan divergentes
la hora local y el mapeo WMO, que son decisiones de plataforma, no defectos.

**Verificación:** 438 aserciones en verde tras el cambio (`domain` 51, `session-v3` 184, `motivation` 34,
`gapestimator` 16, `storage` 37, `climate` 26, `runtime` 20, `migration` 31, `stepdetector` 39).
