---
title: '8.3 — Distribución TestFlight con versionado SemVer'
type: 'feature'
created: '2026-09-12'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '2b19ecd29cfa6ee4629503a5884817fc085ed5a3'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** la app solo llega al iPhone 14 por cable desde Xcode, y un build local caduca con su
perfil de desarrollo. La 8.4 —la caminata de 60 minutos— y todo lo que sigue necesitan la app
instalada de forma duradera, y no hay ninguna regla de versiones que diga qué build es cuál.

**Enfoque:** un script de release reproducible que, con el árbol en un estado verificable, archiva
en Release con el toolchain congelado, sube el build a App Store Connect para TestFlight y etiqueta
el commit con una versión SemVer coherente con la del binario.

## Boundaries & Constraints

**Always:**
- Bundle id `com.walktracker.app`, sin cambios (AD-1).
- Toolchain del Stack del spine: Xcode 26.3 / Swift 6.2.4 / SDK iOS 26.2. El script **se niega** a
  archivar con otra versión mayor de Xcode (AD-2, SPEC OQ-5).
- `project.yml` es la única fuente de la versión (`MARKETING_VERSION`); el número de build sale del
  script, nunca se edita a mano, y crece de forma monótona.
- Antes de archivar: rama `main`, árbol limpio, `Scripts/verify-domain.sh` y
  `Scripts/check-project-shape.sh` en verde. Sin alguna, no hay build.
- La etiqueta git coincide con la versión y el build del binario subido.
- Declarar el cumplimiento de exportación (`ITSAppUsesNonExemptEncryption = NO`: solo HTTPS del
  sistema) y un manifiesto de privacidad sin rastreo.

**Never:**
- App Store: fuera de scope. Nada de metadatos de ficha, capturas ni envío a revisión.
- Ninguna subida sin confirmación explícita de Paul en el momento de subir: un número de build
  subido no se puede reutilizar.
- Credenciales en el repositorio (claves de API, contraseñas, perfiles).
- Dependencias de terceros para la subida (fastlane u otras): `xcodebuild` basta.

**Decisiones de Paul (2026-09-13):**
- **Registro en App Store Connect:** lo crea Paul a mano (iOS, español, bundle id
  `com.walktracker.app`) antes de la primera subida y comunica el nombre que quedó. No hay clave de API.
- **Subida:** el script sube con la cuenta de Apple ya configurada en Xcode (`xcodebuild
  -exportArchive`, destino `upload`). La ejecuta Claude con confirmación de Paul en ese momento, o Paul.
- **Versión:** `MARKETING_VERSION` se queda en `4.0.0` durante todo el MVP; cada subida etiqueta
  `v4.0.0-build.N`, y `v4.0.0` se reserva para el MVP completo. Después: PATCH arreglos, MINOR
  funcionalidad, MAJOR cambios que rompan datos.
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Release correcta | `main` limpio, gates en verde, Xcode 26.x | archiva, sube, etiqueta; imprime versión, build y etiqueta | — |
| Árbol sucio o fuera de `main` | cambios sin commit o rama de feature | no archiva; dice qué falta | sale ≠ 0 |
| Gate rojo | `verify-domain.sh` o `check-project-shape.sh` falla | no archiva | sale ≠ 0 |
| Toolchain equivocado | `xcodebuild -version` no es 26.x | no archiva; nombra la versión encontrada | sale ≠ 0 |
| Etiqueta ya existe | la versión+build ya tiene etiqueta | no archiva | sale ≠ 0 |
| Modo ensayo | `--dry-run`, en cualquier rama con árbol limpio | archiva y exporta un `.ipa` local sin subir ni etiquetar | — |
| Subida rechazada | App Store Connect rechaza el build | no etiqueta; muestra el error de `xcodebuild` | sale ≠ 0 |

</frozen-after-approval>

## Code Map

- `project.yml` — `MARKETING_VERSION: "4.0.0"`, `CURRENT_PROJECT_VERSION: "1"`, `DEVELOPMENT_TEAM:
  Z3M45B4K6D`, `CODE_SIGN_STYLE: Automatic`; esquema `WalkTracker` con `archive: Release`. Los targets
  `WalkTracker` y `WalkTrackerActivity` ejecutan `check-project-shape.sh` como build phase.
- `WalkTracker/App/Info.plist` — ya tiene `UILaunchScreen`, orientación, usage strings y
  `NSSupportsLiveActivities`; falta `ITSAppUsesNonExemptEncryption`.
- `WalkTracker/App/WalkTracker.entitlements` — HealthKit. `WalkTrackerActivity/Info.plist` — extensión
  WidgetKit, bundle `com.walktracker.app.WalkTrackerActivity` (necesita su propio App ID; la firma
  automática lo crea).
- No existe ningún `PrivacyInfo.xcprivacy` del producto (los del árbol son restos de Capacitor y
  Flutter en `build/` e `ios/DerivedData/`, ignorados).
- Etiquetas git: solo `v3.0.0` (PWA). Cuenta: equipo de pago individual `Z3M45B4K6D`, identidad Apple
  Development válida; la firma automática ya funcionó para el iPhone 14 en la 8.6.
- `Scripts/verify-domain.sh` y `Scripts/check-project-shape.sh` — gates previos.
- `README.md` — hoy no documenta ningún release.

## Tasks & Acceptance

**Execution:**
- [x] `WalkTracker/App/Info.plist` — `ITSAppUsesNonExemptEncryption` = `NO`.
- [x] `WalkTracker/Resources/PrivacyInfo.xcprivacy` — sin rastreo, sin dominios de rastreo, sin datos
      recogidos fuera del dispositivo; tipos de API con motivo solo si el código los usa.
- [x] `Scripts/ExportOptions-testflight.plist` — `method: app-store-connect`, `teamID`, firma
      automática, `destination: upload`; el `--dry-run` usa una copia con `export`.
- [x] `Scripts/release-testflight.sh` — comprobaciones de la matriz, número de build
      (`git rev-list --count HEAD`), `xcodegen generate`, `xcodebuild archive` Release, export/subida,
      etiqueta `v<MARKETING_VERSION>-build.<N>`, `--dry-run`.
- [x] `Scripts/release-testflight-tests.sh` — camino rojo sin tocar App Store Connect: árbol sucio,
      rama equivocada, Xcode con otra versión mayor, etiqueta existente.
- [x] `README.md` — política SemVer, cómo hacer un release, qué hace a mano Paul en App Store Connect
      y en TestFlight.
- [ ] Primera subida real desde `main`, tras fusionar esta historia y con el registro de App Store
      Connect creado por Paul; con su confirmación en el momento. Después, la etiqueta.

**Acceptance Criteria:**
- Given `main` limpio y gates en verde, when se ejecuta `release-testflight.sh --dry-run`, then produce
  un `.ipa` firmado para distribución con la versión de `project.yml` y el build calculado.
- Given la primera subida, when App Store Connect termina de procesarla, then el build aparece en
  TestFlight y Paul lo instala en el iPhone 14 desde la app TestFlight.
- Given el build subido, then existe una etiqueta git que nombra su versión y su build.

## Implementation Notes

- **`SKIP_INSTALL: YES` en `Domain` y `Shared` (`project.yml`), fuera del Code Map pero necesario.**
  Con `NO` (desde la 8.5) los frameworks se instalaban además en `Products/Library/Frameworks` del
  archivo; Xcode lo trataba como archivo genérico y la exportación fallaba con
  `expected one {} but found app-store-connect`. Con `YES` el archivo es de app iOS
  (`ApplicationProperties` presente), los frameworks siguen embebidos en `WalkTracker.app/Frameworks`
  y `verify-domain.sh` sigue en verde. El script lo comprueba en cada archivo y falla con un mensaje
  claro si vuelve a pasar.
- **Confirmación de subida:** interactiva (escribir la etiqueta) o `--confirm <etiqueta>` sin
  terminal. `--confirm` se valida antes de archivar y tiene que coincidir con la etiqueta calculada.
- **Monotonía:** además de «etiqueta ya existe», el script se niega si algún `v*-build.N` ya
  etiquetado tiene `N` ≥ el build calculado. La comprobación es contra las etiquetas **locales**.
- **Coherencia binario-etiqueta:** tras archivar se leen `CFBundleShortVersionString` y
  `CFBundleVersion` de la app y de la extensión; si no coinciden con versión y build, no se exporta.
- **La etiqueta no se empuja:** el script la crea anotada sobre el commit archivado e imprime el
  `git push origin <etiqueta>`.
- **Ensayo verificado hasta la exportación (2026-09-13):** en un worktree desechable con este diff
  en un commit sin rama: precondiciones, gates (`check-project-shape`, `verify-domain` en verde) y
  `xcodebuild archive` Release correctos — `WalkTracker 4.0.0 (32)`, app y extensión con la misma
  versión, `ITSAppUsesNonExemptEncryption = false` y `PrivacyInfo.xcprivacy` dentro del `.app`. La
  exportación falla con **«No Accounts»**: Xcode no tiene ninguna cuenta de Apple configurada
  (`DVTDeveloperAccountManagerAppleIDLists` vacío). Hace falta que Paul la añada (Xcode → Ajustes →
  Cuentas) antes de que el `--dry-run` produzca el `.ipa`; el script ya lo detecta y lo dice.

- **Ensayo real (2026-09-13), con la cuenta de Apple ya en Xcode:** `release-testflight.sh --dry-run`
  sobre `ce561d7` → precondiciones, `check-project-shape` y `verify-domain` en verde; archivo
  `WalkTracker 4.0.0 (32)`; `.ipa` firmado con **Apple Distribution (Z3M45B4K6D)**, perfil
  `iOS Team Store Provisioning Profile: com.walktracker.app`, sin dispositivos, `get-task-allow`
  falso, `beta-reports-active` verdadero, HealthKit presente; la extensión firmada igual y
  `PrivacyInfo.xcprivacy` dentro de la app.

- **Tras la revisión (11 correcciones, 1 diferida):** release real con `git fetch --tags` y
  `HEAD == origin/main`; HEAD y árbol revalidados tras gates, tras archivo y antes de subir; aviso y
  recuperación de subida a medias; progreso con `tee`; la suite de tests aborta si falla el montaje
  (antes podía tocar el repositorio real). Camino rojo 31/31. Segundo ensayo real sobre `5cff7b2`:
  `WalkTracker 4.0.0 (33)`, `.ipa` firmado con Apple Distribution.
- **Pendiente tras fusionar:** primera subida desde `main` con confirmación de Paul, etiqueta
  `v4.0.0-build.N`, e instalación desde TestFlight en el iPhone 14. Requiere el registro en App Store
  Connect. La historia queda en `review` hasta entonces.

- **Validación contra App Store Connect (2026-09-13).** Registro creado por Paul con el nombre
  `walktracker`. Validate App del Organizer sobre el archivo del ensayo rechazó el binario por falta de
  `NSHealthShareUsageDescription` (obligatoria con el entitlement de HealthKit aunque la app solo
  escriba); corregido en `fix/8-3-health-share-usage` y revalidado con éxito sobre `WalkTracker 4.0.0
  (36)`. El ensayo local no puede detectar esto: solo lo comprueba App Store Connect.

## Spec Change Log

## Review Triage Log

| # | Capa | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|---|
| B1 · B2 · E4 | blind · edge | No se comprueba `HEAD == origin/main` ni se traen las etiquetas remotas antes de las comprobaciones de etiqueta y monotonía | medium | Los PRs se fusionan en GitHub: un `main` local sin `pull` sube un commit que no es el fusionado, y las etiquetas de otro clon no se ven | patch |
| E6 | edge | HEAD o el árbol pueden cambiar durante el archivo (~10 min) o mientras espera la confirmación | medium | La comprobación de HEAD y árbol solo corre tras los gates; si Paul edita durante el archivo, lo subido difiere del commit etiquetado | patch |
| E1 · E2 | edge | El arnés de tests sigue si falla el montaje del fixture o `mktemp` | medium | `exit 1` dentro de `$(make_repo …)` deja `R=""`; `git -C "" tag/checkout/commit` actúa sobre el repositorio real (verificado leyendo `make_repo`) | patch |
| B5 · E3 | blind · edge | Una subida que falla después de que App Store Connect recibió el build no tiene salida: reintentar recalcula el mismo N | low | El mensaje "(o se intentó)" sugiere que los intentos fallidos se etiquetan y no es así; falta decir que hace falta un commit nuevo. Corrección de texto | patch |
| B4 | blind | El README promete que "si App Store Connect rechaza, no etiqueta", pero muchos rechazos llegan por correo tras procesar | low | La etiqueta ya existe cuando llega el correo. Corrección de texto | patch |
| B9 | blind | Los comentarios de `PrivacyInfo.xcprivacy` e `ITSAppUsesNonExemptEncryption` describen URLSession y Open-Meteo, que aún no existen | low | Presentan como hecho un supuesto que la historia del clima debe revalidar. Corrección de texto | patch |
| B10 | blind | La subida y el archivo no muestran progreso: minutos en silencio | low | Frecuente en cada release, y un Ctrl-C a mitad deja el build gastado sin etiqueta. `tee` es directo | patch |
| B12 | blind | El ensayo en rama de feature imprime una etiqueta con un N que no será el de `main` | low | Corrección de texto | patch |
| V1 | verif | La comprobación de versión y build del archivo no se prueba con solo la extensión distinta ni con el build distinto | gap | Filed: quitar la extensión del bucle o la comparación del build deja 19/19 | patch |
| V2 | verif | La confirmación interactiva nunca se ejecuta en los tests | gap | Filed: aceptar cualquier respuesta deja 19/19 | patch |
| V3 | verif | La comprobación de HEAD y árbol tras los gates no se prueba | gap | Filed: convertir los `die` en no-op deja 19/19 | patch |
| V4 | verif | Nada comprueba en el archivo que `PrivacyInfo.xcprivacy` y el indicador de cifrado lleguen a la app | gap | Filed con disposición defer: comprobado a mano en el archivo real y el manifiesto no declara aún APIs con motivo | defer |
| B3 · E5 | blind · edge | Un clon superficial da un número de build falso | low | Todos los clones de trabajo son completos; la guarda añade una rama | rechazado |
| B6 | blind | Nada vigila `SKIP_INSTALL: YES` antes de archivar | low | El script lo detecta tras el archivo con mensaje claro; regresión improbable | rechazado |
| B7 (resto) | blind | Faltan casos: `MARKETING_VERSION` ausente o duplicada, archivo fallido, sin `xcodegen`, `--confirm` con `--dry-run`, argumento desconocido, aserciones extra | low | Ramas triviales de mensaje; las que protegen la subida van en V1–V3 | rechazado |
| B8 | blind | `release-testflight-tests.sh` no corre automáticamente | low | Se ejecuta al tocar el script de release; los fakes no dependen del estado del repo | rechazado |
| B11 | blind | La regex SemVer acepta ceros a la izquierda | low | `MARKETING_VERSION` lo escribe Paul en `project.yml`; improbable | rechazado |
| E7 | edge | Ficheros ignorados por git bajo las carpetas de fuentes entrarían en el build | low | Solo hay `.DS_Store`/`xcuserdata` ignorados ahí; improbable | rechazado |
| E8 | edge | Repositorio sin commits deja `BUILD` vacío | false | El repositorio del producto tiene historia; el caso no es alcanzable en el uso previsto | rechazado |

## Verification

**Commands:**
- `bash Scripts/release-testflight-tests.sh` — esperado: todos los casos del camino rojo en verde.
- `bash Scripts/release-testflight.sh --dry-run` — esperado: `.ipa` exportado; sin subida ni etiqueta.
- `bash Scripts/verify-domain.sh` — esperado: verde (el release lo exige).

**Manual checks:**
- App Store Connect → TestFlight: el build aparece procesado. iPhone 14 → TestFlight → instalar; la
  app abre. La pantalla de diagnóstico de la 8.6 **no** está: es solo `DEBUG` y TestFlight es Release.
