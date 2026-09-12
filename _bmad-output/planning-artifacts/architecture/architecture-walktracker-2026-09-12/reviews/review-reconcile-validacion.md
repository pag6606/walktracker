---
id: review-reconcile-validacion
tipo: revisión de reconciliación
fecha: 2026-09-12
objeto: architecture-walktracker-2026-09-12/ARCHITECTURE-SPINE.md (draft, 274 líneas)
entradas:
  - ux-designs/ux-walktracker-native/VALIDATION-mockups-v3-2026-09-12.md (11 B · 14 M · 9 m)
  - architecture/estandar-nativo-2026-09-12/OPCIONES-SUSTRATO.md
  - architecture/capacitor-migration/PLAN-CAPACITOR-v2.md (a derogar)
veredicto: SPINE SÓLIDO EN EL NÚCLEO, INCOMPLETO EN LA FRONTERA — no publicable como final hasta cerrar la derogación
---

# Revisión de reconciliación — ¿responde el spine a lo que lo motivó?

## Veredicto

El spine gobierna bien lo que es dominio y estructura —8 de los 11 bloqueantes quedan resueltos o
prevenidos por decisión explícita, y AD-5/AD-6/AD-11 son respuestas de primera calidad—, pero **no
cierra la frontera**: los dos companions que declara (`DEROGACIONES.md`, `REESTIMACION-EPICS.md`,
líneas 22-23) **no existen**, la derogación de `PLAN-CAPACITOR-v2.md` se despacha en media frase
(línea 70) sin decir qué se conserva, y con ella se pierden en silencio decisiones vivas —appId,
entitlements, wake lock, doble canal— que ningún AD recoge.

- 🔴 Bloqueantes de esta revisión: **4**
- 🟠 Mayores: **6**
- 🟡 Menores: **4**

---

## 1 · Los 11 bloqueantes de la validación contra los AD del spine

Leyenda: **RESUELTO** = un AD lo decide explícitamente · **PREVENIDO** = el AD hace que la clase de
error no pueda repetirse · **GOBERNADO** = hay dueño arquitectónico, falta la regla concreta ·
**PARCIAL** · **HUÉRFANO** = ni resuelto, ni diferido, ni mencionado.

| # | Bloqueante | Estado | Dónde lo gobierna el spine |
|---|---|---|---|
| **B-1** | Paridad funcional perdida (10 filas de CAP sin dibujar) | **GOBERNADO (parcial)** | `binds:` línea 11 lista las 17 CAPs; el *Capability → Architecture Map* (líneas 244-262) le da casa a **todas**, incluidas las ocho que faltaban: CAP-3 (línea 248), CAP-5 (250), CAP-6 (251), CAP-10 (255), CAP-14 (259), CAP-17 (261), CAP-2 (247), CAP-4 (249), CAP-18 (262). **Pero**: (a) la *regla* de B-1 (línea 48: "ninguna pantalla puede ofrecer menos capacidades que su equivalente v3") no aparece como AD ni como convención — la tabla de paridad no queda blindada para la v4; (b) los "extras de la v3" (línea 46) quedan sin dueño: `wl-banner` (wake lock) **no tiene puerto** en AD-10 (línea 142) y `btn-delete-all` (borrado total) no está en CAP-15 (línea 260, solo sesiones individuales). Ver 🔴 R-3. |
| **B-2** | CAP-3 sin UI: la marca `~` es invariante de dominio | **RESUELTO** | Contrato heredado línea 49 (*"pasos estimados siempre desglosados y marcados `~`, y descartables"*) + AD-8 línea 112 (al agotarse el timeout *"degrada a estimación marcada `~`"*). El invariante viaja en el dominio, no en la pantalla: es el sitio correcto. |
| **B-3** | Catálogo inventado 24 vs 14 | **PREVENIDO** | **AD-5** (líneas 90-94). La mejor respuesta del documento: los 14 salen de JSON versionado, *"Ningún logro se declara en Swift"*, y el arranque **falla ruidosamente** si no hay 14 entradas con claves únicas. Además cita el incidente real del 2026-09-11 como *Prevents*. Reforzado por la convención de identidad (línea 188: claves de `achievements.md`, *"nunca renumeradas"*). |
| **B-4** | Logros de desnivel imposibles (GPS es non-goal) | **PREVENIDO (por consecuencia)** | Cae dentro de AD-5: si el catálogo se valida contra el esquema y contra las 14 claves canónicas, un logro altimétrico no puede entrar. Ningún AD nombra el non-goal *"GPS de ruta ni mapas"*, pero tampoco hace falta: no hay `LocationPort` en la lista de AD-10 (línea 142). Ver 🟡 R-11 sobre quién posee CoreLocation para el clima. |
| **B-5** | Métricas inventadas (218 kcal, badge `+150`) | **PARCIAL** | CAP-4 → `Domain/Metrics`, gobernado por AD-4 y AD-6 (línea 249): los vectores dorados fijan qué calcula el dominio. **Pero ningún AD prohíbe que una vista pinte un número que el dominio no produce.** AD-3 (línea 82) impide que la lógica *baje* al dominio; nada impide que suba a la vista. Falta la regla recíproca. Ver 🟠 R-6. |
| **B-6** | *"Restaurar compras"* en Ajustes | **HUÉRFANO (inerte)** | No aparece en el spine. Inofensivo de facto —no hay `StoreKitPort` en AD-10 (línea 142), no hay dependencias de terceros (línea 208) y AD-10 exige que los puertos los declare el núcleo— pero es huérfano formal: el non-goal *"Publicación en App Store como requisito de éxito"* solo se menciona de pasada en la envoltura operativa (línea 240). |
| **B-7** | Aritmética rota en las 7 pantallas; fixtures no derivados de `domain-model.md` | **PARCIAL** | Para producción está bien cerrado: AD-6 (líneas 96-100, un vector que falla bloquea el merge) y la convención de Unidades (línea 190: metros y segundos en el dominio, conversión **solo** en la capa de formato). **Pero B-7 es un problema de *fixtures*, y en SwiftUI los fixtures son los `#Preview`.** Nada obliga a que los datos de preview salgan del dominio; los literales incoherentes vuelven por la misma puerta. Ver 🟠 R-7. |
| **B-8** | Contradicción con `PLAN-CAPACITOR-v2.md` (líneas 27/62/179) | **RESUELTO en la letra, INCUMPLIDO en la entrega** | AD-1 línea 70: *"Deroga `PLAN-CAPACITOR-v2.md` y reabre OQ-1 del SPEC."* Es la frase que la validación pedía (salida punto 3, líneas 190-192), y AD-1 también resuelve la ambigüedad *"UI nativa dentro del WebView vs salida de Capacitor"*: no hay WebView. **Pero** la validación pedía *"ADRs + reestimación"* y los dos companions que lo materializan (líneas 22-23) no existen en disco. Ver 🔴 R-1 y 🔴 R-2. |
| **B-9** | Base dimensional inconsistente (291 px con safe areas de 393 pt) | **PREVENIDO** | AD-13 (líneas 164-168): controles SwiftUI nativos, prohibido dibujar barras o materiales propios. En SwiftUI el lienzo es en puntos y las safe areas las da el sistema: la clase de error desaparece. AD-2 línea 76 fija además el dispositivo de validación (iPhone 14, sin Dynamic Island). |
| **B-10** | Sin tema claro en 4 de 7 pantallas (`#000000` cableado) | **PREVENIDO** | Contrato heredado línea 51 (*"claro y oscuro"*) + AD-13 línea 168: *"Los colores del sistema se referencian, no se cablean en hexadecimal."* Cubre incluso el único hueco posible —las tres piezas dibujadas a mano de la línea 168— con la misma frase. |
| **B-11** | Borrado destructivo bajo mínimos: 28×28 px, sin confirmación, sin swipe | **PARCIAL — el fallo peor gobernado del set** | De los tres fallos solo uno tiene respaldo: los ≥ 44 pt están en el contrato heredado (línea 51) y AD-13 los da por construcción al usar controles nativos. **La confirmación de acción destructiva no está en ningún AD**, y **el patrón nativo (swipe-to-delete) tampoco**: CAP-15 solo se mapea a `HistoryStore` bajo AD-9 (línea 260), que es una decisión de persistencia, no de interacción. Ver 🟠 R-5. |

**Recuento:** 2 RESUELTOS (B-2, B-8) · 3 PREVENIDOS (B-3, B-4 por consecuencia, B-9, B-10 → 4) ·
1 GOBERNADO parcial (B-1) · 3 PARCIALES (B-5, B-7, B-11) · **1 HUÉRFANO** (B-6, inerte).
Ninguno queda diferido: la tabla *Deferred* (líneas 266-274) no toca ningún bloqueante — correcto.

---

## 2 · Mayores y menores que son arquitectura, no diseño visual

De los 23 restantes, **15 son arquitectura**. Los agrupo por la decisión que los explica.

### 2.1 · Los que el spine ya gobierna (bien)

| # | Por qué es arquitectura | Dónde lo cierra el spine |
|---|---|---|
| **M-13** *"Tres tab bars distintos… no hay sistema de componentes"* | Es literalmente una queja de arquitectura, la más explícita del set | **AD-14** línea 174: `TabView` de cuatro pestañas fijas (Inicio · Historial · Logros · Ajustes) + `NavigationStack` dentro. Un solo tab bar por construcción. |
| **M-4** Quick actions duplican el tab bar; *"Estadísticas"* es un cuarto destino inexistente | Navegación = topología, no maquetación | **AD-14** línea 174: los destinos son exactamente cuatro. Un quinto no cabe. |
| **m-7** Tab bar sin iconos | Mismo origen que M-13 | **AD-14** + AD-13 (controles nativos). |
| **M-10** *"Guardado en Salud"* incondicional, sin estado denegado ni de fallo (CAP-11) | Es una política de degradación, no una pantalla | **AD-11**, tabla línea 154, palabra por palabra: *"HealthKit denegado o fallo de escritura → la sesión se guarda local igual; el resumen muestra 'no sincronizado', no un error."* **El mejor acierto de reconciliación del spine.** |
| **M-11** Logros inexistentes (*"Primer 5K"*, *"Racha 3 días"*) | Misma clase que B-3 | **AD-5** (línea 94): solo las claves canónicas, validadas al arranque. |
| **M-2 / M-3** Cabecera *"Lunes 11 de septiembre"* con el gráfico marcando sábado; *"Buenos días"* a las 14:05 | Es el bug de reloj y calendario, no de copy | **AD-10** línea 142 (*"el dominio nunca llama a `Date()`"*, `ClockPort`) + convención de Fechas línea 189 (*"Semana ISO (lunes–domingo) siempre con un `Calendar` configurado explícitamente — nunca `Calendar.current` sin fijar `firstWeekday`"*). Cierra también **M-12** (segmentado "Mes" mostrando dos meses). |
| **m-9** *"Live Activity"* agrupada bajo la sección **Salud** | Es una confusión de taxonomía de capacidades | **AD-10** línea 142: `HealthPort` y `LiveActivityPort` son puertos distintos. La taxonomía de Ajustes debería seguir la de puertos. |
| **m-5** `session-time` renderiza *"km"*: el nombre miente | Lenguaje ubicuo | Convención de Nombres línea 186 + Unidades línea 190 (la conversión vive solo en `UI/Format/`, línea 231). |
| **M-9** La pausa pierde la barra de meta que sí tiene la activa | Dos estados de la misma pantalla divergen ⇒ dos fuentes de verdad | **AD-7** línea 106 (`SessionStore` es el único escritor) hace que ambos estados se deriven del mismo store. Gobernado por implicación, no por regla. |
| **M-6** (mitad) `LIVE` en inglés en una UI en español | Copy disperso | Convención de Textos línea 192 (String Catalog, sin literales dispersos). |

### 2.2 · Los que **deberían** estar gobernados por un AD y no lo están

Estos cuatro son arquitectura y hoy son huérfanos. Son el contenido que le falta al spine.

| # | Hallazgo | Por qué es un AD y no un mockup |
|---|---|---|
| **M-14 + m-3** Emoji como iconografía de chrome, revirtiendo la decisión v2 (*"SVG icons en vez de emoji"*); emoji `⏸`/`▶` dentro de botones | **Es una decisión de sistema de diseño con una excepción semántica no trivial.** El spine adopta controles nativos (AD-13) pero **nunca nombra SF Symbols**, y por tanto nunca escribe la excepción que la propia validación identificó (M-14): *en las insignias de logro el emoji sí es correcto — el catálogo los especifica*. Esa excepción ya está bien resuelta estructuralmente (AD-5 mete el emoji de la insignia en `achievements.json`, línea 94), pero nadie lo dice. Sin la regla, la v4 vuelve a mezclar. **Falta:** una fila en *Consistency Conventions* — *Iconografía: SF Symbols en todo el chrome; emoji solo en insignias de logro, y siempre desde `achievements.json`, nunca en código*. |
| **M-8** El ritmo se muestra siempre; CAP-4 exige mostrarlo **solo con distancia ≥ 100 m**, y no hay estado para el caso contrario | **Es un problema de tipado del dominio, no de pantalla.** El SPEC lo exige (CAP-4 success: *"el ritmo solo aparece con distancia ≥ 100 m"*). Si `pace` se modela como `Double` con 0 o infinito, la UI improvisa; si se modela como opcional del dominio, la ausencia es un caso que el compilador obliga a tratar. AD-6 lo cubriría **solo si existe un vector para el tramo < 100 m** — el spine no lo garantiza. **Falta:** regla explícita — *las métricas no disponibles se modelan como opcionales del dominio, nunca como cero o centinela; la UI renderiza el caso ausente*. Es la misma clase que M-10, que sí tiene tabla. |
| **M-7 + B-11** Botón `✕` sin semántica, `flex: 0.4`, sin confirmación, conviviendo con *"Finalizar caminata"*: dos salidas ambiguas · papelera de 28×28 sin confirmación | **La irreversibilidad es una propiedad del agregado, no del botón.** El spine declara que la *"sesión finalizada [es] inmutable"* (línea 46) y que CAP-15 borra del historial (línea 260) — dos acciones irreversibles sin ninguna regla de confirmación. El único gancho existente es la convención de Estado (línea 193, *"mutación solo por métodos de intención"*), que dice cómo se muta, no qué hay que preguntar antes. **Falta:** *toda acción irreversible (finalizar sesión, borrar sesión, borrar todos los datos, importar sobre datos existentes) exige confirmación explícita y usa el patrón nativo de la plataforma (swipe-to-delete en listas, `confirmationDialog` en modos); los ≥ 44 pt son obligación de test, no aspiración.* |
| **M-6** (la otra mitad) Dos indicadores de directo simultáneos: pill `EN CURSO` + badge `LIVE` | **Es duplicación de estado renderizado en dos sitios**, la misma clase de fallo que AD-15 previene *fuera* de la app (la extensión no calcula, solo renderiza el `ContentState`, línea 180) pero no *dentro* de ella. Menor, pero pertenece a la familia "una fuente, un render". |

### 2.3 · Los que sí son solo diseño visual o copy

M-1 (dos `.bar` por columna), M-5 (*"14:05"* sin etiqueta), m-1 (glifo del CTA), m-2 (*"Ver detalles →"*
sin destino), m-4 (prioridad de *"Nueva caminata"*), m-8 (sublabels cruzados). **m-6** ya murió con la
corrección de B-3/B-4. Van a la v4, no al spine.

---

## 3 · La derogación de `PLAN-CAPACITOR-v2.md`

### 3.1 · ¿Dice el spine qué se deroga y qué se conserva?

**Dice lo primero en media frase y no dice lo segundo en absoluto.**

Toda la derogación cabe en la línea 70: *"Deroga `PLAN-CAPACITOR-v2.md` y reabre OQ-1 del SPEC."*
Los dos documentos que la desarrollarían están **declarados y ausentes**:

```
línea 21  companions:
línea 22    - REESTIMACION-EPICS.md     ← NO EXISTE en el directorio
línea 23    - DEROGACIONES.md           ← NO EXISTE en el directorio
```

El directorio contiene únicamente `ARCHITECTURE-SPINE.md` y `.memlog.md`. Un spine que declara
companions inexistentes es un contrato que apunta a la nada, y son exactamente los dos entregables
que la validación asignó al arquitecto (líneas 190-192: *"escribir los ADRs… y la reestimación"*).

`OPCIONES-SUSTRATO.md §4` (líneas 124-129) ya había enumerado las **tres** consecuencias documentales.
Estado real:

| Consecuencia (OPCIONES §4) | ¿La absorbe el spine? |
|---|---|
| Línea 126-127: el SPEC dice *"Capacitor como capa nativa (decisión Paul, OQ-1)"* y *"Descarta la reescritura SwiftUI total"*; **ambas dejan de ser ciertas**; OQ-1 se reabre | **A medias.** AD-1 reabre OQ-1, pero nadie toca el SPEC: su línea 83 sigue mandando Capacitor, su línea 104 sigue listando *"Reescritura SwiftUI total de la app"* como **non-goal explícito**, y su frontmatter sigue listando `PLAN-CAPACITOR-v2.md` como companion canónico. **El spine es hoy la violación literal de un non-goal de su propia fuente canónica.** Ver 🔴 R-4. |
| Línea 128: `PLAN-CAPACITOR-v2.md` líneas 27/62/179 quedan derogadas | **Sí, en la letra** (AD-1 línea 70), pero deroga el fichero entero sin inventario de lo que sobrevive. Ver 3.2. |
| Línea 129: 8 epics y 28 historias se reestiman; E8 cambia de contenido por completo | **No.** `REESTIMACION-EPICS.md` no existe. Y la rama viva es `feature/8-1-montaje-capacitor`, con la story 8.1 (`8-1-montaje-capacitor-web-v3-en-webview-proyecto-xcode-plugin-scaffold.md`) con tareas marcadas como hechas. Nadie ha declarado muerta esa story. |

### 3.2 · Decisiones útiles que se perderían al derogar — inventario

Buscadas en `PLAN-CAPACITOR-v2.md` y en su descendencia (spine 2026-07-28, story 8.1, README). Las
ordeno por lo que cuesta redescubrirlas.

1. **`AD-IOS-01` — appId `com.walktracker.app` [ADOPTED — Winston, 2026-08-01].**
   No vive en el PLAN sino en su descendencia: `_bmad-output/implementation-artifacts/8-1-…md`
   línea 72 y `README.md` línea 42 (*"inmutable post-TestFlight"*). Su *Prevents* sigue siendo
   verdadero palabra por palabra en SwiftUI: *"cambiar el bundle ID post-distribución equivaldría a
   otra app y perdería instalaciones/datos"*. Descartó además `com.paul.walktracker` por exponer el
   nombre personal. **El spine no menciona bundle ID en ninguna de sus 274 líneas**, aunque su
   envoltura operativa (línea 240) contempla TestFlight. Hay un conflicto ya latente que la
   derogación debe zanjar: `PLAN-CAPACITOR-v2.md` línea 140 propone `com.pag6606.walktracker`,
   mientras `capacitor.config.json` y AD-IOS-01 fijan `com.walktracker.app`. **Absorber AD-IOS-01
   tal cual, con su ID o renombrado.**

2. **El App Group de la Live Activity — decisión estructural sin identificador.**
   AD-15 (línea 180) exige que el `ContentState` viva en `Shared/` *"compartido por App Group"*, y el
   propio `.memlog.md` la registra como `[ASSUMPTION]` que *"condiciona el árbol del proyecto desde
   el primer commit"*. **Ningún documento fija el identificador** (`group.com.walktracker.app`) ni
   dice que debe derivar del appId. Es del mismo material que AD-IOS-01 y se decide una sola vez.

3. **Entitlements y usage strings.** El PLAN los tenía repartidos: `NSMotionUsageDescription`
   (línea 149), *"HealthKit capability + `NSHealthShareUsageDescription`"* (línea 154), el
   entitlement de HealthKit (línea 104), y el riesgo mitigado de la línea 173 (*"HealthKit requiere
   aprobación de Apple… documentar uso en review; solo escritura, no lectura de datos sensibles"* —
   coherente con el non-goal del SPEC). **El spine no nombra ni un solo entitlement ni una sola usage
   string.** AD-11 (línea 148) reparte quién *posee el estado* del permiso, que es otra cosa: sin la
   entrada en Info.plist la app crashea al primer `CMPedometer`. Añádase la de ubicación, que el
   clima necesita (AD-11 línea 153 la nombra: *"sin ubicación"*).

4. **El wake lock — se pierde entera y sin sustituto.** `PLAN-CAPACITOR-v2.md` la trata tres veces:
   §1 línea 21 la declara una de las **tres limitaciones bloqueantes de plataforma** que motivan todo
   el pivot; AD-15 del PLAN (líneas 83-86, *"WakeLock nativo via Capacitor… `isIdleTimerDisabled`"*)
   la resuelve; el spine 2026-07-28 y la story 8.1 la arrastran como `KeepAwakePort`/`WakeLockPort`,
   y la validación la ve en la v3 como `wl-banner` (B-1 línea 46). **En el nuevo spine no existe:**
   la lista de puertos de AD-10 (línea 142) tiene ocho y ninguno es de pantalla activa, y ninguna
   línea menciona `isIdleTimerDisabled`, `persistentSystemOverlays` ni "pantalla encendida".
   Es defendible que **muera por obsolescencia** —con CAP-2 (coprocesador) y CAP-18 (Live Activity)
   ya no hace falta mantener la pantalla despierta; el propio Success signal del SPEC exige que Paul
   *no toque la pantalla*—, pero eso es una decisión que hay que **escribir**, no omitir. Hoy es la
   única de las tres limitaciones fundacionales del PLAN que se queda sin heredero.

5. **La estrategia de doble canal PWA (§10, líneas 189-199; AD-C3 del spine 2026-07-28).**
   El PLAN la vendía como *"doble canal sin duplicar código"*: GitHub Pages para web, nativo para
   Paul. Con SwiftUI **el mismo `index.html` ya no sirve para ambos** y el argumento se cae solo.
   Pero el spine dice a la vez dos cosas que hay que reconciliar: su `scope` (línea 7) *"reemplaza el
   stack Capacitor/WebView"*, y **AD-6 (línea 100) mantiene `domain.js` ejecutando los vectores**
   —código vivo, no archivado—. Cruzado con la condición 3 de OPCIONES-SUSTRATO (línea 118,
   *"`domain.js` se congela como referencia de contraste, no como código vivo"*) hace falta la frase
   exacta: `domain.js` sobrevive **solo** como ejecutor de vectores; la PWA en Pages, ¿se archiva, se
   congela o se retira? Hoy nadie lo dice, y `sw.js`, `manifest.webmanifest` y el deploy de Pages
   siguen en el repo.

6. **Requisitos operativos (§6, líneas 128-133).** El spine conserva el iPhone físico (línea 240:
   *"el simulador no tiene coprocesador de movimiento"* — idéntico al PLAN línea 133) y el Mac+Xcode
   vía Stack. **Pierde la cuenta Apple Developer de pago, $99/año** (línea 131), que sigue siendo
   condición necesaria de la distribución TestFlight que el spine promete en la línea 240 — y que el
   SPEC arrastra como A-1, *"barrera documentada desde v3"*. Es la única partida con coste en dinero
   del proyecto; no debería vivir solo en un documento derogado.

7. **`localStorage` no persiste / storage evictable (§8, línea 174).** Muere correctamente: AD-9
   (líneas 132-136) lo sustituye con ficheros JSON en Application Support con escritura atómica. Nada
   que absorber, pero conviene decirlo para que `recovery-banner` y `backup-warning` (extras de la v3
   citados en B-1 línea 46) queden explícitamente **retirados por AD-9**, no olvidados.

8. **Licencias (§5, línea 113).** *"Todas MIT o Apache-2.0 (cumple AGENTS.md — sin copyleft)"*.
   **Se conserva y además se endurece**: contrato heredado línea 50 y Stack línea 208
   (*"Dependencias de terceros: **ninguna**"*). No hay pérdida. Es la única entrada de esta lista que
   la derogación puede cerrar sin trabajo.

9. **Colisión de numeración de ADs — deuda que la derogación crea si no se resuelve hoy.**
   `PLAN-CAPACITOR-v2.md` define AD-12 (Capacitor), AD-13 (CMPedometer), AD-14 (HealthKitPort) y
   AD-15 (WakeLock), líneas 68-86. El nuevo spine define **AD-12** (Swift 6), **AD-13** (Liquid
   Glass), **AD-14** (sesión = modo) y **AD-15** (extensión sin dominio). Cuatro IDs, dos significados
   cada uno — y un tercero en circulación: la story 8.1 escribe *"Única red = Open-Meteo (heredado
   AD-14)"*, que no es ninguno de los dos AD-14. A esto se suman los `AD-C1..AD-C8` del spine
   2026-07-28 y los `AR-n` que cita la story. **La derogación debe incluir una tabla de equivalencias
   o renumerar** (p. ej. `AD-SW-n`); si no, toda referencia cruzada del repo queda ambigua para
   siempre.

---

## 4 · ¿Contradice el spine a `OPCIONES-SUSTRATO.md`?

No lo contradice en lo sustantivo —adopta una de sus tres opciones y responde a su crítica principal—,
pero **promete cosas que allí se costearon distinto, y se apoya en un activo que ya no está donde el
coste lo suponía.**

### 4.1 · La recomendación fue C; el spine adopta B

`OPCIONES-SUSTRATO §3` línea 105 recomienda **Opción C (Flutter, ≈ 4,0 fds)** y argumenta contra B:
*"Pagar 5,5 para llegar donde ya estás a 4,0 sólo se justifica si la indistinguibilidad respecto a una
app de Apple es un requisito, y el SPEC no la pide"* (líneas 107-109). El spine adopta B (AD-1,
líneas 66-70).

**No es una contradicción, es una decisión ejercida por la salida que el propio documento dejó
abierta** (líneas 120-122: *"si la respuesta es 'literalmente Apple: SwiftUI, UIKit, HIG', entonces la
respuesta es B y hay que decirlo hoy"*). Está registrada: `.memlog.md` línea 8, *"Decidido por Paul
2026-09-12… Criterio de Paul: 'nativo' significa literalmente Apple"*.

**El defecto es de trazabilidad, no de fondo:** AD-1 se publica como `[ADOPTED]` **sin decisor ni
fecha**, cuando los demás ADs del ciclo sí los llevan en el memlog, y `OPCIONES-SUSTRATO.md` sigue con
`estado: decisión pendiente de Paul` (frontmatter línea 5). Un lector que abra los dos ficheros en
orden encuentra una recomendación viva por C y un spine en B sin puente. **Coste de arreglo: dos
líneas.**

### 4.2 · 🔴 El coste de B se apoyaba en 446 líneas que el spine no nombra y que no están en la rama

Esta es la contradicción real. `OPCIONES-SUSTRATO`, Opción B, línea 67:

> | Capa nativa: se **reaprovecha** casi entera de `AppDelegate.swift` (446 líneas ya escritas) | 0,5 |

Esas 446 líneas son el `ios/Runner/AppDelegate.swift` del camino **Flutter** (§0, línea 21) y
contienen —dice el mismo documento, líneas 28-29— *"las dos capacidades más caras y más nativas del
proyecto"*: `HKWorkoutBuilder` y `Activity.request`. Es lo que hace que B cueste 5,5 y no 6,0.

Estado verificado del repositorio:

- `ios/Runner/AppDelegate.swift` **no está en el árbol de trabajo**; `lib/` y `pubspec.yaml` tampoco.
- El único `.swift` propio que queda es `ios/App/App/AppDelegate.swift`, 48 líneas de *boilerplate*
  de Capacitor: **cero** ocurrencias de `HKWorkout` o `ActivityKit`.
- El código se salvó en el commit **`d9d3fbc`** *"🧬 Preservar sustrato Flutter (2.812 líneas) antes
  del pivot a SwiftUI"*, que dice literalmente *"Activo principal para el camino SwiftUI: la capa
  nativa de `AppDelegate.swift` porta casi directa"*. Bien hecho — el riesgo inmediato de
  `OPCIONES-SUSTRATO §1` (líneas 31-35, *"a un `git clean -fd` de desaparecer"*) se atendió.
- **Pero ese commit vive solo en la rama `feature/flutter-substrate` y NO es ancestro de `HEAD`.**
- Y el spine **no lo menciona**: su *Structural Seed* (líneas 226-227) lista `Adapters/Health/` y
  `Adapters/LiveActivity/` como directorios nuevos, sin una sola palabra sobre de dónde se portan.

Consecuencia: quien implemente siguiendo el spine escribirá HealthKit y ActivityKit desde cero
—+0,5 fds sobre lo costeado, y perdiendo la única implementación que ya funcionó—, y la rama que
guarda el activo es un `git branch -D` de distancia. **El spine debe nombrar el commit y la rama, y
el mapa de portado `AppDelegate.swift` → `Adapters/Health/` + `Adapters/LiveActivity/`.**

### 4.3 · El spine añade trabajo que la Opción B no costeó

`OPCIONES-SUSTRATO` desglosa B en cuatro partidas (líneas 63-68): dominio 1,5 · 7 pantallas 2,5 ·
adapters 1,0 · capa nativa 0,5. El spine promete, encima de eso:

| Trabajo que manda el spine | ¿Estaba en la partida? |
|---|---|
| **AD-5** (línea 94): esquema JSON del catálogo + validación de arranque que falla ruidosamente | No. *"Portar el dominio"* (1,5) no incluye construir un cargador validado. |
| **AD-6** (líneas 96-100): extraer **168 aserciones** de cuatro ficheros de test a vectores neutrales de lenguaje **y hacer que `domain.js` los ejecute también** | No, y es la partida más grande de las omitidas: es un arnés bilingüe, no un port de tests. |
| **AD-9** (línea 136): escritura atómica temp+rename, tres ficheros con `schemaVersion` | Parcialmente en "adapters: storage" (1,0). |
| **AD-12** (líneas 158-162): strict concurrency completa, todo `Sendable` | No. Es coste real en Swift 6. |
| **AD-15** (líneas 176-180): Widget Extension como target aparte + App Group | No. Estaba dentro de las 446 líneas reaprovechadas de 4.2, que ya no se pueden dar por hechas. |
| **AD-2** (líneas 72-76): subir el suelo a iOS 26.0 | No costeado en ninguna opción. Ver 4.4. |

Es decir: **la Opción B que el spine describe no es la Opción B que se costeó en 5,5.** Y el
documento que reconciliaría ambas cifras —`REESTIMACION-EPICS.md`— es uno de los dos companions que
no existen. No es un error del spine (las decisiones son buenas, sobre todo AD-6, que es la respuesta
correcta al defecto que OPCIONES-SUSTRATO línea 72 le pone a B: *"tercera implementación del mismo
dominio, tres oportunidades de divergir"*); es una cifra que ya no se sostiene y que nadie ha
actualizado.

### 4.4 · El suelo iOS 26.0 contradice A-2 del SPEC, y no lo costeó nadie

**AD-2** (líneas 72-76) fija deployment target 26.0 y **prohíbe `if #available`** hacia atrás. El SPEC
dice otra cosa: **A-2**, *"El iPhone de Paul corre iOS 17+ (la v3 ya asumía 16.4+)"*, y la story 8.1
trabajaba con **16.1** (piso de ActivityKit). El `.memlog.md` línea 17 resuelve el fondo con dato
directo (*"iPhone 14 con iOS 26"*) y razona bien por qué no se pone en 27 — pero **el spine no
declara que A-2 queda superada**, y el suelo es load-bearing: AD-13 (Liquid Glass automático por SDK)
depende de él. Va en el mismo saco que 3.1: es una derogación del SPEC que hay que escribir.

### 4.5 · El destino del dominio Dart queda sin declarar

`OPCIONES-SUSTRATO` pone tres condiciones no negociables (líneas 111-118), de las cuales dos hablan
del código Dart: la 2 (*"el dominio Dart es la única fuente de verdad… el catálogo vuelve a los 14
canónicos"*) y la 3 (*"`domain.js` se congela"*). La condición 2 muere con la Opción C, correcto.
Pero el diagnóstico que la motivaba **sobrevive y el spine lo hereda como su mejor decisión**: el
catálogo Dart tenía 7 logros con semántica cambiada (líneas 96-99), que es exactamente el *Prevents*
de AD-5 (línea 93). Falta cerrar el circuito: decir en la derogación que `lib/` (2.366 líneas Dart) no
se porta —el commit `d9d3fbc` sí lo dice, el spine no— y que de todo el camino Flutter solo se rescata
la capa nativa de 4.2. Igual que la condición 1 (líneas 113-115: eliminar del repo `ios/App/`, `www/`,
`adapters/`, `walktracker-kit/`, `capacitor.config.json`), que estaba escrita para C y **aplica con
más razón a B** — y hoy todos esos ficheros siguen en el árbol de trabajo, con una rama viva
`feature/8-1-montaje-capacitor` encima.

---

## Hallazgos, con severidad

### 🔴 Bloqueantes

- **R-1 · Los dos companions declarados no existen.** `ARCHITECTURE-SPINE.md` líneas 22-23 declaran
  `REESTIMACION-EPICS.md` y `DEROGACIONES.md`; el directorio solo contiene el spine y `.memlog.md`.
  Son justo los dos entregables que la validación asignó al arquitecto (líneas 190-192). Mientras
  falten, el spine no puede pasar de `draft`.
- **R-2 · La derogación de `PLAN-CAPACITOR-v2.md` no tiene inventario.** Media frase (línea 70) para
  un fichero del que hay que rescatar, como mínimo, los nueve puntos de §3.2 — y de los que
  `AD-IOS-01` (appId), el App Group, los entitlements/usage strings y el wake lock **hoy no tienen
  heredero en ninguna línea del spine**.
- **R-3 · Wake lock y borrado total desaparecen sin decisión.** La lista de puertos de AD-10
  (línea 142) tiene ocho y ninguno mantiene la pantalla activa, pese a ser una de las tres
  limitaciones fundacionales del PLAN (línea 21). `btn-delete-all` de la v3 (B-1 línea 46) tampoco
  cabe en CAP-15 (línea 260, solo sesiones individuales). Ambas pueden morir; ninguna puede morir en
  silencio.
- **R-4 · El spine viola un non-goal explícito de su fuente canónica sin derogarlo.** SPEC línea 104:
  *"Reescritura SwiftUI total de la app (decisión Paul, OQ-1: Capacitor)"*, más línea 83 (Constraint
  Capacitor), más `PLAN-CAPACITOR-v2.md` como companion del SPEC. AD-1 (línea 70) reabre OQ-1 pero no
  ordena actualizar el SPEC. Añádase A-2 vs AD-2 (§4.4).

### 🟠 Mayores

- **R-5 · No hay regla de acción irreversible.** B-11 y M-7 (y el `✕` de la sesión) quedan sin AD:
  falta confirmación obligatoria, patrón nativo de borrado y los ≥ 44 pt como criterio verificable y
  no como aspiración heredada de la línea 51.
- **R-6 · No hay regla "sin fuente en el dominio, no se pinta".** B-5 (218 kcal, badge `+150`) solo
  está gobernado por implicación. AD-3 protege el dominio de la UI; falta la simétrica.
- **R-7 · Los `#Preview` son el agujero por donde vuelve B-7.** AD-6 blinda producción; nada obliga a
  que los fixtures de preview se deriven del dominio. Añádase una fila de convención.
- **R-8 · Falta la decisión de iconografía (M-14, m-3).** SF Symbols en el chrome, emoji **solo** en
  insignias y **solo** desde `achievements.json` — la excepción ya está bien resuelta por AD-5, pero
  no escrita.
- **R-9 · La única implementación validada de HealthKit y ActivityKit está fuera del alcance del
  spine.** Commit `d9d3fbc`, rama `feature/flutter-substrate`, no ancestro de `HEAD`, no citado en
  ninguna línea del spine, y con `ios/Runner/AppDelegate.swift` ausente del árbol de trabajo. Sobre
  esas 446 líneas descansa la partida de 0,5 fds de `OPCIONES-SUSTRATO` línea 67.
- **R-10 · La cifra de 5,5 fds ya no describe lo que el spine manda** (§4.3: AD-5, AD-6, AD-9, AD-12,
  AD-15, AD-2 no estaban costeados) y `REESTIMACION-EPICS.md` no existe.

### 🟡 Menores

- **R-11 · Nadie posee CoreLocation.** AD-11 (línea 153) cuenta con *"sin ubicación"* como causa de
  degradación, pero la lista de puertos de AD-10 (línea 142) no tiene `LocationPort`. Basta con decir
  que el `WeatherAdapter` lo posee — pero hay que decirlo, y de ahí sale una usage string (R-2).
- **R-12 · Colisión de IDs de AD.** AD-12..AD-15 significan cosas distintas en el PLAN derogado
  (líneas 68-86) y en el spine, con un tercer AD-14 circulando en la story 8.1. Tabla de
  equivalencias o renumeración.
- **R-13 · AD-1 no registra decisor ni fecha**, y `OPCIONES-SUSTRATO.md` sigue en `estado: decisión
  pendiente de Paul` (frontmatter línea 5) cuando `.memlog.md` línea 8 ya la registra resuelta.
  Dos líneas de arreglo.
- **R-14 · La pantalla de Motion denegado no tiene sitio en el árbol.** AD-11 (línea 152) exige
  *"pantalla bloqueante con explicación y acceso a Ajustes"*, pero `UI/` (línea 229) lista
  Home/Session/Summary/History/Achievements/Settings y ninguna más. La v3 sí la tenía
  (`screen-motion-denied`, B-1 línea 42).
- **R-15 · La regla de paridad de B-1 no está blindada.** La tabla de B-1 es el checklist con el que
  la v4 debe entrar (validación línea 193); nada en el spine la convierte en criterio de aceptación.
- **R-16 · El Success signal del SPEC sigue exigiendo demostrar la viabilidad de Capacitor** (*"una
  sesión completa de 60 min… sin degradación"*). Con SwiftUI el gate desaparece —lo dice
  `OPCIONES-SUSTRATO` línea 92 para C, y aplica igual a B—; entra en la lista de derogaciones.

---

## Lo que hay que conservar del spine

No todo esto es deuda. Cuatro decisiones responden a la validación mejor de lo que se pedía y no
deben tocarse al cerrar los huecos:

- **AD-5** convierte B-3, B-4 y M-11 en errores imposibles, y lo hace citando el incidente real que
  los produjo. Es el patrón que el resto de huecos debería imitar.
- **AD-11** contesta M-10 con la frase exacta que faltaba, y de paso da una tabla única donde antes
  había cuatro criterios.
- **AD-6** es la respuesta correcta —y proporcionada— al único defecto serio que `OPCIONES-SUSTRATO`
  le encontró a la Opción B (línea 72, la tercera implementación del dominio).
- **AD-14** liquida M-13, M-4 y m-7 de una sola vez, que era la queja arquitectónica más explícita de
  toda la validación.
