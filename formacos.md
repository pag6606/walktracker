# WalkTracker — Guía de Instalación para macOS

Esta guía instala todos los prerequisitos necesarios para desarrollar WalkTracker en macOS, incluyendo la futura migración a Capacitor (iOS nativa).

## Prerequisitos

| Herramienta | Versión mínima | Para qué |
|---|---|---|
| **Xcode** | 15.0+ | Compilar iOS, simulator |
| **Node.js** | 20 LTS+ | Capacitor CLI, npm |
| **Git** | 2.40+ | Control de versiones |
| **Apple Developer** | Cuenta activa ($99/año) | Firmar app en dispositivo físico |

---

## 1. Instalar Homebrew (gestor de paquetes)

Homebrew es el gestor de paquetes de macOS. Si ya lo tienes, salta al paso 2.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Verificar:

```bash
brew --version
```

> **Apple Silicon (M1/M2/M3):** si Homebrew se instala en `/opt/homebrew`, añádelo al PATH:
> ```bash
> echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
> eval "$(/opt/homebrew/bin/brew shellenv)"
> ```

---

## 2. Instalar Git

macOS incluye Git, pero conviene tener la versión más reciente vía Homebrew:

```bash
brew install git
```

Verificar:

```bash
git --version
```

### Configurar Git (solo primera vez)

```bash
git config --global user.name "Paul Alarcón"
git config --global user.email "tu-email@gmail.com"
```

---

## 3. Instalar Node.js

```bash
brew install node@20
```

Verificar:

```bash
node --version   # debe mostrar v20.x.x o superior
npm --version    # debe mostrar 10.x.x o superior
```

> **Alternativa con nvm (recomendado si manejas múltiples proyectos):**
> ```bash
> brew install nvm
> mkdir ~/.nvm
> echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zprofile
> echo '[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"' >> ~/.zprofile
> source ~/.zprofile
> nvm install 20
> nvm use 20
> ```

---

## 4. Instalar Xcode

### Desde la Mac App Store (recomendado)

1. Abrir **App Store** en el Mac
2. Buscar **Xcode**
3. Instalar (pesa ~12 GB, requiere tiempo)

### Desde la web (descarga directa)

1. Ir a [developer.apple.com/download](https://developer.apple.com/download/all/)
2. Descargar el `.xip` más reciente
3. Doble clic para descomprimir
4. Mover `Xcode.app` a `/Applications`

### Verificar instalación

```bash
xcode-select --install
xcodebuild -version   # debe mostrar Xcode 15.x
```

### Aceptar licencia

```bash
sudo xcodebuild -license accept
```

---

## 5. Instalar CocoaPods (requerido por Capacitor)

CocoaPods es el gestor de dependencias de iOS. Capacitor lo necesita para instalar plugins nativos.

```bash
sudo gem install cocoapods
```

Verificar:

```bash
pod --version   # debe mostrar 1.15.x o superior
```

> **Apple Silicon:** si hay problemas con `ffi`, instalar primero:
> ```bash
> brew install ffi
> sudo arch -x86_64 gem install ffi
> sudo arch -x86_64 gem install cocoapods
> ```

---

## 6. Configurar cuenta Apple Developer

1. Ir a [developer.apple.com](https://developer.apple.com)
2. Iniciar sesión con tu Apple ID
3. Si no tienes membresía: unirse al **Apple Developer Program** ($99/año)
4. En Xcode: **Settings → Accounts → Add Apple ID**

### Crear Signing Certificate (automático)

Xcode crea el certificado automáticamente la primera vez que compilas para un dispositivo físico:

1. Conectar el iPhone al Mac vía USB
2. Abrir Xcode → Window → Devices and Simulators
3. Seleccionar el iPhone → confiar en el computador en el iPhone
4. En el proyecto: **Signing & Capabilities → Team → tu cuenta**

---

## 7. Clonar el proyecto

```bash
cd ~/Documentos/dev    # o el directorio que prefieras
git clone https://github.com/pag6606/walktracker.git
cd walktracker
```

---

## 8. Verificar que todo funciona

### Probar la app web (sin Xcode)

```bash
python3 -m http.server 8000
# Abrir http://localhost:8000 en Safari
```

### Probar los tests del dominio

```bash
node test/domain-tests.js
# Debe mostrar: 51 passed, 0 failed
```

---

## 9. Instalar Capacitor (para la migración a iOS nativa)

> Solo cuando vayas a ejecutar el Plan Capacitor (v2.0). No es necesario para el rediseño UI.

```bash
# En la raíz del proyecto
npm init -y
npm install @capacitor/core
npm install -D @capacitor/cli
npx cap init "WalkTracker" "com.pag6606.walktracker" --web-dir=.

# Añadir plataforma iOS
npm install @capacitor/ios
npx cap add ios

# Sincronizar
npx cap sync

# Abrir en Xcode
npx cap open ios
```

### Plugins nativos (del Plan Capacitor)

```bash
# Wake Lock nativo
npm install @capacitor-community/keep-awake

# HealthKit (verificar paquete disponible o escribir custom)
# npm install capacitor-healthkit  # confirmar existencia

# Pedometer background (plugin custom — ver Story M-2)
# Se escribe en Swift dentro del proyecto Xcode
```

---

## Checklist final

Antes de empezar a desarrollar, verifica:

```bash
# Ejecuta estos comandos y confirma que todos responden
brew --version          # ✅ Homebrew
git --version           # ✅ Git
node --version          # ✅ Node.js 20+
npm --version           # ✅ npm
xcodebuild -version     # ✅ Xcode 15+
pod --version           # ✅ CocoaPods
python3 --version       # ✅ Python 3 (para servidor local)
```

Si todos responden, **estás listo para desarrollar WalkTracker en macOS**. 🚀

---

## Troubleshooting

### `xcode-select: error: command line tools are already installed`

```bash
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

### CocoaPods falla con `SDK "iphoneos" cannot be located`

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo pod install
```

### `npx cap add ios` falla con error de CocoaPods

```bash
cd ios/App
pod install
cd ../..
npx cap sync
```

### El iPhone no aparece en Xcode

1. iPhone conectado vía USB
2. iPhone → Settings → Privacy & Security → Developer Mode → **ON**
3. Confiar en el computador cuando el iPhone lo pida
4. Xcode → Window → Devices and Simulators → debería aparecer
