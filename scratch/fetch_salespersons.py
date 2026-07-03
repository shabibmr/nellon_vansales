import json
import os
import requests

CLIENT_ID = "1000.45EI6FPO004OW9W6BTB7TUJ9L0C0YP"
CLIENT_SECRET = "1d829f7ee3e1eb7debe6ed370ccc87ab45e7b36103"
REFRESH_TOKEN = "1000.ccb7c895a473ba5569c55565c0aed87d.c2f3a5530356193d39a19c511efed856"
ORG_ID = "783019958"
TOKEN_URL = "https://accounts.zoho.com/oauth/v2/token"
API_BASE = "https://www.zohoapis.com/books/v3"

def get_access_token() -> str:
    print("Obtaining fresh OAuth access token...")
    resp = requests.post(TOKEN_URL, params={
        "grant_type": "refresh_token",
        "refresh_token": REFRESH_TOKEN,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    })
    data = resp.json()
    if "access_token" not in data:
        raise RuntimeError(f"Failed to obtain access token: {data}")
    return data["access_token"]

def main():
    try:
        token = get_access_token()
        headers = {
            "Authorization": f"Zoho-oauthtoken {token}",
            "Content-Type": "application/json",
        }
        url = f"{API_BASE}/salespersons"
        params = {
            "organization_id": ORG_ID
        }
        
        print("Calling /salespersons endpoint...")
        resp = requests.get(url, headers=headers, params=params)
        print(f"Status Code: {resp.status_code}")
        
        data = resp.json()
        
        # Save raw JSON response
        os.makedirs("scratch", exist_ok=True)
        json_path = "scratch/salespersons.json"
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"Raw JSON response saved to {json_path}")
        
        if resp.status_code != 200:
            print(f"Error: {data}")
            return
            
        salespersons = data.get("data", []) or data.get("salespersons", [])
        print(f"\nFound {len(salespersons)} salespersons:")
        
        # Prepare CSV file
        csv_path = "scratch/salespersons.csv"
        with open(csv_path, "w", encoding="utf-8") as f:
            # Write header with '|' separator
            f.write("salesperson_id|salesperson_name|salesperson_email|is_active\n")
            for sp in salespersons:
                sp_id = sp.get("salesperson_id", "")
                name = sp.get("salesperson_name", "")
                email = sp.get("salesperson_email", "")
                is_active = sp.get("is_active", "")
                
                # Print to console
                print(f"ID: {sp_id} | Name: {name} | Email: {email} | Active: {is_active}")
                
                # Write to CSV
                f.write(f"{sp_id}|{name}|{email}|{is_active}\n")
                
        print(f"\nCSV data saved to {csv_path} (separated by '|')")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
