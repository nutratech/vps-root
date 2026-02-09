import csv
import sys

# Usage: python csv_to_bind.py records.csv > zone.txt
input_file = sys.argv[1]
domain = "nutra.tk"  # Change this if needed, or relying on relative names

with open(input_file, "r") as f:
    reader = csv.DictReader(f)

    # Check headers to ensure they match your CSV
    # Common variations: 'Type'/'Record Type', 'Name'/'Host', 'Content'/'Value'/'Target'
    try:
        # adjust these keys based on your actual CSV headers
        headers = reader.fieldnames
        print(f"; Converted from {input_file}")

        for row in reader:
            # Clean up data
            r_type = row.get("Type", "A").strip().upper()
            r_name = row.get("Name", "@").strip()
            r_content = row.get("Content", "").strip()
            r_ttl = row.get("TTL", "1").strip()  # Default to auto

            # Skip empty lines
            if not r_content:
                continue

            # Handle Priority for MX records
            priority = ""
            if r_type == "MX":
                # If priority is in a separate column, grab it. Otherwise assume it's in content or default 10.
                p = row.get("Priority", "10").strip()
                priority = f"{p} "

            # Output in BIND format: name IN TTL TYPE [PRIORITY] CONTENT
            # Cloudflare import is flexible, but standard BIND is safest.
            print(f"{r_name} IN {r_ttl} {r_type} {priority}{r_content}")

    except Exception as e:
        print(f"; Error processing file: {e}")
