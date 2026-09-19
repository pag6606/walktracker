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

    mkdir -p "$root/Domain/Ports" "$root/Domain/Session" "$root/Shared" \
             "$root/WalkTracker/App" "$root/WalkTracker/UI" "$root/WalkTracker/UI/Style" \
             "$root/WalkTracker/UI/Diagnostics" "$root/WalkTracker/Application" \
             "$root/WalkTracker/Adapters/Motion" "$root/WalkTracker/Adapters/Persistence" \
             "$root/WalkTracker/Adapters/Clock" "$root/WalkTracker/Adapters/Location" \
             "$root/WalkTracker/Adapters/Weather" \
             "$root/WalkTrackerActivity" "$root/WalkTrackerTests/Adapters"

    echo 'import Foundation' > "$root/Domain/DomainError.swift"
    echo 'import Foundation' > "$root/Shared/ActivitySnapshot.swift"

    # Usos legítimos de las secciones 7–10: si una regla lo marcara todo, el árbol
    # limpio dejaría de pasar.
    # 8 · El dominio NOMBRA el reloj en comentarios, y usa `Date` sin leer el reloj.
    cat > "$root/Domain/Ports/ClockPort.swift" <<'SWIFT'
import Foundation

/// El dominio nunca llama a `Date()`, `Date.now` ni a `Calendar.current` (AD-3, AD-19).
public protocol ClockPort: Sendable {
    /// Instante actual, inyectado. Nunca `Date()` dentro del dominio.
    var now: Date { get }
}
SWIFT
    cat > "$root/Domain/Session/Session.swift" <<'SWIFT'
import Foundation

public struct Session {
    public let startedAt: Date  // nunca Date.now: llega como argumento
    /* Ni `Calendar.current`:
       ni Date() en una línea intermedia:
       el calendario también se inyecta. */
    /* a /* b */ Date() */
    public static let epoch = Date(timeIntervalSince1970: 0)
    public func elapsedS(at now: Date) -> TimeInterval { now.timeIntervalSince(startedAt) }
    public var nowDate: Date? { nil }
}
SWIFT
    # 9 · El puerto declara los métodos; el store los llama; el adapter los implementa.
    cat > "$root/Domain/Ports/StoragePort.swift" <<'SWIFT'
import Foundation

public protocol StoragePort: Sendable {
    func loadActiveSession() throws -> Data?
    func saveActiveSession(_ data: Data) throws
    func clearActiveSession() throws
    func setAsideActiveSession() throws
}
SWIFT
    cat > "$root/WalkTracker/Application/SessionStore+Recovery.swift" <<'SWIFT'
import Domain

extension SessionStore {
    func restoreOnLaunch() {
        guard let loaded = try? storage.loadActiveSession() else { return }
        try? storage.setAsideActiveSession()
        try? storage.saveActiveSession(loaded)
        try? storage.clearActiveSession()
    }
}
SWIFT
    cat > "$root/WalkTracker/Adapters/Persistence/ActiveSessionFileAdapter.swift" <<'SWIFT'
import Foundation
import Domain

final class ActiveSessionFileAdapter: StoragePort {
    func loadActiveSession() throws -> Data? { nil }
    func saveActiveSession(_ data: Data) throws {}
    func clearActiveSession() throws {}
    func setAsideActiveSession() throws { try clearActiveSession() }
}
SWIFT
    # Fuera de `Domain/`, el reloj del sistema es legítimo: es el adapter de `ClockPort`.
    cat > "$root/WalkTracker/Adapters/Clock/SystemClock.swift" <<'SWIFT'
import Foundation
import Domain

struct SystemClock: ClockPort {
    var now: Date { Date() }
}
SWIFT
    # 7 · CoreMotion en su adapter y en los tests de adapters (fuera del gate).
    printf 'import CoreMotion\nimport Domain\n' > "$root/WalkTracker/Adapters/Motion/MotionAdapter.swift"
    printf '@testable import WalkTracker\nimport CoreMotion\n' > "$root/WalkTrackerTests/Adapters/MotionAdapterTests.swift"
    # 7 · CoreLocation en su adapter y en los tests de adapters (fuera del gate).
    printf 'import CoreLocation\nimport Domain\n' > "$root/WalkTracker/Adapters/Location/LocationAdapter.swift"
    printf '@testable import WalkTracker\nimport CoreLocation\n' > "$root/WalkTrackerTests/Adapters/LocationAdapterTests.swift"
    # 11 · La red en el adapter del clima y en sus tests (fuera del gate); nombrada en comentarios fuera.
    cat > "$root/WalkTracker/Adapters/Weather/OpenMeteoAdapter.swift" <<'SWIFT'
import Foundation
import Network
import Domain

struct OpenMeteoAdapter {
    let session = URLSession(configuration: .ephemeral)
    func request(_ url: URL) -> URLRequest { URLRequest(url: url) }
}
SWIFT
    printf 'import Foundation\nlet s = URLSession.shared\n' > "$root/WalkTrackerTests/Adapters/OpenMeteoAdapterTests.swift"
    printf 'import Foundation\n/// El clima sale por `WeatherPort`: aquí no hay URLSession ni URLRequest.\nprotocol WeatherPort {}\n' \
        > "$root/Domain/Ports/WeatherPort.swift"
    # 10 · Frameworks de sistema fuera de `WalkTracker/UI/`: en `Shared/` y en la extensión.
    echo 'import ActivityKit' > "$root/Shared/WalkTrackerActivityAttributes.swift"
    echo 'import ActivityKit' > "$root/WalkTrackerActivity/WalkTrackerLiveActivity.swift"
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
        Button("Permitir") { Task { await store.confirmLocationPermission() } }
        WeatherCard(weather: store.session?.weather, isCapturing: store.isCapturingWeather)
            .disabled(store.isReconciling == true || store.session?.status != .active)
            .task { await root.sessionStore.restoreOnLaunch() }
    }
    // Ajustes se abre con el `openURL` de SwiftUI, sin UIKit; guardar el snapshot
    // (`saveActiveSession`) es cosa del store.
    func openSettings(_ openURL: OpenURLAction) {
        if let url = URL(string: "app-settings:") { openURL(url) }
    }
}
SWIFT

    # 12 · Los tokens SÍ llevan los valores crudos: `Style/` es donde viven. Y
    # `Diagnostics/` queda fuera por ser `#if DEBUG` y estar marcada para borrado.
    cat > "$root/WalkTracker/UI/Style/DesignTokens.swift" <<'SWIFT'
import SwiftUI

/// Aquí sí viven los valores crudos: es la única definición del vocabulario visual.
enum LayoutMetrics {
    static let touchTargetMin: CGFloat = 44
    static let margin: CGFloat = 16
}
enum Radius {
    static let card: CGFloat = 20
}
enum Colors {
    static let accent = Color.accentColor
    static let estimated = Color("EstimatedSteps")
    static let fallback = Color(red: 0.64, green: 0.31, blue: 0.0)
}
SWIFT
    cat > "$root/WalkTracker/UI/Diagnostics/NativeLayerDiagnosticsView.swift" <<'SWIFT'
import SwiftUI

#if DEBUG
struct DiagnosticsScreen: View {
    var body: some View {
        Text(verbatim: "#CCFF00")
            .frame(minHeight: 44)
            .background(Color(red: 0.8, green: 1.0, blue: 0.0), in: .rect(cornerRadius: 16))
    }
}
#endif
SWIFT
    # 12 · Lo que una vista SÍ hace: tomar el vocabulario del sitio donde vive, y nombrar
    # el 44 pt o un hexadecimal en un comentario para explicarse.
    cat > "$root/WalkTracker/UI/Vocabulario.swift" <<'SWIFT'
import SwiftUI

/// El objetivo táctil de 44 pt (AD-20) y el acento `#CCFF00` se citan aquí en un
/// comentario para explicar la vista; citarlos no es cablearlos.
struct Vocabulario: View {
    var body: some View {
        Text("Iniciar caminata")
            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
            .padding(LayoutMetrics.margin)
            .background(Colors.estimated.opacity(0.12), in: .rect(cornerRadius: Radius.card))
            .foregroundStyle(Colors.accent)
    }
}
SWIFT

    # 12b · El `Info.plist` NOMBRA la key prohibida en un comentario, para decir que lo está.
    cat > "$root/WalkTracker/App/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<!-- AD-13: `UIDesignRequiresCompatibility` está PROHIBIDA. Liquid Glass se hereda. -->
	<key>CFBundleName</key>
	<string>WalkTracker</string>
</dict>
</plist>
PLIST

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
    settings:
      base:
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
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
            'try store.storage.clearActiveSession()' 'store.motion.status' 'store.clock.now' \
            'store.beginWeatherForNewSession()' 'store.cancelWeatherCapture()' 'store.location.status' \
            'try await store.weather.currentWeather(at: c)' 'store.locationPrompt = nil' \
            'store.weatherCapture?.cancel()' 'await store.stepCounting?.value'; do
    ROOT="$(make_fixture)"
    echo "        $call" >> "$ROOT/WalkTracker/UI/SessionView.swift"
    assert_gate "\`$call\` en UI/ falla" "$ROOT" 1 "AD-7/AD-16"
    rm -rf "$ROOT"
done

# ── 4d. Rojo: CoreMotion fuera de su adapter (AD-10) ────────────────────────
# En `Application/` solo lo detecta la sección 7; en `UI/` también la 10, así que se
# busca el mensaje propio de la 7.
ROOT="$(make_fixture)"
printf 'import Foundation\nimport CoreMotion\n' > "$ROOT/WalkTracker/Application/Pasos.swift"
assert_gate "import CoreMotion en Application/ falla" "$ROOT" 1 \
    "Application/Pasos.swift:2: error: AD-10: CoreMotion solo en"
rm -rf "$ROOT"

ROOT="$(make_fixture)"
echo '@preconcurrency import CoreMotion' >> "$ROOT/WalkTracker/UI/SessionView.swift"
assert_gate "import CoreMotion en UI/ falla" "$ROOT" 1 "UI/SessionView.swift:[0-9]*: error: AD-10: CoreMotion solo en"
rm -rf "$ROOT"

# ── 4d'. Rojo: CoreLocation fuera de su adapter (AD-10, 2.1) ────────────────
# En `Application/` y en el adapter del clima solo lo detecta la sección 7; en `UI/`, también
# la 10, así que se busca el mensaje propio de la 7.
for file in Application/Clima.swift Adapters/Weather/OpenMeteoAdapter.swift Adapters/Motion/Extra.swift App/Root.swift; do
    ROOT="$(make_fixture)"
    printf 'import Foundation\nimport CoreLocation\n' > "$ROOT/WalkTracker/$file"
    assert_gate "import CoreLocation en WalkTracker/$file falla" "$ROOT" 1 \
        "$file:2: error: AD-10: CoreLocation solo en .WalkTracker/Adapters/Location/."
    rm -rf "$ROOT"
done

ROOT="$(make_fixture)"
echo '@preconcurrency import CoreLocation' >> "$ROOT/WalkTracker/UI/SessionView.swift"
assert_gate "import CoreLocation en UI/ falla con el mensaje de la sección 7" "$ROOT" 1 \
    "UI/SessionView.swift:[0-9]*: error: AD-10: CoreLocation solo en"
rm -rf "$ROOT"

# Y CoreMotion tampoco vale en el adapter de ubicación: cada framework en el suyo.
ROOT="$(make_fixture)"
printf 'import CoreLocation\nimport CoreMotion\n' > "$ROOT/WalkTracker/Adapters/Location/LocationAdapter.swift"
assert_gate "import CoreMotion en Adapters/Location/ falla" "$ROOT" 1 \
    "Location/LocationAdapter.swift:2: error: AD-10: CoreMotion solo en"
rm -rf "$ROOT"

# ── 4d''. Rojo: la red fuera del adapter del clima (AD-10, 2.1) ──────────────
for call in 'let s = URLSession.shared' 'var r = URLRequest(url: url)' \
            'let c = URLSessionConfiguration.ephemeral' '_ = try await URLSession.shared.data(from: url)'; do
    for dir in WalkTracker/UI WalkTracker/Application; do
        ROOT="$(make_fixture)"
        printf 'import Foundation\nfunc f(url: URL) async throws {\n    %s\n}\n' "$call" > "$ROOT/$dir/Red.swift"
        assert_gate "\`$call\` en $dir/ falla" "$ROOT" 1 "$dir/Red.swift:3: error: AD-10: la red solo sale de"
        rm -rf "$ROOT"
    done
done

for dir in WalkTracker/UI WalkTracker/Application Domain/Ports; do
    ROOT="$(make_fixture)"
    printf 'import Foundation\n@preconcurrency import Network\n' > "$ROOT/$dir/Red.swift"
    assert_gate "\`import Network\` en $dir/ falla" "$ROOT" 1 "$dir/Red.swift:2: error: AD-10: la red solo sale de"
    rm -rf "$ROOT"
done

# ── 4e. Rojo: el dominio lee el reloj o el calendario (AD-3, AD-19) ─────────
# El fixture limpio ya nombra los tres en comentarios: aquí son código.
for call in 'let now = Date()' 'let now = Date.now' 'let cal = Calendar.current' \
            'let now = Foundation.Date()' 'let t = Date() // la hora' \
            'let now = Date.init()' 'let hace = Date(timeIntervalSinceNow: -60)' \
            'let cal = Calendar.autoupdatingCurrent' 'let u = "//"; let t = Date()'; do
    ROOT="$(make_fixture)"
    printf 'import Foundation\nfunc f() {\n    %s\n}\n' "$call" > "$ROOT/Domain/Session/Reloj.swift"
    assert_gate "\`$call\` en Domain/ falla" "$ROOT" 1 "Session/Reloj.swift:3: error: AD-3/AD-19"
    rm -rf "$ROOT"
done

# En la columna 0, sin carácter delante.
ROOT="$(make_fixture)"
printf 'import Foundation\nlet t =\nDate()\n' > "$ROOT/Domain/Session/Reloj.swift"
assert_gate "\`Date()\` en la columna 0 en Domain/ falla" "$ROOT" 1 "Session/Reloj.swift:3: error: AD-3/AD-19"
rm -rf "$ROOT"

# Un `/*` dentro de una cadena no abre comentario ni oculta el resto del fichero.
ROOT="$(make_fixture)"
printf 'import Foundation\nlet p = "/*"\nlet q = "a\\"b"\nfunc f() { _ = Date() }\n' > "$ROOT/Domain/Session/Reloj.swift"
assert_gate "\`Date()\` tras una cadena con \`/*\` en Domain/ falla" "$ROOT" 1 "Session/Reloj.swift:4: error: AD-3/AD-19"
rm -rf "$ROOT"

# Si no se puede leer el código, el gate no da el verde.
ROOT="$(make_fixture)"
chmod 000 "$ROOT/Domain/Session/Session.swift"
assert_gate "un fichero ilegible en Domain/ falla" "$ROOT" 1 "no se pudo escanear"
chmod 644 "$ROOT/Domain/Session/Session.swift"
rm -rf "$ROOT"

# ── 4f. Rojo: `StoragePort` fuera del store (AD-16) ─────────────────────────
ROOT="$(make_fixture)"
echo '        try? storage.saveActiveSession(snapshot)' >> "$ROOT/WalkTracker/UI/SessionView.swift"
assert_gate "\`storage.saveActiveSession\` en UI/ falla" "$ROOT" 1 \
    "UI/SessionView.swift:[0-9]*: error: AD-16: solo .SessionStore. usa .StoragePort."
rm -rf "$ROOT"

ROOT="$(make_fixture)"
echo '        _ = try? root.storage.loadActiveSession()' >> "$ROOT/WalkTracker/App/WalkTrackerApp.swift"
assert_gate "\`storage.loadActiveSession\` en App/ falla" "$ROOT" 1 \
    "App/WalkTrackerApp.swift:2: error: AD-16: solo .SessionStore. usa .StoragePort."
rm -rf "$ROOT"

# Un fichero de `Application/` que no es del store tampoco.
ROOT="$(make_fixture)"
printf 'import Domain\nfunc wipe(_ s: StoragePort) {\n    try? s.clearActiveSession()\n}\n' \
    > "$ROOT/WalkTracker/Application/Limpieza.swift"
assert_gate "\`clearActiveSession\` en Application/ fuera del store falla" "$ROOT" 1 \
    "Application/Limpieza.swift:3: error: AD-16: solo"
rm -rf "$ROOT"

# En la columna 0.
ROOT="$(make_fixture)"
printf 'import SwiftUI\nsaveActiveSession(snapshot)\n' > "$ROOT/WalkTracker/UI/Vista.swift"
assert_gate "\`saveActiveSession\` en la columna 0 en UI/ falla" "$ROOT" 1 "UI/Vista.swift:2: error: AD-16: solo"
rm -rf "$ROOT"

# En el dominio.
ROOT="$(make_fixture)"
printf 'import Foundation\nfunc wipe(_ s: StoragePort) {\n    try? s.clearActiveSession()\n}\n' \
    > "$ROOT/Domain/Session/Limpieza.swift"
assert_gate "\`clearActiveSession\` en Domain/ falla" "$ROOT" 1 "Session/Limpieza.swift:3: error: AD-16: solo"
rm -rf "$ROOT"

# En un subdirectorio de `Application/` que empieza por `SessionStore`: no es el store.
ROOT="$(make_fixture)"
mkdir -p "$ROOT/WalkTracker/Application/SessionStoreKit"
printf 'import Domain\nfunc wipe(_ s: StoragePort) {\n    try? s.clearActiveSession()\n}\n' \
    > "$ROOT/WalkTracker/Application/SessionStoreKit/Limpieza.swift"
assert_gate "\`clearActiveSession\` en Application/SessionStoreKit/ falla" "$ROOT" 1 \
    "SessionStoreKit/Limpieza.swift:3: error: AD-16: solo"
rm -rf "$ROOT"

# Una línea que declara un método del puerto y llama a otro.
for dir in Domain/Ports WalkTracker/UI; do
    ROOT="$(make_fixture)"
    printf 'import Foundation\nextension StoragePort { func setAsideActiveSession() throws { try clearActiveSession() } }\n' \
        > "$ROOT/$dir/Ext.swift"
    assert_gate "declarar y llamar en la misma línea en $dir/ falla" "$ROOT" 1 "$dir/Ext.swift:2: error: AD-16: solo"
    rm -rf "$ROOT"
done

# ── 4g. Rojo: una vista importa un framework de sistema (AD-10) ─────────────
for module in CoreMotion CoreLocation HealthKit ActivityKit WidgetKit CoreHaptics AVFoundation AudioToolbox \
              UserNotifications UIKit 'struct UIKit.UIApplication' 'internal import UIKit' \
              '@_spi(X) import HealthKit'; do
    ROOT="$(make_fixture)"
    case "$module" in
        *import*) line="$module" ;;
        *)        line="import $module" ;;
    esac
    printf 'import SwiftUI\n%s\n' "$line" > "$ROOT/WalkTracker/UI/Vista.swift"
    assert_gate "\`$line\` en UI/ falla" "$ROOT" 1 "UI/Vista.swift:2: error: AD-10: la UI no importa frameworks de sistema"
    rm -rf "$ROOT"
done

# SwiftUI reexporta UIKit: usarlo sin importarlo también falla.
ROOT="$(make_fixture)"
printf 'import SwiftUI\nfunc f() {\n    UIApplication.shared.open(url)\n}\n' > "$ROOT/WalkTracker/UI/Vista.swift"
assert_gate "\`UIApplication.shared\` en UI/ sin import falla" "$ROOT" 1 "UI/Vista.swift:3: error: AD-10: la UI no usa UIKit"
rm -rf "$ROOT"

# ── 4h. Rojo: una vista cablea el vocabulario visual (AD-13, UX-DR3, AD-20) ─
# Sin target de UI tests, esto es lo único que impide que la 3.1, la 3.3, la 5.2 y la 2.3
# vuelvan a inventarse cada una su 44, su radio y su color.
for line in '            .frame(maxWidth: .infinity, minHeight: 44)' \
            '            .frame(minWidth: 44, minHeight: 44)' \
            '        .frame(minHeight:44)' \
            '            .background(.orange, in: .rect(cornerRadius: 16))' \
            '            .clipShape(.rect(cornerRadius: 20))' \
            '            .foregroundStyle(Color(red: 0.64, green: 0.31, blue: 0.0))' \
            '            .foregroundStyle(Color(.sRGB, red: 0.8, green: 1, blue: 0))' \
            '            .background(Color(white: 0.5))' \
            '            .tint(Color(hue: 0.2, saturation: 1, brightness: 1))' \
            '        let lima = "#CCFF00"' \
            '        let lima = 0xCCFF00'; do
    ROOT="$(make_fixture)"
    printf 'import SwiftUI\nstruct Vista: View {\n    var body: some View {\n%s\n    }\n}\n' "$line" \
        > "$ROOT/WalkTracker/UI/Vista.swift"
    assert_gate "\`$(echo "$line" | sed 's/^ *//')\` en UI/ falla" "$ROOT" 1 \
        "UI/Vista.swift:4: error: AD-13/UX-DR3"
    rm -rf "$ROOT"
done

# En la columna 0, sin carácter delante.
ROOT="$(make_fixture)"
printf 'import SwiftUI\ncornerRadius: 20\n' > "$ROOT/WalkTracker/UI/Vista.swift"
assert_gate "\`cornerRadius: 20\` en la columna 0 en UI/ falla" "$ROOT" 1 "UI/Vista.swift:2: error: AD-13/UX-DR3"
rm -rf "$ROOT"

# Un subdirectorio de `UI/` que no es `Style/` ni `Diagnostics/` tampoco se libra.
ROOT="$(make_fixture)"
mkdir -p "$ROOT/WalkTracker/UI/Achievements"
printf 'import SwiftUI\nlet lado: CGFloat = 44\nlet marco = "minHeight: 44"\n' \
    > "$ROOT/WalkTracker/UI/Achievements/Badge.swift"
assert_gate "\`minHeight: 44\` en una cadena de UI/Achievements/ falla" "$ROOT" 1 \
    "Achievements/Badge.swift:3: error: AD-13/UX-DR3"
rm -rf "$ROOT"

# Y `Style/` sigue siendo el único sitio donde el valor crudo es legítimo: moverlo fuera falla.
ROOT="$(make_fixture)"
mv "$ROOT/WalkTracker/UI/Style/DesignTokens.swift" "$ROOT/WalkTracker/UI/DesignTokens.swift"
assert_gate "los tokens fuera de Style/ fallan" "$ROOT" 1 "UI/DesignTokens.swift:[0-9]*: error: AD-13/UX-DR3"
rm -rf "$ROOT"

# La exención es de UN fichero, no de la carpeta: `Style/` no es una puerta trasera.
ROOT="$(make_fixture)"
cat > "$ROOT/WalkTracker/UI/Style/AchievementBadge.swift" <<'SWIFT'
import SwiftUI

struct AchievementBadge: View {
    var body: some View {
        Text(verbatim: "#CCFF00")
            .frame(minHeight: 44)
    }
}
SWIFT
assert_gate "un fichero de Style/ que no es DesignTokens.swift NO está exento" "$ROOT" 1 \
    "Style/AchievementBadge.swift:[0-9]*: error: AD-13/UX-DR3"
rm -rf "$ROOT"

# Y `DesignTokens.swift` sigue siendo el sitio donde el valor crudo —y el color del
# sistema que los tokens sustituyen— es legítimo.
ROOT="$(make_fixture)"
echo 'let sistema = Color.orange' >> "$ROOT/WalkTracker/UI/Style/DesignTokens.swift"
assert_gate "\`Color.orange\` en Style/DesignTokens.swift pasa" "$ROOT" 0 "forma del proyecto correcta"
rm -rf "$ROOT"

# ── 4h2. Rojo: las formas que esquivaban la regla, y las dos reglas nuevas ───
# Cada línea de aquí pasaba el gate antes de esta vuelta: `.frame(height: 44)` (la regla
# solo miraba `min…`), `.cornerRadius(16)` (solo miraba `cornerRadius:`), `0xCC_FF_00` y
# `Color.init(red:)` (los dos patrones no los contemplaban), `.orange` (el color que este
# vocabulario sustituye porque incumple AA) y la escala de UX-DR3 reteclada.
for line in '            .frame(height: 44)' \
            '            .frame(width: 44, height: 44)' \
            '            .frame(idealHeight: 88)' \
            '            .frame(maxHeight: 120)' \
            '            .cornerRadius(16)' \
            '            .cornerRadius( 20 )' \
            '        let lima = 0xCC_FF_00' \
            '            .foregroundStyle(Color.init(red: 0.64, green: 0.31, blue: 0.0))' \
            '            .foregroundStyle(Color .init(.displayP3, red: 1, green: 1, blue: 0))' \
            '            .foregroundStyle(.orange)' \
            '            .background(Color.orange)' \
            '            .tint(Color . orange)' \
            '        VStack(spacing: 4) { Text("a") }' \
            '        VStack(spacing: 8) { Text("a") }' \
            '        HStack(spacing: 12) { Text("a") }' \
            '        VStack(spacing: 16) { Text("a") }' \
            '        VStack(alignment: .leading, spacing: 24) { Text("a") }' \
            '        Spacer(minLength: 24)' \
            '            .padding(16)' \
            '            .padding(.horizontal, 16)' \
            '            .padding(.vertical, 12)' \
            '            .padding(.top, 24)' \
            '            .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))'; do
    ROOT="$(make_fixture)"
    printf 'import SwiftUI\nstruct Vista: View {\n    var body: some View {\n%s\n    }\n}\n' "$line" \
        > "$ROOT/WalkTracker/UI/Vista.swift"
    assert_gate "\`$(echo "$line" | sed 's/^ *//')\` en UI/ falla" "$ROOT" 1 \
        "UI/Vista.swift:4: error: AD-13/UX-DR3"
    rm -rf "$ROOT"
done

# ── 4h3. Verde: lo que la spec decide NO tokenizar sigue pasando ────────────
# La regla del espaciado prohíbe los cinco peldaños de UX-DR3, no todo número: `spacing: 0`,
# `spacing: 2` y `.padding(.top, 48)` son decisiones declaradas de la spec, y
# `.frame(maxWidth: .infinity)` no lleva número. Si alguna de estas fallara, la regla
# estaría mal calibrada y criminalizaría lo que a propósito no es token.
for line in '            .frame(maxWidth: .infinity)' \
            '            .frame(minHeight: LayoutMetrics.touchTargetMin)' \
            '        VStack(spacing: 0) { Text("a") }' \
            '        VStack(spacing: 2) { Text("a") }' \
            '        HStack(alignment: .firstTextBaseline, spacing: 2) { Text("a") }' \
            '            .padding(.top, 48)' \
            '            .padding()' \
            '            .padding(.horizontal)' \
            '            .padding(LayoutMetrics.margin)' \
            '            .padding(.vertical, Surface.cardPaddingVertical)' \
            '        Spacer(minLength: Spacing.xl)' \
            '        // el .orange del sistema daba 2,20:1 sobre blanco: por eso hay token' \
            '        // el acento es #CCFF00, y el objetivo táctil .frame(minHeight: 44)'; do
    ROOT="$(make_fixture)"
    printf 'import SwiftUI\nstruct Verde: View {\n    var body: some View {\n%s\n    }\n}\n' "$line" \
        > "$ROOT/WalkTracker/UI/Verde.swift"
    assert_gate "\`$(echo "$line" | sed 's/^ *//')\` en UI/ pasa" "$ROOT" 0 "forma del proyecto correcta"
    rm -rf "$ROOT"
done

# ── 4h4. Rojo: sin `WalkTracker/UI/` el gate no se declara en verde ─────────
# Saltarse la sección en silencio por no encontrar la carpeta es dar el verde por no mirar.
ROOT="$(make_fixture)"
rm -rf "$ROOT/WalkTracker/UI"
assert_gate "sin WalkTracker/UI/ el gate no da el verde" "$ROOT" 1 "WalkTracker/UI: error: no existe"
rm -rf "$ROOT"

# ── 4i. Rojo: `UIDesignRequiresCompatibility` en el Info.plist (AD-13) ──────
for target in WalkTracker/App WalkTrackerActivity; do
    ROOT="$(make_fixture)"
    mkdir -p "$ROOT/$target"
    cat > "$ROOT/$target/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>UIDesignRequiresCompatibility</key>
	<true/>
</dict>
</plist>
PLIST
    assert_gate "\`UIDesignRequiresCompatibility\` en $target/Info.plist falla" "$ROOT" 1 \
        "$target/Info.plist:4: error: AD-13"
    rm -rf "$ROOT"
done

# Y la lista de plists sale del MANIFIESTO, no de una lista fija: un target nuevo con plist
# propio se comprueba sin tocar el gate. (Los dos casos de arriba prueban el respaldo: el
# manifiesto del fixture no declara ninguno.)
ROOT="$(make_fixture)"
mkdir -p "$ROOT/WalkTracker/Otro"
cat > "$ROOT/WalkTracker/Otro/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>UIDesignRequiresCompatibility</key>
	<true/>
</dict>
</plist>
PLIST
perl -0pi -e 's/(        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor\n)/$1        INFOPLIST_FILE: WalkTracker\/Otro\/Info.plist\n/' "$ROOT/project.yml"
grep -q 'INFOPLIST_FILE' "$ROOT/project.yml" || { echo "  ⚠️  fixture no mutado"; exit 1; }
assert_gate "un Info.plist declarado en el manifiesto también se comprueba" "$ROOT" 1 \
    "Otro/Info.plist:4: error: AD-13"
rm -rf "$ROOT"

# ── 4j. Rojo: el acento de la app deja de ser una decisión (AD-13) ──────────
# Verificado: sin esta key el chrome vuelve al azul del sistema y NADA falla — justo el
# defecto que el chore denuncia ("azul por omisión, no por decisión").
ROOT="$(make_fixture)"
perl -0pi -e 's/^        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor\n//m' "$ROOT/project.yml"
grep -q 'ACCENT_COLOR_NAME' "$ROOT/project.yml" && { echo "  ⚠️  fixture no mutado"; exit 1; }
assert_gate "borrar la key del acento global falla" "$ROOT" 1 \
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"
rm -rf "$ROOT"

ROOT="$(make_fixture)"
perl -0pi -e 's/ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor/ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AppIcon/' "$ROOT/project.yml"
assert_gate "la key del acento apuntando a otro colorset falla" "$ROOT" 1 \
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"
rm -rf "$ROOT"

# ── 5. Rojo: manifiesto ausente ──────────────────────────────────────────────
ROOT="$(make_fixture)"
rm -f "$ROOT/project.yml"
assert_gate "project.yml ausente falla" "$ROOT" 1 "no existe project.yml"
rm -rf "$ROOT"

echo "══════════════════════════════════════════════════════════"
echo "  Total: $((pass + fail))  |  ✅ $pass passed  |  ❌ $fail failed"
echo "══════════════════════════════════════════════════════════"

[ "$fail" -eq 0 ]
