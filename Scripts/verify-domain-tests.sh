#!/bin/bash
#
# Camino rojo del inventario de suites de `verify-domain.sh` (B-6). Un gate sin prueba
# de su camino rojo no es un gate: es un script que nadie ha visto fallar.
#
# El defecto que cierra: la lista de `-only-testing:` era explícita y se mantenía a mano,
# así que un `@Suite` nuevo —o uno más en un fichero ya listado— no se ejecutaba y el gate
# salía VERDE igual. Mordió dos veces: `WorkoutRecordTests` llevaba sin ejecutarse aquí
# desde que existe, y en la retro del Epic 2 un fichero con dos `@Suite` corrió solo el
# primero y devolvió `TEST SUCCEEDED` sin ejecutar el test que se estaba investigando (D10).
#
# Monta un árbol temporal —no toca el repositorio— con la misma forma que
# `WalkTrackerTests/`, aplica UNA mutación por caso y afirma el código de salida Y el
# mensaje. Se invoca `verify-domain.sh --suites-only <raíz>`, que hace SOLO el inventario:
# no arranca el simulador, así que el camino rojo se ejecuta en segundos.
#
# Uso:  bash Scripts/verify-domain-tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/verify-domain.sh"

pass=0
fail=0

report_pass() { echo "  ✅ $1"; pass=$((pass + 1)); }
report_fail() { echo "  ❌ $1"; fail=$((fail + 1)); }

# Afirma el código de salida y, si se pide, que la salida menciona un texto concreto
# (para no dar por buena una violación detectada por la razón equivocada).
assert_gate() {
    local name="$1" root="$2" want="$3" needle="${4:-}"
    local out status
    out="$(bash "$GATE" --suites-only "$root" 2>&1)"
    status=$?

    if [ "$status" -ne "$want" ]; then
        report_fail "$name — esperado exit $want, obtenido $status"
        echo "$out" | sed 's/^/      /'
        return
    fi
    if [ -n "$needle" ] && ! grep -q -- "$needle" <<< "$out"; then
        report_fail "$name — exit $want correcto, pero la salida no menciona '$needle'"
        echo "$out" | sed 's/^/      /'
        return
    fi
    report_pass "$name"
}

# Un fichero de suite con la forma real: atributo en una línea, tipo en la siguiente.
write_suite() {
    local file="$1" type_name="$2" title="$3"
    mkdir -p "$(dirname "$file")"
    cat > "$file" <<SWIFT
import Testing
@testable import Domain

@Suite("$title")
struct $type_name {
    @Test func placeholder() {}
}
SWIFT
}

# ── Fixture: el alcance del gate con un suite por cada nombre de `DOMAIN_SUITES` ─────
# La lista sale del propio gate, para que el arnés no mantenga una segunda copia a mano
# (que es exactamente el defecto que B-6 cierra).
listed_suites() {
    sed -nE '/^DOMAIN_SUITES=\(/,/^\)/p' "$GATE" | sed -E '1d;$d;s/^[[:space:]]+//;s/[[:space:]]+$//' | grep -v '^$'
}

make_fixture() {
    local root name dir
    root="$(mktemp -d)"
    mkdir -p "$root/WalkTrackerTests/Domain" "$root/WalkTrackerTests/Vectors" \
             "$root/WalkTrackerTests/Scenarios" "$root/WalkTrackerTests/Application" \
             "$root/WalkTrackerTests/UI"

    while IFS= read -r name; do
        case "$name" in
            *Scenarios)          dir=Scenarios ;;
            DomainVectorTests|VectorHarnessTests) dir=Vectors ;;
            *)                   dir=Domain ;;
        esac
        write_suite "$root/WalkTrackerTests/$dir/$name.swift" "$name" "$name"
    done < <(listed_suites)

    # Fuera del alcance: `Application/` y `UI/` los ejecuta la suite completa, no este gate.
    write_suite "$root/WalkTrackerTests/Application/SessionStoreTests.swift" \
        SessionStoreTests "SessionStore · iniciar y cronómetro"
    write_suite "$root/WalkTrackerTests/UI/DesignTokensTests.swift" \
        DesignTokensTests "Tokens de estilo"

    echo "$root"
}

echo "══════════════════════════════════════════════════════════"
echo "  Camino rojo del inventario de suites de verify-domain.sh"
echo "══════════════════════════════════════════════════════════"

# ── 0. Verde: el árbol y la lista cuadran ────────────────────────────────────
ROOT="$(make_fixture)"
assert_gate "árbol y lista cuadrando pasan" "$ROOT" 0 "derivados del árbol y cuadrando con la lista"
rm -rf "$ROOT"

# ── 1. Rojo: un `@Suite` nuevo en el alcance que nadie añadió a la lista ─────
for dir in Domain Vectors Scenarios; do
    ROOT="$(make_fixture)"
    write_suite "$ROOT/WalkTrackerTests/$dir/NuevoTests.swift" NuevoTests "Un suite que nadie listó"
    assert_gate "un \`@Suite\` nuevo en $dir/ sin listar falla nombrándolo" "$ROOT" 1 \
        "\`NuevoTests\`"
    rm -rf "$ROOT"
done

# ── 2. Rojo: un SEGUNDO `@Suite` en un fichero YA listado ───────────────────
# Es el caso exacto que mordió en la retro del Epic 2: `SettingsFileAdapterTests.swift`
# tenía dos suites, el gate seleccionaba por el primero y el segundo no corría.
ROOT="$(make_fixture)"
cat >> "$ROOT/WalkTrackerTests/Domain/FormulasTests.swift" <<'SWIFT'

@Suite("El segundo suite del mismo fichero")
struct SegundoTests {
    @Test func placeholder() {}
}
SWIFT
assert_gate "un segundo \`@Suite\` en un fichero ya listado falla nombrándolo" "$ROOT" 1 \
    "\`SegundoTests\`"
rm -rf "$ROOT"

# ── 3. Verde: un `@Suite` FUERA del alcance no entra ────────────────────────
# El alcance de este gate no cambia: es dominio y vectores (AD-6, hallazgo B3 de la 1.1).
# `Application/` y `UI/` los ejecuta la suite completa, y esta regla no debe arrastrarlos.
for dir in Application UI; do
    ROOT="$(make_fixture)"
    write_suite "$ROOT/WalkTrackerTests/$dir/OtroTests.swift" OtroTests "Fuera del alcance"
    assert_gate "un \`@Suite\` nuevo en $dir/ NO entra en el gate" "$ROOT" 0 \
        "derivados del árbol y cuadrando con la lista"
    rm -rf "$ROOT"
done

# ── 4. Rojo: un suite listado que ya no existe en el árbol ──────────────────
# `-only-testing:` con un nombre que no casa con nada NO falla por sí solo: la lista
# envejecería en silencio y el gate ejecutaría menos de lo que cree.
ROOT="$(make_fixture)"
rm -f "$ROOT/WalkTrackerTests/Domain/ChronometerTests.swift"
assert_gate "un suite listado que ya no está en el árbol falla nombrándolo" "$ROOT" 1 \
    "\`ChronometerTests\`"
rm -rf "$ROOT"

# Renombrar el tipo sin tocar la lista es el mismo caso, y es el que hace un IDE solo.
ROOT="$(make_fixture)"
write_suite "$ROOT/WalkTrackerTests/Domain/ChronometerTests.swift" CronometroTests "Cronómetro wall-clock"
assert_gate "renombrar el tipo de un suite listado falla por los dos lados" "$ROOT" 1 \
    "\`CronometroTests\`"
rm -rf "$ROOT"

# ── 5. Rojo: un `@Suite` anidado, que este gate no sabe expresar ────────────
# `-only-testing:` lo nombraría por su ruta (`Externo/Interno`) y la derivación trabaja
# línea a línea. Se declara como límite en rojo, no se da por cubierto en verde.
ROOT="$(make_fixture)"
cat > "$ROOT/WalkTrackerTests/Domain/AnidadoTests.swift" <<'SWIFT'
import Testing

@Suite("Externo")
struct ExternoTests {
    @Suite("Interno")
    struct InternoTests {
        @Test func placeholder() {}
    }
}
SWIFT
assert_gate "un \`@Suite\` anidado falla en vez de darse por cubierto" "$ROOT" 1 \
    "es un \`@Suite\` ANIDADO"
rm -rf "$ROOT"

# ── 6. Rojo: falta un directorio del alcance ────────────────────────────────
# No se declara verde lo que no se miró: la misma regla que la sección 12 de
# `check-project-shape.sh` y que la 12b desde B-5.
for dir in Domain Vectors Scenarios; do
    ROOT="$(make_fixture)"
    rm -rf "$ROOT/WalkTrackerTests/$dir"
    assert_gate "sin WalkTrackerTests/$dir/ el gate no da el verde" "$ROOT" 1 \
        "No se declara en verde por no haber mirado"
    rm -rf "$ROOT"
done

echo "══════════════════════════════════════════════════════════"
echo "  Total: $((pass + fail))  |  ✅ $pass passed  |  ❌ $fail failed"
echo "══════════════════════════════════════════════════════════"

[ "$fail" -eq 0 ]
