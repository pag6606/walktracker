#!/bin/bash
#
# Comprueba lo que el grafo de módulos NO puede comprobar por sí solo.
#
# El grafo de targets ya hace estructural la dirección de dependencias (AD-3) y ya
# impide que `WalkTrackerActivity` importe `Domain` (AD-15): esos símbolos no existen
# en su módulo y el enlazador lo dice. Lo que el grafo no ve es esto:
#
#   1. Que `Domain/` exista. Sin él no hay frontera que verificar y el proyecto se
#      generaría igual, en verde, sin dominio.
#   2. Que las `sources:` de `WalkTrackerActivity` no ALCANCEN `Domain/`. El grafo
#      protege contra `import Domain`; no protege contra meter los ficheros del
#      dominio dentro del target de la extensión, que los compilaría como propios
#      y dejaría AD-15 sin efecto sin un solo import.
#   3. Que todo `.swift` del árbol esté en algún target. `WalkTracker.xcodeproj` no
#      se versiona y XcodeGen fija la lista de ficheros: un fichero añadido sin
#      regenerar NO rompe el build, se ignora EN SILENCIO. Se comprobó de la peor
#      manera durante la verificación de esta historia.
#   4. Que ningún fichero de `Domain/` importe un framework de plataforma.
#      Esto SÍ es parseo de imports, y es deliberado: `import SwiftUI` dentro de un
#      framework compila perfectamente —SwiftUI está en el SDK— así que el compilador
#      NO puede hacer cumplir AD-3 en su mitad de "imports". La restricción congelada
#      del spec lo exige explícitamente: "un `import SwiftUI` o `import CoreMotion`
#      ahí tiene que romper el build". Sin esta comprobación, no se rompe.
#   5. Que la extensión no importe `Domain` (AD-15). Ver la sección.
#   6. Que la UI y la app no escriban el estado de `SessionStore` (AD-7, AD-16). Desde el
#      A-1 de la retro del Epic 1 sus propiedades y pasos internos tienen acceso de
#      módulo, porque los comparten sus extensiones: el compilador ya no impide un
#      `store.session = nil` en una vista.
#   7. Que solo el adapter de movimiento importe CoreMotion (AD-10): en `WalkTracker/`,
#      `import CoreMotion` solo en `WalkTracker/Adapters/Motion/`. Y lo mismo para la
#      ubicación (2.1): `import CoreLocation` solo en `WalkTracker/Adapters/Location/`.
#   8. Que el dominio no lea el reloj ni el calendario del sistema (AD-3, AD-19): en
#      `Domain/` no hay `Date()`, `Date.now` ni `Calendar.current` en código. El tiempo
#      entra por `ClockPort`. Los comentarios que los nombran no cuentan.
#   9. Que solo `SessionStore` use `StoragePort` (AD-16): las llamadas a
#      `load`/`save`/`clear`/`setAsideActiveSession` solo en
#      `WalkTracker/Application/SessionStore*.swift` y en su implementación de
#      `WalkTracker/Adapters/Persistence/`.
#  10. Que ninguna vista importe un framework de sistema (AD-10): `WalkTracker/UI/` no
#      importa CoreMotion, CoreLocation, HealthKit, ActivityKit, WidgetKit, CoreHaptics,
#      AVFoundation, AudioToolbox, UserNotifications ni UIKit. Esas capacidades entran
#      por un puerto y su adapter.
#  11. Que la red solo salga del adapter del clima (2.1, AD-10): en `WalkTracker/` y
#      `Domain/`, `URLSession`, `URLRequest` e `import Network` solo en
#      `WalkTracker/Adapters/Weather/`. Open-Meteo es la única llamada de red del producto.
#
#   Las secciones 7–11 no miran `WalkTrackerTests/`, `Shared/` ni `WalkTrackerActivity/`.
#
# Uso:  check-project-shape.sh [raíz-del-repo]
# En el build lo invoca la preBuildScript de `WalkTracker` y la de
# `WalkTrackerActivity` — en las dos, porque la extensión compila ANTES que la app.

set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST="$ROOT/project.yml"

fail_count=0

# Formato `fichero:línea: error:` para que Xcode lo enseñe en su sitio.
err() {
    echo "$1: error: $2" >&2
    fail_count=$((fail_count + 1))
}

if [ ! -f "$MANIFEST" ]; then
    err "$MANIFEST" "no existe project.yml. Es la fuente de verdad del proyecto: sin él no hay nada que comprobar."
    exit 1
fi

# ── Parseo de las `sources:` del manifiesto ──────────────────────────────────
# project.yml es nuestro y su forma es conocida y estrecha. No se instala un
# parser de YAML para leer un fichero que controlamos.
parse_sources() {
    awk '
        /^[A-Za-z_]/          { section = $1; target = ""; insrc = 0; next }
        section != "targets:" { next }
        /^  [A-Za-z_][A-Za-z0-9_]*:/ { target = $1; sub(/:$/, "", target); insrc = 0; next }
        /^    sources:/       { insrc = 1; next }
        /^    [A-Za-z_]/      { insrc = 0 }
        insrc && /^      - path:/ { p = $3; gsub(/"/, "", p); print target, p }
    ' "$MANIFEST"
}

SOURCES="$(parse_sources)"

if [ -z "$SOURCES" ]; then
    err "$MANIFEST" "no se pudo leer ninguna \`sources:\` del manifiesto. El gate no puede validar nada y no se declara en verde por no saber."
    exit 1
fi

# ── 1. `Domain/` existe ──────────────────────────────────────────────────────
if [ ! -d "$ROOT/Domain" ]; then
    err "$ROOT/Domain" "AD-3: no existe \`Domain/\`. El dominio es su propio módulo y es lo que hace estructural la dirección de dependencias; sin él el proyecto compila sin frontera que verificar."
fi

# ── 2. Las `sources:` de la extensión no alcanzan `Domain/` ──────────────────
# "Alcanzar" en los dos sentidos: la ruta ES el dominio o está dentro de él, o el
# dominio está dentro de la ruta (un `path: .` se los llevaría todos).
while read -r target path; do
    [ "$target" = "WalkTrackerActivity" ] || continue
    clean="${path%/}"
    case "$clean" in
        Domain | Domain/*)
            err "$MANIFEST" "AD-15: las \`sources:\` de WalkTrackerActivity incluyen '$path', que está dentro de \`Domain/\`. La extensión SOLO renderiza: compilar los ficheros del dominio dentro de su target deja AD-15 sin efecto sin un solo import."
            ;;
        . | ./ | "")
            err "$MANIFEST" "AD-15: las \`sources:\` de WalkTrackerActivity incluyen la raíz ('$path'), que arrastra \`Domain/\` al target de la extensión."
            ;;
        *)
            if [ -d "$ROOT/$clean/Domain" ]; then
                err "$MANIFEST" "AD-15: las \`sources:\` de WalkTrackerActivity incluyen '$path', que contiene \`Domain/\` y lo arrastra al target de la extensión."
            fi
            ;;
    esac
done <<< "$SOURCES"

# ── 3. Todo `.swift` del árbol está en algún target ──────────────────────────
TARGET_PATHS="$(echo "$SOURCES" | awk '{ print $2 }' | sed 's:/*$::' | sort -u)"

swift_files="$(
    find "$ROOT" -name '*.swift' -type f \
        -not -path '*/.git/*' \
        -not -path '*/node_modules/*' \
        -not -path '*/DerivedData/*' \
        -not -path '*/.build/*' \
        -not -path '*/build/*' \
        -not -path '*/Pods/*' \
        -not -path '*/_bmad-output/*' \
        -not -path '*.xcodeproj/*' \
        2>/dev/null | sort
)"

# Lo que git ignora no está en el árbol: son restos de build ajenos al producto
# —el `ios/Flutter/ephemeral/` que deja Flutter, el primero—. Preguntarle a git es
# más honesto que mantener una segunda lista de exclusiones que se desincroniza.
# Si no hay repositorio (el arnés del camino rojo monta un árbol pelado), se queda
# con las exclusiones estáticas de arriba.
if [ -n "$swift_files" ] && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ignored="$(git -C "$ROOT" check-ignore --stdin 2>/dev/null <<< "$swift_files" | sort)"
    if [ -n "$ignored" ]; then
        swift_files="$(comm -23 <(echo "$swift_files") <(echo "$ignored"))"
    fi
fi

while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel="${file#"$ROOT"/}"
    covered=0
    while IFS= read -r tp; do
        [ -n "$tp" ] || continue
        if [ "$rel" = "$tp" ] || [ "${rel#"$tp"/}" != "$rel" ]; then
            covered=1
            break
        fi
    done <<< "$TARGET_PATHS"
    if [ "$covered" -eq 0 ]; then
        err "$file" "no pertenece a ningún target de project.yml. XcodeGen fija la lista de ficheros: este fichero NO se compila y el build pasa en verde sin él. Añádelo a un target y ejecuta \`xcodegen generate\`."
    fi
done <<< "$swift_files"

# ── 4. `Domain/` no importa ningún framework de plataforma ───────────────────
# El compilador no puede hacer cumplir esto: `import SwiftUI` dentro de un framework
# compila. La restricción congelada del spec exige que rompa el build.
if [ -d "$ROOT/Domain" ]; then
    banned='SwiftUI|UIKit|AppKit|CoreMotion|CoreLocation|HealthKit|ActivityKit|WidgetKit|CoreHaptics|UserNotifications|Combine|WatchKit|Observation'
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        module="$(echo "${rest#*:}" | sed -E 's/^[[:space:]]*import[[:space:]]+//; s/[[:space:]].*$//')"
        err "$hit_file:$hit_line" "AD-3: \`Domain/\` solo puede importar Foundation, y este fichero importa \`$module\`. El dominio no conoce SwiftUI, CoreMotion, HealthKit, ActivityKit, CoreLocation ni UIKit: esas capacidades entran por un puerto de \`Domain/Ports/\`."
    done < <(grep -rnE "^[[:space:]]*import[[:space:]]+($banned)\b" "$ROOT/Domain" --include='*.swift' 2>/dev/null)
fi

# ── 5. La extensión no importa `Domain` (AD-15) ──────────────────────────────
# Verificado a mano, y NO es redundante con el grafo de targets: `Domain` no es
# dependencia declarada de `WalkTrackerActivity`, pero la app SÍ lo embebe, así que
# el módulo queda resoluble desde `BUILT_PRODUCTS_DIR` y `import Domain` en la
# extensión COMPILA EN VERDE. Se comprobó: el build pasaba.
#
# Por eso este gate está enganchado también al target de la extensión. La extensión
# es dependencia de la app y compila ANTES: con el script solo en la app, el fallo
# llegaba tarde o no llegaba.
if [ -d "$ROOT/WalkTrackerActivity" ]; then
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        err "$hit_file:$hit_line" "AD-15: \`WalkTrackerActivity\` no puede importar \`Domain\`. La extensión SOLO renderiza: no calcula, no lee ficheros y no tiene dominio. Su contrato de datos es \`ActivitySnapshot\`, en \`Shared/\`, con los valores ya formateados."
    done < <(grep -rnE "^[[:space:]]*import[[:space:]]+Domain\b" "$ROOT/WalkTrackerActivity" --include='*.swift' 2>/dev/null)
fi

# ── 6. La UI y la app no escriben el estado del store (AD-7, AD-16) ─────────
# `SessionStore` es el único escritor de la sesión y del snapshot. Sus propiedades y sus
# pasos internos tienen acceso de módulo para que los compartan `SessionStore*.swift`, así
# que el compilador no lo hace cumplir fuera de ahí. En `WalkTracker/UI` y `WalkTracker/App`
# se permite leer el estado y llamar a las intenciones (y a `restoreOnLaunch()`); no se
# permite asignar una propiedad del store, llamar a sus pasos internos ni tocar sus puertos.
# "Del store" es cualquier receptor que acabe en `store`/`Store` (`store`, `sessionStore`).
store_write='[sS]tore\.[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[^=]'
store_internal='[sS]tore\.(persist|record|reconcile|countSteps|stopCountingSteps|clearSnapshot|capLastSampleAt|beginWeatherForNewSession|cancelWeatherCapture|weatherCapture|stepCounting|storage|motion|clock|location|weather)\b'
for dir in "$ROOT/WalkTracker/UI" "$ROOT/WalkTracker/App"; do
    [ -d "$dir" ] || continue
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        err "$hit_file:$hit_line" "AD-7/AD-16: la UI y la app no escriben el estado de \`SessionStore\`: solo leen y llaman a sus intenciones. Asignar una propiedad del store, llamar a \`persist\`, \`record\`, \`reconcile\`, \`countSteps\`, \`stopCountingSteps\`, \`clearSnapshot\`, \`capLastSampleAt\`, \`beginWeatherForNewSession\` o \`cancelWeatherCapture\`, tocar sus tareas \`stepCounting\`/\`weatherCapture\`, o usar \`storage\`/\`motion\`/\`clock\`/\`location\`/\`weather\` del store es cosa de \`SessionStore*.swift\`."
    done < <(grep -rnE "$store_write|$store_internal" "$dir" --include='*.swift' 2>/dev/null)
done

# ── Ayudantes de las secciones 7–10 ──────────────────────────────────────────
# Lo que puede ir delante de `import`: atributos, con o sin argumentos (`@testable`,
# `@preconcurrency`, `@_spi(X)`), y el nivel de acceso de Swift 6 (`internal import`).
import_prefix='^[[:space:]]*(@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?(@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?'

# Un `import` de Swift en todas sus formas: con prefijo (ver arriba), de un símbolo
# (`import struct UIKit.UIApplication`) o de un submódulo
# (`import UIKit.UIGestureRecognizerSubclass`). Uso: `import_re 'A|B'`.
import_re() {
    echo "$import_prefix($1)\b"
}

# El módulo que importa una línea de `import`.
imported_module() {
    echo "$1" | sed -E "s/$import_prefix//; s/[.[:space:]].*\$//"
}

# Imprime `fichero:línea:código` de cada `.swift` bajo los directorios dados, sin los
# comentarios: quita `// …` hasta el final de la línea y los `/* … */`, anidados como
# en Swift y aunque ocupen varias líneas. Dentro de un literal de cadena (`"…"`, con
# escapes, y `"""…"""`, aunque ocupe varias líneas) `//` y `/*` no abren comentario; el
# contenido del literal se conserva, así que un nombre dentro de una cadena cuenta como
# código. No distingue las cadenas crudas (`#"…"#`): en ellas `\` no escapa.
# Si `find` o `awk` fallan, sale con estado ≠ 0: quien llama no puede dar el verde.
code_lines() {
    local dirs=()
    local d
    for d in "$@"; do
        [ -d "$d" ] && dirs+=("$d")
    done
    [ "${#dirs[@]}" -gt 0 ] || return 0
    find "${dirs[@]}" -name '*.swift' -type f -exec awk '
        FNR == 1 { depth = 0; instr = 0 }
        {
            line = $0; out = ""; i = 1; n = length(line)
            if (instr == 1) instr = 0
            while (i <= n) {
                c = substr(line, i, 1); two = substr(line, i, 2); three = substr(line, i, 3)
                if (depth > 0) {
                    if (two == "/*") { depth++; i += 2; continue }
                    if (two == "*/") { depth--; i += 2; if (depth == 0) out = out " "; continue }
                    i++; continue
                }
                if (instr > 0) {
                    if (c == "\\") { out = out two; i += 2; continue }
                    if (instr == 3 && three == "\"\"\"") { out = out three; i += 3; instr = 0; continue }
                    if (instr == 1 && c == "\"") { out = out c; i++; instr = 0; continue }
                    out = out c; i++; continue
                }
                if (three == "\"\"\"") { out = out three; i += 3; instr = 3; continue }
                if (c == "\"") { out = out c; i++; instr = 1; continue }
                if (two == "//") break
                if (two == "/*") { depth++; i += 2; continue }
                out = out c; i++
            }
            print FILENAME ":" FNR ":" out
        }
    ' {} +
}

# `code_lines` en una variable; si el escaneo falla, lo dice y deja el gate en rojo.
# Uso: `scan_code "$dir"…` (el resultado queda en `SCANNED`).
scan_code() {
    if ! SCANNED="$(code_lines "$@")"; then
        err "$1" "no se pudo escanear el código Swift de $*. El gate no se declara en verde sin haber comprobado."
        SCANNED=""
    fi
}

# Prefijo de `grep -E` sobre la salida de `code_lines`: el código empieza tras
# `fichero:línea:`, y lo buscado va al principio o tras un carácter que no es de nombre.
code_at='^[^:]+:[0-9]+:(.*[^A-Za-z0-9_])?'

# ── 7. CoreMotion y CoreLocation solo en su adapter (AD-10) ─────────────────
# `MotionAdapter` es el único que conoce CoreMotion, y `LocationAdapter` el único que conoce
# CoreLocation (2.1); el resto de la app habla con `MotionPort` y `LocationPort`. `Domain/`
# ya lo cubre la sección 4, y los tests de adapters quedan fuera.
# Uso: `framework_only_in MÓDULO SUBDIRECTORIO-DE-ADAPTERS EXPLICACIÓN`.
framework_only_in() {
    local module="$1" adapter_dir="$2" why="$3"
    [ -d "$ROOT/WalkTracker" ] || return 0
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        case "$hit_file" in
            "$ROOT/WalkTracker/Adapters/$adapter_dir/"*) continue ;;
        esac
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        err "$hit_file:$hit_line" "AD-10: $module solo en \`WalkTracker/Adapters/$adapter_dir/\`. Este fichero importa $module: $why"
    done < <(grep -rnE "$(import_re "$module")" "$ROOT/WalkTracker" --include='*.swift' 2>/dev/null)
}
framework_only_in CoreMotion Motion "el resto de la app cuenta pasos a través de \`MotionPort\`, que implementa \`MotionAdapter\`."
framework_only_in CoreLocation Location "el resto de la app pide la ubicación aproximada a través de \`LocationPort\`, que implementa \`LocationAdapter\` y redondea las coordenadas antes de entregarlas."

# ── 8. El dominio no lee el reloj ni el calendario del sistema (AD-3, AD-19) ─
# Todo instante entra por `ClockPort` (o como argumento), para que el dominio sea
# determinista y probable con vectores. Solo cuenta el código: los comentarios que
# nombran `Date()` —como el de `ClockPort`— no son una llamada.
if [ -d "$ROOT/Domain" ]; then
    time_call='(Date[[:space:]]*(\.[[:space:]]*init[[:space:]]*)?\([[:space:]]*(\)|timeIntervalSinceNow[[:space:]]*:)|Date[[:space:]]*\.[[:space:]]*now\b|Calendar[[:space:]]*\.[[:space:]]*(current|autoupdatingCurrent)\b)'
    scan_code "$ROOT/Domain"
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        code="${rest#*:}"
        [[ "$code" =~ ^[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] && code="${BASH_REMATCH[1]}"
        err "$hit_file:$hit_line" "AD-3/AD-19: \`Domain/\` no lee el reloj ni el calendario del sistema (\`Date()\`, \`Date.init()\`, \`Date(timeIntervalSinceNow:)\`, \`Date.now\`, \`Calendar.current\`, \`Calendar.autoupdatingCurrent\`). El instante entra por \`ClockPort\` o como argumento (\`at now: Date\`). Código: \`$code\`"
    done < <(grep -E "$code_at$time_call" <<< "$SCANNED")
fi

# ── 9. Solo `SessionStore` usa `StoragePort` (AD-16) ────────────────────────
# El store es el único escritor y lector del snapshot. Se admiten las llamadas en
# `WalkTracker/Application/SessionStore*.swift` y en el adapter de persistencia, que las
# implementa. Las declaraciones (`func loadActiveSession`) no son llamadas, y los
# comentarios que las nombran tampoco; una línea que declara Y llama sí cuenta.
storage_names='(load|save|clear|setAside)ActiveSession'
# Sin `\b`: se evalúa con `[[ =~ ]]`, y el ERE del sistema no lo garantiza.
storage_call_bash="(^|[^A-Za-z0-9_])$storage_names([^A-Za-z0-9_]|\$)"
scan_code "$ROOT/WalkTracker" "$ROOT/Domain"
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    hit_file="${hit%%:*}"
    case "$hit_file" in
        "$ROOT/WalkTracker/Application/SessionStore"*.swift)
            # Solo los ficheros de `Application/`, no un subdirectorio que empiece igual.
            [[ "${hit_file#"$ROOT/WalkTracker/Application/"}" == */* ]] || continue
            ;;
        "$ROOT/WalkTracker/Adapters/Persistence/"*) continue ;;
    esac
    rest="${hit#*:}"
    hit_line="${rest%%:*}"
    code="${rest#*:}"
    # Se quitan las declaraciones y se vuelve a buscar: lo que queda es una llamada.
    calls="$(sed -E "s/(^|[^A-Za-z0-9_])func[[:space:]]+$storage_names/\\1/g" <<< "$code")"
    [[ "$calls" =~ $storage_call_bash ]] || continue
    err "$hit_file:$hit_line" "AD-16: solo \`SessionStore\` usa \`StoragePort\`. \`loadActiveSession\`, \`saveActiveSession\`, \`clearActiveSession\` y \`setAsideActiveSession\` se llaman desde \`WalkTracker/Application/SessionStore*.swift\`; fuera de ahí se pide al store una intención."
done < <(grep -E "$code_at$storage_names\b" <<< "$SCANNED")

# ── 10. Ninguna vista importa un framework de sistema (AD-10) ───────────────
# La UI solo pinta el estado del store y llama a sus intenciones. Sensores, salud,
# Live Activities, háptica, sonido y notificaciones entran por un puerto y su adapter.
# `UIKit` también, sin excepciones: para abrir Ajustes basta el `openURL` de SwiftUI.
# Como SwiftUI reexporta UIKit, prohibir el import no basta: también se buscan en el
# código los tipos de UIKit que una vista podría usar sin importarlo.
if [ -d "$ROOT/WalkTracker/UI" ]; then
    ui_banned='CoreMotion|CoreLocation|HealthKit|ActivityKit|WidgetKit|CoreHaptics|AVFoundation|AudioToolbox|UserNotifications|UIKit'
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        module="$(imported_module "${rest#*:}")"
        err "$hit_file:$hit_line" "AD-10: la UI no importa frameworks de sistema, y esta vista importa \`$module\`. CoreMotion, CoreLocation, HealthKit, ActivityKit, WidgetKit, CoreHaptics, AVFoundation, AudioToolbox, UserNotifications y UIKit entran por un puerto y su adapter; la vista lee el store."
    done < <(grep -rnE "$(import_re "$ui_banned")" "$ROOT/WalkTracker/UI" --include='*.swift' 2>/dev/null)

    uikit_symbol='UI(Application|Device|Screen|ViewController|View)\b'
    scan_code "$ROOT/WalkTracker/UI"
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        hit_file="${hit%%:*}"
        rest="${hit#*:}"
        hit_line="${rest%%:*}"
        err "$hit_file:$hit_line" "AD-10: la UI no usa UIKit, tampoco sin importarlo: \`UIApplication\`, \`UIDevice\`, \`UIScreen\`, \`UIViewController\` y \`UIView\` son cosa de un adapter. Ajustes se abre con el \`openURL\` de SwiftUI."
    done < <(grep -E "$code_at$uikit_symbol" <<< "$SCANNED")
fi

# ── 11. La red solo sale del adapter del clima (2.1, AD-10) ─────────────────
# Open-Meteo es la única llamada de red del producto, y la hace `OpenMeteoAdapter` por
# `WeatherPort`. Fuera de `WalkTracker/Adapters/Weather/` no se construye ni una petición
# (`URLRequest`) ni una sesión de red (`URLSession` y sus tipos) ni se importa `Network`. Solo
# cuenta el código: los comentarios que las nombran no son una llamada. Los tests quedan fuera.
network_symbol='(URLSession|URLRequest)'
scan_code "$ROOT/WalkTracker" "$ROOT/Domain"
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    hit_file="${hit%%:*}"
    case "$hit_file" in
        "$ROOT/WalkTracker/Adapters/Weather/"*) continue ;;
    esac
    rest="${hit#*:}"
    hit_line="${rest%%:*}"
    err "$hit_file:$hit_line" "AD-10: la red solo sale de \`WalkTracker/Adapters/Weather/\`. \`URLSession\`, \`URLRequest\` e \`import Network\` son del adapter del clima: la única llamada de red del producto es Open-Meteo, a través de \`WeatherPort\`."
done < <(grep -E "$code_at$network_symbol|^[^:]+:[0-9]+:$(import_re 'Network' | sed 's/^\^//')" <<< "$SCANNED")

# ── Veredicto ────────────────────────────────────────────────────────────────
if [ "$fail_count" -gt 0 ]; then
    echo "check-project-shape: $fail_count violación(es) de la forma del proyecto." >&2
    exit 1
fi

echo "check-project-shape: forma del proyecto correcta."
exit 0
