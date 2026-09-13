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

WORK="$(mktemp -d -t release-testflight-tests)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
report_pass() { echo "  ✅ $1"; pass=$((pass + 1)); }
report_fail() { echo "  ❌ $1"; fail=$((fail + 1)); }

# ── Herramientas falsas ──────────────────────────────────────────────────────
# `xcodebuild` falso. Versión por FAKE_XCODE_VERSION. `archive` crea un archivo con
# los Info.plist que diría el real (versión FAKE_MARKETING o 4.0.0, build el de
# CURRENT_PROJECT_VERSION=); con FAKE_GENERIC_ARCHIVE=1, un archivo genérico.
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
        for p in "Products/Applications/WalkTracker.app" \
                 "Products/Applications/WalkTracker.app/PlugIns/WalkTrackerActivity.appex"; do
            mkdir -p "$archive/$p"
            plutil -create xml1 "$archive/$p/Info.plist"
            plutil -insert CFBundleShortVersionString -string "${FAKE_MARKETING:-4.0.0}" "$archive/$p/Info.plist"
            plutil -insert CFBundleVersion -string "$build" "$archive/$p/Info.plist"
        done
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
# Gates de mentira: salen con el código de GATE_SHAPE_EXIT / GATE_DOMAIN_EXIT.
make_repo() {
    local root="$WORK/repo-$1"
    mkdir -p "$root/Scripts"
    cp "$SCRIPT" "$OPTIONS" "$root/Scripts/"
    printf '#!/bin/bash\necho "gate forma" >> "$FAKE_LOG"\nexit "${GATE_SHAPE_EXIT:-0}"\n' > "$root/Scripts/check-project-shape.sh"
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
        git commit -q --allow-empty -m tres
    ) || { echo "  ⚠️  no se pudo montar el fixture" >&2; exit 1; }
    echo "$root"
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
R="$(make_repo sucio)"
echo cambio >> "$R/project.yml"
run_case "$R" --confirm v4.0.0-build.3
expect "árbol con cambios sin commit no archiva" "$R" nonzero "árbol sucio" no-gates no-archive no-upload no-tag

R="$(make_repo sin-seguimiento)"
touch "$R/nuevo.swift"
run_case "$R" --dry-run
expect "fichero sin seguimiento no archiva (tampoco en ensayo)" "$R" nonzero "árbol sucio" no-gates no-archive no-upload no-tag

# ── Rama equivocada ──────────────────────────────────────────────────────────
R="$(make_repo rama)"
git -C "$R" checkout -q -b feature/algo
run_case "$R" --confirm v4.0.0-build.3
expect "rama de feature no archiva y nombra main" "$R" nonzero "Solo se sube desde 'main'" no-gates no-archive no-upload no-tag

# ── Toolchain equivocado ─────────────────────────────────────────────────────
R="$(make_repo xcode27)"
FAKE_XCODE_VERSION=27.0 run_case "$R" --confirm v4.0.0-build.3
expect "Xcode 27 no archiva y nombra la versión encontrada" "$R" nonzero "Xcode 27.0" no-gates no-archive no-upload no-tag

R="$(make_repo xcode16)"
FAKE_XCODE_VERSION=16.4 run_case "$R" --dry-run
expect "Xcode 16 no archiva ni en ensayo" "$R" nonzero "Xcode 16.4" no-gates no-archive no-upload no-tag

# ── Etiqueta ya existe ───────────────────────────────────────────────────────
R="$(make_repo etiqueta)"
git -C "$R" tag -a v4.0.0-build.3 -m previa
PRE_TAG=v4.0.0-build.3
run_case "$R" --confirm v4.0.0-build.3
expect "etiqueta existente no archiva" "$R" nonzero "ya existe" no-gates no-archive no-upload no-tag
PRE_TAG=""

R="$(make_repo monotonia)"
git -C "$R" tag -a v4.0.0-build.9 -m "historial reescrito"
PRE_TAG=v4.0.0-build.9
run_case "$R" --confirm v4.0.0-build.3
expect "build menor que uno ya etiquetado no archiva" "$R" nonzero "no supera el mayor ya etiquetado" no-gates no-archive no-upload no-tag
PRE_TAG=""

# ── Confirmación ─────────────────────────────────────────────────────────────
R="$(make_repo sin-confirmacion)"
run_case "$R"
expect "sin terminal y sin --confirm no archiva" "$R" nonzero "--confirm v4.0.0-build.3" no-gates no-archive no-upload no-tag

R="$(make_repo confirmacion-otra)"
run_case "$R" --confirm v4.0.0-build.2
expect "--confirm de otro build no archiva" "$R" nonzero "no coincide" no-gates no-archive no-upload no-tag

# ── Gate rojo ────────────────────────────────────────────────────────────────
R="$(make_repo gate-forma)"
GATE_SHAPE_EXIT=1 run_case "$R" --confirm v4.0.0-build.3
expect "check-project-shape.sh en rojo no archiva" "$R" nonzero "check-project-shape.sh en rojo" no-archive no-upload no-tag

R="$(make_repo gate-dominio)"
GATE_DOMAIN_EXIT=1 run_case "$R" --dry-run
expect "verify-domain.sh en rojo no archiva (tampoco en ensayo)" "$R" nonzero "verify-domain.sh en rojo" no-archive no-upload no-tag

# ── Versión ──────────────────────────────────────────────────────────────────
R="$(make_repo semver)"
sed -i '' 's/"4.0.0"/"4.0"/' "$R/project.yml"
git -C "$R" commit -q -am "versión rota"
run_case "$R" --dry-run
expect "MARKETING_VERSION no SemVer no archiva" "$R" nonzero "no es SemVer" no-gates no-archive no-upload no-tag

R="$(make_repo binario-otra-version)"
FAKE_MARKETING=3.9.9 run_case "$R" --confirm v4.0.0-build.3
expect "binario con otra versión que la etiqueta no se sube" "$R" nonzero "se esperaba 4.0.0 (3)" no-upload no-tag

R="$(make_repo archivo-generico)"
FAKE_GENERIC_ARCHIVE=1 run_case "$R" --confirm v4.0.0-build.3
expect "archivo genérico (framework instalado fuera de la app) no se sube" "$R" nonzero "el archivo es genérico" no-upload no-tag

# ── Subida rechazada ─────────────────────────────────────────────────────────
R="$(make_repo rechazo)"
FAKE_EXPORT_FAIL=1 run_case "$R" --confirm v4.0.0-build.3
expect "subida rechazada no etiqueta y muestra el error" "$R" nonzero "bundle version must be higher" dest=upload no-tag

R="$(make_repo sin-cuenta)"
FAKE_EXPORT_FAIL=accounts run_case "$R" --dry-run
expect "Xcode sin cuenta de Apple falla y dice dónde añadirla" "$R" nonzero "Ajustes → Cuentas" no-upload no-tag

# ── Caminos verdes (con herramientas falsas) ─────────────────────────────────
# Sin ellos, un script que fallara siempre pasaría todo el camino rojo.
R="$(make_repo ensayo)"
git -C "$R" checkout -q -b feature/ensayo
run_case "$R" --dry-run
expect "ensayo en rama de feature exporta .ipa sin subir ni etiquetar" "$R" 0 "WalkTracker.ipa" dest=export no-upload no-tag

R="$(make_repo release)"
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
