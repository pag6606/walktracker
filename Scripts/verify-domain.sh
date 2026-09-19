#!/bin/bash
#
# Verificación del dominio (AD-6). Su verde es Definition of Done de TODA historia
# que toque `Domain/`: no hay CI, así que este script es el mecanismo, no una
# recomendación.
#
# Tres pasos, y cualquiera en rojo deja el script en rojo:
#
#   1. Inventario — cada sitio de aserción de test/{domain,session-v3,motivation,
#      gapestimator}-tests.js aparece exactamente una vez en
#      WalkTrackerTests/Vectors/inventory.json, con su categoría. Después, el camino
#      rojo del arnés JS (Scripts/vectors/red-path-tests.sh).
#   2. Runner JS — domain.js/motivation.js contra los vectores. Solo pueden fallar
#      los vectores marcados con una de las dos divergencias declaradas
#      (localTime · wmoCategory); un divergente que pase también rompe.
#   3. Swift — xcodebuild test de los vectores, el arnés, el catálogo de logros,
#      las constantes de fórmula, los escenarios portados a mano del Epic 1, el
#      clima del inicio (`WeatherSnapshotTests`, 2.1) y la motivación
#      (`MotivationEngineTests` y `QuoteBankTests`, 2.2).
#      La lista de `-only-testing:` es EXPLÍCITA: un suite nuevo que no se añada a
#      mano no se ejecuta aquí y nadie se entera.
#      Las funciones aún no portadas se listan como pendientes; las portadas que
#      fallan rompen.
#
# Uso:  bash Scripts/verify-domain.sh
# Destino del simulador: VERIFY_DESTINATION (por defecto iPhone 16e).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${VERIFY_DESTINATION:-platform=iOS Simulator,name=iPhone 16e}"
LOG="$(mktemp "${TMPDIR:-/tmp}/verify-domain-xcodebuild.XXXXXX")"

failed=()

section() { printf '\n── %s ─────────────────────────────────────────\n' "$1"; }

# ── 1. Inventario ────────────────────────────────────────────────────────────
section "1/3 · Inventario de AD-6"
if ! node "$ROOT/Scripts/vectors/check-inventory.js"; then
    failed+=("inventario")
fi

# El camino rojo del propio arnés JS: si el runner o el inventario dejaran de
# detectar lo que dicen detectar, su verde no demostraría nada.
echo
if ! bash "$ROOT/Scripts/vectors/red-path-tests.sh"; then
    failed+=("camino rojo del arnés JS")
fi

# ── 2. Runner JS ─────────────────────────────────────────────────────────────
section "2/3 · Vectores contra domain.js"
if ! node "$ROOT/Scripts/vectors/run-js.js"; then
    failed+=("runner JS")
fi

# ── 3. Swift ─────────────────────────────────────────────────────────────────
section "3/3 · Vectores, catálogo y escenarios en Swift"
# El proyecto no se versiona y XcodeGen fija la lista de ficheros: un vector nuevo
# sin regenerar no entraría en el bundle de tests y no se ejecutaría EN SILENCIO.
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen no está instalado (brew install xcodegen)." >&2
    failed+=("Swift (sin xcodegen)")
elif ! (cd "$ROOT" && xcodegen generate --quiet); then
    failed+=("xcodegen generate")
else
    (cd "$ROOT" && xcodebuild test \
        -project WalkTracker.xcodeproj \
        -scheme WalkTracker \
        -destination "$DESTINATION" \
        CODE_SIGNING_ALLOWED=NO \
        -only-testing:WalkTrackerTests/DomainVectorTests \
        -only-testing:WalkTrackerTests/VectorHarnessTests \
        -only-testing:WalkTrackerTests/AchievementCatalogTests \
        -only-testing:WalkTrackerTests/FormulasTests \
        -only-testing:WalkTrackerTests/ChronometerTests \
        -only-testing:WalkTrackerTests/SessionStartScenarios \
        -only-testing:WalkTrackerTests/StepCountingScenarios \
        -only-testing:WalkTrackerTests/MetricsScenarios \
        -only-testing:WalkTrackerTests/SessionLifecycleScenarios \
        -only-testing:WalkTrackerTests/GapReconstructionScenarios \
        -only-testing:WalkTrackerTests/SessionRecoveryScenarios \
        -only-testing:WalkTrackerTests/WeatherSnapshotTests \
        -only-testing:WalkTrackerTests/MotivationEngineTests \
        -only-testing:WalkTrackerTests/QuoteBankTests \
        -only-testing:WalkTrackerTests/AppSettingsTests) >"$LOG" 2>&1
    status=$?

    grep -E '^[[:space:]]*(✘|✔ Suite)|AD-6 · Swift|error:|Test run with' "$LOG" | sed 's/^/  /'
    if [ "$status" -ne 0 ] || ! grep -q '\*\* TEST SUCCEEDED \*\*' "$LOG"; then
        echo "xcodebuild test salió con $status. Log completo: $LOG" >&2
        failed+=("Swift")
    elif ! grep -q 'AD-6 · Swift pendientes:' "$LOG"; then
        # Si el test de vectores no llegó a correr, un verde no demuestra nada.
        echo "El log no trae el resumen de DomainVectorTests: el test no se ejecutó. Log: $LOG" >&2
        failed+=("Swift (vectores no ejecutados)")
    fi
fi

# ── Veredicto ────────────────────────────────────────────────────────────────
section "Veredicto"
if [ "${#failed[@]}" -gt 0 ]; then
    echo "verify-domain: ROJO en: $(printf '%s · ' "${failed[@]}" | sed 's/ · $//')." >&2
    exit 1
fi
echo "verify-domain: verde."
exit 0
