---
id: review-rubric-architecture-walktracker-2026-09-12
tipo: rubric-walk (puerta de revisión de arquitectura)
objeto: ../ARCHITECTURE-SPINE.md
revisor: rubric walker
fecha: 2026-09-12
veredicto: CAMBIOS REQUERIDOS — no apto como sustrato de build
---

# Rubric walk — ARCHITECTURE-SPINE.md (WalkTracker iOS)

## Veredicto

**CAMBIOS REQUERIDOS.** El spine es fuerte donde decide —AD-7 (escritor único), AD-8 (reconciliación
atómica acotada), AD-9 (formato en disco = formato de intercambio), AD-11 (tabla de degradación)
son ADs de verdad: verificables y con una divergencia real detrás—, pero **no es todavía un sustrato
de build**: tiene una contradicción interna en una regla load-bearing (AD-9 vs. el CSV de CAP-14),
una dimensión entera en silencio (rendimiento/batería, que el SPEC declara criterio de éxito),
tres puntos de divergencia reales sin fijar (semana ISO local vs. UTC, snapshot de sesión activa,
CoreLocation + redondeo de coordenadas) y un cuerpo de artefactos vinculantes —el propio SPEC que
dice `binds`— que hoy dice lo contrario de lo que el spine adopta, sin que exista el documento de
derogación que el spine promete en su frontmatter.

Resumen por punto de la checklist:

| # | Punto | Resultado |
|---|---|---|
| 1 | Fija los puntos de divergencia reales del nivel de abajo | ❌ Fija ~10, deja 5 abiertos y ninguno marcado como pregunta |
| 2 | Cada Rule es ejecutable y previene lo que declara | ⚠️ 10/15 sí; AD-3, AD-4, AD-6, AD-9 y AD-15 no en su forma actual |
| 3 | Nada bajo Deferred permite divergencia | ✅ (casi) — el fallo no está en la tabla, está en lo que no aparece en ninguna parte |
| 4 | Tecnologías verificadas y vigentes | ✅ con dos matices de precisión |
| 5 | Brownfield: ratifica o contradice diciéndolo | ❌ No menciona el repositorio que existe |
| 6 | Cubre CAP-1..15, 17, 18 | ⚠️ Las 17 aparecen en el mapa; 5 tienen cobertura nominal, no gobierno |
| 7 | Toda dimensión decidida, diferida o marcada | ❌ Rendimiento/batería en silencio total; accesibilidad y privacidad casi |
| 8 | Terso | ⚠️ ~15 % sobra; 2 convenciones deberían ser ADs y 2 ADs deberían ser convenciones |

---

## 1 · Puntos de divergencia: los que fija y los que deja abiertos

### Lo que sí fija (y fija bien)

Un desarrollador de historias que lea este spine no puede divergir en: dirección de dependencias
(AD-3), quién muta la sesión viva (AD-7), qué pasa con los comandos durante la reconciliación (AD-8),
formato y granularidad de fichero en disco (AD-9), existencia y nombre de los puertos (AD-10),
qué hace la app cuando falta cada permiso (AD-11, tabla), forma de la navegación (AD-14), qué hay
dentro de la extensión (AD-15), unidades del dominio, traducción de errores, catálogo de strings.
Ese conjunto es el valor real del documento.

### Los que deja abiertos — cada uno hará divergir dos historias

**D-1 · Frontera de semana y hora local vs. UTC. [ALTA]**
Tres fuentes vinculantes dicen tres cosas y el spine no arbitra:

- `ARCHITECTURE-SPINE.md` L189 (Convenciones · Fechas): *"Semana ISO (lunes–domingo) siempre con un
  `Calendar` configurado explícitamente — nunca `Calendar.current` sin fijar `firstWeekday`"*.
  Fija el `firstWeekday`, **no fija la zona**.
- `domain-model.md` §5 GoalEngine: *"lunes 00:00 **UTC** de la semana corriente"*.
- `domain-model.md` §9 y `achievements.md` (nota de zona horaria): *"la PWA evaluaba
  `early_bird`/`night_walker` y rachas en UTC por detalle de implementación. En iOS se evalúan en
  **hora local** del dispositivo... Se registra aquí para que la portación lo corrija
  deliberadamente, no por arrastre."*

Resultado previsible: la historia de `GoalEngine` implementa UTC (porque el domain-model lo dice
literalmente) y la de `AchievementEngine` implementa local (porque la nota lo exige), y el anillo
semanal y la racha de 7 días discreparán en el borde del día para un usuario que no está en UTC.
Agravante: **AD-6 congela la divergencia**. Los vectores dorados se extraen de `domain.js`, que
evalúa en UTC; si el vector es el suelo y bloquea el merge, el spine acaba prohibiendo por
construcción la corrección que §9 pide hacer deliberadamente. Hace falta una regla explícita
—"todo cálculo de calendario en hora local del dispositivo; los vectores de calendario llevan zona
en la entrada"— o AD-6 y §9 se anulan mutuamente.

**D-2 · Snapshot de sesión activa y recuperación tras force-quit. [ALTA]**
No aparece en el spine. Comprobado: `snapshot`, `recuper`, `autosave`, `force-quit` → 0 ocurrencias
en `ARCHITECTURE-SPINE.md`. Sin embargo es contrato:

- `capabilities.md` CAP-1, tercer criterio: *"Force-quit de la app con sesión activa → al reabrir,
  la sesión se recupera con el tiempo correcto recomputado desde `startedAt` (recuperación
  silenciosa, indicador 'Sesión recuperada' 3 s)"*.
- `domain-model.md` §8 define la forma `activeSession` como uno de los cuatro stores, y §8 cierra
  con *"Autosave del snapshot cada 10 s y al ir a background; recuperación silenciosa al reabrir."*
- `domain-model.md` §3: *"Al reabrir la app con sesión activa, elapsed se recomputa desde `startedAt`."*

AD-9 (L136) enumera **exactamente tres ficheros** —`sessions.json`, `achievements.json`,
`settings.json`— y ninguno es el snapshot. El mapa (L246) gobierna CAP-1 con AD-3, AD-7 y AD-14, que
no hablan de disco. Queda abierto: dónde vive el snapshot, con qué cadencia se escribe, quién lo
escribe (¿el escritor único de AD-7, en el main actor, cada 10 s?), y cómo interactúa con la
reconciliación de AD-8 al reabrir. Cuatro decisiones que hoy tomará quien escriba la historia 1-6.

**D-3 · Adquisición de ubicación y redondeo de coordenadas. [ALTA]**
AD-10 (L142) declara ocho puertos —`MotionPort, HealthPort, FeedbackPort, WeatherPort,
NotificationPort, LiveActivityPort, ClockPort, StoragePort`— y el árbol (L227) ocho carpetas de
adapter. **No hay `LocationPort` ni `Adapters/Location/`**, pese a que AD-11 (L153) reconoce la
ubicación como capacidad ausente independiente (*"Clima no disponible (sin red, **sin ubicación**)"*)
y a que CoreLocation es un framework con su propio permiso y su propio ciclo de autorización.
La consecuencia es exactamente lo que AD-10 dice prevenir: o `WeatherAdapter` se traga CoreLocation
en silencio, o alguien lo instancia donde le convenga.

Peor: la regla de privacidad concreta del SPEC desaparece. `SPEC.md § Constraints · Privacidad`:
*"si el clima sale por red, las coordenadas se redondean a **2 decimales** antes de enviarse"*, y
`capabilities.md` CAP-5 lo repite. En el spine, "decimal" aparece una sola vez (L189, fracción
ISO-8601) y "ubicac" una sola vez (L153, la fila de degradación). El redondeo no está ni en un AD,
ni en Convenciones, ni en Deferred. Es la única regla de privacidad **accionable** del producto y el
spine la pierde al reescribir el contrato heredado (ver §8, hallazgo T-1).

**D-4 · Quién dispara las celebraciones y dónde vive la deduplicación. [MEDIA]**
CAP-12 exige feedback en cuatro eventos (inicio, cada km, meta cumplida, logro desbloqueado);
CAP-7 añade *"cruzar el 100 % dispara celebración **una sola vez por semana**"*; CAP-8 exige
celebración al desbloquear. El spine crea `FeedbackPort` (AD-10) y para ahí. No dice quién detecta
el cruce de km (¿`SessionStore` en cada tick? ¿el dominio devolviendo eventos?), quién orquesta la
tripleta visual+sonora+háptica, ni dónde se guarda el "ya celebré esta semana" (no está en ninguno
de los tres ficheros de AD-9 ni en la forma `config` de `domain-model.md` §8). Tres pantallas
—Sesión, Summary, Logros— celebran; sin regla, tres implementaciones.

**D-5 · Mapeo de condición climática → categoría `rain`. [MEDIA]**
`achievements.md` (nota de mapeo) exige mapear códigos WMO (51–67, 80–82, 95–99) a una categoría
interna `rain`, sin depender de strings localizados. Es precisamente el tipo de constante que AD-5
saca a datos, pero `formulas.json` (L233) no se especifica y AD-5 solo detalla la validación del
catálogo de logros. Queda sin decidir si el mapeo vive en el `WeatherAdapter` (y el dominio recibe
un enum) o en el dominio (y recibe el código crudo). Afecta a `rain_walker` y al snapshot de CAP-5.

**D-6 · Paridad funcional con la v3. [MEDIA]**
`VALIDATION-mockups-v3-2026-09-12.md` —citado como fuente en L18— cierra su bloqueante B-1 con una
regla explícita: *"ninguna pantalla del rediseño puede ofrecer menos capacidades que su equivalente
v3. Esta tabla es el checklist de paridad."* El spine no la ratifica. AD-13 y AD-14 gobiernan
estética y navegación; nadie gobierna paridad. Como la v4 de mockups está diferida (L270), la única
red de seguridad contra la regresión que esa validación documentó era esta regla, y el spine la
deja fuera.

---

## 2 · ¿Es ejecutable cada Rule? ¿Previene lo que declara?

Ejecutables y bien apuntadas: **AD-2** (grep de `if #available` + un ajuste de proyecto),
**AD-5** (validación de arranque que falla ruidosamente, con criterios contables: 14 entradas,
claves únicas), **AD-7** (un solo tipo con el método mutador; revisable en diff), **AD-8**
(estado `reconciling` en el store, timeout obligatorio), **AD-11** (tabla; cada fila es un test),
**AD-12** (flag del compilador), **AD-13** (revisable: prohibido `.ultraThinMaterial` a mano, tres
piezas dibujadas y no cuatro), **AD-14** (`fullScreenCover` vs. quinta pestaña, verificable en el
árbol de vistas). Estos ocho hacen su trabajo.

Los que no:

**E-1 · AD-3 afirma un fallo de build que la estructura declarada no puede producir. [MEDIA]**
L82: *"Un `import` de plataforma en `Domain/` es un fallo de build, no una discusión de revisión."*
Falso tal y como está montado el proyecto: el Structural Seed (L212-238) describe **carpetas**, no
módulos, y el Stack (L199-208) no declara ningún paquete SPM local. En un target de app único,
`import SwiftUI` dentro de `Domain/Session.swift` compila sin quejarse. Para que la afirmación sea
cierta, `Domain` (y probablemente `Application`) tienen que ser targets SPM separados — y eso es una
decisión estructural que el spine debe tomar, porque condiciona el árbol desde el primer commit y
tiene coste (acceso `public`, tiempos de build, cómo se comparte `Shared` con la extensión). O se
declara la modularización, o la regla se degrada a convención de revisión y deja de mentir sobre su
propio mecanismo de enforcement. Mismo problema, menor grado, en AD-10 L142 (*"Ninguna vista importa
un framework de sistema"*: revisable con `rg`, no es un fallo de build) y en AD-15 L180 (ahí sí es
casi real, porque la pertenencia de ficheros a targets lo impone).

**E-2 · AD-6 tiene tres defectos, y es la única prueba de equivalencia del proyecto. [ALTA]**
L100. Es el AD más importante del spine —es lo único que impide repetir el incidente Dart— y hoy no
se sostiene:

- **(a) El número es incorrecto.** Dice *"las 168 aserciones"*. Ejecutados los cuatro ficheros hoy:
  `domain-tests.js` 51, `session-v3-tests.js` **182**, `motivation-tests.js` 32,
  `gapestimator-tests.js` 16 → **281**, no 168. El 168 viene arrastrado del `.memlog.md` (líneas 12
  y 13), donde ya figuraba antes de contarse. Un número load-bearing dentro de una Rule que nadie
  verificó contra la fuente, en un spine cuyo AD-5 existe precisamente porque alguien retecleó datos
  sin verificarlos.
- **(b) La cobertura no incluye lo que el AD dice vincular.** AD-6 declara `Binds: ... CAP-7, CAP-8`.
  Comprobado por grep: `GoalEngine`, `AchievementEngine`, `weekly_goal`, `first_km`, `marathon`,
  `streak`, `consistency` **no aparecen en ninguno de los cuatro ficheros nombrados**; las únicas
  ocurrencias de claves de logro en el árbol de tests están en `test/storage-tests.js` (líneas 76-82)
  y son un fixture de persistencia, no una prueba de regla. Es decir: los vectores dorados, tal como
  están definidos, **no cubren la meta semanal ni ninguno de los 14 logros** — exactamente las dos
  cosas que divergieron en Dart y que motivan AD-5. Hay que ampliar el conjunto de origen o aceptar
  que CAP-7 y CAP-8 sólo están protegidos por AD-5 (que garantiza el *catálogo*, no la *evaluación*).
- **(c) La sanción no tiene mecanismo.** *"Un vector que falla bloquea el merge"* frente a
  L240: *"**Sin CI**"*. Nada bloquea nada. O aparece un gate mínimo (un hook de pre-push, un script
  `make verify` que el flujo de PR de `AGENTS.md` exija), o la frase es una aspiración y hay que
  escribirla como lo que es.
- **(d) Dependencia operativa no declarada.** *"`domain.js` y el dominio Swift ejecutan **el mismo
  fichero**"* convierte a Node y al árbol JS del repo en **dependencia permanente del build de la
  app iOS**. El Stack dice *"Dependencias de terceros: **ninguna**"* y el Structural Seed no contiene
  una sola línea de JS. La condición 3 de `OPCIONES-SUSTRATO.md` §3 (*"`domain.js` se congela como
  referencia de contraste"*) es compatible, pero el spine tiene que decirlo: qué se conserva del
  repo v3, quién lo ejecuta y bajo qué runtime.

**E-3 · AD-9 se contradice con la capability que el propio mapa le asigna en negrita. [CRÍTICA]**
L136: *"El export de CAP-14 **no tiene serializador propio**: emite el mismo formato."*
L259, mapa: `CAP-14 export / import → Adapters/Persistence → **AD-9**`.
Pero CAP-14 es, literalmente, *"exporta su historial en **CSV**/JSON"*, con criterio de aceptación
*"el CSV abre en Numbers/Excel"* (`SPEC.md` CAP-14, `capabilities.md` CAP-14). **CSV es por
definición un segundo serializador**: no hay forma de emitir CSV "con el mismo formato" que un
`Codable` JSON. La regla es inejecutable en la mitad de lo que gobierna, y al declararlo resuelto
cierra la puerta a decidir lo que sí hace falta decidir: columnas, orden, separador, y —crítico para
una UI en español abriéndose en Numbers en un Mac con locale `es`— si el separador decimal es coma
o punto y si el de campo es `,` o `;`. Hoy quien escriba la historia de export lo inventa.
Corrección mínima: acotar AD-9 al JSON (*"el JSON de intercambio ES el de disco"*) y añadir el CSV
como decisión propia o como Deferred explícito con su punto de divergencia nombrado.

**E-4 · AD-4 es aspiración, no regla. [BAJA, pero es ruido en el sitio equivocado]**
L88: *"value types, métodos, `throws`, errores tipados"*. Nada de eso es verificable como gate, y el
propio AD lo admite al delegar la prueba en AD-6 (*"La equivalencia con la v3 se demuestra por AD-6,
nunca por parecido visual del código"*). Lo verificable —conservar los nombres del lenguaje ubicuo
de `domain-model.md` §1— ya está en Convenciones (L186). AD-4 no previene nada por sí solo: lo
previene AD-6. Ver §8.

**E-5 · AD-15 gobierna la estructura de la extensión y no el mecanismo. [MEDIA]**
L180 fija bien que la extensión no calcula y que `ContentState` vive en `Shared/`. No fija **cómo
llega el estado**: `Activity.update(...)` empujado por la app, o escritura en el contenedor del App
Group y refresco del widget. Son dos arquitecturas distintas con dos presupuestos de actualización
distintos, y ambas son "compatibles" con la letra del AD. Como CAP-18 exige *"métricas
actualizándose en vivo"* con la app en background, y ActivityKit impone un presupuesto de
actualizaciones, la cadencia es una decisión de arquitectura, no de historia (ver §7, hallazgo O-1).
Falta también el identificador del App Group como convención — hoy es el tipo de cadena que dos
targets escriben distinto y sólo falla en dispositivo.

---

## 3 · ¿Hay algo bajo "Deferred" que permitiría divergir?

**Casi no, y ese es el hallazgo.** La tabla de Deferred (L264-274) es honesta y está bien construida:
cinco de sus seis entradas difieren un *valor* o un *dibujo* sobre un mecanismo ya fijado, que es
exactamente la forma correcta de diferir.

- *Timeout de la reconciliación*: correcto. AD-8 fija que existe, que está acotado y qué hace al
  agotarse; el número es calibración. **No permite divergencia.**
- *Migración de esquema*: correcto. `schemaVersion` presente desde el día uno + arranque limpio
  (OQ-3). **No permite divergencia.**
- *Diseño de las tres piezas dibujadas*: correcto — AD-13 ya acotó que son **tres** y cuáles.
  **No permite divergencia** (sí bloquea historias de UI, que es otra cosa).
- *WeatherKit vs. Open-Meteo*: correcto, y es la mejor justificación de la tabla: *"el cambio es de
  adapter, aislado por AD-10"*. Es el patrón que las demás entradas deberían imitar.
- *XCUITest*: correcto.
- *Dynamic Island — "solo debe compilar"*: **única entrada con riesgo real, bajo.** El
  `ContentState` de AD-15 tiene que servir a dos presentaciones y la entrada no dice si los layouts
  de isla se escriben ahora como stub o no se escriben. Dos personas resolverán distinto qué
  significa "que compile". Coste bajo; conviene una frase (*"se declara el layout mínimo de isla,
  sin validación de hardware; el `ContentState` no gana campos por ella"*).

El fallo de esta dimensión **no está en la tabla**: está en que los cuatro puntos que sí permitirían
divergir (D-2 snapshot, D-3 ubicación/coordenadas, D-4 celebraciones, O-1 batería/cadencia) **no
están en Deferred tampoco**. No están en ningún sitio. Un Deferred honesto es mejor que un silencio;
el spine tiene un Deferred honesto y cuatro silencios.

---

## 4 · Tecnologías: verificadas y vigentes

Verificado en web hoy, 12 sep 2026. El Stack está **vigente**; el memlog hizo bien su trabajo. Dos
matices de precisión, ambos de severidad baja:

| Declarado (L199-208) | Verificado | Juicio |
|---|---|---|
| Swift **6.3.2** | Existe: release de mantenimiento anunciada el 13 may 2026. Pero **Xcode 26.6 empaqueta Swift 6.3**, y swift.org ya publicó **6.3.3**. | ⚠️ Ver V-1 |
| Xcode **26.6** | Correcto: 26.6 (17F113), 25 jun 2026; es la estable vigente. Trae SDKs de iOS **26.5**. | ✅ |
| iOS deployment target **26.0** | Correcto y bien razonado. iOS 26 y 27 soportan iPhone 11+; el iPhone 14 (A15) está cubierto. | ✅ |
| Liquid Glass automático al recompilar contra el SDK de iOS 26 | Correcto (comportamiento por defecto del SDK 26, con opt-out explícito). AD-13 se apoya bien en ello. | ✅ |
| Swift Testing incluido en Xcode 26 | Correcto; es el default recomendado para tests nuevos, XCTest queda para XCUITest/performance. | ✅ |
| Open-Meteo sin key, timeout 3 s | Coherente con `climate.js` en el repo y con CAP-5. | ✅ |
| Dependencias de terceros: ninguna | Coherente con la restricción de licencias del SPEC… salvo por la dependencia de Node/JS que introduce AD-6 sin declararla (ver E-2d). | ⚠️ |

**V-1 · El pin de Swift no es verificable en el build. [BAJA]** El toolchain que usa el proyecto es
el que trae Xcode 26.6 (Swift 6.3), no una descarga de swift.org. Fijar `6.3.2` como número de
Stack es un pin que nadie puede comprobar con `swift --version` bajo Xcode y que además ya está
superado por 6.3.3 en el canal de swift.org. Lo correcto es pinchar **Xcode 26.6** (que sí determina
todo lo demás: compilador, SDK, Swift Testing) y anotar Swift como "el que trae Xcode 26.6".

**V-2 · AD-2 mete un hecho perecedero dentro de una Rule. [BAJA]** L76: *"El dispositivo de
validación es un iPhone 14 (A15, sin Dynamic Island) con iOS 26."* iOS 27 sale el **14 sep 2026**
—en dos días— y soporta el iPhone 14. El *suelo* (26.0) sigue siendo correcto y esa parte de la
regla no caduca; la frase sobre el estado del dispositivo sí, y no pertenece a una Rule sino al
contexto de validación. Además nadie ha decidido qué pasa si Paul actualiza: el suelo aguanta, pero
Liquid Glass y ActivityKit cambian de comportamiento entre generaciones y el único dispositivo de
validación del proyecto está a dos días de moverse. Merece una línea, aunque sea en Deferred.

---

## 5 · Brownfield: ¿ratifica o contradice en silencio?

**Contradice en silencio, y el silencio es grande.** El spine se escribe como si el repositorio
estuviera vacío. No lo está.

**B-1 · El spine no dice nada sobre los sustratos que siguen vivos en el árbol. [ALTA]**
Estado real del repo hoy (`/Users/paul/Dev/walktracker`, rama `feature/8-1-montaje-capacitor`):

| Resto | Ubicación | Estado |
|---|---|---|
| Proyecto Xcode de Capacitor | `ios/App/` (`App.xcodeproj`, `App.xcworkspace`, `Podfile`, `Pods/`) | commiteado |
| Proyecto Xcode de Flutter | `ios/Runner.xcodeproj`, `ios/Runner.xcworkspace`, `ios/Flutter/` | commiteado |
| Web app v3 + adapters Capacitor | `www/`, `adapters/`, `index.html` (53 KB), `capacitor.config.json`, `sw.js`, `storage.js`, `runtime.js` | commiteado |
| Artefactos de build Flutter | `.dart_tool/`, `build/`, `.flutter-plugins-dependencies` | en el árbol |
| Plugins Cordova | `ios/capacitor-cordova-ios-plugins/` | commiteado |

`OPCIONES-SUSTRATO.md` §3 —fuente declarada del spine en L17— puso esto como **condición no
negociable número 1**: *"Un solo sustrato. Se elimina el camino Capacitor del repo (`ios/App/`,
`www/`, `adapters/`, `walktracker-kit/`, `capacitor.config.json`). **Dos proyectos Xcode conviviendo
en `ios/` es deuda que se cobra en cada build.**"* Hoy hay dos proyectos Xcode en `ios/` y el spine
va a introducir un tercer árbol (`WalkTracker/`, L213) sin decir **dónde vive respecto a `ios/`**,
qué se borra, qué se archiva y qué se conserva. La rama activa se llama, literalmente,
`feature/8-1-montaje-capacitor`, y la historia 8-1 en curso
(`_bmad-output/implementation-artifacts/8-1-montaje-capacitor-web-v3-en-webview-proyecto-xcode-plugin-scaffold.md`)
construye lo que AD-1 deroga. El spine tiene que ratificar o derogar el estado del repo, no ignorarlo.

**B-2 · El activo más caro que costeó la opción elegida ya no existe, y el spine no lo revisa. [ALTA]**
`OPCIONES-SUSTRATO.md` §0 y §2 valoran la Opción B (la adoptada) con la partida *"Capa nativa: se
**reaprovecha** casi entera de `AppDelegate.swift` (446 líneas ya escritas) — 0,5 fds"*, y §0 señala
que ahí vivían *"las dos capacidades más caras y más nativas del proyecto"*: `HKWorkoutBuilder`
(CAP-11) y `Activity.request` (CAP-18). Comprobado hoy: **`ios/Runner/` no existe**; el único
`AppDelegate.swift` del árbol es el de Capacitor (`ios/App/App/AppDelegate.swift`), y `lib/`,
`pubspec.yaml` y `walktracker-kit/` tampoco están. Eran código sin trackear —el §1 de ese mismo
documento avisaba: *"a un `git clean -fd` de desaparecer"*— y desaparecieron. Consecuencia directa:
la estimación de la Opción B ya no vale, CAP-11 y CAP-18 pasan de "cablear" a "escribir", y esa es
precisamente la reestimación que el spine promete y no entrega (ver B-3).

**B-3 · Los dos companions que el spine declara no existen. [CRÍTICA]**
Frontmatter L21-23:
```
companions:
  - REESTIMACION-EPICS.md
  - DEROGACIONES.md
```
Ninguno de los dos existe en el repositorio (`find` sobre todo el árbol: 0 resultados). No son
opcionales: `VALIDATION-mockups-v3-2026-09-12.md` §"Salida de esta validación", punto 3, encarga
explícitamente al arquitecto *"escribir los ADRs (incluido el que corrige `PLAN-CAPACITOR-v2.md`
líneas 27/62/179) **y la reestimación**"*. Y son el único lugar donde puede resolverse el problema
que sigue.

**B-4 · El spine `binds` 17 capabilities cuyo texto vinculante dice lo contrario. [CRÍTICA]**
AD-1 (L70) despacha esto en media línea: *"Deroga `PLAN-CAPACITOR-v2.md` y reabre OQ-1 del SPEC."*
Pero reabrir una OQ no reescribe el contrato, y el contrato que el spine dice vincular (L13-16) hoy
dice:

- `SPEC.md § Constraints`, primera entrada: *"**Capacitor como capa nativa** (decisión Paul, OQ-1):
  la web app v3 existente (UI + dominio) se reutiliza dentro de un WebView nativo... **Descarta la
  reescritura SwiftUI total.**"*
- `SPEC.md § Non-goals`, última entrada: *"**Reescritura SwiftUI total de la app** (decisión Paul,
  OQ-1: Capacitor)."*
- `SPEC.md § Success signal`: *"La viabilidad de **Capacitor** queda demostrada en su iPhone físico."*
- `SPEC.md § Open Questions`: *"(Ninguna abierta — OQ-1 ... resuelta)"*.
- `capabilities.md` CAP-5 (proveedor por Capacitor), CAP-9 (*"Bajo Capacitor, el storage vive en el
  sandbox... `@capacitor/preferences` como refuerzo"*), CAP-18 (*"Costo aceptado bajo Capacitor...
  bridge para empujar las métricas desde el WebView"*).
- `platform-matrix.md`: la matriz **entera** (R1–R10 y la comparativa de cierre) está escrita en
  clave Capacitor, y es companion adoptado del SPEC.

**El caso más grave es CAP-17**, porque no es sólo texto obsoleto: es la justificación de su
presencia en el scope. `capabilities.md` CAP-17: *"**Condición de Paul:** entra a scope **solo si el
esfuerzo es bajo** → confirmado: con Capacitor se implementa vía `@capacitor/local-notifications`
(plugin estándar, licencia MIT), **sin código nativo custom**."* Adoptado SwiftUI, la premisa que
satisfacía la condición de Paul deja de ser cierta, y nadie ha vuelto a comprobar la condición.
El spine incluye CAP-17 en `binds` (L11) y en el mapa (L261) como si nada hubiera pasado.
Con `UserNotifications` nativo el esfuerzo probablemente sigue siendo bajo — pero eso es una
conclusión que hay que **escribir**, no asumir.

**B-5 · `AGENTS.md` no se ratifica ni se enmienda. [MEDIA]**
`AGENTS.md` es el fichero de convenciones vivo del repo, se carga en cada sesión de agente y se
declara a sí mismo *"invariantes, no sugerencias"*. Coincide con el spine en lo hexagonal, la regla
de dependencia, la validación en la frontera y las licencias — **eso el spine lo ratifica de hecho,
y hace bien**. Pero sus "Convenciones de código" sólo cubren Java/Spring, Python y JS/TS (`pnpm`),
no Swift; y su sección "Ramas (GitFlow)" impone *"todo merge a `main`/`develop` es vía Pull Request
revisado"*, que es justamente el gate donde AD-6 dice que *"un vector que falla bloquea el merge"*.
El spine debería o bien apoyarse explícitamente en ese flujo (y resolver así E-2c), o bien decir que
lo enmienda. Hoy no menciona `AGENTS.md`.

---

## 6 · Cobertura de CAP-1..15, CAP-17, CAP-18

Las **17** capabilities declaradas en `binds` (L11) aparecen en el mapa (L242-262), con la ubicación
y los ADs que las gobiernan. CAP-16 está correctamente ausente (retirada por OQ-3, ID reservada).
El mapa es útil y hay que conservarlo. Pero "aparecer" y "estar gobernada" no son lo mismo:

| CAP | Cobertura | Nota |
|---|---|---|
| CAP-1 | ⚠️ parcial | Falta la persistencia/recuperación de la sesión activa (D-2). Los ADs listados no tocan disco |
| CAP-2, CAP-3 | ✅ | AD-8 + AD-10 + AD-11 la gobiernan de verdad |
| CAP-4 | ✅ | |
| CAP-5 | ⚠️ parcial | Sin `LocationPort` y sin la regla de redondeo de coordenadas (D-3) |
| CAP-6 | ⚠️ nominal | Mapeado a AD-5, pero la Rule de AD-5 (L94) sólo especifica el catálogo de logros y las constantes de fórmula; **`quotes.json` no entra en su validación de arranque** pese a que A-3 lo blinda igual que el catálogo ("100 frases íntegras, sin cambios"). Cualquier fichero de 37 frases arrancaría sin ruido |
| CAP-7 | ⚠️ parcial | Gobernada por AD-5 y AD-6, pero AD-6 no tiene vectores de `GoalEngine` (E-2b), y la frontera de semana está en conflicto (D-1) |
| CAP-8 | ⚠️ parcial | AD-5 protege el *catálogo*; AD-6 debería proteger la *evaluación* y no la cubre (E-2b). Zona horaria en conflicto (D-1) |
| CAP-9 | ✅ | AD-9, salvo la política de lectura corrupta (ver O-4) |
| CAP-10 | ✅ | |
| CAP-11, CAP-12 | ⚠️ | CAP-12: `FeedbackPort` existe, pero nadie dispara (D-4) |
| CAP-13 | ✅ | La zancada congelada viene del contrato heredado |
| CAP-14 | ❌ | AD-9 la declara resuelta y no lo está (E-3, CSV) |
| CAP-15 | ⚠️ nominal | Mapeada a `HistoryStore` + AD-9. Su regla transversal —borrar una sesión **recalcula** totales/meta/acumulados pero **no revoca** logros ya desbloqueados (`achievements.md` §Reglas transversales, `capabilities.md` CAP-15)— es una invariante que cruza `HistoryStore`, `GoalEngine` y `AchievementEngine`, y el spine no la coloca en ninguna capa |
| CAP-17 | ⚠️ | Cubierta estructuralmente; su justificación de scope quedó anulada (B-4) |
| CAP-18 | ⚠️ parcial | AD-15 fija estructura, no mecanismo ni cadencia (E-5, O-1) |

---

## 7 · Dimensiones de esta altitud: ¿decididas, diferidas o marcadas?

**O-1 · Rendimiento y batería: dimensión entera en silencio. [CRÍTICA]**
Comprobado: `bater`/`batería` → **0 ocurrencias** en el spine. No hay AD, no hay convención, no hay
Deferred, no hay pregunta abierta. Y no es una dimensión opcional en este producto:

- `SPEC.md § Constraints`, entrada propia: *"**Batería:** una sesión de 60 min con conteo continuo
  no degrada la batería de forma notoria."*
- `SPEC.md § Success signal` la eleva a criterio de éxito: *"una sesión completa de 60 min con
  conteo en background **sin degradación de performance ni de batería notoria**."*
- `OPCIONES-SUSTRATO.md` la trata como el gate de riesgo que decide entre sustratos.

Las decisiones que cuelgan de aquí son de arquitectura, no de historia, porque las toman varias
unidades a la vez y tienen que coincidir: (a) `CMPedometer` en `startUpdates` continuo vs. query
periódica; (b) frecuencia del tick de UI durante la sesión (el cronómetro es wall-clock, así que el
timer sólo refresca: 1 Hz basta, pero nadie lo dice); (c) **cadencia de actualización de la Live
Activity** y su presupuesto ActivityKit —CAP-18 exige "en vivo" con la app en background, y ese
presupuesto es el consumidor de batería más probable de todo el diseño—; (d) qué se apaga al pasar
a background. Como mínimo, el gate de 60 min debe aparecer como criterio arquitectónico verificable;
lo demás puede diferirse, pero **diciéndolo**.

**O-2 · Seguridad y privacidad: presente como eslogan, ausente como regla. [ALTA]**
Lo que hay: *"sin telemetría de terceros"* (L50), *"Sin telemetría, sin red, sin terceros"* (L195),
*"Sin crash reporting ni analítica"* (L240). Todo eso son **prohibiciones**, y las prohibiciones son
la parte fácil. Lo que falta son las reglas accionables:

- El **redondeo de coordenadas a 2 decimales** antes de salir a Open-Meteo — la única regla de
  privacidad ejecutable del producto, perdida en la reescritura del contrato heredado (D-3).
- **Protección de datos en disco.** AD-9 pone los ficheros en Application Support con escritura
  atómica y no dice nada de la clase de `NSFileProtection`. Es el historial médico-adyacente de una
  persona; la clase por defecto (`CompleteUntilFirstUserAuthentication`) probablemente esté bien,
  pero es una decisión, no un descuido.
- **Entitlements e identificadores**: HealthKit, App Group, Live Activity. El identificador del App
  Group (AD-15) es una cadena compartida por dos targets — convención obligada.
- Cadenas de **`Info.plist`** (`NSMotionUsageDescription`, `NSHealthUpdateUsageDescription`,
  `NSLocationWhenInUseUsageDescription`): AD-11 dice que cada adapter posee su permiso; el texto que
  ve el usuario al pedirlo es tono de producto ("celebrar, nunca culpar") y hoy no tiene sitio —
  ni en el String Catalog, porque `Info.plist` no pasa por ahí.

**O-3 · Accesibilidad: una línea heredada, y apunta al revés. [MEDIA]**
Todo lo que hay: *"Targets táctiles ≥ 44 pt · claro y oscuro"* (L51). Cero ocurrencias de
`accesib`, `VoiceOver`, `Dynamic Type`. AD-13 hace lo correcto al heredar Liquid Glass —los
controles nativos traen accesibilidad gratis— pero **autoriza tres piezas dibujadas a mano**
(`GoalRing`, `TrendChart`, `AchievementBadge`, L230) que son exactamente las que no traen nada: un
anillo de progreso sin `accessibilityValue` es invisible para VoiceOver, y un gráfico de tendencia
sin descripción no existe. Súmese la dirección de UX heredada *"números grandes"*, que compite
directamente con Dynamic Type en tamaños grandes. Una regla de dos líneas en Convenciones cierra
esto ("las tres piezas dibujadas exponen `accessibilityLabel`/`Value`; ninguna tipografía se fija en
puntos absolutos") y hoy no está.

**O-4 · Gestión de errores: buena en la salida, muda en la entrada. [MEDIA]**
La convención de errores (L191) es sólida: dominio con errores tipados, **una** traducción a mensaje
de usuario, nunca un error crudo del sistema. AD-11 cubre magistralmente los fallos de *capacidad*.
Lo que no está cubierto es el fallo de **datos propios**: AD-5 falla ruidosamente si
`achievements.json` (recurso del bundle, controlado por el desarrollador) no cuadra, pero AD-9 no
dice nada de qué ocurre si `sessions.json` —única copia de los datos del usuario, no reproducible—
está corrupto, truncado o trae un `schemaVersion` desconocido. Con CAP-9 prometiendo *"persistencia
garantizada"*, "fallar ruidosamente" no puede ser la respuesta por defecto también aquí, y
"ignorar y empezar de cero" es peor. Hay que decidirlo o diferirlo nombrándolo.

**O-5 · Observabilidad: mínima pero coherente. [BAJA]**
`OSLog` con subsistema propio, sin red ni terceros (L195). Para un producto de un solo usuario sin
CI es proporcionado y está bien resuelto. Único hueco menor: no dice qué se registra
—transiciones de sesión, resultados de reconciliación, decisiones de degradación de AD-11— que es
justo lo que hará falta para diagnosticar el gate de 60 min de O-1 desde el dispositivo.

**O-6 · Envoltura operativa: es la dimensión mejor tratada de las siete, con dos huecos. [BAJA]**
L240 decide dev (build local a iPhone 14 físico, con la razón: *"el simulador no tiene coprocesador
de movimiento"* — excelente), distribución (TestFlight opcional) y ausencia de CI y de telemetría,
esta última **derivada de una restricción del SPEC**, que es la forma correcta de justificar una
ausencia. Huecos: (a) no ata la assumption A-1 (cuenta Apple Developer **de pago**), que no es
opcional aquí porque HealthKit, App Groups y Live Activity la exigen; (b) no fija bundle identifier
ni identificador de App Group. Y "Sin CI" choca con AD-6 (E-2c).

---

## 8 · Tersura

El spine tiene ~275 líneas y podría decir lo mismo en ~230 mejor colocadas. La prosa es buena
—densa, con la razón detrás de cada decisión y sin relleno de plantilla— y los dos diagramas
existen. El problema no es el volumen: es que hay material en la altitud equivocada.

**T-1 · "Contrato heredado del SPEC" (L40-51) es una copia lossy. [ALTA — es la causa de D-3]**
Nueve viñetas que reescriben `SPEC.md § Constraints`. Una copia de un contrato vinculante es deuda
por definición: se desincroniza. Y ya se desincronizó — al resumir se perdieron **las dos
restricciones del SPEC que el spine luego incumple**: el redondeo de coordenadas a 2 decimales
(D-3/O-2) y la restricción de batería (O-1). El resumen no es inocuo: es exactamente el mecanismo
por el que esas dos dimensiones desaparecieron. O se cita (*"vinculante tal cual: `SPEC.md
§ Constraints` completo"*, con un puntero) o se copia entero. Un extracto de nueve de once, sin
marcar que es un extracto, es la peor de las tres opciones.

**T-2 · El primer diagrama (L55-64) no añade sobre la tabla que tiene encima. [BAJA]**
La tabla de capas (L32-38) ya declara, por capa, qué puede importar — y es la forma **ejecutable**
del mismo hecho. El grafo repite eso con flechas, y el nodo `X((∅))` con la etiqueta
*"no importa nada"* es decoración. Si se conserva un diagrama de estructura, que muestre lo que la
tabla no puede: los límites de **target** (app, extensión, `Shared`, y los módulos SPM si E-1 se
resuelve por modularización), que es la información que hoy falta.

**T-3 · La nota dentro del diagrama de estados (L123-129) repite AD-8 en prosa. [BAJA]**
El `stateDiagram` sí gana su sitio: la máquina de estados de la sesión es información que la prosa
transmite mal. La nota de cinco líneas dentro de él transcribe la Rule de AD-8, que está quince
líneas más arriba. Basta con `reconciling: comandos rechazados (AD-8)`.

**T-4 · Dos ADs que son convenciones. [MEDIA]**

- **AD-4** no previene nada por sí solo y lo reconoce al delegar en AD-6 (ver E-4). Su mitad
  verificable —conservar el lenguaje ubicuo— ya está duplicada en Convenciones (L186). Propuesta:
  eliminarlo y añadir a AD-6 una frase de encuadre (*"el dominio se escribe idiomático; la
  equivalencia no la da el parecido del código sino estos vectores"*). Se ahorran cinco líneas y se
  gana un AD menos que revisar.
- La última frase de **AD-13** (*"Los colores del sistema se referencian, no se cablean en
  hexadecimal"*) es una convención de código pura, verificable con `rg`, y está bien — pero en la
  tabla de Convenciones, no dentro de un AD sobre lenguaje visual.

**T-5 · Dos convenciones que son ADs, y una de ellas está en conflicto abierto. [ALTA]**

- **Unidades** (L190): *"Metros y segundos en el dominio, **siempre**. La conversión a km y a
  `mm:ss` ocurre solo en la capa de formato de UI."* Esto vincula a **todas** las capabilities,
  cruza las cuatro capas, y la divergencia que previene —dos unidades del mismo dato en dos
  módulos— es la más clásica y la más cara de todas. Es un AD con `Binds: todo` disfrazado de fila
  de tabla, y su ubicación actual hace que un lector de historias lo lea como estilo.
- **Fechas** (L189): mismo caso, agravado porque **hoy contradice `domain-model.md` §5 sin decirlo**
  (D-1) y porque AD-6 lo congelará al extraer los vectores de una implementación que evalúa en UTC.
  Es la decisión que necesita más discusión escrita del documento y es la que menos tiene.

**T-6 · "Envoltura operativa" es un párrafo huérfano. [BAJA]**
L240 vive bajo "Structural Seed", después del bloque de código, sin encabezado propio. Es la única
aparición de la dimensión operativa en todo el spine y contiene tres decisiones reales. Merece su
propia sección `## Operational Envelope`, aunque sea de cuatro líneas — entre otras cosas para que
sea evidente lo que le falta (O-6) y para que "Sin CI" quede visible al lado de AD-6.

---

## Acciones mínimas para levantar la puerta

Ordenadas por lo que desbloquea.

1. **Escribir `DEROGACIONES.md`** (B-3, B-4): qué frases del `SPEC.md`, `capabilities.md`
   (CAP-5, 9, 17, 18) y `platform-matrix.md` (R1–R10) quedan derogadas, y **re-verificar la
   condición de scope de CAP-17** bajo `UserNotifications` nativo.
2. **Escribir `REESTIMACION-EPICS.md`** (B-2, B-3): la estimación de la Opción B asumía reutilizar
   446 líneas de Swift que ya no están en el árbol; CAP-11 y CAP-18 vuelven a ser trabajo nuevo.
3. **Añadir un AD de higiene del repositorio** (B-1): qué se borra, qué se archiva, dónde vive
   `WalkTracker/` respecto a `ios/`, y qué se conserva del árbol JS —porque AD-6 lo necesita vivo—.
4. **Corregir AD-9** (E-3): acotarlo al JSON y decidir o diferir explícitamente el CSV, con
   separador decimal y de campo.
5. **Corregir AD-6** (E-2): contar de nuevo (281, no 168), ampliar el conjunto de origen para cubrir
   `GoalEngine` y `AchievementEngine`, declarar el gate real de merge o rebajar la frase, y declarar
   la dependencia de Node.
6. **Resolver D-1** (semana ISO / hora local) como AD, no como fila de tabla; incluye qué zona
   llevan los vectores de calendario.
7. **Añadir las tres decisiones ausentes**: snapshot y recuperación de sesión activa (D-2),
   `LocationPort` + redondeo de coordenadas (D-3), disparador y deduplicación de celebraciones (D-4).
8. **Abrir la dimensión de rendimiento/batería** (O-1), aunque sea íntegramente en Deferred, con el
   gate de 60 min y la cadencia de la Live Activity nombrados.
9. **Dos líneas de accesibilidad** para las tres piezas dibujadas (O-3) y **una** de política de
   lectura corrupta (O-4).
10. **Tersura**: sustituir T-1 por una cita completa o un puntero, eliminar AD-4, promover Unidades
    y Fechas a ADs, sacar la envoltura operativa a sección propia.
