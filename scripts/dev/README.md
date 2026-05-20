# Dev scripts (local machine)

Run from repo root or call scripts directly (they `cd` to the repo root).

| Script | Description |
|--------|-------------|
| `setup.bat` / `setup.sh` | First-time Python venv + Flutter `pub get` |
| `start_servers.ps1` | Start kk API (:5000) and proxy (:5003) |
| `open_firewall_port.bat` | Windows firewall helper for local ports |
| `fix_firewall_port_5000.bat` | Allow inbound TCP 5000 |

Production deploy: use [`start_render.sh`](../../start_render.sh) on Render, not these scripts.
