# Platform Matrix — de PWA v3 a iOS nativa

Companion de `SPEC.md`. Matriz de restricciones de la PWA (R1–R10 del SPEC v3) y su resolución en la app iOS. Es la evidencia del Why: cada fila es un límite estructural de la web en iOS que la app instalada elimina. **Stack decidido (OQ-1 reabierta, Paul 2026-09-12): SwiftUI nativo** — sin WebView y sin capa híbrida; cada framework de la columna "Framework nativo" se consume directamente desde un adapter detrás de su puerto (`ARCHITECTURE-SPINE.md` AD-10).

| # | Capacidad | PWA v3 (límite estructural) | iOS nativa (resolución) | Framework nativo | Capability |
|---|---|---|---|---|---|
| R1 | Conteo de pasos | Acelerómetro vía `DeviceMotionEvent`, solo foreground con pantalla activa; precisión ±5–10 % | Coprocesador de movimiento: pasos 24/7, foreground y background, precisión del sistema | CoreMotion (CMPedometer) | CAP-2 |
| R2 | Background | JS congelado; pasos del gap perdidos → extrapolación por cadencia marcada "~" | Reconstrucción exacta por query histórica al coprocesador; estimación solo como degradación | CoreMotion (query por rango) | CAP-3 |
| R3 | Clima | Open-Meteo por red (sin key, sin SLA, timeout 3 s) | **Open-Meteo permanece**, consumido por `WeatherAdapter` con `URLSession`; WeatherKit se difiere (cambio de adapter, aislado por AD-10). CC-BY 4.0: atribución obligatoria | URLSession + CoreLocation | CAP-5 |
| R4 | Apple Salud | Sin acceso; flujo manual CSV + Shortcuts | Escritura automática de workout al finalizar sesión | HealthKit (HKWorkout) | CAP-11 |
| R5 | Feedback | Solo sonido (Web Audio); `navigator.vibrate` inexistente en iOS Safari | Háptica + sonido | CoreHaptics + AVFoundation | CAP-12 |
| R6 | Storage | IndexedDB/localStorage **evictable** por iOS en PWA home-screen; `storage.persist()` no garantiza → export como respaldo obligatorio | Sandbox de app instalada: ficheros JSON `Codable` en Application Support con escritura atómica, no evictables; export pasa a respaldo voluntario | Foundation (FileManager, Codable) | CAP-9 |
| R7 | Glanceable en sesión | Sin equivalente; wake lock mantiene la pantalla como "live view" | **Live Activity en scope (decisión Paul):** métricas vivas en pantalla de bloqueo; Widget Extension + ActivityKit alimentado desde la app, sin App Group. En el iPhone 14 no hay Dynamic Island que validar | ActivityKit (Widget Extension) | CAP-18 |
| R8 | Distancia | Solo estimada: pasos × zancada → calibración manual obligatoria | Distancia estimada por el sistema disponible; zancada queda como fallback y calibración opcional | CoreMotion (distance) | CAP-4 |
| R9 | Timers | Congelados en background → cronómetro wall-clock como defensa | Ejecución garantizada; wall-clock se conserva como invariante de dominio | Foundation | CAP-1 |
| R10 | Recordatorios | Web Push (iOS 16.4+, PWA instalada) — Could, diferido | Notificaciones locales nativas (sin servidor push, coherente con no-backend) | UserNotifications | CAP-17 |

## Comparativa de cierre

| Dimensión | PWA v3 | iOS (SwiftUI nativo) |
|---|---|---|
| Pasos | Acelerómetro JS, pantalla activa, ±5–10 % | Coprocesador, 24/7, precisión del sistema (`CMPedometer` directo) |
| Música en paralelo | Tiempo exacto; pasos estimados "~" | Todo exacto (reconstrucción por query) |
| Clima | Open-Meteo (red, sin SLA) | Open-Meteo (adapter nativo; WeatherKit diferido) |
| Salud | Export manual + Shortcuts | Sync automático (`HKWorkoutBuilder`, verificado vigente) |
| Feedback | Sonido | Háptica + sonido |
| Storage | Evictable (export = respaldo) | Garantizado (sandbox de app instalada, JSON atómico) |
| Costo de entrada | $0, deploy inmediato (GitHub Pages) | Mac + Xcode + cuenta Apple Developer (A-1) |

## Lo que NO cambia de plataforma

- Offline-first: todo funciona sin red excepto el clima, que degrada limpio.
- Única llamada de red: clima (con coordenadas redondeadas a 2 decimales si sale por red — constraint Privacidad).
- Distribución del contenido motivacional: `quotes.json` como asset local en el bundle (sin red).
- Los invariantes de dominio de la v3, con las cuatro divergencias obligatorias declaradas en `ARCHITECTURE-SPINE.md` AD-6 (hora local, código WMO, pausas restadas una vez, rachas comparadas como fechas).
- UI: español, claro/oscuro, targets ≥ 44 pt, dirección "celebrar, nunca culpar".
