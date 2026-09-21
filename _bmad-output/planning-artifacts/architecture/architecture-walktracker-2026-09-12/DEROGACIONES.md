---
id: DEROGACIONES-swiftui
fecha: 2026-09-12
actualizado: 2026-09-20
companion_de: ARCHITECTURE-SPINE.md
estado: vinculante
---

> `fecha` es la de creación y no se mueve: es la fecha del pivot que este inventario registra.
> `actualizado` es la de la última enmienda — **2026-09-20**, el chore A-5: §4 reescrita (tercer
> color, condición del gate, ratios en oscuro que faltaban y la marca de fuente única de la tabla) y
> §1 anotada con el estado abierto del wake lock. El spine companion lleva su propio `updated`, y
> los dos apuntan ahora al mismo día.

# Derogaciones y absorciones — pivot a SwiftUI

Inventario de lo que el spine SwiftUI anula, lo que absorbe con heredero, y lo que otro ciclo debe enmendar.
Una derogación sin heredero explícito es una pérdida silenciosa: esta tabla existe para que no las haya.

## 1. `PLAN-CAPACITOR-v2.md` — DEROGADO ENTERO

| Contenido | Destino |
| --- | --- |
| Líneas 27, 62, 179 — *"reutiliza el 90 % del código actual"*, *"el dominio y la UI no se tocan"* | **Anulado.** Falso desde AD-1 |
| Comparativa que descartó SwiftUI *"por effort"* | **Anulada.** Recosteada en `OPCIONES-SUSTRATO.md` |
| **AD-IOS-01** — appId `com.walktracker.app`, inmutable post-distribución | **ABSORBIDO → AD-1** |
| Wake lock como limitación fundacional | **ABSORBIDO → AD-10** (`WakeLockPort`) — ⚠️ **con la absorción sin completar, ver la nota de abajo** |
| Entitlements y usage strings | **ABSORBIDO → envoltura operativa del spine** |
| Cuenta Apple Developer de pago | **ABSORBIDO → envoltura operativa** (sigue siendo A-1 del SPEC) |
| Licencias Apache-2.0 / MIT | **Vigente**, con la enmienda de AD-24 (CC-BY admisible en fuentes de datos) |
| Plugin `walktracker-kit`, adapters `Capacitor*`, `server.url`, `webDir` | **Anulados.** Sin heredero: no hay WebView |

> ⚠️ **El wake lock: la absorción está declarada, no cumplida (anotado el 2026-09-20).** `WakeLockPort`
> es uno de los 11 puertos del conjunto cerrado de AD-10 y **no está escrito**: el Epic 1 cerró con
> sus seis historias en `done` sin él, ninguna lo asumió, la 1.6 lo excluye en sus Boundaries y no
> hay `Adapters/WakeLock/` en el árbol. Esta fila decía "ABSORBIDO → AD-10" con la misma confianza
> que `epics.md` afirmaba que "sobrevive como `WakeLockPort` en Epic 1", y esa frase ya está
> corregida allí y en la nota de AD-10.
>
> **Aquí no se decide nada**: si el puerto sigue siendo necesario —ahora que el conteo funciona con
> la pantalla bloqueada— y, si lo es, en qué epic, es la **pregunta abierta Q-3** de la
> retrospectiva del Epic 1, y la tiene **Paul**. Lo único que cambia esta nota es que la fila deje
> de leerse como trabajo hecho. [`epic-1-retro-2026-09-14.md`, S5 y Q-3; `ARCHITECTURE-SPINE.md`
> AD-10; `epics.md`, historias anuladas 8.2]

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
| **UX-DR1** | Design tokens Volt (`#CCFF00`, `#1A1A1A`…) | **AD-13** | Colores del sistema y Liquid Glass heredado. Cablear hexadecimales pelea con el SDK. **Con una excepción declarada desde el 2026-09-18: ver abajo** |
| **UX-DR2** | Tipografía en `px` con `clamp()` | **AD-13** + convención de accesibilidad | Dynamic Type nativo; `px` y `clamp()` son conceptos de CSS |

`UX-DR3`, `UX-DR4`, `UX-DR6` y `UX-DR8` siguen vigentes: espaciado, catálogo de componentes,
accesibilidad WCAG AA y los seis flujos no dependen del sustrato.

### Excepción declarada a UX-DR1 — tres colores propios (chore de tokens 2026-09-18; ampliada por B-2 el 2026-09-20)

La derogación sigue en pie: **no vuelve la paleta Volt** y ninguna vista cablea un hexadecimal. Lo que
se promueve a excepción es distinto, y son exactamente **tres colores**, en
`WalkTracker/Resources/Assets.xcassets/`.

> 📍 **Esta tabla es la fuente única de los tres colores.** `ARCHITECTURE-SPINE.md` (AD-13) y
> `epics.md` (UX-DR1, UX-DR6) remiten aquí y **no repiten los datos**: cuando los repetían, la copia
> de AD-13 ya se había quedado sin los ratios en oscuro de `ErrorMessage`. Los hexadecimales salen
> del catálogo y los ratios de `WalkTrackerTests/UI/DesignTokensTests.swift`, que los recalcula con
> la fórmula de WCAG 2.1 en cada ejecución de la suite. *(Completada el 2026-09-20: faltaban los dos
> ratios en oscuro de `EstimatedSteps`, que no estaban escritos en ninguno de los tres documentos.)*

| Colorset | Claro | Oscuro | Por qué existe |
| --- | --- | --- | --- |
| `AccentColor` | `#4F7200` oliva — **5,62:1** sobre blanco | `#CCFF00` lima — **17,87:1** sobre negro | El acento de la app **no estaba elegido**: sin él `.tint` salía azul del sistema *por omisión, no por decisión*. Recupera el `#CCFF00` de UX-DR1 **solo en oscuro**; en claro el `#CC9900` original da 2,58:1 e incumple AA, así que se sustituye por un oliva |
| `EstimatedSteps` | `#A34F00` — **5,71:1** sobre blanco, **4,81:1** sobre el fondo del propio aviso | `#FF9F0A` (el naranja del sistema) — **10,22:1** sobre negro, **8,87:1** sobre el fondo del propio aviso | El `.orange` del sistema daba **2,20:1 sobre blanco**: un incumplimiento WCAG AA **vivo en producción**, que AD-13 por sí solo no arreglaba porque el color del sistema *era* el problema. En oscuro el naranja del sistema sí cumple con holgura, y por eso se conserva tal cual: la variante clara es la que hubo que sustituir |
| `ErrorMessage` | `#D70015`, el rojo accesible que Apple publica para este uso — **5,38:1** sobre blanco, **4,83:1** sobre el gris agrupado claro | `#FF453A` (el rojo del sistema) — **6,16:1** sobre negro, **4,99:1** sobre el gris agrupado oscuro | **Añadido por B-2.** El chore de tokens sustituyó `.orange` por incumplir AA y **la primera pantalla posterior eligió `Color.red`**, que da 3,55:1 sobre blanco y 3,18:1 sobre el gris agrupado: el mismo fallo por la misma puerta, el mismo día del merge. Lo que faltaba no era el color, era el **rol** medido. Es el color de **un error** —algo que se rechazó—, no el de todo lo que avisa: el aviso de rango humano se guardó y se distingue por jerarquía |

Los **ocho fondos** contra los que se mide son los reales de cada sitio, y están enumerados en el
arnés: fondo de pantalla (blanco / negro), gris agrupado (`#F2F2F7` / `#1C1C1E`), el cristal de la
pre-pantalla de ubicación (`#EFEFF4` / `#2C2C2E`, el borde desfavorable de lo que `.regular` puede
rendir) y el fondo tintado del propio aviso —el mismo color al **12 %** (`Surface.noticeTintOpacity`)
sobre el fondo de pantalla—, que es el caso más apretado.

Las condiciones de la excepción, y son las que la hacen compatible con AD-13:

- Son **colorsets con variante clara y oscura**, no hexadecimales en código. Las vistas los
  referencian por nombre (`Colors.accent`, `Colors.estimated`, `Colors.error`, en
  `WalkTracker/UI/Style/DesignTokens.swift`); el hexadecimal solo existe dentro del catálogo.
- El **contraste está medido** en los dos temas contra el fondo real sobre el que se pintan, y
  `WalkTrackerTests/UI/DesignTokensTests.swift` lo **recalcula en cada ejecución de la suite**: si
  alguien retoca un colorset y cae de 4,5:1, la suite lo dice. Desde B-2 mide también la **separación
  de tono** (≥ 30°) entre los tres, para que el eje que los distingue no sea solo la luminancia.
- `Scripts/check-project-shape.sh` (sección 12) **falla** si una vista escribe un hexadecimal, un
  color por componentes, o **cualquiera de los doce colores cromáticos con nombre de SwiftUI**
  (`.red`, `.orange`, `.yellow`, `.green`, `.mint`, `.teal`, `.cyan`, `.blue`, `.indigo`, `.purple`,
  `.pink`, `.brown`). **Desde B-2 el gate veta la familia cromática, no un nombre**: antes vetaba
  `.orange` en concreto, y `Color.red` pasó en verde precisamente porque no se llamaba `.orange`.
  Los **roles** del sistema —`.primary`, `.secondary`, `.tint`— y los acromáticos sí se usan: su
  contraste lo garantiza el sistema. La excepción es de tres ficheros del catálogo, no una puerta
  abierta a una paleta.
- El resto de la paleta sigue siendo del sistema y se referencia por su nombre (`.secondary`,
  `.fill.quaternary`): esto son **tres decisiones de color**, no una capa de apariencia.

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
| Meta semanal dada por cumplida al redondear | `motivation.js` (`getWeeklyProgress`) | `isComplete` comparaba los km ya redondeados a 2 decimales: 9 995 m (10,00 km al mostrar) cumplían una meta de 10 km. Sumar km fraccionarios, además, dejaba 10 000 m exactos en 9,999999… km | ✅ **Corregido (decisión de Paul, historia 8.7).** La semana se suma en metros e `isComplete` compara los metros sin redondear con `weeklyGoalKm × 1000`. No es una divergencia: `domain.js` pasa los vectores `nueve-995-km-no-cumplen-10` y `diez-km-exactos-en-seis-sesiones` |
| `Date.now()` dentro del dominio | `domain.js:249`, `:392` | Viola el `ClockPort`; hace esas funciones invectorizables | ⏳ **Pendiente en el port.** Cambiar la firma en la v3 rompería a sus llamantes sin beneficio; en Swift entra por `ClockPort` (AD-10) desde el día uno |
| `checkTimeOfDay` y rachas en UTC | `motivation.js` | `early_bird` y `night_walker` evalúan la hora en UTC, no local. Según el desfase horario de Paul, un logro puede dispararse a la hora equivocada | ⏳ **Deliberadamente no tocado.** `domain-model.md §9` lo ordena corregir **en iOS**; cambiarlo en la v3 es una decisión de producto, no un arreglo. Sigue siendo divergencia declarada de AD-6 |

**Consecuencia para AD-6:** la tabla de divergencias declaradas pasa de **cuatro filas a dos**.
`domain.js` ya no falla los vectores de ritmo, cadencia y racha — los pasa. Solo quedan divergentes
la hora local y el mapeo WMO, que son decisiones de plataforma, no defectos.

**Verificación:** 438 aserciones en verde tras el cambio (`domain` 51, `session-v3` 184, `motivation` 34,
`gapestimator` 16, `storage` 37, `climate` 26, `runtime` 20, `migration` 31, `stepdetector` 39).
