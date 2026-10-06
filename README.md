# Instalar MateOS 🧉

Este repo tiene una sola función: que puedas instalar MateOS copiando **un** comando.

## Antes de empezar

Necesitás dos cosas:

1. **Una cuenta de GitHub** (gratis): https://github.com/signup
2. **La invitación a MateOS aceptada.** Te llegó un mail de GitHub que dice *"invited you"*.
   Abrilo y tocá **Accept invitation**. (Si no lo encontrás, el instalador te avisa y te
   dice dónde aceptarla.)

## Instalar

### En Mac o Linux

Abrí la app **Terminal**, pegá esto y apretá Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/businessos-hq/instalar/main/instalar.sh | bash
```

### En Windows

Abrí **PowerShell** (tocá Inicio, escribí `PowerShell`, Enter), pegá esto y apretá Enter:

```powershell
irm https://raw.githubusercontent.com/businessos-hq/instalar/main/instalar.ps1 | iex
```

## Qué va a pasar

El instalador te guía de a un paso por vez y te pregunta antes de hacer cualquier cosa
importante:

1. Instala lo que tu compu necesite (git, uv, GitHub CLI y Node), si falta. Node es para
   que las apps nuevas que te arme tu equipo tengan pantalla: si no lo puede instalar solo,
   te deja el link y sigue igual.
2. Te hace entrar a tu cuenta de GitHub: se abre el navegador y aceptás.
3. Revisa que ya tengas acceso a MateOS.
4. Crea **tu cerebro**: una copia de MateOS privada, sólo tuya, en tu cuenta de GitHub y en
   una carpeta de tu compu (por default `MateOS/mi-cerebro`, adentro de tu carpeta personal).
5. Instala MateOS y su equipo de agentes, y prepara lo necesario para tus apps nuevas (la
   primera vez tarda un poco).
6. Te ofrece instalar Claude Code, para el chat con IA (es opcional).

Al final abre MateOS en tu navegador. Para abrirlo otro día, en la Terminal (o PowerShell):

```bash
cd ~/MateOS/mi-cerebro && mateos ui
```

> **No muevas ni renombres la carpeta de tu cerebro después de instalar.** MateOS se acuerda
> de dónde está; si la movés, deja de abrir. Si ya pasó, volvé a correr el instalador.

## Si algo sale mal

- Volvé a pegar el mismo comando: lo que ya quedó hecho se saltea y sigue desde donde quedó.
- Si vuelve a fallar, mandale a quien te pasó MateOS una foto de la pantalla y el archivo de
  registro que te indica el instalador (`mateos-instalar-<fecha>.log`).

## ¿Por qué no hay nada más acá?

MateOS en sí vive en un repo privado al que te invitaron. Éste es público sólo para que el
comando de arriba funcione sin tener que entrar a ningún lado antes. No tiene datos de nadie
ni secretos: sólo los dos scripts, que podés leer antes de correrlos.

---

<details>
<summary>Para soporte</summary>

Opciones de `instalar.sh` (después de `bash -s --`) y de `instalar.ps1`:

| sh | ps1 | Qué hace |
|---|---|---|
| `--vidriera <owner/repo>` | `-Vidriera` | Plantilla de la que sale el cerebro (default `businessos-hq/mateos`) |
| `--nombre <nombre>` | `-Nombre` | Nombre del cerebro y del repo (default `mi-cerebro`) |
| `--carpeta <ruta>` | `-Carpeta` | Dónde queda (default `~/MateOS/<nombre>`) |
| `--sin-ia` | `-SinIa` | No ofrece instalar Claude Code |
| `--si` | `-Si` | No pregunta nada: acepta los defaults |

```bash
curl -fsSL https://raw.githubusercontent.com/businessos-hq/instalar/main/instalar.sh | bash -s -- --nombre mi-negocio
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/businessos-hq/instalar/main/instalar.ps1))) -Nombre mi-negocio
```

En PowerShell también se pueden pasar por variables de entorno: `MATEOS_VIDRIERA`,
`MATEOS_NOMBRE`, `MATEOS_CARPETA`, `MATEOS_SIN_IA=1`, `MATEOS_SI=1`.

Los scripts se mantienen en el repo de desarrollo de MateOS (`instalar.sh` / `instalar.ps1`
en la raíz) y se copian acá tal cual en cada cambio: no se editan en este repo.

</details>
