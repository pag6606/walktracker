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
#   3. Swift — primero el camino rojo del inventario (`verify-domain-tests.sh`),
#      después el INVENTARIO DE SUITES y por último `xcodebuild test`.
#      El alcance es y sigue siendo el dominio: SOLO suites de
#      `WalkTrackerTests/{Domain,Vectors,Scenarios}` (AD-6). Los de `Application/`
#      —`SessionStoreTests`, `SettingsStoreStrideTests`, `SettingsStorePersistenceTests`—
#      y los de `UI/`, `App/` y `Adapters/` los ejecuta la suite completa. El
#      criterio está fijado desde la 1.1 (hallazgo B3, rechazado) y la 2.3 lo
#      volvió a aplicar quitando de aquí `SettingsStoreStrideTests`, que había
#      entrado siendo de `Application/`.
#      Dentro de ese alcance, la lista de `-only-testing:` YA NO SE RECUERDA A
#      MANO (B-6, 2026-09-20): se deriva del árbol y el gate falla nombrando el
#      `@Suite` que no esté en `DOMAIN_SUITES` — o el de `DOMAIN_SUITES` que ya no
#      esté en el árbol. Antes la lista era explícita y el script lo confesaba por
#      escrito: un suite nuevo que nadie añadiera no se ejecutaba y nadie se
#      enteraba. Ya mordió dos veces: `WorkoutRecordTests` llevaba sin ejecutarse
#      aquí desde que existe, y en la retro del Epic 2 un fichero con dos `@Suite`
#      corrió solo el primero y devolvió `TEST SUCCEEDED` sin ejecutar el test que
#      se estaba investigando (D10).
#      Las funciones aún no portadas se listan como pendientes; las portadas que
#      fallan rompen.
#
# Uso:  bash Scripts/verify-domain.sh
#       bash Scripts/verify-domain.sh --suites-only [raíz]   (solo el inventario)
# Destino del simulador: VERIFY_DESTINATION (por defecto iPhone 16e).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${VERIFY_DESTINATION:-platform=iOS Simulator,name=iPhone 16e}"
LOG="$(mktemp "${TMPDIR:-/tmp}/verify-domain-xcodebuild.XXXXXX")"

SUITES_ONLY=0
if [ "${1:-}" = "--suites-only" ]; then
    SUITES_ONLY=1
    ROOT="$(cd "${2:-$ROOT}" && pwd)"
fi

failed=()

section() { printf '\n── %s ─────────────────────────────────────────\n' "$1"; }

# ── Inventario de suites del gate de dominio (B-6) ───────────────────────────
# Los suites que este gate ejecuta. Es una lista escrita —el ALCANCE es una decisión
# (AD-6) y tiene que quedar a la vista— pero NO es de fiar por sí sola: `derive_suites`
# la contrasta contra el árbol y `check_suite_inventory` deja el gate en rojo nombrando
# cualquier diferencia, en los dos sentidos. Añadir un `@Suite` en el alcance sin tocar
# esta lista ya no sale en verde: sale en rojo diciendo cuál falta.
SUITE_DIRS=(Domain Vectors Scenarios)
DOMAIN_SUITES=(
    AchievementCatalogTests
    AppSettingsTests
    ChronometerTests
    DomainVectorTests
    FormulasTests
    GapReconstructionScenarios
    MetricsScenarios
    MotivationEngineTests
    QuoteBankTests
    SessionLifecycleScenarios
    SessionRecoveryScenarios
    SessionStartScenarios
    StepCountingScenarios
    VectorHarnessTests
    WeatherSnapshotTests
    WorkoutRecordTests
)

# `nombre<TAB>indentación<TAB>fichero:línea` de cada `@Suite` del alcance.
#
# Lo que esto SÍ ve: un `@Suite` con su tipo en la línea siguiente o en la misma, con
# atributos y modificadores por medio, en `struct`, `class`, `enum` o `actor`, y varios
# por fichero (que es justo lo que mordió en la retro del Epic 2).
# Lo que NO ve, y por eso lo declara en vez de callárselo: un `@Suite` ANIDADO dentro de
# otro tipo. `-only-testing:` lo nombraría por su ruta (`Externo/Interno`) y esta
# derivación trabaja línea a línea; `check_suite_inventory` lo convierte en un fallo
# explícito en vez de darlo por cubierto. Las líneas de comentario `//` se descartan.
derive_suites() {
    local d dir
    for d in "${SUITE_DIRS[@]}"; do
        dir="$ROOT/WalkTrackerTests/$d"
        if [ ! -d "$dir" ]; then
            echo "!MISSING	0	$dir"
            continue
        fi
        find "$dir" -name '*.swift' -type f -exec awk '
            FNR == 1 { pending = 0 }
            {
                line = $0
                sub(/[[:space:]]+$/, "", line)
                if (line ~ /^[[:space:]]*\/\//) next
                if (pending) {
                    if (match(line, /(struct|class|enum|actor)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                        decl = substr(line, RSTART, RLENGTH)
                        sub(/^.*[[:space:]]/, "", decl)
                        printf "%s\t%d\t%s:%d\n", decl, pind, FILENAME, pline
                        pending = 0
                    }
                    next
                }
                if (line !~ /@Suite/) next
                pind = match(line, /[^[:space:]]/) - 1
                pline = FNR
                rest = substr(line, index(line, "@Suite") + 6)
                if (match(rest, /(struct|class|enum|actor)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                    decl = substr(rest, RSTART, RLENGTH)
                    sub(/^.*[[:space:]]/, "", decl)
                    printf "%s\t%d\t%s:%d\n", decl, pind, FILENAME, pline
                } else {
                    pending = 1
                }
            }
        ' {} + || return 1
    done
}

check_suite_inventory() {
    local derived rc=0 name indent where listed
    if ! derived="$(derive_suites)"; then
        echo "verify-domain: no se pudo recorrer WalkTrackerTests/ para derivar los suites. Sin eso el gate no sabe qué debería ejecutar y no se declara en verde." >&2
        return 1
    fi

    while IFS=$'\t' read -r name indent where; do
        [ -n "$name" ] || continue
        if [ "$name" = "!MISSING" ]; then
            echo "verify-domain: no existe \`$where\`, que es uno de los directorios del alcance de este gate (AD-6). No se declara en verde por no haber mirado." >&2
            rc=1
            continue
        fi
        if [ "$indent" != "0" ]; then
            echo "verify-domain: \`$name\` ($where) es un \`@Suite\` ANIDADO. Este gate selecciona por nombre de tipo de primer nivel y no sabe construir su \`-only-testing:\`; sácalo a primer nivel o amplía el gate. No se ejecuta y no se da por cubierto." >&2
            rc=1
            continue
        fi
        listed=0
        for s in "${DOMAIN_SUITES[@]}"; do
            [ "$s" = "$name" ] && { listed=1; break; }
        done
        if [ "$listed" -eq 0 ]; then
            echo "verify-domain: el \`@Suite\` \`$name\` ($where) está en el alcance del gate de dominio y NO está en \`DOMAIN_SUITES\` de este script: no se ejecutaría aquí y nadie se enteraría. Añádelo, o sácalo del alcance." >&2
            rc=1
        fi
    done <<< "$derived"

    # Y al revés: un suite listado que ya no existe en el árbol. `-only-testing:` con un
    # nombre que no existe no falla por sí solo, así que la lista envejecería en silencio.
    for s in "${DOMAIN_SUITES[@]}"; do
        if ! awk -F'\t' -v n="$s" '$1 == n { found = 1 } END { exit !found }' <<< "$derived"; then
            echo "verify-domain: \`DOMAIN_SUITES\` lista \`$s\` y no hay ningún \`@Suite\` con ese nombre en WalkTrackerTests/$(IFS=,; echo "${SUITE_DIRS[*]}"). Un \`-only-testing:\` que no casa con nada no falla: quítalo o arregla el nombre." >&2
            rc=1
        fi
    done

    if [ "$rc" -eq 0 ]; then
        echo "Inventario de suites: ${#DOMAIN_SUITES[@]} suites de WalkTrackerTests/$(IFS=,; echo "${SUITE_DIRS[*]}"), derivados del árbol y cuadrando con la lista."
    fi
    return "$rc"
}

if [ "$SUITES_ONLY" -eq 1 ]; then
    check_suite_inventory
    exit $?
fi

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
# El camino rojo del propio inventario: si dejara de detectar un suite sin listar, su
# verde no demostraría nada. Es el mismo argumento que el del arnés JS del paso 1.
if ! bash "$ROOT/Scripts/verify-domain-tests.sh"; then
    failed+=("camino rojo del inventario de suites")
fi
echo

# Antes de arrancar el simulador: qué suites DEBERÍA ejecutar, según el árbol. Va
# primero a propósito, para que un suite sin listar se vea en segundos y no tras un
# `xcodebuild` entero.
if ! check_suite_inventory; then
    failed+=("inventario de suites")
fi

only_testing=()
for suite in "${DOMAIN_SUITES[@]}"; do
    only_testing+=("-only-testing:WalkTrackerTests/$suite")
done

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
        "${only_testing[@]}") >"$LOG" 2>&1
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
