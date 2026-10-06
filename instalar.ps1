# instalar.ps1 - el instalador de MateOS para CLIENTES (Windows / PowerShell).
#
# Es el comando que copia y pega el dueño de un negocio, sin saber nada de programación.
# En PowerShell (Inicio, escribí "PowerShell", Enter):
#
#   irm https://raw.githubusercontent.com/businessos-hq/instalar/main/instalar.ps1 | iex
#
# y de ahí en adelante todo es guiado, de a un paso por vez:
#
#   1. Las herramientas: git, uv, GitHub CLI (gh) y Node. Instala lo que falte con winget.
#      Node no frena nada si no se puede: sólo hace falta para ver las apps NUEVAS que le arme
#      su equipo (su pantalla se compila); MateOS abre igual con lo ya compilado.
#   2. Tu cuenta de GitHub: `gh auth login` por el navegador, si no entraste todavía.
#   3. El acceso a MateOS: chequea que ya aceptaste la invitación a la vidriera.
#   4. Tu cerebro: crea TU repo privado desde la plantilla y lo baja a tu compu.
#   5. Instala el comando `mateos`, prepara `frontend\` (`npm ci`, si hay Node) y activa el
#      equipo de agentes (`mateos install`).
#   6. El chat con IA: Claude Code o Codex (opcional; ofrece instalar Claude Code).
#   y al final abre `mateos ui`.
#
# Es el gemelo de instalar.sh (macOS/Linux): mismos pasos, mismos mensajes. Ver ahí la
# diferencia con install.ps1 (camino de desarrollo/soporte, repo ya clonado).
#
# Reglas del script (no aflojarlas):
# - Corre con `irm ... | iex`. Por eso NUNCA hay un `exit` suelto: bajo iex, `exit` cierra la
#   ventana de PowerShell del cliente. Los errores se tiran como excepción y los atrapa el
#   bloque final, que muestra el mensaje humano. Sólo si se corre como ARCHIVO
#   ($PSCommandPath) se devuelve un código de salida.
# - Windows PowerShell 5.1 lee un .ps1 sin BOM como ANSI: los símbolos (tilde de check, cruz,
#   el mate) se arman con [char] y en el fuente no hay rayas largas ni comillas tipográficas
#   (sus bytes UTF-8 se leen como comillas y rompen los strings). Lo cuida un test.
# - Idempotente: re-correrlo salta lo que ya está hecho (herramientas, login, repo, carpeta).
# - Nada de secretos acá: el login lo hace `gh` con el navegador y guarda él la credencial.
#
# Ojo con mover la carpeta: `uv tool install --editable` graba la RUTA ABSOLUTA de la carpeta
# del cerebro. Si después se mueve o renombra, `mateos` se rompe con `ModuleNotFoundError: No
# module named 'mateos_cli'` sin ninguna pista. Por eso el paso 4 pregunta la carpeta ANTES de
# instalar y lo advierte. Arreglo: `uv tool uninstall mateos-cli` y re-correr con -Carpeta.
#
# Parámetros (para soporte; el cliente no necesita ninguno):
#   -Vidriera <owner/repo>   Plantilla de la que sale el cerebro (default businessos-hq/mateos)
#   -Nombre <nombre>         Nombre del cerebro / de tu repo (default mi-cerebro)
#   -Carpeta <ruta>          Dónde queda (default $HOME\MateOS\<nombre>)
#   -SinIa                   No ofrece instalar Claude Code
#   -Si                      No pregunta nada: acepta todo lo que viene por default
#
# Con parámetros, en vez de `| iex`:
#   & ([scriptblock]::Create((irm <url>/instalar.ps1))) -Nombre mi-negocio
# o por variables de entorno: MATEOS_VIDRIERA, MATEOS_NOMBRE, MATEOS_CARPETA, MATEOS_SIN_IA=1,
# MATEOS_SI=1.

param(
    [string]$Vidriera = $(if ($env:MATEOS_VIDRIERA) { $env:MATEOS_VIDRIERA } else { "businessos-hq/mateos" }),
    [string]$Nombre = $env:MATEOS_NOMBRE,
    [string]$Carpeta = $env:MATEOS_CARPETA,
    [switch]$SinIa,
    [switch]$Si
)

$script:TotalPasos = 6
# Node mínimo para compilar la pantalla de una app nueva: lo pide Tailwind v4
# (@tailwindcss/oxide, engines >= 20). Mismo número que NODE_MINIMO en
# mateos_cli/web/build.py (lo ata un test).
$script:NodeMinimo = 20
$script:PasoActual = 0
$script:PasoTitulo = "la preparación"
$script:SinIa = [bool]$SinIa -or ($env:MATEOS_SIN_IA -eq "1")
$script:Si = [bool]$Si -or ($env:MATEOS_SI -eq "1")
$script:Vidriera = $Vidriera
$script:Nombre = if ($Nombre) { $Nombre } else { "" }
$script:Carpeta = if ($Carpeta) { $Carpeta } else { "" }
$script:CarpetaDefault = $false
$script:Duenio = ""
$script:ToolIa = ""
$script:Log = ""
$script:Fallo = $false

$script:CHECK = [string][char]0x2713
$script:CRUZ = [string][char]0x2717
$script:PUNTOS = [string][char]0x2026
$script:MATE = [char]::ConvertFromUtf32(0x1F9C9)

# --- Pantalla -------------------------------------------------------------------------

function Ok([string]$m)    { Write-Host "  $script:CHECK $m" -ForegroundColor Green }
function Mal([string]$m)   { Write-Host "  $script:CRUZ $m" -ForegroundColor Red }
function Aviso([string]$m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Info([string]$m)  { Write-Host "    $m" }
function Suave([string]$m) { Write-Host "    $m" -ForegroundColor DarkGray }

function Paso([int]$n, [string]$titulo) {
    $script:PasoActual = $n
    $script:PasoTitulo = $titulo
    Write-Host ""
    Write-Host "-- Paso $n de $script:TotalPasos - $titulo --" -ForegroundColor Cyan
    Write-Host ""
}

function Bienvenida {
    Write-Host ""
    Write-Host "$script:MATE Hola. Vamos a instalar MateOS en tu compu."
    Write-Host ""
    Info "Te voy a ir guiando de a un paso por vez. Son estos $($script:TotalPasos):"
    Write-Host ""
    Info "  1. Las herramientas que MateOS necesita (las instalo si faltan)"
    Info "  2. Entrar a tu cuenta de GitHub (se abre el navegador)"
    Info "  3. Revisar que ya tengas acceso a MateOS"
    Info "  4. Crear tu cerebro: una copia privada, sólo tuya"
    Info "  5. Instalar MateOS y su equipo de agentes"
    Info "  6. El chat con IA (opcional)"
    Write-Host ""
    Info "Si algo sale mal, podés volver a pegar el mismo comando: lo que ya"
    Info "está hecho se saltea y sigue desde donde quedó."
    if (-not $script:Si) {
        Write-Host ""
        EsperarEnter "Apretá Enter para empezar (o Ctrl+C para salir)."
    }
}

# --- Preguntas ------------------------------------------------------------------------

function Preguntar([string]$texto, [string]$default) {
    if ($script:Si) { return $default }
    $r = Read-Host "  ? $texto [$default]"
    if ([string]::IsNullOrWhiteSpace($r)) { return $default }
    return $r.Trim()
}

function Confirmar([string]$texto) {
    if ($script:Si) { return $true }
    while ($true) {
        $r = (Read-Host "  ? $texto [S/n]").Trim().ToLower()
        if ($r -in @("", "s", "si", "sí", "y", "yes")) { return $true }
        if ($r -in @("n", "no")) { return $false }
        Info "Contestá s (sí) o n (no)."
    }
}

function EsperarEnter([string]$texto) {
    if ($script:Si) { return }
    [void](Read-Host "  > $texto")
}

# --- Registro y errores ---------------------------------------------------------------

function PrepararLog {
    $base = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    $script:Log = Join-Path $base ("mateos-instalar-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
    "Instalador de MateOS - $(Get-Date)" | Out-File -FilePath $script:Log -Encoding utf8
}

function Registrar([string]$texto) {
    $texto | Out-File -FilePath $script:Log -Append -Encoding utf8
}

# Fallar: el error con nombre y apellido. Se tira como excepción marcada; la atrapa Principal.
function Fallar([string]$que, [string]$hacer = "") {
    $e = New-Object System.Exception $que
    $e.Data["mateos"] = $true
    $e.Data["hacer"] = $hacer
    throw $e
}

function PedirAyuda {
    Write-Host ""
    Info "Si vuelve a fallar, pedí ayuda a quien te pasó MateOS: mandale una"
    Info "foto de esta pantalla y este archivo, que tiene el detalle técnico:"
    Info "  $script:Log"
    Write-Host ""
}

# Correr: corre sin ensuciar la pantalla (todo al registro) y avisa con check o cruz.
function Correr([string]$desc, [scriptblock]$bloque) {
    Write-Host "  $script:PUNTOS $desc" -NoNewline
    Registrar "`n> $desc"
    $ok = $true
    $previo = $ErrorActionPreference
    $ErrorActionPreference = "Continue"   # en 5.1, el stderr de un nativo con Stop es excepción
    try {
        $global:LASTEXITCODE = 0
        & $bloque 2>&1 | Out-File -FilePath $script:Log -Append -Encoding utf8
        if ($LASTEXITCODE -ne 0) { $ok = $false }
    }
    catch {
        Registrar ($_ | Out-String)
        $ok = $false
    }
    finally {
        $ErrorActionPreference = $previo
    }
    Write-Host "`r" -NoNewline
    if ($ok) { Ok $desc } else { Mal $desc }
    return $ok
}

# Corre un nativo en silencio y dice si salió bien.
function Silencioso([scriptblock]$bloque) {
    $previo = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $global:LASTEXITCODE = 0
        & $bloque 2>&1 | Out-File -FilePath $script:Log -Append -Encoding utf8
        return ($LASTEXITCODE -eq 0)
    }
    catch { return $false }
    finally { $ErrorActionPreference = $previo }
}

function Hay([string]$cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# winget y los instaladores oficiales dejan el PATH nuevo en el registro: esta ventana no lo
# ve hasta que se relee. ($env:PATH y PathSeparator, no "Path" y ";": así corre igual en el
# pwsh de Linux con el que se testea.)
function RefrescarPath {
    $sep = [System.IO.Path]::PathSeparator
    $maquina = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $usuario = [Environment]::GetEnvironmentVariable("Path", "User")
    $extra = @((Join-Path (Join-Path $HOME ".local") "bin"), (Join-Path (Join-Path $HOME ".cargo") "bin"))
    $env:PATH = (@($env:PATH, $maquina, $usuario) + $extra | Where-Object { $_ }) -join $sep
}

# --- Paso 1: herramientas -------------------------------------------------------------

function AsegurarWinget([string]$que) {
    if (Hay "winget") { return $true }
    Aviso "No encuentro winget (el instalador de programas de Windows) para instalar $que."
    Info "Actualizá 'Instalador de aplicación' desde la Microsoft Store, o instalá"
    Info "$que a mano desde el link que te paso."
    return $false
}

function InstalarConWinget([string]$id, [string]$que) {
    if (-not (AsegurarWinget $que)) { return $false }
    Info "Windows te puede preguntar si permitís que haga cambios: decile que sí."
    $r = Correr "Instalando $que" { winget install --id $id -e --source winget --accept-package-agreements --accept-source-agreements --silent }
    RefrescarPath
    return $r
}

function EsperarHerramienta([string]$cmd, [string]$que, [string]$link) {
    $intento = 0
    while (-not (Hay $cmd)) {
        $intento++
        if ($script:Si -or $intento -gt 3) {
            Fallar "Todavía no encuentro $que." "Bajalo de $link, instalalo y volvé a pegar el comando."
        }
        Aviso "No pude instalar $que solo."
        Info "Bajalo de $link, instalalo como cualquier programa y volvé a esta ventana."
        EsperarEnter "Cuando esté instalado, apretá Enter."
        RefrescarPath
    }
}

function AsegurarGit {
    if (Hay "git") { Ok "git ya está instalado (guarda el historial de tu cerebro)."; return }
    Info "Falta git: es el programa que guarda el historial de tu cerebro."
    [void](InstalarConWinget "Git.Git" "git")
    EsperarHerramienta "git" "git" "https://git-scm.com/download/win"
    Ok "git instalado."
}

function AsegurarUv {
    RefrescarPath
    if (Hay "uv") { Ok "uv ya está instalado (instala MateOS sin tocar el resto de tu compu)."; return }
    Info "Falta uv: instala MateOS aislado, sin tocar el resto de tu compu."
    $ok = Correr "Instalando uv (instalador oficial)" {
        powershell -NoProfile -ExecutionPolicy ByPass -Command "irm https://astral.sh/uv/install.ps1 | iex"
    }
    RefrescarPath
    if (-not $ok -or -not (Hay "uv")) {
        Fallar "No pude instalar uv." "Revisá tu conexión a internet, cerrá PowerShell, abrí uno nuevo y volvé a pegar el comando."
    }
    Ok "uv instalado."
}

function AsegurarGh {
    if (Hay "gh") { Ok "GitHub CLI ya está instalado (conecta tu compu con tu cuenta de GitHub)."; return }
    Info "Falta GitHub CLI (gh): conecta tu compu con tu cuenta de GitHub, que"
    Info "es donde se guarda tu cerebro."
    [void](InstalarConWinget "GitHub.cli" "GitHub CLI")
    EsperarHerramienta "gh" "GitHub CLI" "https://cli.github.com"
    Ok "GitHub CLI instalado."
}

# Node: para que las apps nuevas que le arme su equipo al cliente tengan pantalla (su UI se
# compila adentro de la interfaz). NO frena la instalación: sin Node, MateOS abre igual con
# lo ya compilado. Por eso acá nunca hay Fallar.

# El número mayor del Node instalado (0 si no está o no contesta).
function MayorNode {
    if (-not (Hay "node")) { return 0 }
    $previo = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $v = (node --version 2>$null | Out-String).Trim() } catch { $v = "" }
    finally { $ErrorActionPreference = $previo }
    if ($v -match '^v(\d+)\.') { return [int]$Matches[1] }
    return 0
}

function NodeAlcanza { return ((MayorNode) -ge $script:NodeMinimo) }

# npm.cmd y no npm: con la política de ejecución por default de Windows, `npm` resuelve a
# npm.ps1 y PowerShell se niega a correrlo ("la ejecución de scripts está deshabilitada").
function ComandoNpm {
    if (Get-Command "npm.cmd" -ErrorAction SilentlyContinue) { return "npm.cmd" }
    if (Hay "npm") { return "npm" }
    return ""
}

function AsegurarNode {
    RefrescarPath
    if (NodeAlcanza) { Ok "Node ya está instalado (para que las apps nuevas que te arme tu equipo tengan pantalla)."; return }
    $previo = MayorNode
    if ($previo -gt 0) {
        Info "Tenés Node $previo, pero las apps nuevas necesitan Node $($script:NodeMinimo) o más nuevo."
    }
    else {
        Info "Falta Node: para que las apps nuevas que te arme tu equipo tengan pantalla."
    }
    [void](InstalarConWinget "OpenJS.NodeJS.LTS" "Node")
    if (NodeAlcanza) { Ok "Node instalado."; return }
    Aviso "No pude instalar Node solo. MateOS anda igual: Node sólo hace falta"
    Info "para ver las apps nuevas que te arme tu equipo."
    Info "Bajalo de https://nodejs.org (el botón que dice LTS), instalalo como"
    Info "cualquier programa y volvé a esta ventana."
    if (-not $script:Si) {
        EsperarEnter "Cuando esté instalado apretá Enter (o Enter directo para seguir sin Node)."
        RefrescarPath
        if (NodeAlcanza) { Ok "Node instalado."; return }
    }
    Suave "Sigo sin Node. Lo sumás cuando quieras volviendo a correr este instalador."
}

# --- Paso 2: login --------------------------------------------------------------------

function AsegurarLogin {
    if (Silencioso { gh auth status }) {
        Ok "Ya entraste a GitHub."
    }
    else {
        if ($script:Si) {
            Fallar "No entraste a GitHub todavía." "Corré: gh auth login --web --git-protocol https y volvé a correr el instalador."
        }
        Info "Ahora entrás a tu cuenta de GitHub. Va a pasar esto:"
        Info "  1. Te muestro un código de 8 letras: copialo."
        Info "  2. Apretá Enter y se abre el navegador."
        Info "  3. Pegá el código y tocá Authorize (Autorizar)."
        Write-Host ""
        $global:LASTEXITCODE = 0
        gh auth login --web --git-protocol https --hostname github.com
        if ($LASTEXITCODE -ne 0) {
            Fallar "No se pudo completar la entrada a GitHub." "Volvé a pegar el comando y repetí el paso del navegador. Si no tenés cuenta, creala gratis en https://github.com/signup"
        }
        Ok "Entraste a GitHub."
    }
    if (-not (Correr "Conectando git con tu cuenta" { gh auth setup-git })) {
        Fallar "No pude conectar git con tu cuenta de GitHub." "Volvé a pegar el comando."
    }
    $previo = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $script:Duenio = (gh api user --jq .login 2>$null | Out-String).Trim() } catch { $script:Duenio = "" }
    finally { $ErrorActionPreference = $previo }
    if (-not $script:Duenio) {
        Fallar "No pude saber cuál es tu usuario de GitHub." "Revisá tu conexión a internet y volvé a pegar el comando."
    }
    Suave "Tu usuario: $script:Duenio"
}

# --- Paso 3: acceso a la vidriera -----------------------------------------------------

function AsegurarAccesoVidriera {
    $v = $script:Vidriera
    while (-not (Silencioso { gh api "repos/$v" })) {
        Mal "Todavía no tenés acceso a MateOS."
        Info "Lo más probable es que no hayas aceptado la invitación. Revisá tu mail"
        Info "(buscá 'invited you' de GitHub) o entrá a:"
        Info "  https://github.com/$v/invitations"
        Info "y tocá Accept invitation (Aceptar)."
        if ($script:Si) { Fallar "Sin acceso a $v." "Aceptá la invitación y volvé a correr el instalador." }
        EsperarEnter "Cuando la aceptes, apretá Enter y pruebo de nuevo."
    }
    Ok "Tenés acceso a MateOS."
}

# --- Paso 4: el repo propio -----------------------------------------------------------

function NombreValido([string]$n) {
    return ($n -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') -and ($n.Length -le 60)
}

function CarpetaPorDefault([string]$n) { return (Join-Path (Join-Path "~" "MateOS") $n) }

function ExpandirRuta([string]$r) {
    if ($r -eq "~") { return $HOME }
    if ($r.StartsWith("~\") -or $r.StartsWith("~/")) { return (Join-Path $HOME $r.Substring(2)) }
    if ([System.IO.Path]::IsPathRooted($r)) { return $r }
    return (Join-Path (Get-Location).Path $r)
}

function EsMiClon([string]$c) {
    if (-not (Test-Path (Join-Path $c ".git"))) { return $false }
    $previo = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $url = (git -C $c remote get-url origin 2>$null | Out-String).Trim() } catch { $url = "" }
    finally { $ErrorActionPreference = $previo }
    $base = "github.com/$($script:Duenio)/$($script:Nombre)"
    return ($url -eq "https://$base.git") -or ($url -eq "https://$base") -or ($url -like "*github.com:$($script:Duenio)/$($script:Nombre).git")
}

function CarpetaLibre([string]$c) {
    if (-not (Test-Path $c)) { return $true }
    if (-not (Test-Path $c -PathType Container)) { return $false }
    return -not (Get-ChildItem -Force -LiteralPath $c | Select-Object -First 1)
}

function ElegirNombreYCarpeta {
    Info "Tu cerebro es una copia de MateOS sólo tuya: un repo PRIVADO en tu"
    Info "cuenta de GitHub, más una carpeta en esta compu."
    Write-Host ""
    while ($true) {
        if (-not $script:Nombre) {
            $script:Nombre = Preguntar "¿Cómo le ponemos? (minúsculas, números y guiones)" "mi-cerebro"
        }
        if (NombreValido $script:Nombre) { break }
        Mal "'$($script:Nombre)' no sirve: usá sólo minúsculas, números y guiones (ej: mi-negocio)."
        if ($script:Si) { Fallar "Nombre inválido." "Pasá otro con -Nombre." }
        $script:Nombre = ""
    }
    while ($true) {
        if (-not $script:Carpeta) {
            $def = CarpetaPorDefault $script:Nombre
            $script:Carpeta = Preguntar "¿En qué carpeta lo guardo?" $def
            if ($script:Carpeta -eq $def) { $script:CarpetaDefault = $true }
        }
        $script:Carpeta = ExpandirRuta $script:Carpeta
        $padre = Split-Path -Parent $script:Carpeta
        try { New-Item -ItemType Directory -Force -Path $padre -ErrorAction Stop | Out-Null }
        catch {
            Mal "No puedo crear carpetas en $padre."
            if ($script:Si) { Fallar "Carpeta inválida." "Pasá otra con -Carpeta." }
            $script:Carpeta = ""
            $script:CarpetaDefault = $false
            continue
        }
        if ((EsMiClon $script:Carpeta) -or (CarpetaLibre $script:Carpeta)) { break }
        Mal "La carpeta $($script:Carpeta) ya existe y tiene otras cosas adentro."
        if ($script:Si) { Fallar "Carpeta ocupada." "Pasá otra con -Carpeta." }
        Info "Elegí otra (por ejemplo $(CarpetaPorDefault "$($script:Nombre)-2"))."
        $script:Carpeta = ""
    }
    Aviso "Importante: después de instalar, no muevas ni le cambies el nombre a"
    Info "esta carpeta. MateOS se acuerda de dónde está y, si la movés, deja de"
    Info "abrir. (Si te pasa, volvé a correr este instalador.)"
}

function RepoExiste {
    $r = "$($script:Duenio)/$($script:Nombre)"
    return (Silencioso { gh repo view $r --json name })
}

function EsperarRepoListo([string]$url) {
    # GitHub arma el repo desde la plantilla en segundo plano: unos segundos sin ramas.
    for ($i = 0; $i -lt 30; $i++) {
        $previo = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try { $ramas = (git ls-remote --heads $url 2>$null | Out-String).Trim() } catch { $ramas = "" }
        finally { $ErrorActionPreference = $previo }
        if ($ramas) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function ChequearQueEsMateos {
    $py = Join-Path $script:Carpeta "pyproject.toml"
    if (-not ((Test-Path $py) -and (Select-String -Path $py -Pattern '^name = "mateos-cli"' -Quiet))) {
        Fallar "El repo '$($script:Nombre)' no parece un MateOS." "Volvé a correr el instalador y elegí otro nombre para tu cerebro."
    }
}

function AsegurarRepoPropio {
    if (EsMiClon $script:Carpeta) {
        Ok "Tu cerebro ya está en $($script:Carpeta) (lo dejo como está)."
        ChequearQueEsMateos
        return
    }
    while (RepoExiste) {
        Aviso "Ya tenés un repo que se llama '$($script:Nombre)' en tu GitHub."
        if (Confirmar "¿Es tu cerebro de MateOS y querés usar ése?") { break }
        $script:Nombre = ""
        while (-not $script:Nombre -or -not (NombreValido $script:Nombre)) {
            $script:Nombre = Preguntar "Entonces, ¿qué otro nombre le ponemos?" "mi-cerebro-2"
        }
        if ($script:CarpetaDefault) { $script:Carpeta = ExpandirRuta (CarpetaPorDefault $script:Nombre) }
        if (-not (CarpetaLibre $script:Carpeta) -and -not (EsMiClon $script:Carpeta)) {
            Fallar "La carpeta $($script:Carpeta) ya existe y tiene otras cosas adentro." "Volvé a pegar el comando y elegí otra carpeta."
        }
        if (EsMiClon $script:Carpeta) {
            Ok "Tu cerebro ya está en $($script:Carpeta) (lo dejo como está)."
            ChequearQueEsMateos
            return
        }
    }
    $url = "https://github.com/$($script:Duenio)/$($script:Nombre).git"
    if (-not (RepoExiste)) {
        $n = $script:Nombre
        $v = $script:Vidriera
        if (-not (Correr "Creando tu repo privado '$n' desde la plantilla" { gh repo create $n --template $v --private })) {
            Fallar "No pude crear tu repo en GitHub." "Revisá que tengas acceso a MateOS (paso 3) y volvé a pegar el comando."
        }
        Write-Host "  $script:PUNTOS Esperando que GitHub lo termine de armar" -NoNewline
        $listo = EsperarRepoListo $url
        Write-Host "`r" -NoNewline
        if (-not $listo) {
            Mal "Esperando que GitHub lo termine de armar"
            Fallar "GitHub está tardando en armar tu repo." "Esperá un minuto y volvé a pegar el comando (va a usar el repo que ya se creó)."
        }
        Ok "Esperando que GitHub lo termine de armar"
    }
    $c = $script:Carpeta
    if (-not (Correr "Bajando tu cerebro a $c" { git clone $url $c })) {
        Fallar "No pude bajar tu repo a la compu." "Revisá tu conexión y volvé a pegar el comando."
    }
    ChequearQueEsMateos
    Ok "Tu cerebro está listo en $c"
}

# --- Paso 5: instalar MateOS ----------------------------------------------------------

function DetectarIa {
    if (Hay "claude") { $script:ToolIa = "claude" }
    elseif (Hay "codex") { $script:ToolIa = "codex" }
    else { $script:ToolIa = "" }
}

function InstalarMateos {
    $c = $script:Carpeta
    Push-Location $c
    try {
        if (-not (Correr "Instalando MateOS (la primera vez tarda unos minutos)" { uv tool install --editable ".[completo]" --force })) {
            Fallar "No pude instalar MateOS." "Revisá tu conexión a internet y volvé a pegar el comando."
        }
        $previo = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $bin = (uv tool dir --bin 2>$null | Out-String).Trim()
            if ($bin) { $env:PATH = $bin + [System.IO.Path]::PathSeparator + $env:PATH }
            uv tool update-shell 2>&1 | Out-File -FilePath $script:Log -Append -Encoding utf8
        }
        catch {}
        finally { $ErrorActionPreference = $previo }
        if (-not (Hay "mateos")) {
            Fallar "MateOS se instaló, pero esta ventana todavía no lo ve." "Cerrá PowerShell, abrí uno nuevo y volvé a pegar el comando."
        }
        PrepararApps
        if (Silencioso { mateos verificar --sin-ping }) {
            Ok "Revisé tu compu: está todo en orden."
        }
        else {
            Aviso "Revisé tu compu y hay algo para mirar más adelante (no frena nada)."
        }
        $tool = if ($script:ToolIa -eq "codex") { "codex" } else { "claude" }
        if (-not (Correr "Activando tu equipo de agentes" { mateos install --tool $tool })) {
            Fallar "No pude activar el equipo de agentes." "Volvé a pegar el comando."
        }
    }
    finally {
        Pop-Location
    }
}

# Baja las piezas para compilar la pantalla de las apps nuevas (frontend\node_modules). No es
# bloqueante: sin esto MateOS anda igual con el static/ versionado, y `mateos ui` lo reintenta
# solo cuando haga falta. Idempotente: si ya están, no se rehace (npm ci borra y re-baja todo).
function PrepararApps {
    $frontend = Join-Path $script:Carpeta "frontend"
    if (-not (Test-Path (Join-Path $frontend "package.json"))) { return }
    $npm = ComandoNpm
    if (-not (NodeAlcanza) -or -not $npm) {
        Suave "Sin Node, salteo lo de las apps nuevas (MateOS anda igual)."
        return
    }
    $bin = Join-Path (Join-Path $frontend "node_modules") ".bin"
    $hayVite = (Test-Path (Join-Path $bin "vite")) -or (Test-Path (Join-Path $bin "vite.cmd"))
    $hayTsc = (Test-Path (Join-Path $bin "tsc")) -or (Test-Path (Join-Path $bin "tsc.cmd"))
    if ($hayVite -and $hayTsc) { Ok "Lo necesario para tus apps nuevas ya está preparado."; return }
    $sub = if (Test-Path (Join-Path $frontend "package-lock.json")) { "ci" } else { "install" }
    Push-Location $frontend
    try {
        $ok = Correr "Preparando lo necesario para tus apps nuevas (tarda un poco la primera vez)" { & $npm $sub --no-audit --no-fund }
    }
    finally { Pop-Location }
    if (-not $ok) {
        Aviso "No pude prepararlo ahora (suele ser la conexión). No frena nada: MateOS"
        Info "lo vuelve a intentar solo la primera vez que tu equipo te arme una app nueva."
    }
}

# --- Paso 6: IA -----------------------------------------------------------------------

function AsegurarIa {
    if ($script:ToolIa -eq "claude") { Ok "Ya tenés Claude Code: el chat con IA va a andar."; return }
    if ($script:ToolIa -eq "codex") { Ok "Ya tenés Codex: el chat con IA va a andar."; return }
    if ($script:SinIa) { Suave "Salteado (-SinIa). El chat con IA se puede sumar cuando quieras."; return }
    Info "El chat con IA de MateOS necesita Claude Code (de Anthropic). Sin eso,"
    Info "MateOS anda igual: la bienvenida guiada no lo necesita."
    if (-not (Confirmar "¿Instalo Claude Code ahora?")) {
        Suave "Dale. Cuando quieras sumarlo: https://claude.ai/download"
        return
    }
    $ok = Correr "Instalando Claude Code (instalador oficial)" {
        powershell -NoProfile -ExecutionPolicy ByPass -Command "irm https://claude.ai/install.ps1 | iex"
    }
    RefrescarPath
    if (-not $ok) {
        Aviso "No pude instalar Claude Code. MateOS anda igual; lo podés sumar después"
        Info "desde https://claude.ai/download"
        return
    }
    if (-not (Hay "claude")) {
        Aviso "Claude Code quedó instalado; vas a poder usarlo cuando abras un"
        Info "PowerShell nuevo."
        return
    }
    Ok "Claude Code instalado."
    Info "La primera vez tenés que entrar con tu cuenta de Claude: abrí"
    Info "PowerShell, escribí claude y seguí los pasos. Al terminar, escribí /exit."
    if (-not $script:Si -and (Confirmar "¿Entrás ahora?")) {
        Info "Cuando hayas entrado, escribí /exit para volver acá."
        Push-Location $script:Carpeta
        try { claude } catch {} finally { Pop-Location }
        Ok "Listo con Claude Code."
    }
}

# --- Final ----------------------------------------------------------------------------

function Despedida {
    $script:PasoTitulo = "el final"
    $c = $script:Carpeta
    Write-Host ""
    Write-Host "-- Listo $script:MATE --" -ForegroundColor Green
    Write-Host ""
    Info "MateOS quedó instalado en: $c"
    Write-Host ""
    Info "Para abrirlo cualquier día, abrí PowerShell y escribí:"
    Write-Host ""
    Write-Host "      cd `"$c`"; mateos ui" -ForegroundColor White
    Write-Host ""
    Info "(Si en un PowerShell nuevo no reconoce 'mateos', cerralo y abrí otro.)"
    Write-Host ""
    if (Confirmar "¿Lo abro ahora?") {
        Info "Se abre en el navegador. Para cerrarlo, volvé acá y apretá Ctrl+C."
        Set-Location $c
        mateos ui
    }
    else {
        Info "Dale. ¡Que lo disfrutes!"
    }
}

# --- Principal ------------------------------------------------------------------------

function Principal {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
    if ($script:Vidriera -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        Fallar "La vidriera tiene que tener la forma dueño/repo (me llegó '$($script:Vidriera)')."
    }
    if ($script:Nombre -and -not (NombreValido $script:Nombre)) {
        Fallar "El nombre '$($script:Nombre)' no sirve." "Usá minúsculas, números y guiones (ej: mi-cerebro)."
    }
    Bienvenida

    Paso 1 "Las herramientas"
    AsegurarGit
    AsegurarUv
    AsegurarGh
    AsegurarNode

    Paso 2 "Tu cuenta de GitHub"
    AsegurarLogin

    Paso 3 "El acceso a MateOS"
    AsegurarAccesoVidriera

    Paso 4 "Tu cerebro"
    ElegirNombreYCarpeta
    AsegurarRepoPropio

    Paso 5 "Instalar MateOS"
    DetectarIa
    InstalarMateos

    Paso 6 "El chat con IA"
    AsegurarIa

    Despedida
}

$ErrorActionPreference = "Stop"
PrepararLog
try {
    Principal
}
catch {
    $script:Fallo = $true
    $ex = $_.Exception
    Write-Host ""
    if ($ex.Data["mateos"]) {
        Mal $ex.Message
        if ($ex.Data["hacer"]) { Info $ex.Data["hacer"] }
    }
    else {
        Registrar ($_ | Out-String)
        Mal "Algo salió mal en el paso $($script:PasoActual) ($($script:PasoTitulo))."
        Info "Probá volver a pegar el mismo comando: lo que ya quedó hecho se"
        Info "saltea y sigue desde acá."
    }
    PedirAyuda
}
# Sólo como archivo (.\instalar.ps1) se devuelve un código: bajo `iex` cerraría la ventana.
if ($script:Fallo -and $PSCommandPath) { exit 1 }
