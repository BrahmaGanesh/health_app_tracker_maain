from dotenv import load_dotenv
import os

load_dotenv(r"C:\health_app_main\.env", override=True)

print(os.getenv("MAIL_USERNAME"))
print(os.getenv("MAIL_PASSWORD"))