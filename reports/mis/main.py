"""Transition shim: the installed systemd units still run `main.py serve`.

Delete once /etc/systemd/system/koyson-mis-*.service use `python -m backend serve`.
"""

from backend.main import main

raise SystemExit(main())
