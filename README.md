# WalkTracker

Registro de caminatas con conteo de pasos, clima, metas y motivación. **App iOS nativa (SwiftUI).**

El sustrato Capacitor/WebView está derogado (AD-1, AD-23): no hay PWA, ni plugins Capacitor, ni
doble canal. El producto vive en un único árbol y se compila con Xcode.

## Qué hace falta instalado

| Herramienta | Versión | Para qué |
| --- | --- | --- |
| Xcode | **26.3** (17C529) | toolchain Swift 6.2.4, SDK iOS 26.2 |
| XcodeGen | **2.46.0** (`brew install xcodegen`) | genera `WalkTracker.xcodeproj` desde `project.yml` |
| Node | ≥ 18 | ejecutar las suites de referencia de AD-6 |
| pnpm | 12.x | dependencias de desarrollo del JS de referencia |

XcodeGen es herramienta de build, **no dependencia de la app**: no entra en ningún target. El
producto no tiene dependencias de terceros.

## Generar el proyecto

`WalkTracker.xcodeproj` **no se versiona**. La fuente de verdad es `project.yml`, y el proyecto se
regenera:

```bash
xcodegen generate       # crea WalkTracker.xcodeproj
open WalkTracker.xcodeproj
```

Así nadie cambia un ajuste de build sin que aparezca en el diff, y no hay `.pbxproj` que resolver
en un merge.

> **Coste operativo, y conviene saberlo antes de perder una hora:** XcodeGen fija la lista de
> ficheros. Si añades o borras un `.swift` **desde fuera de Xcode**, tienes que volver a ejecutar
> `xcodegen generate` antes de compilar. Un fichero nuevo sin regenerar no rompe el build: se
> ignora **en silencio**. `Scripts/check-project-shape.sh` corre en cada build precisamente para
> convertir ese silencio en un fallo ruidoso.

### Compilar y probar

```bash
# Simulador, sin firma
xcodebuild build -project WalkTracker.xcodeproj -scheme WalkTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16e' CODE_SIGNING_ALLOWED=NO

# Suite de Swift Testing
xcodebuild test -project WalkTracker.xcodeproj -scheme WalkTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16e' CODE_SIGNING_ALLOWED=NO
```

El simulador **no tiene coprocesador de movimiento**: nada que dependa de CAP-2 o CAP-3 se valida
ahí. La validación real es en el iPhone 14 físico, congelado en iOS 26.

## Estructura

```text
Domain/               # PURO — solo Foundation. Su propio módulo.
  Ports/  Engines/  DomainError.swift
WalkTracker/          # la app
  App/                # entrada SwiftUI + composition root
  Application/  Adapters/  UI/  Resources/
Shared/               # ActivitySnapshot + su formateo — compartido con la extensión
WalkTrackerActivity/  # Widget Extension — SOLO renderiza
WalkTrackerTests/     # Swift Testing · Vectors/ (AD-6, 8.7) · Scenarios/ (Epic 1)
Scripts/              # gates, verificación del dominio y release a TestFlight
project.yml           # fuente de verdad del proyecto Xcode
```

**`Domain/` es su propio módulo, y eso no es cosmético.** Es lo que hace *estructural* la dirección
de dependencias (AD-3): desde `Domain` no se puede nombrar un tipo de `UI/` ni de `Adapters/`
**aunque no escribas ningún import**, porque esos símbolos no existen en su módulo. No es una regla
de revisión: es el enlazador.

## Los gates

`Scripts/check-project-shape.sh` corre como build phase de `WalkTracker` **y** de
`WalkTrackerActivity` —en las dos, porque la extensión compila antes que la app— y comprueba lo que
el grafo de módulos no ve:

1. Que `Domain/` exista.
2. Que las `sources:` de `WalkTrackerActivity` no **alcancen** `Domain/`.
3. Que todo `.swift` del árbol esté en algún target.
4. Que ningún fichero de `Domain/` importe un framework de plataforma (AD-3).
5. Que `WalkTrackerActivity` no importe `Domain` (AD-15).

Los puntos 4 y 5 son parseo de imports y son necesarios: `import SwiftUI` dentro de un framework
compila perfectamente, y `import Domain` en la extensión **también** compila, porque la app embebe
`Domain.framework` y el módulo queda resoluble desde `BUILT_PRODUCTS_DIR`. El compilador no puede
hacer cumplir esa mitad de AD-3/AD-15 por sí solo.

Su camino rojo es ejecutable, y correrlo es obligatorio si tocas el gate:

```bash
bash Scripts/check-project-shape-tests.sh
```

Monta un árbol temporal y afirma que el script **falla** en cada violación que dice detectar, y que
pasa sobre un árbol limpio. Un gate sin prueba de su camino rojo no es un gate.

> La build phase corre con `basedOnDependencyAnalysis: false` **a propósito**. Declarar un fichero
> de salida la hacía cacheable y desactivaba el gate en silencio (verificado: una violación pasó el
> build). El precio es una `note:` de Xcode en cada build. No es un warning.

## Dominio de referencia (AD-6)

`domain.js`, `motivation.js`, `climate.js`, `storage.js` y las suites de `test/` se conservan
**congelados** como referencia de contraste del port a Swift. No son código vivo y no se editan
salvo para corregir un defecto de la v3.

```bash
pnpm install

for t in domain session-v3 motivation gapestimator storage climate runtime migration stepdetector; do
  node test/$t-tests.js
done
```

Esperado: **438 aserciones en verde**.

Estas suites corren con `node`, no con vitest: son scripts autoejecutables y vitest no los
recolecta. `npx vitest run` sí ejecuta `test/index-tests.js` (integración jsdom del `index.html`
heredado), que arrastra 9 fallos previos al pivot y no bloquea nada de este epic.

## Verificación del dominio (AD-6)

```bash
bash Scripts/verify-domain.sh
```

**Su verde es Definition of Done de toda historia que toque `Domain/`.** No hay CI: este script es
el mecanismo, no una recomendación. Hace tres cosas y sale ≠ 0 si cualquiera falla:

1. **Inventario** (`Scripts/vectors/check-inventory.js`). Cada sitio de aserción de
   `test/{domain,session-v3,motivation,gapestimator}-tests.js` está **exactamente una vez** en
   `WalkTrackerTests/Vectors/inventory.json`: vector, escenario (con la historia del Epic 1 que lo
   porta) o excluido (con motivo). Los totales vigentes son los que imprime `check-inventory` (y
   declara `totals` en el inventario); un sitio que falta, sobra o cambió se nombra como
   `fichero:línea`. A continuación, dentro del mismo paso, corre `Scripts/vectors/red-path-tests.sh`:
   el **camino rojo del arnés JS**. Sobre copias temporales de los vectores, el inventario y el
   catálogo (nunca el árbol real) afirma código de salida y mensaje de cada fallo que el runner y el
   inventario dicen detectar. Si un gate deja de detectar lo que dice, `verify-domain.sh` sale en rojo.
2. **Runner JS** (`Scripts/vectors/run-js.js`). Ejecuta `domain.js` y `motivation.js` contra
   `WalkTrackerTests/Vectors/*.json`. Solo pueden fallar los vectores marcados con una de las dos
   divergencias declaradas —`localTime` (hora local, no UTC) y `wmoCategory` (lluvia por código WMO,
   incluidos los chubascos 80–82)—; el vector lleva el valor de Swift. Un divergente que `domain.js`
   **pase** también rompe: la divergencia ya no existe y hay que retirarla. Fuera de
   `evaluateAchievements`, un divergente lleva además `expectedJs` —el valor exacto que da
   `domain.js`— para que un error del vector no se esconda tras la divergencia. Comprueba además que los
   14 logros tengan un vector que desbloquea y otro que no, y que `achievements.json` conserve
   nombres, descripciones e iconos de la referencia.
3. **Swift** (`xcodebuild test` de `DomainVectorTests`, `VectorHarnessTests` y
   `AchievementCatalogTests`). Regenera el proyecto antes, para que un vector nuevo no quede fuera
   del bundle en silencio. Las funciones aún sin portar se listan como **pendientes**; las portadas
   que fallan rompen.

**Al portar una función al dominio Swift**, regístrala en `VectorHarness.swiftDomain`
(`WalkTrackerTests/Vectors/VectorHarness.swift`): desde ese momento sus vectores dejan de estar
pendientes y pasan a vincular. Un vector nuevo va en el fichero de su función, en datos neutrales
(`NaN`/`Infinity` como cadena en la entrada; `null` para una métrica ausente) y, si es de hora,
con `timeZone`.

El destino del simulador se cambia con `VERIFY_DESTINATION`.

## Releases a TestFlight (8.3)

TestFlight es el canal duradero al iPhone 14. App Store está **fuera de scope**: no hay ficha,
capturas ni envío a revisión.

### Política de versiones (SemVer)

- **`project.yml` es la única fuente de la versión** (`MARKETING_VERSION`). El número de build
  **no se edita a mano**: lo calcula el script (`git rev-list --count HEAD`) y solo crece.
- **Durante todo el MVP la versión se queda en `4.0.0`.** Cada subida etiqueta
  `v4.0.0-build.N`; la etiqueta `v4.0.0` a secas se reserva para el MVP completo.
- **Después del MVP:** PATCH para arreglos, MINOR para funcionalidad, MAJOR para cambios que rompan
  datos. Se cambia `MARKETING_VERSION` en `project.yml`, en un commit, antes del release.
- La etiqueta nombra **exactamente** el binario subido: el script comprueba en el archivo que la app
  y la extensión dicen esa versión y ese build antes de exportar.

### Hacer un release

```bash
git checkout main && git pull
bash Scripts/release-testflight.sh --dry-run     # opcional: archiva y exporta un .ipa local
bash Scripts/release-testflight.sh               # archiva, pide confirmación, sube y etiqueta
git push origin v4.0.0-build.N                   # publica la etiqueta que imprimió
```

Antes de archivar, el script exige **todo** esto y, si falta algo, dice qué y sale ≠ 0 sin archivar:

- Xcode **26.x** (se niega con otra versión mayor; 26.3 es el verificado).
- Rama `main` y árbol **limpio**, sin ficheros sin seguimiento.
- Tras `git fetch --tags origin`, **HEAD igual a `origin/main`**: los PR se fusionan en GitHub, y un
  `main` sin pull subiría un commit que no es el fusionado. Las etiquetas de otros clones cuentan.
- `MARKETING_VERSION` SemVer y definida una sola vez.
- La etiqueta `v<versión>-build.<N>` libre y `N` mayor que cualquier build ya etiquetado.
- `Scripts/check-project-shape.sh` y `Scripts/verify-domain.sh` en verde.

**La subida pide confirmación explícita**: hay que escribir la etiqueta. Un número de build subido
queda gastado para siempre, suba bien o no. Sin terminal interactiva (p. ej. cuando lo ejecuta
Claude) se pasa `--confirm v4.0.0-build.N`, **solo con la confirmación de Paul en ese momento**, y
tiene que coincidir con la etiqueta calculada o no se archiva.

HEAD y el árbol se vuelven a comprobar tras los gates, tras el archivo y justo antes de subir: si
alguien edita o hace commit mientras tanto, el script se detiene. El archivo y la subida muestran su
progreso en la terminal y lo guardan en los logs.

El `--dry-run` vale en cualquier rama con árbol limpio y no va a la red: exporta un `.ipa` firmado
para distribución en `build/release/<etiqueta>-ensayo/export/` y no sube ni etiqueta nada. El número
de build que muestra es **provisional**: el real se calcula en `main` al hacer el release. Archivos y logs quedan en
`build/release/` (ignorado por git).

La subida usa la cuenta de Apple **configurada en Xcode** (Ajustes → Cuentas) con
`xcodebuild -exportArchive` y `Scripts/ExportOptions-testflight.plist` (`destination: upload`). No
hay clave de API, contraseñas ni perfiles en el repositorio, ni fastlane: la firma automática crea
lo que falte (certificado Apple Distribution, App ID de la extensión) con `-allowProvisioningUpdates`.

El camino rojo del script es ejecutable y no toca App Store Connect:

```bash
bash Scripts/release-testflight-tests.sh
```

### Lo que Paul hace a mano

**En Xcode, una sola vez:** Ajustes → Cuentas → **+** → Apple ID del equipo de pago
(`Z3M45B4K6D`). Sin cuenta, `xcodebuild -exportArchive` falla con «No Accounts» incluso en el
`--dry-run`: los perfiles de desarrollo que ya hay en disco sirven para archivar, pero no para firmar
la distribución.

### Cuando una subida falla o App Store Connect rechaza el build

- **La subida falla o se interrumpe** (error de `xcodebuild`, Ctrl-C, red): el script **no
  etiqueta**, pero el build `N` puede haber llegado ya a App Store Connect y quedar gastado. Repetir
  desde el mismo commit da el mismo `N` y se rechazaría. Para reintentar hace falta un **commit nuevo
  en `origin/main`** —vale uno vacío: `git commit --allow-empty -m "release: reintento"`, empujado o
  fusionado— y otro release, que calculará `N+1`.
- **App Store Connect lo rechaza después de procesarlo** (llega por correo, minutos después): la
  subida ya terminó bien y **la etiqueta ya existe**. No se borra: queda como registro de un build
  gastado. El arreglo entra como un commit nuevo en `main` y sale en un build nuevo.

**En App Store Connect, una sola vez, antes de la primera subida:** Apps → **+** → Nueva app →
plataforma iOS, idioma principal español, bundle id `com.walktracker.app`, un SKU cualquiera. El
nombre de la ficha es el que quede disponible (no tiene que ser «WalkTracker»). **Creado el
2026-09-13 con el nombre `walktracker`.**

**Validar antes de gastar un build:** abrir el `.xcarchive` de un `--dry-run` en Xcode (Organizer) →
**Validate App**. Comprueba el binario contra App Store Connect sin subirlo. Así se descubrió que
HealthKit exige también `NSHealthShareUsageDescription`, aunque la app solo escriba.

**En cada release:**

1. App Store Connect → la app → **TestFlight**: esperar a que el build pase de «Procesando» a listo
   (unos minutos; llega un correo).
2. La primera vez, añadirse como **tester interno** (grupo de pruebas interno con tu Apple ID). Los
   testers internos no necesitan revisión de Apple.
   **El grupo tiene que tener el build asignado** (grupo → Compilaciones → +, o activar la
   distribución automática): con el tester dentro pero sin build, TestFlight no envía la invitación y
   el tester aparece con «No hay compilaciones disponibles».
3. Si pregunta por el cumplimiento de exportación, no debería: `ITSAppUsesNonExemptEncryption = NO`
   ya va en el `Info.plist`. Se basa en la suposición de que la app solo usará el HTTPS del sistema;
   la historia del clima la revisa cuando entre la primera llamada de red.
4. iPhone 14 → app **TestFlight** → WalkTracker → Instalar. La app abre; la pantalla de diagnóstico
   de la 8.6 **no** aparece, porque es solo `DEBUG` y TestFlight instala Release.

Un build de TestFlight caduca a los **90 días**: antes de eso, otro release.

**Privacidad:** `WalkTracker/Resources/PrivacyInfo.xcprivacy` declara cero rastreo y cero datos
recogidos. Hoy la app no hace ninguna llamada de red; lo que dice sobre el clima es una suposición
que la historia del clima tiene que revisar cuando entre. La primera historia que use una API con motivo obligatorio (`UserDefaults`, fechas de
ficheros, tiempo desde el arranque, espacio en disco) la declara ahí o App Store Connect rechaza el
build.

## Estado

- El proyecto y el árbol limpio son la historia **8.5** (esta).
- La capa nativa se extrae de `feature/flutter-substrate` en la **8.6** — esa rama **no se mergea**:
  entra por `git checkout` de un único fichero. Por eso `ios/` sigue en `.gitignore` aunque hoy no
  tenga contenido versionado.
- El arnés de verificación del dominio es la **8.7**: `Scripts/verify-domain.sh`, arriba.
- La distribución por TestFlight con etiquetas SemVer es la **8.3**: `Scripts/release-testflight.sh`, arriba.
