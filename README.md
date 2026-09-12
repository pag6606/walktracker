# WalkTracker

Registro de caminatas con conteo de pasos, clima, metas y motivación. iOS + PWA.

## Entornos

WalkTracker opera en cuatro entornos (dos canales: app nativa y PWA). **Nunca** commitear con `server.url` en producción (AD-C7, bundle local).

### Dev: App nativa en iPhone físico

```bash
# Conectar el iPhone vía USB y desbloquearlo
xcrun devicectl list devices        # confirmar conexión (Identifier/UDID)
pnpm build:web                      # regenera el bundle www/
npx cap sync ios                    # copia bundle + pod install
npx cap run ios --target=<UDID>     # build Xcode + deploy al iPhone
```

- El WebView carga desde el bundle local (`webDir: "www"`, capacitor.config.json)
- Wake lock nativo: plugin `@capacitor-community/keep-awake` 8.0.1 vía `CapacitorKeepAwakeAdapter` (`adapters/`)
- El simulador iOS **no tiene acelerómetro real** — la validación de pasos va al dispositivo físico (AR-11)

### Dev: PWA en navegador

```bash
python3 -m http.server             # o npx serve .
# Abrir http://localhost:8000
```

- Web Wake Lock API (`navigator.wakeLock`) vía `WakeLockPort` en `runtime.js`
- La PWA es el canal secundario; el dominio (`domain.js`) no conoce Capacitor (AD-C1)
- Verificar líneas de base: `pnpm test:legacy` → 383 tests

### Prod: App nativa (TestFlight)

```bash
xcodebuild archive -workspace ios/App/App.xcworkspace -scheme App -archivePath ios/build/App.xcarchive
# Subir a App Store Connect → distribuir vía TestFlight
```

- Bundle local (`webDir: "www"`), **sin `server.url`** en capacitor.config.json (AD-C7)
- `appId`: `com.walktracker.app` (inmutable post-TestFlight, AD-IOS-01)
- Plugins: KeepAwake (comunitario), LocalNotifications, Preferences, WalktrackerKit (local)

### Prod: PWA (GitHub Pages)

- Deploy directo del repo a Pages; la PWA sigue funcionando intacta como canal secundario (AD-C3)
- Service worker (`sw.js`) solo en PWA — no se registra en nativo (guard `isNative` en composition root)

## Arquitectura

- **Hexagonal (AD-1):** el dominio (`domain.js`, `runtime.js`, etc.) no importa Capacitor ni infraestructura
- **Una frontera nativa (AD-C2):** un solo plugin custom `walktracker-kit/` (CMPedometer, HKWorkout, ActivityKit) + plugins comunitarios (keep-awake, local-notifications)
- **WakeLockPort:** el código heredado v3 (`runtime.js`) usa `navigator.wakeLock`; el spine AR-10 lo llama `KeepAwakePort` — mismos conceptos, nombres divergentes por compatibilidad
- **iOS deployment target 16.1** (piso ActivityKit); Xcode 26.3; Capacitor 8.4.2; CocoaPods

## Tests

```bash
pnpm test:legacy     # 383 tests de dominio (línea base v3)
pnpm vitest test/adapters/  # tests de adapters (jsdom)
```
