#!/bin/bash
#
# Camino rojo de `check-project-shape.sh`. Un gate sin prueba de su camino rojo no
# es un gate: es un script que nadie ha visto fallar.
#
# Monta un árbol temporal —no toca el repositorio— y afirma que el gate FALLA en
# cada violación que dice detectar, y que PASA sobre un árbol limpio.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/check-project-shape.sh"

pass=0
fail=0

report_pass() { echo "  ✅ $1"; pass=$((pass + 1)); }
report_fail() { echo "  ❌ $1"; fail=$((fail + 1)); }

# Afirma que el gate sale con el código esperado y, si se pide, que su salida
# menciona un texto concreto (para no dar por buena una violación detectada por
# la razón equivocada).
assert_gate() {
    local name="$1" root="$2" want="$3" needle="${4:-}"
    local out status
    out="$("$GATE" "$root" 2>&1)"
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

# ── Fixture: el árbol mínimo con la misma forma que el real ──────────────────
make_fixture() {
    local root
    root="$(mktemp -d)"

    mkdir -p "$root/Domain/Ports" "$root/Shared" \
             "$root/WalkTracker/App" "$root/WalkTracker/UI" "$root/WalkTrackerActivity" "$root/WalkTrackerTests"

    echo 'import Foundation' > "$root/Domain/DomainError.swift"
    echo 'import Foundation' > "$root/Domain/Ports/ClockPort.swift"
    echo 'import Foundation' > "$root/Shared/ActivitySnapshot.swift"
    echo 'import SwiftUI'    > "$root/WalkTracker/App/WalkTrackerApp.swift"
    echo 'import WidgetKit'  > "$root/WalkTrackerActivity/Bundle.swift"
    echo 'import Testing'    > "$root/WalkTrackerTests/SmokeTests.swift"
    # Lo que la UI y la app sí hacen con el store: leer, comparar y llamar a intenciones.
    cat > "$root/WalkTracker/UI/SessionView.swift" <<'SWIFT'
import SwiftUI
struct SessionView: View {
    let store: SessionStore
    var body: some View {
        Button("Pausar") { store.pause() }
            .disabled(store.isReconciling == true || store.session?.status != .active)
            .task { await root.sessionStore.restoreOnLaunch() }
    }
}
SWIFT

    cat > "$root/project.yml" <<'YAML'
name: WalkTracker
targets:
  Domain:
    type: framework
    sources:
      - path: Domain
    settings:
      base:
        PRODUCT_NAME: Domain
  Shared:
    type: framework
    sources:
      - path: Shared
  WalkTracker:
    type: application
    sources:
      - path: WalkTracker
    dependencies:
      - target: Domain
  WalkTrackerActivity:
    type: app-extension
    sources:
      - path: WalkTrackerActivity
    dependencies:
      - target: Shared
  WalkTrackerTests:
    type: bundle.unit-test
    sources:
      - path: WalkTrackerTests
schemes:
  WalkTracker:
    build:
      targets:
        WalkTracker: all
YAML

    echo "$root"
}

echo "══════════════════════════════════════════════════════════"
echo "  Camino rojo de check-project-shape.sh"
echo "══════════════════════════════════════════════════════════"

# ── 0. Verde: árbol limpio ───────────────────────────────────────────────────
ROOT="$(make_fixture)"
assert_gate "árbol limpio pasa" "$ROOT" 0 "forma del proyecto correcta"
rm -rf "$ROOT"

# ── 1. Rojo: las sources: de la extensión alcanzan Domain/ ───────────────────
ROOT="$(make_fixture)"
# La extensión se lleva el dominio dentro de su target. No hay ningún import de
# por medio: el grafo de módulos no ve nada, y AD-15 queda sin efecto.
perl -0pi -e 's/(  WalkTrackerActivity:\n    type: app-extension\n    sources:\n      - path: WalkTrackerActivity\n)/$1      - path: Domain\n/' "$ROOT/project.yml"
grep -q '      - path: Domain' "$ROOT/project.yml" || { echo "  ⚠️  fixture no mutado"; exit 1; }
assert_gate "sources: de la extensión alcanzando Domain/ falla" "$ROOT" 1 "AD-15"
rm -rf "$ROOT"

# ── 1b. Rojo: la extensión toma la raíz, que arrastra Domain/ ────────────────
ROOT="$(make_fixture)"
perl -0pi -e 's/(  WalkTrackerActivity:\n    type: app-extension\n    sources:\n)      - path: WalkTrackerActivity\n/$1      - path: .\n/' "$ROOT/project.yml"
assert_gate "sources: de la extensión en la raíz falla" "$ROOT" 1 "AD-15"
rm -rf "$ROOT"

# ── 2. Rojo: un .swift que no está en ningún target ──────────────────────────
ROOT="$(make_fixture)"
mkdir -p "$ROOT/Huerfano"
echo 'import Foundation' > "$ROOT/Huerfano/Perdido.swift"
assert_gate "un .swift fuera de todo target falla" "$ROOT" 1 "no pertenece a ningún target"
rm -rf "$ROOT"

# ── 3. Rojo: Domain/ no existe ───────────────────────────────────────────────
ROOT="$(make_fixture)"
rm -rf "$ROOT/Domain"
assert_gate "Domain/ inexistente falla ruidosamente" "$ROOT" 1 "no existe"
rm -rf "$ROOT"

# ── 4. Rojo: import de plataforma en Domain/ ─────────────────────────────────
# El compilador no puede detectarlo: `import SwiftUI` dentro de un framework
# compila. La restricción congelada del spec exige que rompa el build.
ROOT="$(make_fixture)"
echo 'import SwiftUI' > "$ROOT/Domain/Ports/ClockPort.swift"
assert_gate "import SwiftUI en Domain/ falla" "$ROOT" 1 "AD-3"
rm -rf "$ROOT"

ROOT="$(make_fixture)"
echo 'import CoreMotion' > "$ROOT/Domain/DomainError.swift"
assert_gate "import CoreMotion en Domain/ falla" "$ROOT" 1 "AD-3"
rm -rf "$ROOT"

# ── 4b. Rojo: la extensión importa Domain ────────────────────────────────────
# El grafo de targets NO basta: la app embebe `Domain.framework`, así que el módulo
# es resoluble desde `BUILT_PRODUCTS_DIR` y `import Domain` en la extensión compila
# en verde. Verificado contra el build real antes de escribir esta comprobación.
ROOT="$(make_fixture)"
echo 'import Domain' > "$ROOT/WalkTrackerActivity/Bundle.swift"
assert_gate "import Domain en la extensión falla" "$ROOT" 1 "AD-15"
rm -rf "$ROOT"

# ── 4c. Rojo: la UI o la app escriben el estado del store (AD-7, AD-16) ─────
# Las propiedades y los pasos internos de `SessionStore` tienen acceso de módulo desde el
# A-1: el compilador no lo impide.
ROOT="$(make_fixture)"
echo '        Button("x") { store.session = nil }' >> "$ROOT/WalkTracker/UI/SessionView.swift"
assert_gate "asignar una propiedad del store en UI/ falla" "$ROOT" 1 "AD-7/AD-16"
rm -rf "$ROOT"

ROOT="$(make_fixture)"
echo '        root.sessionStore.isReconciling = false' >> "$ROOT/WalkTracker/App/WalkTrackerApp.swift"
assert_gate "asignar una propiedad del store en App/ falla" "$ROOT" 1 "AD-7/AD-16"
rm -rf "$ROOT"

for call in 'store.persist()' 'store.record(sample)' 'await store.reconcile(until: now)' 'store.countSteps(from: now)' \
            'store.stopCountingSteps()' 'store.clearSnapshot()' 'store.capLastSampleAt(at: now)' \
            'try store.storage.clearActiveSession()' 'store.motion.status' 'store.clock.now'; do
    ROOT="$(make_fixture)"
    echo "        $call" >> "$ROOT/WalkTracker/UI/SessionView.swift"
    assert_gate "\`$call\` en UI/ falla" "$ROOT" 1 "AD-7/AD-16"
    rm -rf "$ROOT"
done

# ── 5. Rojo: manifiesto ausente ──────────────────────────────────────────────
ROOT="$(make_fixture)"
rm -f "$ROOT/project.yml"
assert_gate "project.yml ausente falla" "$ROOT" 1 "no existe project.yml"
rm -rf "$ROOT"

echo "══════════════════════════════════════════════════════════"
echo "  Total: $((pass + fail))  |  ✅ $pass passed  |  ❌ $fail failed"
echo "══════════════════════════════════════════════════════════"

[ "$fail" -eq 0 ]
