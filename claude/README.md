# Configuración de Claude Code

Copia de la configuración personal de Claude Code. La skill `crear-tutorial` vive en [`../skills/crear-tutorial`](../skills/crear-tutorial/SKILL.md).

| Fichero | Destino en un equipo nuevo |
|---|---|
| `CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `settings.example.json` | Base para `~/.claude/settings.json` (modelo, tema, interfaz y línea de estado) |
| `statusline-command.sh` | `~/.claude/statusline-command.sh` |
| `memory/` | `~/.claude/projects/<carpeta-del-proyecto>/memory/` (la carpeta se llama como la ruta del repositorio, con `-` en lugar de separadores) |
| `../skills/crear-tutorial` | Enlace simbólico `~/.claude/skills/crear-tutorial` |

Recrear el enlace de la skill:

```bash
# Git Bash, con modo desarrollador de Windows activado o como administrador
ln -s "$HOME/GitRepos/Learning/skills/crear-tutorial" "$HOME/.claude/skills/crear-tutorial"
```

## Fuera de la copia

- Credenciales, historial de sesiones y permisos locales (`.credentials.json`, `history.jsonl`, `settings.local.json`).
- Las reglas de modo automático y los hooks de `settings.json`, que contienen datos de proyectos de empresa.
- Las skills y comandos de la empresa.
