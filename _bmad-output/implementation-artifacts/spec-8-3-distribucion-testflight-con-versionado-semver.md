---
title: '8.3 — Distribución TestFlight con versionado SemVer'
type: 'feature'
created: '2026-09-12'
status: 'in-progress'
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

## Spec Change Log

## Review Triage Log

## Verification

**Commands:**
- `bash Scripts/release-testflight-tests.sh` — esperado: todos los casos del camino rojo en verde.
- `bash Scripts/release-testflight.sh --dry-run` — esperado: `.ipa` exportado; sin subida ni etiqueta.
- `bash Scripts/verify-domain.sh` — esperado: verde (el release lo exige).

**Manual checks:**
- App Store Connect → TestFlight: el build aparece procesado. iPhone 14 → TestFlight → instalar; la
  app abre. La pantalla de diagnóstico de la 8.6 **no** está: es solo `DEBUG` y TestFlight es Release.
