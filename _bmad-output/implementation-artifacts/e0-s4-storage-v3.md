---
baseline_commit: NO_VCS
epic: E0
story_key: e0-s4-storage-v3
status: review
---

# E0-S4 — IndexedDBAdapter + StoragePort actualizado

**Epic:** E0 — Conteo automático de pasos
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S2

## Story

**Como** Paul, **quiero** que mis sesiones se guarden en IndexedDB para que el historial crezca sin problemas y no pierda datos por límites de localStorage.

## Acceptance Criteria

- [x] `StoragePort` abstrae IndexedDB (sesiones, logros) + localStorage (config, snapshot)
- [x] IndexedDB store `sessions`: CRUD completo (getSessions, saveSession, deleteSession)
- [x] IndexedDB store `achievements`: CRUD completo (getAchievements, saveAchievement)
- [x] localStorage `wt:config`: getConfig, saveConfig
- [x] localStorage `wt:activeSession`: getActiveSession, saveActiveSession
- [x] `navigator.storage.persist()` soportado (delega al adapter)
- [x] Migration flag `isMigrated()` / `setMigrated()` en adaptadores
- [x] ≥12 tests (MemoryAdapter), 0 fallos

## Tasks / Subtasks

- [x] **T1: Implementar módulo storage.js**
  - [x] T1.1: `createStoragePort()` factory con adaptadores inyectables
  - [x] T1.2: `LocalStorageConfigAdapter` — getConfig/saveConfig + migration flag
  - [x] T1.3: `LocalStorageActiveSessionAdapter` — get/save active session
  - [x] T1.4: `IndexedDBSessionAdapter` — CRUD sessions via IndexedDB
  - [x] T1.5: `IndexedDBAchievementAdapter` — CRUD achievements via IndexedDB
  - [x] T1.6: `MemoryAdapter` — in-memory para tests en Node
  - [x] T1.7: `persist()` delega al adapter
- [x] **T2: Tests**
  - [x] T2.1: Config roundtrip (getConfig/saveConfig)
  - [x] T2.2: Session roundtrip (saveSession/getSessions)
  - [x] T2.3: Delete session específica
  - [x] T2.4: Empty sessions array
  - [x] T2.5: Achievement roundtrip
  - [x] T2.6: Active session roundtrip
  - [x] T2.7: 10 sesiones guardadas y recuperadas
  - [x] T2.8: Custom adapters injectados
  - [x] T2.9: MemoryAdapter standalone
  - [x] T2.10: Persist returns true
  - [x] T2.11: Config defaults
  - [x] T2.12: Session upsert (mismo id)
  - [x] T2.13: Migration flag

## Dev Notes

### Architecture Reference (AD-3)
- StoragePort con adaptadores inyectables
- IndexedDB para sessions/achievements (browser)
- localStorage para config/snapshot
- MemoryAdapter para tests en Node

### Arquitectura
```
createStoragePort({ useIndexedDB, sessionAdapter, achievementAdapter, configAdapter, activeSessionAdapter })
  → StoragePort { getConfig, saveConfig, getSessions, saveSession, deleteSession,
                   getAchievements, saveAchievement, getActiveSession, saveActiveSession,
                   persist, isMigrated, setMigrated }
```

## File List

- `storage.js` — NEW: StoragePort + 5 adapters (Memory, LocalStorage config/active, IndexedDB session/achievement)
- `test/storage-tests.js` — NEW: 37 tests

## Change Log

- 2026-07-07: Implementación E0-S4 completa. StoragePort con adaptadores inyectables. MemoryAdapter para tests. 37 tests, 0 fallos.

## Status

**Current:** review
**Last updated:** 2026-07-07
