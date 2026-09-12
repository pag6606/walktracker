# Architecture Spine — WalkTracker iOS (Flutter)

## Meta

- **Name:** WalkTracker iOS (Flutter)
- **Type:** architecture-spine
- **Purpose:** build-substrate
- **Altitude:** feature
- **Paradigm:** hexagonal-lite + Riverpod + BLoC
- **Scope:** app Flutter iOS 16.1+ que reemplaza el stack Capacitor/Web; todo lo existente (Epics 1–7) se migra en una sola iteración
- **Status:** draft
- **Binds:** FR-1–FR-15, NFR-1–NFR-10, CAP-1–CAP-18

---

## 1. Why Flutter

| Old | New |
|---|---|---|
| Capacitor + WebView (web vanilla) | Flutter (Dart) |
| Vanilla JS, IIFE modules, global state object `state = {}` | Riverpod + BLoC, dependency injection explícito |
| HTML/CSS con media queries responsivos | Widgets natively adaptive, safe-area handled by Flutter |
| DOM con event listeners | Flutter tree reactivo |
| `domain.js` puro JS reimplementado como Dart puro | mismo dominio: `Domain` class con pure functions |
| `walktracker-kit` Swift plugin (CMPedometer + CoreHaptics) | mismo plugin Swift, registrado como platform channel |
| PWA como canal secundario (se descarta) | iOS-only, un solo canal |

**Why big-bang:** Paul es usuario único; no hay deuda de usuarios/equipo; un solo canal elimina el doble mantenimiento Capacitor/PWA.

---

## 2. Architecture Overview

```
lib/
  main.dart                    # entry point, ProviderScope
  app.dart                     # MaterialApp, theme, router

  domain/                      # PURE — zero dependencies outward
    domain.dart                # Domain class: Session, Chronometer, Metrics,
                               # CalibrationProfile, GoalEngine, AchievementEngine,
                               # MotivationEngine, GapEstimator (same logic as domain.js)
    feedback_port.dart         # FeedbackPort interface
    storage_port.dart          # StoragePort interface
    motion_port.dart           # MotionPort interface
    health_port.dart           # HealthKitPort interface
    clock_port.dart            # ClockPort interface

  application/                 # orchestrates use cases
    session_bloc.dart          # BLoC: start, pause, resume, finish session
    settings_bloc.dart         # BLoC: stride, weeklyGoal, soundEnabled
    achievements_bloc.dart     # BLoC: evaluate, unlock, persist
    history_bloc.dart          # BLoC: load sessions, export
    feedback_bloc.dart         # BLoC: fire haptic/audio events

  adapters/                    # IMPLEMENTS ports — iOS native only
    ios/
      motion_adapter.dart      # MethodChannel → CMPedometer (walktracker-kit)
      feedback_adapter.dart    # MethodChannel → CoreHaptics + AudioToolbox (walktracker-kit)
      health_adapter.dart      # MethodChannel → HealthKit (walktracker-kit)
      storage_adapter.dart     # Hive or Drift (SQLite) for sessions, achievements, config
      clock_adapter.dart       # SystemClockAdapter

  ui/                          # Flutter widgets
    screens/
      home_screen.dart         # goal ring, weather card, Iniciar button
      session_screen.dart      # live metrics, pause/resume, timer
      summary_screen.dart      # post-session stats, achievements toast
      history_screen.dart      # session list, weekly trend chart
      achievements_screen.dart # badges grid
      settings_screen.dart     # stride, weekly goal, sound toggle
    widgets/
      goal_ring.dart
      metric_tile.dart
      achievement_badge.dart
      toggle_tile.dart
      trend_chart.dart
    theme/
      app_theme.dart           # colors, typography, dark/light

ios/
  Runner/
    AppDelegate.swift          # registers walktracker-kit plugin
  walktracker-kit/             # SAME plugin as today (CMPedometer, CoreHaptics, HKWorkout, ActivityKit)
    ios/Sources/WalktrackerKitPlugin/WalktrackerKitPlugin.swift
    podspec
```

---

## 3. Invariants (herited + new)

### From Capacitor spine

| ID | Rule | Applies |
|---|---|---|
| AD-1 | Dependencias hacia el dominio; dominio no conoce frameworks | all |
| AD-4 | Session aggregate: stepsMeasured/stepsEstimated/strideM; inmutable al cerrar | domain |
| AD-5 | strideM congelada al cierre de sesión | domain |
| AD-6 | Cronómetro wall-clock; pausa explícita | domain |
| AD-7 | Validación en la frontera (input del usuario) | application layer |
| AD-8 | Autosave + recuperación silenciosa de sesión activa | application |
| AD-14 | Open-Meteo; timeout 3s; degradación limpia | adapters |

### New for Flutter

| ID | Rule |
|---|---|
| FL-1 | Platform channels solo cruzan el bridge en adapters; domain y BLoCs no importan `dart:io` ni `package:flutter/services` |
| FL-2 | Cada feature Epic 1–7 tiene su propio BLoC; no hay un mega-bloc |
| FL-3 | Riverpod para estado de UI (theme, navigation, derived display values); BLoC para lógica de negocio (sesión, logros, historial) |
| FL-4 | Plugin Swift `walktracker-kit` se mantiene intacto — mismo código, solo cambia cómo se invoca (MethodChannel en vez de Capacitor bridge) |

---

## 4. Platform Channel Contract

Plugin name: `com.walktracker.app / walktracker_kit`

### Methods

| Method | Params | Returns |
|---|---|---|
| `startStepTracking` | none | `{started: bool, startDate: String (ISO8601)}` |
| `stopStepTracking` | none | `{stopped: bool}` |
| `queryPedometerData` | `{startDate: String, endDate: String}` | `{steps: int, distanceM: int?, startDate: String, endDate: String}` |
| `requestPermission` | none | `{status: 'granted'/'denied'/'restricted'}` |
| `isAvailable` | none | `{stepCounting: bool, distance: bool, floorCounting: bool}` |
| `fireFeedback` | `{type: String}` | `{fired: String}` |
| `setSoundEnabled` | `{enabled: bool}` | `{soundEnabled: bool}` |
| `isSoundEnabled` | none | `{soundEnabled: bool}` |
| `writeWorkout` | `{startDate: String, endDate: String, steps: int, distanceM: double}` | `{written: bool}` |

### Events (EventChannel: `com.walktracker.app/pedometer_events`)

```dart
// Stream<Map<String, dynamic>>
{
  'steps': int,
  'distanceM': int?,
  'startDate': String,
  'endDate': String
}
```

---

## 5. Domain Model (from domain.js)

Se移植 faithfully a Dart. Tests también se portan.

```dart
// lib/domain/domain.dart

class Domain {
  // V3 Session
  static Session createV3Session(int nowMs, double strideM);
  static Session addSteps(Session s, int stepsAdded);
  static Session addEstimatedSteps(Session s, int estimated);
  static Session pause(Session s, int nowMs);
  static Session resume(Session s, int nowMs);
  static Session finishV3(Session s, int nowMs);
  static Session restoreV3Session(Map snapshot);

  // Shared
  static double elapsedS(int startedAtMs, int totalPausesMs, int nowMs, int pausedAtMs);
  static double v3distance(Session s);
  static double pace(int durationS, int pausesS, int distanceMm);
  static double calculateCadence(int stepsMeasured, int activeSeconds);
  static int estimateSteps(double cadence, int gapSeconds);

  // Calibration
  static Map recalibrate({required double strideM, required int stepsPerLap});

  // Motivation
  static Quote selectQuote(List<Quote> pool, List<String> recentIds);
  static List<Achievement> evaluateAchievements(Session session, List<Session> allSessions, List<Achievement> achievements);

  // Goal
  static WeeklyProgress getWeeklyProgress(List<Session> sessions, double goalKm);
}

// Session state machine
enum SessionStatus { idle, active, paused, finished }

class Session {
  final SessionStatus status;
  final int startedAt;
  final int totalPausesMs;
  final int pausedAtMs;
  final int pausesS;
  final double strideM;
  final int stepsMeasured;
  final int stepsEstimated;
  final int distanceM; // override from CMPedometer
  final String? id;
}

// Feedback events
class FeedbackEvent {
  static const String sessionStart = 'session_start';
  static const String km = 'km';
  static const String goal = 'goal';
  static const String achievement = 'achievement';
}
```

---

## 6. BLoC Design

### SessionBloc

```
Events: StartSession, PauseSession, ResumeSession, FinishSession,
        StepsReceived(cumulative, distanceM?), RecoveryQueried

States: SessionIdle, SessionActive(Session, elapsed, distanceKm, cadence),
        SessionPaused(Session, elapsed), SessionFinished(SessionSummary)
```

### SettingsBloc

```
Events: LoadSettings, UpdateStride(double), UpdateWeeklyGoal(double),
        ToggleSound(bool)

States: SettingsLoaded(Config config)
```

### AchievementsBloc

```
Events: EvaluateAchievements(Session session, List<Session> all),
        UnlockAchievement(String key)

States: AchievementsLoaded(List<Achievement> all, List<Achievement> newlyUnlocked)
```

### FeedbackBloc

```
Events: FireFeedback(String eventType)

States: FeedbackIdle
(no state changes — side-effect only via adapter)
```

### HistoryBloc

```
Events: LoadSessions, DeleteSession(String id), ExportCsv

States: HistoryLoading, HistoryLoaded(List<Session> sessions, WeeklyStats stats)
```

---

## 7. Navigation

```
GoRouter or Navigator 2.0 (declarative)

/                 → HomeScreen
/session          → SessionScreen (can pop back)
/summary/:id      → SummaryScreen
/history          → HistoryScreen
/achievements     → AchievementsScreen
/settings         → SettingsScreen
```

---

## 8. Data Persistence

- **Hive** para todo (sessions, achievements, config)
- misma schema que storage.js (ISO-8601 timestamps, same shapes)
- migración versionada igual que migration.js

---

## 9. UI Conventions (from Capacitor spine)

| Concern | Rule |
|---|---|
| Touch targets | ≥ 44 pt |
| Theme | dark/light via `MediaQuery.platformBrightnessOf(context)` |
| Goal ring | `min(300, 80vw)` responsive |
| Safe area | `SafeArea` widget en cada screen |
| Colors | same CSS vars → Flutter `Color(0xFF...)` |
| Typography | same scale (hero 64px, sub 16px bold, etc.) |
| Language | Spanish only |
| Feedback | haptic + audio via native plugin |
| Animations | implicit animations (`AnimatedOpacity`, `TweenAnimationBuilder`) |

---

## 10. Epic Mapping to Flutter Structure

| Epic | Flutter Owner |
|---|---|
| E1 — Step counting + session | SessionBloc + MotionAdapter |
| E2 — Climate + quotes | ClimateAdapter (HTTP) + MotivationAdapter |
| E3 — Weekly goal + achievements | GoalBloc + AchievementsBloc + StorageAdapter |
| **E4 — Haptic + audio** | FeedbackBloc + FeedbackAdapter |
| E5 — History + persistence | HistoryBloc + StorageAdapter (Hive) |
| E6 — HealthKit write | HealthAdapter |
| E7 — Live Activity | ActivityKit via walktracker-kit |

---

## 11. Build & Distribution

```bash
flutter pub get
flutter build ios --release
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -exportOptionsPlist ios/ExportOptions.plist
```

- TestFlight como distribución duradero
- Device: iPhone 14 (iOS 17+)
- Minimum iOS: 16.1

---

## 12. Migration Checklist (big-bang)

- [ ] Crear proyecto Flutter: `flutter create --org com.walktracker --platforms ios walktracker`
- [ ] Port domain.dart (pure functions from domain.js)
- [ ] Port platform channel adapter (walktracker_kit channel)
- [ ] Implementar SessionBloc + SessionScreen
- [ ] Implementar SettingsBloc + SettingsScreen
- [ ] Implementar AchievementsBloc + AchievementsScreen
- [ ] Implementar HistoryBloc + HistoryScreen
- [ ] Implementar FeedbackBloc (wired to native)
- [ ] Implementar GoalRing + SummaryScreen
- [ ] Port climate/motivation adapters
- [ ] Live Activity (E7)
- [ ] HealthKit write (E6)
- [ ] Theme: dark/light, safe-area, responsive ring
- [ ] TestFlight build + deploy
