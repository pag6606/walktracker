---
title: 'B-1 — Unos ajustes que no se pudieron leer no se sobrescriben'
type: 'bugfix'
created: '2026-09-20'
baseline_commit: 'd775ba19a1c5d282597c065a070c0bc1207bf510'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-retro-2026-09-20.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** un fallo de lectura de `settings.json` al arrancar **borra la configuración de Paul en
la primera caminata**. `SettingsStore.load()` colapsa tres situaciones distintas —no hay fichero, no
se pudo leer, es de un esquema del futuro— en el mismo estado en memoria (`AppSettings.defaults`) y
**no recuerda que la lectura falló**. La siguiente escritura es incondicional: `openSession()` llama
a `recordShownQuote(id:)`, que llama a `save()`, que escribe encima.

Confirmado ejecutando el caso (retro del Epic 2, hallazgo D1):

```
✘ (storage.settings?.strideM → nil) == 0.72
✘ (storage.settings?.recentQuoteIds.prefix(3) → [7]) == [1, 2, 3]
```

Un error transitorio de unos cientos de bytes se lleva por delante la zancada recalibrada de la 2.3 y
la ventana de frases de la 2.2, de forma permanente, en cuanto Paul pulsa "Iniciar caminata". El
fichero no se corrompió: lo sobrescribe la app con sus valores por omisión.

**La misma mecánica hace falsa una promesa escrita en el código.** `SettingsFileAdapter.swift:28-32`
declara que un fichero de un esquema más nuevo se deja intacto *"para que la versión que sí lo
entiende lo recupere entero"*. La preservación dura hasta que Paul anda.

**Enfoque:** el store aprende a distinguir **"no hay nada que perder"** de **"hay algo y no pude
leerlo"**, y en el segundo caso **no escribe**. Antes de una escritura bloqueada reintenta la
lectura: un fallo transitorio se recupera solo, y lo que de verdad no se puede interpretar —un
esquema del futuro— sigue protegido mientras exista.

## Boundaries & Constraints

**Always:**
- **Sin una lectura buena no se escribe.** Un `settings.json` que existe pero no se pudo interpretar
  nunca se sobrescribe con valores por omisión.
- **Sin fichero sí se escribe.** "No hay nada todavía" es el caso normal de la primera instalación y
  no puede quedar bloqueado, o nada se guardaría nunca.
- **Un fallo transitorio se recupera solo:** antes de una escritura bloqueada se reintenta la
  lectura, y si ahora funciona, el cambio se aplica **sobre lo que había en disco**, no sobre los
  valores por omisión que el store arrastraba.
- **La app sigue funcionando sin ajustes:** se camina, se cuentan pasos y se muestran frases con los
  valores por omisión. Perder la configuración no puede impedir caminar; sobrescribirla, tampoco.
- **El log distingue los tres casos**, porque hoy no se distinguen y esa es la causa raíz.
- El resultado observable que ya existe para "no se pudo guardar" (`SettingsStore+Stride.swift`) se
  reutiliza: Ajustes ya sabe decir que no se persistió.
- Los gates y la suite siguen en verde; `verify-domain.sh` incluido.

**Never:**
- Tocar el adapter para que aparte, borre o migre un fichero que hoy deja intacto: la política del
  adapter es correcta y el defecto está en su dueño.
- Cambiar el esquema de `settings.json`, ni su versión.
- Arreglar aquí los otros hallazgos de la retro (el color del mensaje de error, la zancada que
  desborda, el solape frase/permiso): cada uno tiene su action item.
- Bloquear, retrasar o condicionar el arranque de una caminata a que los ajustes se puedan leer.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Primera instalación | no hay `settings.json` | valores por omisión, y **sí se escribe** al caminar | — |
| Fallo transitorio, sin recuperación | la lectura falla al arrancar y sigue fallando | valores por omisión en memoria; **no se escribe**; el fichero sobrevive intacto | `log.error` que nombra el caso |
| Fallo transitorio, recuperado | la lectura falla al arrancar y funciona al reintentar | el cambio se aplica **sobre lo leído del disco**: la zancada y la ventana anteriores sobreviven | — |
| Esquema del futuro | `settings.json` con una versión mayor | valores por omisión en memoria; **nunca se escribe**, ni aunque se reintente | `log` que lo diga |
| Caminar con la lectura fallida | sesión completa con frases | la app funciona; la ventana de esta ejecución vive en memoria; el fichero no cambia | — |
| Guardar zancada con la lectura fallida | Paul pulsa Guardar en Ajustes | **no se persiste**, y la pantalla lo dice con el resultado que ya existe | mensaje, no "guardada" |
| Guardar zancada tras recuperarse | la lectura vuelve a funcionar | se persiste, y la ventana anterior del disco **no se pierde** | — |
| Fallo de escritura | la lectura fue buena, la escritura falla | como hoy: en memoria sí, en disco no, y la pantalla lo dice | — |

</frozen-after-approval>

## Code Map

- `WalkTracker/Application/SettingsStore.swift:55-59` `init` → `load()`; `:64-76` `load()` — **aquí
  está la causa**: los tres `catch`/`guard` acaban en el mismo estado y ninguno deja rastro en el
  objeto. `:84-87` `recordShownQuote(id:)` → `save()`. `:91-…` `save()`, que desde la 2.3 devuelve
  `Bool` y no propaga el error.
- `WalkTracker/Adapters/Persistence/SettingsFileAdapter.swift:28-32` — la promesa que hoy es falsa.
  `:62-83` distingue esquema **mayor** (devuelve por omisión y **deja el fichero**) de esquema
  anterior desconocido (sí aparta). **No tocar esta política**: es correcta.
- `WalkTracker/Application/SettingsStore+Stride.swift` — ya tiene el resultado observable de "no se
  persistió" y su texto en la pantalla. Reutilizarlo, no inventar otro.
- `WalkTracker/Application/SessionStore+Motivation.swift:65` — el llamador que dispara la escritura
  en la primera caminata, vía `openSession()` (`SessionStore+StartFlow.swift:109`).
- **La costura que falta** (hallazgo V1 de la retro): `WalkTrackerTests/Support/StorageStub.swift:22`
  guarda `AppSettings?`, **no bytes**, así que un "fichero del futuro" no se puede expresar en los
  tests del store; y los tests del adapter no montan un `SettingsStore`. Para cubrir la matriz hace
  falta al menos un test de ciclo de vida completo con `FileStorageAdapter` y un directorio real:
  escribir el fichero → construir el store → **hacer algo que escriba** → releer los bytes crudos.
  `StorageStub` ya tiene `failLoadSettings(with:)` (`:168`) para la variante transitoria.
- `WalkTrackerTests/Adapters/SettingsFileAdapterTests.swift` — contiene **dos** `@Suite`:
  `SettingsFileAdapterTests` (:10) y `SettingsStoreTests` (:355). **Ojo**: `verify-domain.sh`
  selecciona por suite y `SettingsStoreTests` **no está en su lista** (hallazgo D10). Si los tests
  nuevos van ahí, comprobar si deben entrar en el gate y, si entran, añadirlos a mano.
- `WalkTrackerTests/Adapters/SettingsFileAdapterTests.swift:390` `unreadableKeepsTheFile` — afirma lo
  correcto pero **solo mide el instante posterior a construir el store**, antes de que nadie escriba.
  Es el test que dio falsa confianza.

## Tasks & Acceptance

**Execution:**
- [x] `WalkTracker/Application/SettingsStore.swift` — que `load()` deje constancia de cuál de los tres
      casos ocurrió, y que `save()` no escriba sin una lectura buena, reintentando antes de bloquear y
      aplicando el cambio sobre lo leído si el reintento funciona.
- [x] `WalkTracker/Application/SettingsStore+Stride.swift` — que guardar la zancada con la lectura
      fallida acabe en el resultado de "no persistido" que ya existe.
- [x] `WalkTrackerTests/` — la matriz entera, **incluido al menos un test de ciclo de vida completo**
      con `FileStorageAdapter` y un directorio real, que era el hueco que dejó pasar el defecto.
- [x] `WalkTrackerTests/Adapters/SettingsFileAdapterTests.swift:390` — ampliar `unreadableKeepsTheFile`
      para que siga la vida del proceso más allá de la construcción del store.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` — registrar lo que no se cierre aquí.

**Acceptance Criteria:**
- Dado un `settings.json` con zancada y ventana, cuando la lectura falla al arrancar y después se
  completa una caminata, entonces el fichero **sigue conteniendo la zancada y la ventana anteriores**.
- Dado un `settings.json` de un esquema mayor, cuando se completa una caminata, entonces sus **bytes
  no han cambiado**.
- Dada una instalación nueva sin fichero, cuando se completa una caminata, entonces el fichero **se
  crea** con la ventana.
- Dada la lectura recuperada tras un fallo transitorio, cuando se guarda una zancada, entonces se
  persiste **sin perder la ventana que había en disco**.

## Implementation Notes

**El vocabulario que faltaba: `SettingsStore.ReadOutcome`** (`loaded` / `absent` / `unreadable(StorageError)`),
escrito solo por `load()`. `absent` y `loaded` dejan escribir; `unreadable` no. `save()` pasó a ser
`save(applying: (inout AppSettings) -> Void)`: el cambio se entrega como una **función**, no como una
mutación hecha antes de llamar, porque si el reintento recupera la lectura hay que aplicarlo sobre lo
que acaba de venir del disco y no sobre los valores por omisión que el store arrastraba. Con la
escritura bloqueada el cambio **sí** se aplica en memoria —la caminata sigue, la ventana de esta
ejecución no repite— y se devuelve `false`, que es lo que `SettingsStore+Stride.swift` traduce al
`notPersisted` que la 2.3 ya pintaba. El nombre `save` se conserva a propósito: la sección 6 del gate
lo lleva en su lista de pasos internos y renombrarlo lo habría desarmado.

**El único cambio fuera del store, y por qué hizo falta.** `SettingsFileAdapter.loadSettings()`
devolvía `AppSettings.defaults` ante un esquema **mayor**, así que el dueño del fichero no podía
distinguir "aquí no había nada" de "aquí hay algo que no entiendo": la fila "esquema del futuro" de la
matriz era inexpresable desde el store. Ahora propaga `unsupportedSchemaVersion(version)`. **La
política del adapter no se ha tocado**: el fichero se sigue dejando exactamente donde está, y el
esquema **anterior** desconocido se sigue apartando — lo que cambia es que ahora se dice. Es además lo
que el propio diseño de esta spec asume ("un esquema del futuro seguirá fallando el reintento por
definición"): sin lanzar, el reintento tendría éxito y escribiría encima. `Domain/Ports/StoragePort.swift`
solo cambia comentarios (el de `unsupportedSchemaVersion` y el de `loadSettings`, que ahora dicen que
`nil` y un error no son lo mismo).

**Un ilegible (`malformed`) no bloquea para siempre, y es correcto:** el adapter ya lo apartó, así que
`settings.json` ya no existe y el reintento lo lee como "no hay fichero" — el caso de la primera
instalación. Lo apartado sigue a salvo con su nombre `settings.corrupt.<marca>.json`. `StorageStub`
se alineó con eso (tras apartar, deja de fallar) y con que un esquema del **futuro** no se aparta.

**Lo que se pierde al recuperarse, dicho en voz alta:** si la lectura falla al arrancar, se camina un
rato —la ventana avanza solo en memoria— y **después** se recupera, el reintento trae el disco y los
ids acumulados en memoria se descartan; el cambio en curso sí se aplica encima. Es lo que la Intent
congelada pide literalmente ("el cambio se aplica sobre lo que había en disco"): entre perder unos ids
de frase de esta ejecución y perder la zancada recalibrada y la ventana entera, gana el disco.

**La costura que faltaba (V1)** vive ahora en `WalkTrackerTests/Application/SettingsStorePersistenceTests.swift`:
`FileStorageAdapter` + directorio temporal + `SettingsStore` **y un `SessionStore` de verdad**, para
que la escritura la dispare `openSession()` como en producción. El fallo de lectura se monta quitándole
al fichero el permiso de lectura (`chmod 000`) y no corrompiéndolo: los bytes siguen enteros y el
directorio sigue siendo escribible, o sea que la escritura destructiva **es posible** y lo único que la
evita es el store. Las afirmaciones son sobre **bytes crudos** (`Data(contentsOf:) == bytes`).

## Spec Change Log

## Review Triage Log

## Design Notes

**Por qué el arreglo va en el store y no en el adapter.** El adapter ya distingue bien: aparta lo que
no tiene futuro y deja intacto lo que otra versión podrá leer. Quien pierde la información es el
store, que traduce tres situaciones a un único `AppSettings.defaults`. Mover la política al adapter
sería arreglarlo en el sitio equivocado.

**Por qué reintentar y no bloquear para siempre.** Un fallo de lectura al arrancar es casi siempre
transitorio. Bloquear la escritura de por vida convertiría un problema de un segundo en una sesión
entera sin guardar nada. Reintentar antes de la primera escritura bloqueada recupera el caso común y
deja protegido el caso real —un esquema del futuro—, que seguirá fallando el reintento por definición.

**Lo que este chore no arregla y por qué importa decirlo:** los otros dos defectos confirmados de la
retro —el mensaje de error que incumple AA (B-2) y la zancada que desborda y estrella la app (B-3)—
siguen en pie, con su action item cada uno.

## Verification

**Commands:**
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` — TEST SUCCEEDED, sin
  warnings propios.
- `bash Scripts/verify-domain.sh` — verde.
- `bash Scripts/check-project-shape.sh` y `check-project-shape-tests.sh` — verdes.
- **Mutación obligatoria:** con el arreglo revertido, el test del fallo transitorio **debe fallar**.
  Es el caso que la retro demostró y el que este chore existe para cerrar.
- **Y comprobar que el test nuevo se ejecuta de verdad**: contar los casos del `.xcresult`, no
  conformarse con `TEST SUCCEEDED` — el fichero tiene dos suites y esa trampa ya se pisó una vez.

**Manual checks:** ninguno. El defecto es de persistencia y se reproduce entero en test.

**Ejecutado (2026-09-20):**
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` → **TEST SUCCEEDED**,
  622 tests en 50 suites (609 antes), sin warnings nuevos. Los tres warnings de
  `SettingsViewTests.swift` (aislamiento de `@MainActor`) son previos y de un fichero no tocado.
- `bash Scripts/verify-domain.sh` → **verde** (227 tests en 15 suites). Los suites nuevos son de
  `Application/` y `Adapters/`, así que **no entran** en su lista: el criterio de "solo `Domain/` y
  `Vectors/`" está fijado desde la 1.1 y la 2.3 lo volvió a aplicar. Registrado en `deferred-work.md`.
- `bash Scripts/check-project-shape.sh` → verde. `bash Scripts/check-project-shape-tests.sh` → 161/161.
- **Los tests nuevos se ejecutan de verdad**, contado sobre el `.xcresult` por nombre y no por
  `TEST SUCCEEDED`: `SettingsStore · el ciclo completo sobre settings.json` **10 casos**, y
  `SettingsStore · dueño de settings.json` pasa de 5 a **9**. Los 19 aparecen como `Passed`.

**Mutación (obligatoria), las dos mitades:**
- `save(applying:)` escribiendo siempre (`let writable = true`) → **9 tests fallan**, entre ellos el
  caso que la retro transcribió, con la misma salida: `(onDisk.strideM → nil) == 0.72` y
  `(onDisk.recentQuoteIds → [1]) == [1, 2, 3]`.
- El adapter devolviendo `.defaults` ante un esquema mayor (como antes) → **3 tests fallan**: los dos
  del fichero del futuro y el del adapter.
- Árbol restaurado y suite completa en verde después de las dos.
