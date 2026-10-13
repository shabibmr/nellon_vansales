#!/usr/bin/env python3
import os
import sys
import requests
from dotenv import load_dotenv

ENV_PATH = os.path.join(os.path.dirname(__file__), "..", ".env_zoho")
load_dotenv(ENV_PATH)

def exchange(code: str, client_id: str = None, client_secret: str = None):
    client_id = client_id or os.getenv("ZOHO_CLIENT_ID")
    client_secret = client_secret or os.getenv("ZOHO_CLIENT_SECRET")
    
    if not client_id or not client_secret:
        print("Error: ZOHO_CLIENT_ID and ZOHO_CLIENT_SECRET required.")
        sys.exit(1)
        
    print(f"Exchanging code for client {client_id[:10]}...")
    url = "https://accounts.zoho.com/oauth/v2/token"
    resp = requests.post(url, data={
        "grant_type": "authorization_code",
        "client_id": client_id,
        "client_secret": client_secret,
        "code": code,
    }, timeout=30)
    
    data = resp.json()
    if "error" in data:
        print(f"Zoho error: {data.get('error')} - {data.get('error_description', '')}")
        sys.exit(1)
        
    refresh_token = data.get("refresh_token")
    if not refresh_token:
        print("Response did not contain a refresh_token:", data)
        sys.exit(1)
        
    print("Success! Received new refresh token.")
    
    lines = []
    if os.path.exists(ENV_PATH):
        with open(ENV_PATH, "r") as f:
            lines = f.readlines()
            
    updated_rt = False
    new_lines = []
    for line in lines:
        if line.startswith("ZOHO_REFRESH_TOKEN="):
            new_lines.append(f"ZOHO_REFRESH_TOKEN={refresh_token}\n")
            updated_rt = True
        elif line.startswith("ZOHO_CLIENT_ID=") and client_id:
            new_lines.append(f"ZOHO_CLIENT_ID={client_id}\n")
        elif line.startswith("ZOHO_CLIENT_SECRET=") and client_secret:
            new_lines.append(f"ZOHO_CLIENT_SECRET={client_secret}\n")
        else:
            new_lines.append(line)
            
    if not updated_rt:
        new_lines.append(f"ZOHO_REFRESH_TOKEN={refresh_token}\n")
        
    with open(ENV_PATH, "w") as f:
        f.writelines(new_lines)
        
    cache = os.path.join(os.path.dirname(__file__), "settle_runs", ".token_cache.json")
    if os.path.exists(cache):
        os.remove(cache)
        
    print(f"Updated {ENV_PATH} and removed token cache.")
    return refresh_token

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 zoho_endpoints/exchange_code.py <grant_code> [client_id] [client_secret]")
        sys.exit(1)
    code = sys.argv[1].strip()
    cid = sys.argv[2].strip() if len(sys.argv) > 2 else None
    csec = sys.argv[3].strip() if len(sys.argv) > 3 else None
    exchange(code, cid, csec)
