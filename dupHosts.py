import requests
import csv
import urllib3

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# File paths
server_file = "C:\\temp\\Audit\\NagiosServerWithAPIs.csv"
hosts_file = "C:\\temp\\Audit\\Audit.txt"
output_file = "C:\\temp\\Audit\\Audit_New_including_all_servers_26July.csv"

# Read target hosts
with open(hosts_file, 'r', encoding='utf-8') as f:
    target_hosts = {line.strip().lower() for line in f if line.strip()}

results = []
found_hosts = set()
seen_servers = set()

# Function to get services
def service_details(hostname, url, apikey):
    base_url = (
        f"{url}/nagiosxi/api/v1/objects/servicestatus"
        f"?apikey={apikey}&host_name={hostname}&pretty=1"
    )
    try:
        response = requests.get(base_url, verify=False)
        response.raise_for_status()
        data = response.json()
        services = data.get('servicestatus', [])
        return services
    except requests.RequestException as e:
        print(f"Error contacting Nagios XI API: {e}")
        return []

# Read Nagios server config
with open(server_file, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        server = row['server_name'].strip().lower()
        api_key = row['api_key'].strip()

        if not server or not api_key or server in seen_servers:
            continue
        seen_servers.add(server)

        print(f"🔍 Checking server: {server}")

        url = f"https://{server}/nagiosxi/api/v1/config/host"
        params = {
            "apikey": api_key,
            "pretty": 1
        }

        try:
            response = requests.get(url, params=params, verify=False, timeout=500000)
            response.raise_for_status()
            data = response.json()

            all_hosts = []
            if isinstance(data, list):
                all_hosts = [host.get("host_name", "").strip().lower() for host in data]
            elif isinstance(data, dict):
                for key in ["hostconfig", "hosts", "data", "results"]:
                    if key in data and isinstance(data[key], list):
                        all_hosts = [host.get("host_name", "").strip().lower() for host in data[key]]
                        break

            for host in target_hosts:
                if host in all_hosts:
                    found_hosts.add(host)

                    # Get services for host
                    services_data = service_details(host, f"https://{server}", api_key)
                    service_names = [s.get("service_description", "") for s in services_data]
                    service_list_str = "; ".join(service_names)
                    service_count = len(service_names)

                    results.append({
                        "host_name": host,
                        "server_name": server,
                        "status": "found",
                        "services": service_list_str,
                        "service_count": service_count
                    })

        except requests.exceptions.Timeout:
            print(f"Timeout while trying to reach {server}")
        except requests.exceptions.RequestException as e:
            print(f"Error with server {server}: {e}")
        except KeyboardInterrupt:
            print("\nScript interrupted by user.")
            exit()
        except Exception as e:
            print(f"Unexpected error with server {server}: {e}")

# Add not found hosts
not_found_hosts = target_hosts - found_hosts
for host in not_found_hosts:
    results.append({
        "host_name": host,
        "server_name": "Host not found in any server or inactive",
        "status": "Inactive/Not Found",
        "services": "",
        "service_count": 0
    })

# Write to CSV
with open(output_file, 'w', newline='', encoding='utf-8') as f:
    fieldnames = ["host_name", "server_name", "status", "services", "service_count"]
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(results)

print(f"\n✅ Matching complete. Results saved to: {output_file}")
