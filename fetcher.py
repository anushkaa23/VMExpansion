import requests
import json
import time
import urllib3
import pandas as pd
from collections import Counter
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
# --- Host Groups for a Host ---
def get_host_groups_for_host(hostname, url, apikey):
    base_url = (
        f"{url}/nagiosxi/api/v1/config/host"
        f"?apikey={apikey}&pretty=1"
    )
    response = requests.get(base_url, verify=False)
    data = response.json()

    # print(f"\nFetching host group details for host '{hostname}'...")
    host_info = None
    for host in data:
        if host.get("host_name") == hostname:
            host_info = host
            break

    if not host_info:
        print(f"Host '{hostname}' not found.")
        return []

    host_groups = host_info.get("hostgroups", [])
    return host_groups

# --- Services for a Host ---
def service_details(hostname,url,apikey):
    base_url = (
        f"{url}/nagiosxi/api/v1/objects/servicestatus"
        f"?apikey={apikey}&host_name={hostname}&pretty=1"
    )
    try:
        response = requests.get(base_url, verify=False)
        response.raise_for_status()
        data = response.json()

        services = data.get('servicestatus', [])
        if not services:
            print(f"No services found for host: {hostname}")
        return services

    except requests.RequestException as e:
        print(f"Error contacting Nagios XI API: {e}")
        return []

# --- Host Details ---
def host_details(hostname, url, apikey):
    base_url = (
        f"{url}/nagiosxi/api/v1/config/host"
        f"?apikey={apikey}&pretty=1"
    )
    response = requests.get(base_url, verify=False)
    data = response.json()

    print(f"\nFetching host details for '{hostname}'...")
    host_info = None
    for host in data:
        if host.get("host_name") == hostname:
            host_info = host
            break

    if not host_info:
        print(f"Host '{hostname}' not found.")
        return

    while True:
        print("\nPlease select an option:")
        print("1. Address")
        print("2. Alias")
        print("3. Contact and Contact Groups")
        print("4. Max Check Attempts")
        print("5. Check Interval")
        print("6. Check Period")
        print("7. Notification Interval")
        print("8. Notification Period")
        print("9. Go back to Main Menu")
        print("10. Show All Info")
        print("11. Show Host Groups")
        print("12. Show Services")

        try:
            switch = int(input("Enter your choice: "))
        except ValueError:
            print("Invalid input. Please enter a number.")
            time.sleep(1)
            continue

        choice = {
            1: "address",
            2: "alias",
            3: "contact_groups",
            4: "max_check_attempts",
            5: "check_interval",
            6: "check_period",
            7: "notification_interval",
            8: "notification_period",
            9: "exit",
            10: "all_info",
            11: "host_groups",
            12: "services"
        }

        if switch == 9:
            print("Exiting host details view.")
            break
        elif switch == 10:
            print("\n--- All Host Details ---")
            # Display each key-value pair in a human-readable way
            print(f"Host Name: {host_info.get('host_name', 'N/A')}")
            print(f"Address: {host_info.get('address', 'N/A')}")
            print(f"Alias: {host_info.get('alias', 'N/A')}")
            print(f"Max Check Attempts: {host_info.get('max_check_attempts', 'N/A')}")
            print(f"Check Interval: {host_info.get('check_interval', 'N/A')}")
            print(f"Check Period: {host_info.get('check_period', 'N/A')}")
            print(f"Notification Interval: {host_info.get('notification_interval', 'N/A')}")
            print(f"Notification Period: {host_info.get('notification_period', 'N/A')}")
            print(f"Contact Groups: {', '.join(host_info.get('contact_groups', [])) if host_info.get('contact_groups') else 'N/A'}")
            print(f"Contacts: {', '.join(host_info.get('contacts', [])) if host_info.get('contacts') else 'N/A'}")
            services = service_details(hostname,url,apikey)
            if(services):
                state_map = {
                    '0': "OK",
                    '1': "WARNING",
                    '2': "CRITICAL",
                    '3': "UNKNOWN"
                }
                print("\n--- All the Services of the {} ---".format("hostname"))
                print("------------------------------------------------------------------------------------------------------")
                for svc in services:
                    state = svc.get('current_state')
                    state_str = state_map.get(state, "UNKNOWN")
                    service_name = svc.get('service_description', 'N/A')
                    print(f"Service: {svc['host_name']} - {service_name} - Status: {state_str} ")
            # Show Host Groups
            host_groups = get_host_groups_for_host(hostname, url, apikey)
            print(f"Host Groups: {', '.join(host_groups) if host_groups else 'N/A'}")
            time.sleep(1)
        elif switch == 3:  # Option to show contact groups
            contact_groups = host_info.get("contact_groups", [])
            print(f"Contact Groups: {', '.join(contact_groups) if contact_groups else 'N/A'}")
            if contact_groups:
                show_members = input("\nDo you want to see the members of the contact group(s)? (yes/no): ").strip().lower()
                if show_members == "yes":
                    for contact_group in contact_groups:
                        members = get_members_of_contact_group(contact_group, url, apikey)
                        if members:
                            print(f"\nMembers of contact group '{contact_group}':")
                            for member in members:
                                print(f"- {member}")
                        else:
                            print(f"No members found for the contact group '{contact_group}'.")
            else:
                print("No contact groups found.")
            time.sleep(1)
        elif switch == 11:  # Show Host Groups
            host_groups = get_host_groups_for_host(hostname, url, apikey)
            if host_groups:
                print(f"Host Groups for {hostname}: {', '.join(host_groups)}")
            else:
                print(f"No host groups found for {hostname}.")
            time.sleep(1)
        elif switch == 12:  
            services = service_details(hostname,url,apikey)
            if(services):
                state_map = {
                    '0': "OK",
                    '1': "WARNING",
                    '2': "CRITICAL",
                    '3': "UNKNOWN"
                }
                print("\n--- All the Services of the {} ---".format("hostname"))
                print("------------------------------------------------------------------------------------------------------")
                for svc in services:
                    state = svc.get('current_state')
                    state_str = state_map.get(state, "UNKNOWN")
                    service_name = svc.get('service_description', 'N/A')
                    print(f"Service: {svc['host_name']} - {service_name} - Status: {state_str} ")
        elif switch in choice:
            key = choice[switch]
            value = host_info.get(key, "N/A")
            print(f"{key.replace('_', ' ').title()}: {value}")
            time.sleep(1)
        else:
            print("Invalid choice. Try again.")
            time.sleep(1)

# --- Down Hosts ---
def get_down_hosts(api_key, url):
    baseurl = f"{url}/nagiosxi/api/v1/objects/hoststatus"
    params = {
        "apikey": api_key,
        "current_state": 1,  # 1 = DOWN
        "pretty": 1
    }

    try:
        response = requests.get(baseurl, params=params, verify=False)
        response.raise_for_status()
        data = response.json()

        if "hoststatus" in data and data["hoststatus"]:
            print("Down Hosts:")
            for host_item in data["hoststatus"]:
                host_name = host_item.get("host_name", "<unknown>")
                print(f"{host_name}")
            print(f"Total Down Hosts: {len(data['hoststatus'])}")
        else:
            print("No down hosts found or API returned no results.")
    except requests.exceptions.RequestException as e:
        print(f"Error contacting Nagios XI API: {e}")

# --- Unreachable Hosts ---
def unreachable_down_hosts(api_key, url):
    baseurl = f"{url}/nagiosxi/api/v1/objects/hoststatus"
    params = {
        "apikey": api_key,
        "current_state": 2,  # 2 = unreachable
        "pretty": 1
    }

    try:
        response = requests.get(baseurl, params=params, verify=False)
        response.raise_for_status()
        data = response.json()

        if "hoststatus" in data and data["hoststatus"]:
            print("unreachable Hosts:")
            for host_item in data["hoststatus"]:
                host_name = host_item.get("host_name", "<unknown>")
                print(f"{host_name}")
            print(f"Total unreachable Hosts: {len(data['hoststatus'])}")
        else:
            print("No Unreachable hosts found or API returned no results.")
    except requests.exceptions.RequestException as e:
        print(f"Error contacting Nagios XI API: {e}")

# get all the hosts in alphabetical order
def get_all_hosts_sorted(url, apikey):
    """
    Fetch all host names from a Nagios XI server and return them in sorted order.
    """
    base_url = f"{url}/nagiosxi/api/v1/objects/hoststatus?apikey={apikey}&pretty=1"
    all_hosts = []

    try:
        response = requests.get(base_url, verify=False)
        response.raise_for_status()
        data = response.json()

        if "hoststatus" in data:
            for host in data["hoststatus"]:
                hostname = host.get("host_name")
                if hostname:
                    all_hosts.append(hostname)

        sorted_hosts = sorted(all_hosts, key=lambda x: x.lower())  # case-insensitive sort
        # print(f"Total Hosts Found: {len(sorted_hosts)}")
        return sorted_hosts

    except requests.exceptions.RequestException as e:
        print(f"Error fetching hosts: {e}")
        return []

# --- Services for a Host ---
def service_details(hostname,url,apikey):
    base_url = (
        f"{url}/nagiosxi/api/v1/objects/servicestatus"
        f"?apikey={apikey}&host_name={hostname}&pretty=1"
    )
    try:
        response = requests.get(base_url, verify=False)
        response.raise_for_status()
        data = response.json()

        services = data.get('servicestatus', [])
        if not services:
            print(f"No services found for host: {hostname}")
        return services

    except requests.RequestException as e:
        print(f"Error contacting Nagios XI API: {e}")
        return []


# --- Hosts from Hostgroup ---
def get_hosts_from_hostgroup(hostgroup_name, url, apikey):
    base_url = f"{url}/nagiosxi/api/v1/objects/hostgroupmembers?apikey={apikey}&hostgroup_name={hostgroup_name}&pretty=1"
    try:
        response = requests.get(base_url, verify=False)
        response.raise_for_status()
        data = response.json()

        hosts = data["hostgroup"][0]["members"]["host"]
        host_names = [host["host_name"] for host in hosts]
        return host_names
    except (requests.RequestException, KeyError, IndexError) as e:
        print(f"Error: {e}")
        return []

# --- Members from Contact Group ---
def get_members_of_contact_group(contactgroup_name, url, apikey):
    base_url = f"{url}/nagiosxi/api/v1/objects/contactgroupmembers?apikey={apikey}&contactgroup_name={contactgroup_name}&pretty=1"
    try:
        response = requests.get(base_url, verify=False)
        response.raise_for_status()
        data = response.json()

        contacts = data["contactgroup"][0]["members"]["contact"]
        contact_names = [c["contact_name"] for c in contacts]
        return contact_names
    except (requests.RequestException, KeyError, IndexError) as e:
        print(f"Error: {e}")
        return []

# get duplicate hosts
def get_duplicate_hosts(url, apikey):
    """
    Identify and list duplicate host names from a Nagios XI server.
    """
    hosts = get_all_hosts_sorted(url, apikey)
    host_count = Counter(hosts)

    duplicates = [host for host, count in host_count.items() if count > 1]

    if duplicates:
        print(f"\nDuplicate Hosts Found ({len(duplicates)}):")
        for host in duplicates:
            print(f"- {host} (count: {host_count[host]})")
    else:
        print("\nNo duplicate hosts found.")

    return duplicates
def fetch_and_summarize_nagios_hosts(url, apikey, output_excel_path="nagios_host_state_summary.xlsx"):
    # Clean URL and setup API endpoint
    url = url.rstrip('/')
    endpoint = f"{url}/nagiosxi/api/v1/objects/hoststatus?apikey={apikey}&pretty=1"

    try:
        response = requests.get(endpoint, verify=False, timeout=15)
        response.raise_for_status()
    except Exception as e:
        print(f"Error fetching data from Nagios: {e}")
        return

    try:
        data = response.json()
        hosts_data = data.get("hoststatus", [])
    except Exception as e:
        print(f"Error parsing response JSON: {e}")
        return

    # Mapping Nagios state codes
    state_map = {
        0: "OK",
        1: "DOWN",
        2: "UNREACHABLE",
        3: "UNKNOWN"
    }

    # Categorize hosts into lists
    categorized_hosts = {
        "OK": [],
        "DOWN": [],
        "UNREACHABLE": [],
        "UNKNOWN": []
    }

    for host in hosts_data:
        hostname = host.get("host_name") or host.get("name") or "UnnamedHost"
        try:
            state_code = int(host.get("current_state", 3))
        except (ValueError, TypeError):
            state_code = 3

        state = state_map.get(state_code, "UNKNOWN")
        categorized_hosts[state].append(hostname)

    # Determine max number of rows to balance the Excel columns
    max_len = max(len(lst) for lst in categorized_hosts.values())

    # Build DataFrame
    df = pd.DataFrame({
        "OK": categorized_hosts["OK"] + [""] * (max_len - len(categorized_hosts["OK"])),
        "DOWN": categorized_hosts["DOWN"] + [""] * (max_len - len(categorized_hosts["DOWN"])),
        "UNREACHABLE": categorized_hosts["UNREACHABLE"] + [""] * (max_len - len(categorized_hosts["UNREACHABLE"])),
        "UNKNOWN": categorized_hosts["UNKNOWN"] + [""] * (max_len - len(categorized_hosts["UNKNOWN"]))
    })

    # Save to Excel
    df.to_excel(output_excel_path, index=False)
    print(f"\nHost state summary saved to: {output_excel_path}")

    # Print summary counts
    print("\nHost Status Summary:")
    for state in ["OK", "DOWN", "UNREACHABLE", "UNKNOWN"]:
        count = len(categorized_hosts[state])
        print(f"{state} - {count} host{'s' if count != 1 else ''}")

def fetch_multiple_hostgroups_and_export(api_url, api_key):
    input_groups = input("Enter hostgroup names (comma-separated): ").strip()
    group_names = [name.strip() for name in input_groups.split(",") if name.strip()]
    
    results = []

    for group in group_names:
        print(f"🔍 Getting hosts for hostgroup: {group}")
        hosts = get_hosts_from_hostgroup(group, api_url, api_key)
        if not hosts:
            print(f"No hosts found in hostgroup '{group}'.")
        for host in hosts:
            results.append({"Hostgroup Name": group, "Host Name": host})

    if not results:
        print("No hosts found for the provided hostgroups.")
        return

    print(f"\nFound {len(results)} total host entries across {len(group_names)} hostgroups.")

    export = input("Do you want to export the results to Excel? (yes/no): ").strip().lower()
    if export == "yes":
        df = pd.DataFrame(results)
        output_file = "hostgroups_hosts_output.xlsx"
        df.to_excel(output_file, index=False)
        print(f"Output saved to: {output_file}")
    else:
        for entry in results:
            print(f"{entry['Hostgroup Name']} → {entry['Host Name']}")
# === Main Application ===

def main():
    print("=== Welcome to Nagios XI Fetcher ===\n")
    print("Choose the Location:")
    print("1.Hyderabad\n2.San Jose\n3.Singapore\n4.Colorado\n5.Atlanta\n6.EMEA\n7.Exit")
    print("Enter your choice:")
    choice = input().strip()
    if choice == "1":
        print("Connected to Hyderabad")
        choice=input("choose the type of server:\n1.hello\n2.hello\nEnter your choice (1-2): ").strip()
        if choice == "1":
            url = "https://hello.com"
            apikey = ""
            location = "hello"
        elif choice=="2":
            url = "https://hello.com"
            apikey = ""
            location = "hello"
    elif choice == "2":
        print("You have selected San Jose. Please choose the type of server:")
        print("\n1.hello\n2.hello\n3.hello")
        choice = input("Enter your choice (1-3): ").strip()
        if choice == "1":
            url = "https://hello.com"
            apikey = ""
            location = "hello"
        elif choice == "2":
            url="https://hello.com"
            apikey=""
            location = "hello"
        elif choice=="3":
            url="https://hello.com"
            apikey=""
            location = "hello"
    elif choice == "3":
        url="https://hello.com"
        apikey=""
        location = "Singapore"
    elif choice =="4":
        url="https://hello.com"
        apikey=""
        location = "Colorado"
    elif choice =="5":
        print("You have selected Atlanta. Please choose the type of server:")
        
        print("\n1.Atlanta - Non-grid Linux\n2.Atlanta – Grid\n3.Atlanta – Windows")
        choice = input("Enter your choice (1-3): ").strip()
        if choice == "1":
            url="https://hello.amd.com/"
            apikey=""
            location = "Atlanta - Non-grid Linux"
        elif choice == "2":
            url="https://hello.amd.com/"
            apikey=""
            location = "Atlanta - Grid"
        elif choice == "3":
            url="https://hello.amd.com/"
            apikey=""
            location = "Atlanta - Windows"
    elif choice == "6":
        url="https://hello.com"
        apikey = ""
        location = "EMEA"
    elif choice == "7":
        print("Exiting... Goodbye!")
        return
    else: 
        print("Invalid choice. Exiting...")
        return
        
    print(f"\nConnecting to Nagios XI at {location}...")
    time.sleep(1)
    print("Connected successfully!\n")

    while True:
        print("\nMain Menu:")
        print("1. Get Host Details")
        print("2. List Down Hosts")
        print("3. List Unreachable Hosts")
        print("4. List Services of a Host")
        print("5. List Hosts in a Hostgroup")
        print("6. List Contacts in a Contactgroup")
        print("7. Get All Hosts")
        print("8. Get All Hosts with Categorized Summary")
        print("9. Get Duplicate Hosts")
        print("10. Fetch Hosts from Multiple Hostgroups and Export to Excel")
        print("11. Exit")

        choice = input("Enter your choice (1-11): ").strip()

        if choice == "1":
            hostname = input("Enter Host Name: ").strip()
            host_details(hostname, url, apikey)

        elif choice == "2":
            print("\nFetching down hosts...")
            get_down_hosts(apikey, url)
            time.sleep(1)

        elif choice == "3":
            print("\nFetching unreachable hosts...")
            unreachable_down_hosts(apikey, url)
            time.sleep(1)

        elif choice == "4":
            hostname=input("Enter Host Name: ").strip()
            #hostname = "atletx8-tst01"
            services = service_details(hostname,url,apikey)
            if(services):
                state_map = {
                    '0': "OK",
                    '1': "WARNING",
                    '2': "CRITICAL",
                    '3': "UNKNOWN"
                }
                print("\n--- All the Services of the {} ---".format("hostname"))
                print("------------------------------------------------------------------------------------------------------")
                for svc in services:
                    state = svc.get('current_state')
                    state_str = state_map.get(state, "UNKNOWN")
                    service_name = svc.get('service_description', 'N/A')
                    print(f"Service: {svc['host_name']} - {service_name} - Status: {state_str} ")

        elif choice == "5":
            hostgroup_name = input("Enter Hostgroup Name: ").strip()
            hosts = get_hosts_from_hostgroup(hostgroup_name, url, apikey)
            if hosts:
                print("\nHosts in Hostgroup:")
                for host in hosts:
                    print(f"- {host}")
                print("Number of hosts in this hostgroup: ", len(hosts))
            else:
                print("No hosts found in this hostgroup.")
                

        elif choice == "6":
            contactgroup_name = input("Enter Contactgroup Name: ").strip()
            contacts = get_members_of_contact_group(contactgroup_name, url, apikey)
            if contacts:
                print("\nContacts in Contactgroup:")
                for contact in contacts:
                    print(f"- {contact}")
            else:
                print("No contacts found in this contactgroup.")
        elif choice == "7":
            print("\nFetching all hosts in the server (sorted)...")
            hosts = get_all_hosts_sorted(url, apikey)
            for h in hosts:
                print(f"- {h}") 
            print(f"Total Hosts Found: {len(hosts)}")
        elif choice == "8":
            fetch_and_summarize_nagios_hosts(url, apikey)
        elif choice == "9":
            print("\nChecking for duplicate host names...")
            get_duplicate_hosts(url, apikey)

        elif choice == "10":
            print("\nFetching hosts from multiple hostgroups...")
            fetch_multiple_hostgroups_and_export(url, apikey)
        elif choice == "11":
            print("Exiting... Goodbye!")
            break

        else:
            print("Invalid choice. Please try again.")

if __name__ == "__main__":
    main()



 

