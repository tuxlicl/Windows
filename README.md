# 🪟 Windows PowerShell Scripts

Colección de scripts PowerShell para administración de entornos Windows, Active Directory y Microsoft 365.

![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![Microsoft 365](https://img.shields.io/badge/Microsoft_365-D83B01?style=for-the-badge&logo=microsoft-office&logoColor=white)

---

## 📁 Estructura del Repositorio

```
Windows/
├── ActiveDirectoryScript's/      # Scripts de Active Directory
│   ├── InformeSanidadAD.ps1         # Informe de sanidad del dominio AD
│   ├── InformeSanidadADFull.ps1     # Informe completo con detalles extendidos
│   ├── Informe_Auditoria_AD.ps1     # Auditoría general de Active Directory
│   ├── ReporteUsuariosAD.ps1        # Reporte de usuarios del dominio
│   └── AgregarCamposSMTPUsuariosAD.ps1  # Agregar campos SMTP a usuarios
│
├── CargaLicenciasOf365/          # Gestión de licencias Office 365
│   └── Licencias365Masiva.ps1       # Carga masiva de licencias M365
│
├── CorreoPasswordVencidaAD/      # Notificaciones de contraseñas
│   └── Notify_exp_pass_AD.ps1       # Notificar usuarios con clave por vencer
│
├── PowerShell365/                # Gestión de Microsoft 365
│   ├── AgregarLicenciaMasiva.ps1    # Asignar licencias en masa
│   └── RemoveLicenciaMasiva.ps1     # Remover licencias en masa
│
├── Powershells/                  # Scripts de uso general en servidores
│   └── Uso en Servidores/
│       ├── CrearUsuariosMasivosAD.ps1   # Crear usuarios desde CSV
│       ├── MoveFileFoldersToFolders.ps1 # Mover archivos entre carpetas
│       └── pingmasivo.ps1               # Ping masivo a lista de servidores
│
├── RepotMonthUserAD/             # Reportes mensuales
│   └── Report_User_AD.ps1           # Reporte mensual de usuarios AD
│
└── ValidaCambioHoras/            # Validación de cambio de hora
    ├── ValidaCambioHoraWindowsServer2024.ps1   # Versión 2024
    └── ValidarCambiodeHoraWindwosServer2026.ps1 # Versión 2026
```

---

## 🚀 Scripts Destacados

### 🔍 Informe de Sanidad de Active Directory
Genera un informe completo del estado del dominio: replicación, FSMO, GPOs, usuarios inactivos y más.
```powershell
.\ActiveDirectoryScript's\InformeSanidadADFull.ps1
```

### 📧 Notificación de Contraseñas por Vencer
Envía correos automáticos a usuarios cuya contraseña está próxima a expirar.
```powershell
.\CorreoPasswordVencidaAD\Notify_exp_pass_AD.ps1
```

### 🪪 Carga Masiva de Licencias Microsoft 365
Asigna licencias M365 a múltiples usuarios desde un archivo CSV.
```powershell
.\CargaLicenciasOf365\Licencias365Masiva.ps1
```

### ⏰ Validación de Cambio de Hora en Servidores
Verifica y valida la sincronización horaria en servidores Windows.
```powershell
.\ValidaCambioHoras\ValidarCambiodeHoraWindwosServer2026.ps1
```

### 👥 Creación Masiva de Usuarios en AD
Crea usuarios en Active Directory desde un archivo CSV de forma automatizada.
```powershell
.\Powershells\"Uso en Servidores"\CrearUsuariosMasivosAD.ps1
```

---

## ⚙️ Requisitos

- **PowerShell** 5.1 o superior (se recomienda PowerShell 7+)
- **Módulo ActiveDirectory** (`RSAT: Active Directory Domain Services`)
- **Módulo MSOnline / AzureAD** para scripts de M365
- **Módulo ExchangeOnlineManagement** para scripts de Exchange
- Permisos de **Domain Admin** o delegados según el script

### Instalación de módulos necesarios
```powershell
# Instalar módulo de M365
Install-Module -Name MSOnline -Force

# Instalar módulo de Azure AD
Install-Module -Name AzureAD -Force

# Instalar módulo de Exchange Online
Install-Module -Name ExchangeOnlineManagement -Force
```

---

## 📋 Uso General

1. Clonar el repositorio:
```bash
git clone https://github.com/tuxlicl/Windows.git
```

2. Abrir PowerShell como **Administrador**

3. Ejecutar el script deseado:
```powershell
cd Windows
.\ActiveDirectoryScript's\InformeSanidadAD.ps1
```

> **Nota:** Algunos scripts requieren ajustar parámetros internos (dominio, servidor SMTP, rutas de salida) antes de ejecutarlos.

---

## 👤 Autor

**Claudio Aliste R.** — Infrastructure & Connectivity Engineer | Cloud Engineer
- GitHub: [@tuxlicl](https://github.com/tuxlicl)
- LinkedIn: [in/claudioalisterequena](https://linkedin.com/in/claudioalisterequena)

---

## 📄 Licencia

Uso libre para fines educativos y de administración de sistemas. Scripts desarrollados para entornos de producción reales en Chile.
