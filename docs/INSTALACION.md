# Instalación (usuario final)

La app se entrega como un **instalador de Windows**. No necesitas Python ni configurar nada.
Hay **dos instaladores** según tu rol — ejecuta solo el que te corresponda:

| Tú eres… | Instalador | Qué te instala |
|---|---|---|
| **Equipo de gobernanza** (datos maestros) | `Instalar Gobernanza de Datos Maestros 1.0.1.exe` | **Dashboard Gobernanza** |
| **Figura que registra su avance** | `Instalar Registro de Avance - Gobernanza de Datos 1.0.1.exe` | **Importador de Decisiones** |

## Instalar

1. Ejecuta el instalador que te corresponde (tabla de arriba).
2. Se instala **por usuario** (no pide permisos de administrador) y crea **un** acceso directo
   en el Menú Inicio (y, si lo eliges, en el escritorio):
   - **Dashboard Gobernanza** — para el equipo de datos maestros, o
   - **Importador de Decisiones** — para las figuras que analizan.
3. Ábrelo desde el Menú Inicio.

Todo viene incluido (Instant Client y credenciales). Único requisito: **red al servidor
`oracle-host.example`** (VPN si aplica).

## Uso rápido

- **Dashboard:** botones para *Correr foto* (nueva corrida), *Generar Excels* de captura,
  *Actualizar* el monitoreo y *Reporte* de avance. Las tarjetas y gráficas muestran el avance.
- **Importador:** el revisor escribe su nombre, elige su rol, selecciona su Excel de captura
  (carpeta `entregables`) y da *Cargar decisiones*. Es re-ejecutable.

## Desinstalar

Panel de control → **Agregar o quitar programas** → *Gobernanza de Datos Maestros*
(equipo) o *Registro de Avance - Gobernanza de Datos* (figuras). Son independientes.

## Distribución

El instalador incluye el `.env` con la cuenta Oracle dedicada: distribúyelo **solo por
canales internos** (red interna / USB), no por correo público ni repositorios externos.

> ¿Cómo se genera el instalador? Ver **`BUILD.md`**.
