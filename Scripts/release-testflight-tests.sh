#!/bin/bash
#
# Camino rojo de `release-testflight.sh`. Un gate sin prueba de su camino rojo no es
# un gate: es un script que nadie ha visto fallar.
#
# NO toca App Store Connect, ni el repositorio real, ni Xcode. Cada caso monta un
# repositorio git temporal con una copia del script, gates de mentira y un
# `xcodebuild`/`xcodegen` falsos en el PATH que apuntan cada invocación. Se afirma el
# código de salida, el mensaje y —lo que importa— que NO se archivó, NO se subió y NO
# se etiquetó cuando no tocaba.
#
# Uso:  bash Scripts/release-testflight-tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/release-testflight.sh"
OPTIONS="$SCRIPT_DIR/ExportOptions-testflight.plist"

# Un fallo de montaje aborta TODA la suite: con una ruta vacía, `git -C ""` actuaría
# sobre el repositorio real.
WORK="$(mktemp -d -t release-testflight-tests)" || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "  ⚠️  no se pudo crear el directorio temporal" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
report_pass() { echo "  ✅ $1"; pass=$((pass + 1)); }
report_fail() { echo "  ❌ $1"; fail=$((fail + 1)); }

# ── Herramientas falsas ──────────────────────────────────────────────────────
# `xcodebuild` falso. Versión por FAKE_XCODE_VERSION. `archive` crea un archivo con
# los Info.plist que diría el real (versión FAKE_MARKETING o 4.0.0, build el de
# CURRENT_PROJECT_VERSION= o FAKE_BUILD); la extensión, FAKE_EXT_MARKETING y
# FAKE_EXT_BUILD si se dan; con FAKE_GENERIC_ARCHIVE=1, un archivo genérico; con
# FAKE_ARCHIVE_DIRTY=1, ensucia el árbol mientras archiva. La app lleva
# `PrivacyInfo.xcprivacy` y `ITSAppUsesNonExemptEncryption = false`, salvo con
# FAKE_NO_PRIVACY=1 (sin manifiesto), FAKE_BAD_PRIVACY=1 (manifiesto que no es plist),
# FAKE_ENCRYPTION=<valor> (el flag como cadena) o FAKE_ENCRYPTION=absent (sin el flag). El
# manifiesto declara la ubicación aproximada y el Info.plist su explicación, salvo con
# FAKE_EMPTY_PRIVACY=1 (sin datos recogidos, el de la 8.3), FAKE_OTHER_PRIVACY=1 (otro dato
# recogido) o FAKE_NO_LOCATION_USAGE=1 (sin NSLocationWhenInUseUsageDescription).
# `-exportArchive` apunta el `destination` de sus opciones y falla si
# FAKE_EXPORT_FAIL=1, como un rechazo de App Store Connect (=accounts: Xcode sin cuenta).
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/xcodebuild" <<'FAKE'
#!/bin/bash
LOG="${FAKE_LOG:?}"
if [ "${1:-}" = "-version" ]; then
    echo "Xcode ${FAKE_XCODE_VERSION:-26.3}"
    echo "Build version 17C529"
    exit 0
fi
action="" archive="" options="" export_path="" build=""
while [ $# -gt 0 ]; do
    case "$1" in
        archive) action=archive ;;
        -exportArchive) action=export ;;
        -archivePath) shift; archive="$1" ;;
        -exportOptionsPlist) shift; options="$1" ;;
        -exportPath) shift; export_path="$1" ;;
        CURRENT_PROJECT_VERSION=*) build="${1#CURRENT_PROJECT_VERSION=}" ;;
    esac
    shift
done
case "$action" in
    archive)
        echo "archive build=$build" >> "$LOG"
        app="$archive/Products/Applications/WalkTracker.app"
        ext="$app/PlugIns/WalkTrackerActivity.appex"
        mkdir -p "$ext"
        plutil -create xml1 "$app/Info.plist"
        plutil -insert CFBundleShortVersionString -string "${FAKE_MARKETING:-4.0.0}" "$app/Info.plist"
        plutil -insert CFBundleVersion -string "${FAKE_BUILD:-$build}" "$app/Info.plist"
        [ "${FAKE_NO_LOCATION_USAGE:-0}" = "1" ] ||
            plutil -insert NSLocationWhenInUseUsageDescription -string "Clima de la caminata" "$app/Info.plist"
        case "${FAKE_ENCRYPTION:-false}" in
            false) plutil -insert ITSAppUsesNonExemptEncryption -bool false "$app/Info.plist" ;;
            absent) ;;
            *) plutil -insert ITSAppUsesNonExemptEncryption -string "$FAKE_ENCRYPTION" "$app/Info.plist" ;;
        esac
        if [ "${FAKE_BAD_PRIVACY:-0}" = "1" ]; then
            echo "no es un plist" > "$app/PrivacyInfo.xcprivacy"
        elif [ "${FAKE_NO_PRIVACY:-0}" != "1" ]; then
            plutil -create xml1 "$app/PrivacyInfo.xcprivacy"
            plutil -insert NSPrivacyTracking -bool false "$app/PrivacyInfo.xcprivacy"
            plutil -insert NSPrivacyCollectedDataTypes -array "$app/PrivacyInfo.xcprivacy"
            if [ "${FAKE_EMPTY_PRIVACY:-0}" != "1" ]; then
                collected="NSPrivacyCollectedDataTypeCoarseLocation"
                [ "${FAKE_OTHER_PRIVACY:-0}" = "1" ] && collected="NSPrivacyCollectedDataTypePreciseLocation"
                plutil -insert NSPrivacyCollectedDataTypes.0 -dictionary "$app/PrivacyInfo.xcprivacy"
                plutil -insert NSPrivacyCollectedDataTypes.0.NSPrivacyCollectedDataType -string "$collected" "$app/PrivacyInfo.xcprivacy"
            fi
        fi
        plutil -create xml1 "$ext/Info.plist"
        plutil -insert CFBundleShortVersionString -string "${FAKE_EXT_MARKETING:-${FAKE_MARKETING:-4.0.0}}" "$ext/Info.plist"
        plutil -insert CFBundleVersion -string "${FAKE_EXT_BUILD:-$build}" "$ext/Info.plist"
        [ "${FAKE_ARCHIVE_DIRTY:-0}" = "1" ] && touch "$PWD/editado-durante-el-archivo.swift"
        plutil -create xml1 "$archive/Info.plist"
        if [ "${FAKE_GENERIC_ARCHIVE:-0}" != "1" ]; then
            plutil -insert ApplicationProperties -dictionary "$archive/Info.plist"
            plutil -insert ApplicationProperties.ApplicationPath -string "Applications/WalkTracker.app" "$archive/Info.plist"
        else
            mkdir -p "$archive/Products/Library/Frameworks/Domain.framework"
        fi
        echo "** ARCHIVE SUCCEEDED **"
        ;;
    export)
        dest="$(plutil -extract destination raw -o - "$options")"
        echo "export destination=$dest" >> "$LOG"
        if [ "${FAKE_EXPORT_FAIL:-0}" = "accounts" ]; then
            echo "error: exportArchive No Accounts"
            echo "** EXPORT FAILED **"
            exit 70
        fi
        if [ "${FAKE_EXPORT_FAIL:-0}" = "1" ]; then
            echo "error: exportArchive: The bundle version must be higher than the previously uploaded version."
            echo "** EXPORT FAILED **"
            exit 70
        fi
        mkdir -p "$export_path"
        [ "$dest" = "export" ] && touch "$export_path/WalkTracker.ipa"
        echo "** EXPORT SUCCEEDED **"
        ;;
    *) echo "xcodebuild falso: invocación inesperada" >&2; exit 64 ;;
esac
FAKE
cat > "$FAKE_BIN/xcodegen" <<'FAKE'
#!/bin/bash
echo "xcodegen $*" >> "${FAKE_LOG:?}"
FAKE
chmod +x "$FAKE_BIN/xcodebuild" "$FAKE_BIN/xcodegen"

# ── Fixture: un repositorio mínimo con la forma que el script lee ────────────
# Gates de mentira: salen con el código de GATE_SHAPE_EXIT / GATE_DOMAIN_EXIT. Con
# GATE_DIRTY=1 el gate de forma ensucia el árbol; con GATE_COMMIT=1, hace un commit.
# `origin` es un repositorio bare local con `main` empujado.
make_repo() {
    local root="$WORK/repo-$1"
    mkdir -p "$root/Scripts"
    cp "$SCRIPT" "$OPTIONS" "$root/Scripts/"
    cat > "$root/Scripts/check-project-shape.sh" <<'GATE'
#!/bin/bash
echo "gate forma" >> "$FAKE_LOG"
[ "${GATE_DIRTY:-0}" = "1" ] && touch "$1/tocado-durante-los-gates.swift"
[ "${GATE_COMMIT:-0}" = "1" ] && git -C "$1" commit -q --allow-empty -m "commit durante los gates"
exit "${GATE_SHAPE_EXIT:-0}"
GATE
    printf '#!/bin/bash\necho "gate dominio" >> "$FAKE_LOG"\nexit "${GATE_DOMAIN_EXIT:-0}"\n' > "$root/Scripts/verify-domain.sh"
    cat > "$root/project.yml" <<'YAML'
name: WalkTracker
settings:
  base:
    MARKETING_VERSION: "4.0.0"
    CURRENT_PROJECT_VERSION: "1"
YAML
    printf 'build/\n' > "$root/.gitignore"
    (
        cd "$root" &&
        git init -q -b main &&
        git config user.name "Test" &&
        git config user.email "test@example.invalid" &&
        git config commit.gpgsign false &&
        git config tag.gpgsign false &&
        git add -A &&
        git commit -q -m uno &&
        git commit -q --allow-empty -m dos &&
        git commit -q --allow-empty -m tres &&
        git init -q --bare "$root-origin.git" &&
        git remote add origin "$root-origin.git" &&
        git push -q origin main
    ) || { echo "  ⚠️  no se pudo montar el fixture" >&2; exit 1; }
    echo "$root"
}

# new_repo NOMBRE — deja el fixture en $R. Sin subshell: si el montaje falla, el
# `exit` aborta la suite en vez de dejar R vacío.
new_repo() {
    R="$(make_repo "$1")"
    if [ -z "$R" ] || [ ! -d "$R/.git" ]; then
        echo "  ⚠️  fixture '$1' sin montar: se aborta la suite" >&2
        exit 1
    fi
}

# run_case NOMBRE REPO -- ARGS...   (el entorno FAKE_*/GATE_* lo pone quien llama)
# Deja la salida en $OUT y el código en $STATUS. Stdin cerrado: nunca hay terminal.
run_case() {
    local repo="$1"
    shift
    export FAKE_LOG="$repo.log"
    : > "$FAKE_LOG"
    OUT="$(PATH="$FAKE_BIN:$PATH" bash "$repo/Scripts/release-testflight.sh" "$@" </dev/null 2>&1)"
    STATUS=$?
}

# run_case_tty REPO RESPUESTA -- ARGS...  Igual, pero en un pseudo-terminal con la
# respuesta en su entrada. La entrada se mantiene abierta hasta que el script
# termina: un EOF temprano llegaría como ^D antes que la respuesta.
run_case_tty() {
    local repo="$1" answer="$2"
    shift 2
    export FAKE_LOG="$repo.log"
    : > "$FAKE_LOG"
    local done_marker="$repo.done"
    rm -f "$done_marker"
    OUT="$(
        { printf '%s\n' "$answer"; while [ ! -e "$done_marker" ]; do sleep 0.1; done; } |
            PATH="$FAKE_BIN:$PATH" script -q /dev/null bash -c \
                'bash "$0" "$@"; s=$?; touch "'"$done_marker"'"; exit $s' \
                "$repo/Scripts/release-testflight.sh" "$@" 2>&1
    )"
    STATUS=$?
}

# expect NOMBRE REPO CODIGO("0"|"nonzero") TEXTO [no-archive] [no-upload] [no-tag] [tag=X] [dest=X]
expect() {
    local name="$1" repo="$2" want="$3" needle="$4"
    shift 4
    local problems=()

    if [ "$want" = "nonzero" ] && [ "$STATUS" -eq 0 ]; then
        problems+=("esperado exit ≠ 0, obtenido 0")
    elif [ "$want" = "0" ] && [ "$STATUS" -ne 0 ]; then
        problems+=("esperado exit 0, obtenido $STATUS")
    fi
    if [ -n "$needle" ] && ! grep -qF -- "$needle" <<< "$OUT"; then
        problems+=("la salida no menciona '$needle'")
    fi
    for check in "$@"; do
        case "$check" in
            no-archive) grep -q '^archive' "$FAKE_LOG" && problems+=("archivó y no debía") ;;
            no-gates) grep -q '^gate' "$FAKE_LOG" && problems+=("corrió los gates y no debía") ;;
            no-upload) grep -q '^export destination=upload' "$FAKE_LOG" && problems+=("subió y no debía") ;;
            no-tag)
                [ -z "$(git -C "$repo" tag -l 'v*-build.*' | grep -vxF "${PRE_TAG:-}")" ] ||
                    problems+=("creó una etiqueta y no debía: $(git -C "$repo" tag -l | tr '\n' ' ')")
                ;;
            tag=*)
                git -C "$repo" rev-parse --quiet --verify "refs/tags/${check#tag=}" >/dev/null ||
                    problems+=("no existe la etiqueta ${check#tag=}")
                ;;
            dest=*) grep -qx "export destination=${check#dest=}" "$FAKE_LOG" ||
                    problems+=("la exportación no usó destination=${check#dest=}") ;;
        esac
    done

    if [ "${#problems[@]}" -eq 0 ]; then
        report_pass "$name"
    else
        report_fail "$name — $(printf '%s; ' "${problems[@]}")"
        echo "$OUT" | sed 's/^/      /'
    fi
}

echo "══════════════════════════════════════════════════════════"
echo "  Camino rojo de release-testflight.sh"
echo "══════════════════════════════════════════════════════════"

# ── Árbol sucio ──────────────────────────────────────────────────────────────
new_repo sucio
echo cambio >> "$R/project.yml"
run_case "$R" --confirm v4.0.0-build.3
expect "árbol con cambios sin commit no archiva" "$R" nonzero "árbol sucio" no-gates no-archive no-upload no-tag

new_repo sin-seguimiento
touch "$R/nuevo.swift"
run_case "$R" --dry-run
expect "fichero sin seguimiento no archiva (tampoco en ensayo)" "$R" nonzero "árbol sucio" no-gates no-archive no-upload no-tag

# ── Rama equivocada ──────────────────────────────────────────────────────────
new_repo rama
git -C "$R" checkout -q -b feature/algo
run_case "$R" --confirm v4.0.0-build.3
expect "rama de feature no archiva y nombra main" "$R" nonzero "Solo se sube desde 'main'" no-gates no-archive no-upload no-tag

# ── Toolchain equivocado ─────────────────────────────────────────────────────
new_repo xcode27
FAKE_XCODE_VERSION=27.0 run_case "$R" --confirm v4.0.0-build.3
expect "Xcode 27 no archiva y nombra la versión encontrada" "$R" nonzero "Xcode 27.0" no-gates no-archive no-upload no-tag

new_repo xcode16
FAKE_XCODE_VERSION=16.4 run_case "$R" --dry-run
expect "Xcode 16 no archiva ni en ensayo" "$R" nonzero "Xcode 16.4" no-gates no-archive no-upload no-tag

# ── Etiqueta ya existe ───────────────────────────────────────────────────────
new_repo etiqueta
git -C "$R" tag -a v4.0.0-build.3 -m previa
PRE_TAG=v4.0.0-build.3
run_case "$R" --confirm v4.0.0-build.3
expect "etiqueta existente no archiva" "$R" nonzero "ya existe" no-gates no-archive no-upload no-tag
PRE_TAG=""

new_repo monotonia
git -C "$R" tag -a v4.0.0-build.9 -m "historial reescrito"
PRE_TAG=v4.0.0-build.9
run_case "$R" --confirm v4.0.0-build.3
expect "build menor que uno ya etiquetado no archiva" "$R" nonzero "no supera el mayor ya etiquetado" no-gates no-archive no-upload no-tag
PRE_TAG=""

# La etiqueta nace en otro clon, sobre un commit que este no tiene: así solo la trae
# `fetch --tags` (una que apuntara a algo local llegaría sola por auto-follow).
new_repo etiqueta-remota
git clone -q "$R-origin.git" "$R-otro-clon" || exit 1
git -C "$R-otro-clon" -c user.name=Otro -c user.email=otro@example.invalid \
    commit -q --allow-empty -m "build desde otro clon" || exit 1
git -C "$R-otro-clon" -c user.name=Otro -c user.email=otro@example.invalid \
    tag -a v4.0.0-build.9 -m "subida desde otro clon" || exit 1
git -C "$R-otro-clon" push -q origin v4.0.0-build.9 || exit 1
PRE_TAG=v4.0.0-build.9
run_case "$R" --confirm v4.0.0-build.3
expect "build etiquetado en otro clon (solo en origin) no archiva" "$R" nonzero "no supera el mayor ya etiquetado (v4.0.0-build.9)" no-gates no-archive no-upload
PRE_TAG=""

# ── HEAD distinto de origin/main ─────────────────────────────────────────────
new_repo sin-empujar
git -C "$R" commit -q --allow-empty -m "local, sin empujar"
run_case "$R" --confirm v4.0.0-build.4
expect "HEAD distinto de origin/main no archiva" "$R" nonzero "no es origin/main" no-gates no-archive no-upload no-tag

new_repo sin-pull
git -C "$R" commit -q --allow-empty -m "fusionado en GitHub"
git -C "$R" push -q origin main
git -C "$R" reset -q --hard HEAD~1
run_case "$R" --confirm v4.0.0-build.3
expect "main sin pull (origin/main por delante) no archiva" "$R" nonzero "no es origin/main" no-gates no-archive no-upload no-tag

# ── Confirmación ─────────────────────────────────────────────────────────────
new_repo sin-confirmacion
run_case "$R"
expect "sin terminal y sin --confirm no archiva" "$R" nonzero "--confirm v4.0.0-build.3" no-gates no-archive no-upload no-tag

new_repo confirmacion-otra
run_case "$R" --confirm v4.0.0-build.2
expect "--confirm de otro build no archiva" "$R" nonzero "no coincide" no-gates no-archive no-upload no-tag

new_repo tty-respuesta-mala
run_case_tty "$R" "si"
expect "confirmación interactiva equivocada cancela la subida" "$R" nonzero "subida cancelada" no-upload no-tag

new_repo tty-respuesta-buena
run_case_tty "$R" "v4.0.0-build.3"
expect "confirmación interactiva correcta sube y etiqueta" "$R" 0 "etiqueta: v4.0.0-build.3" dest=upload tag=v4.0.0-build.3

# ── HEAD o árbol cambian durante el release ──────────────────────────────────
new_repo gate-ensucia
GATE_DIRTY=1 run_case "$R" --confirm v4.0.0-build.3
expect "árbol ensuciado durante los gates no archiva" "$R" nonzero "el árbol quedó sucio mientras corrían los gates" no-archive no-upload no-tag

new_repo gate-commit
GATE_COMMIT=1 run_case "$R" --confirm v4.0.0-build.3
expect "commit durante los gates no archiva" "$R" nonzero "HEAD cambió mientras corrían los gates" no-archive no-upload no-tag

new_repo archivo-ensucia
FAKE_ARCHIVE_DIRTY=1 run_case "$R" --confirm v4.0.0-build.3
expect "árbol ensuciado durante el archivo no se sube" "$R" nonzero "el árbol quedó sucio mientras se archivaba" no-upload no-tag

# ── Gate rojo ────────────────────────────────────────────────────────────────
new_repo gate-forma
GATE_SHAPE_EXIT=1 run_case "$R" --confirm v4.0.0-build.3
expect "check-project-shape.sh en rojo no archiva" "$R" nonzero "check-project-shape.sh en rojo" no-archive no-upload no-tag

new_repo gate-dominio
GATE_DOMAIN_EXIT=1 run_case "$R" --dry-run
expect "verify-domain.sh en rojo no archiva (tampoco en ensayo)" "$R" nonzero "verify-domain.sh en rojo" no-archive no-upload no-tag

# ── Versión ──────────────────────────────────────────────────────────────────
new_repo semver
sed -i '' 's/"4.0.0"/"4.0"/' "$R/project.yml"
git -C "$R" commit -q -am "versión rota"
run_case "$R" --dry-run
expect "MARKETING_VERSION no SemVer no archiva" "$R" nonzero "no es SemVer" no-gates no-archive no-upload no-tag

new_repo binario-otra-version
FAKE_MARKETING=3.9.9 run_case "$R" --confirm v4.0.0-build.3
expect "binario con otra versión que la etiqueta no se sube" "$R" nonzero "se esperaba 4.0.0 (3)" no-upload no-tag

new_repo extension-otra-version
FAKE_EXT_MARKETING=3.9.9 run_case "$R" --confirm v4.0.0-build.3
expect "solo la extensión con otra versión no se sube" "$R" nonzero "WalkTrackerActivity.appex/Info.plist dice versión '3.9.9'" no-upload no-tag

new_repo extension-otro-build
FAKE_EXT_BUILD=2 run_case "$R" --confirm v4.0.0-build.3
expect "solo la extensión con otro build no se sube" "$R" nonzero "WalkTrackerActivity.appex/Info.plist dice versión '4.0.0' build '2'" no-upload no-tag

new_repo app-otro-build
FAKE_BUILD=99 run_case "$R" --confirm v4.0.0-build.3
expect "app con la versión bien y el build mal no se sube" "$R" nonzero "WalkTracker.app/Info.plist dice versión '4.0.0' build '99'" no-upload no-tag

new_repo archivo-generico
FAKE_GENERIC_ARCHIVE=1 run_case "$R" --confirm v4.0.0-build.3
expect "archivo genérico (framework instalado fuera de la app) no se sube" "$R" nonzero "el archivo es genérico" no-upload no-tag

# ── Privacidad y exportación en el binario (2.1) ─────────────────────────────
new_repo sin-manifiesto
FAKE_NO_PRIVACY=1 run_case "$R" --confirm v4.0.0-build.3
expect "app sin PrivacyInfo.xcprivacy no se sube" "$R" nonzero "no lleva PrivacyInfo.xcprivacy" no-upload no-tag

new_repo manifiesto-roto
FAKE_BAD_PRIVACY=1 run_case "$R" --dry-run
expect "PrivacyInfo.xcprivacy que no es plist no se exporta (tampoco en ensayo)" "$R" nonzero "no es un plist válido" no-upload no-tag
grep -q '^export' "$FAKE_LOG" && report_fail "con el manifiesto roto no debía exportar" ||
    report_pass "con el manifiesto roto no se llega a exportar"

new_repo manifiesto-vacio
FAKE_EMPTY_PRIVACY=1 run_case "$R" --confirm v4.0.0-build.3
expect "manifiesto sin datos recogidos (el de la 8.3) no se sube" "$R" nonzero "no declara NSPrivacyCollectedDataTypeCoarseLocation" no-upload no-tag

new_repo manifiesto-otro-dato
FAKE_OTHER_PRIVACY=1 run_case "$R" --dry-run
expect "manifiesto que declara otro dato y no la ubicación aproximada no se exporta" "$R" nonzero "no declara NSPrivacyCollectedDataTypeCoarseLocation" no-upload no-tag

new_repo sin-explicacion-ubicacion
FAKE_NO_LOCATION_USAGE=1 run_case "$R" --confirm v4.0.0-build.3
expect "Info.plist sin NSLocationWhenInUseUsageDescription no se sube" "$R" nonzero "no lleva NSLocationWhenInUseUsageDescription" no-upload no-tag

new_repo cifrado-true
FAKE_ENCRYPTION=true run_case "$R" --confirm v4.0.0-build.3
expect "ITSAppUsesNonExemptEncryption distinto de false no se sube" "$R" nonzero "ITSAppUsesNonExemptEncryption 'true'" no-upload no-tag

new_repo cifrado-ausente
FAKE_ENCRYPTION=absent run_case "$R" --confirm v4.0.0-build.3
expect "sin ITSAppUsesNonExemptEncryption no se sube" "$R" nonzero "ITSAppUsesNonExemptEncryption '(ausente)'" no-upload no-tag

# ── Subida rechazada ─────────────────────────────────────────────────────────
new_repo rechazo
FAKE_EXPORT_FAIL=1 run_case "$R" --confirm v4.0.0-build.3
expect "subida rechazada no etiqueta, muestra el error y avisa del build gastado" "$R" nonzero "bundle version must be higher" dest=upload no-tag
grep -qF "puede haber llegado ya a App Store Connect" <<< "$OUT" &&
    report_pass "el aviso de subida fallida pide un commit nuevo en origin/main" ||
    report_fail "el aviso de subida fallida no dice que el build puede estar gastado"


new_repo sin-cuenta
FAKE_EXPORT_FAIL=accounts run_case "$R" --dry-run
expect "Xcode sin cuenta de Apple falla y dice dónde añadirla" "$R" nonzero "Ajustes → Cuentas" no-upload no-tag

# ── Caminos verdes (con herramientas falsas) ─────────────────────────────────
# Sin ellos, un script que fallara siempre pasaría todo el camino rojo.
new_repo ensayo
git -C "$R" checkout -q -b feature/ensayo
run_case "$R" --dry-run
expect "ensayo en rama de feature exporta .ipa sin subir ni etiquetar" "$R" 0 "WalkTracker.ipa" dest=export no-upload no-tag

new_repo release
run_case "$R" --confirm v4.0.0-build.3
expect "release correcta sube y etiqueta v4.0.0-build.3" "$R" 0 "etiqueta: v4.0.0-build.3" dest=upload tag=v4.0.0-build.3
if [ "$(git -C "$R" rev-list -n 1 v4.0.0-build.3 2>/dev/null)" = "$(git -C "$R" rev-parse HEAD)" ] &&
   grep -qx 'archive build=3' "$FAKE_LOG"; then
    report_pass "la etiqueta apunta al commit archivado con CURRENT_PROJECT_VERSION=3"
else
    report_fail "la etiqueta no apunta a HEAD o el archivo no recibió el build 3"
fi

echo "══════════════════════════════════════════════════════════"
echo "  Total: $((pass + fail))  |  ✅ $pass passed  |  ❌ $fail failed"
echo "══════════════════════════════════════════════════════════"

[ "$fail" -eq 0 ]
