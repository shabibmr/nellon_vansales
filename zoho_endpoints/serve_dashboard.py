"""
Lightweight local HTTP server for the Zoho Aged-Debt Settlement Dashboard.
Serves dashboard.html and dynamically streams live progress from settle_runs/*.csv
"""
import glob
import http.server
import json
import os
import socketserver

PORT = 8765
RUNS_DIR = os.path.join(os.path.dirname(__file__), "settle_runs")
HTML_FILE = os.path.join(os.path.dirname(__file__), "dashboard.html")


def get_latest_status():
    csv_files = glob.glob(os.path.join(RUNS_DIR, "settle_log_*.csv"))
    if not csv_files:
        return {
            "rows": [],
            "totalOk": 0,
            "totalSkip": 0,
            "totalFail": 0,
            "totalApplied": 0.0,
            "startTimeIso": None,
        }

    latest_csv = max(csv_files, key=os.path.getmtime)
    rows = []
    try:
        with open(latest_csv, encoding="utf-8-sig") as f:
            lines = [l.strip().split("|") for l in f.readlines()]
        if len(lines) > 1:
            header = lines[0]
            for r in lines[1:]:
                if len(r) == len(header):
                    rows.append(dict(zip(header, r)))
                elif len(r) > 10:
                    padded = r + [""] * (len(header) - len(r))
                    rows.append(dict(zip(header, padded[:len(header)])))
    except Exception as e:
        print(f"Error reading CSV {latest_csv}: {e}")

    total_ok = sum(1 for r in rows if r.get("status") == "OK")
    total_skip = sum(1 for r in rows if r.get("status") == "SKIP")
    total_fail = sum(1 for r in rows if r.get("status") == "FAIL")
    total_applied = sum(float(r.get("amount_applied") or 0) for r in rows if r.get("status") == "OK")
    start_time = rows[0].get("timestamp") if rows else None

    return {
        "rows": rows,
        "totalOk": total_ok,
        "totalSkip": total_skip,
        "totalFail": total_fail,
        "totalApplied": round(total_applied, 2),
        "startTimeIso": start_time,
        "logFile": os.path.basename(latest_csv),
    }


class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/status":
            data = get_latest_status()
            payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        if self.path in ("/", "/index.html", "/dashboard.html"):
            try:
                with open(HTML_FILE, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return
            except Exception as e:
                self.send_error(500, f"Error reading dashboard: {e}")
                return

        super().do_GET()

    def log_message(self, format, *args):
        # Quiet logger to avoid spamming the console
        pass


def main():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), DashboardHandler) as httpd:
        print(f"==================================================")
        print(f" Live Dashboard running at: http://localhost:{PORT}")
        print(f"==================================================")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
