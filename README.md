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
Scripts/              # gates de forma del proyecto
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

## Estado

- El proyecto y el árbol limpio son la historia **8.5** (esta).
- La capa nativa se extrae de `feature/flutter-substrate` en la **8.6** — esa rama **no se mergea**:
  entra por `git checkout` de un único fichero. Por eso `ios/` sigue en `.gitignore` aunque hoy no
  tenga contenido versionado.
- El arnés de verificación del dominio es la **8.7**: `Scripts/verify-domain.sh`, arriba.
