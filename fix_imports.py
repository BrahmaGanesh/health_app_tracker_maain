import re
import os

# Read the file
filepath = "/c/health_app_main/routes/bp_routes.py"
with open(filepath, "r") as f:
    content = f.read()

# Replace imports - remove extensions import and sqlalchemy import
content = re.sub(r"from extensions import db\n", "", content)
content = re.sub(r"from sqlalchemy import func, extract\n", "", content)

# Write back
with open(filepath, "w") as f:
    f.write(content)

print("Step 1: Imports cleaned")