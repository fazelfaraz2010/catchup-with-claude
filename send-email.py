#!/usr/bin/env python3
"""Send the newsletter .docx via Gmail SMTP.

Uses Gmail App Password stored in macOS Keychain.
To store the password once:
  security add-generic-password -a "fazelfaraz2010@gmail.com" -s "catchup-with-claude-smtp" -w "YOUR_APP_PASSWORD"
"""

import smtplib
import subprocess
import sys
import os
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email.mime.text import MIMEText
from email import encoders
from datetime import date

TO_EMAIL = "ffazel@marqeta.com"
FROM_EMAIL = "fazelfaraz2010@gmail.com"
KEYCHAIN_SERVICE = "catchup-with-claude-smtp"


def get_app_password():
    result = subprocess.run(
        ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print("ERROR: No Gmail App Password in Keychain.")
        print(f'Run: security add-generic-password -a "{FROM_EMAIL}" -s "{KEYCHAIN_SERVICE}" -w "YOUR_APP_PASSWORD"')
        sys.exit(1)
    return result.stdout.strip()


def send(docx_path, md_path=None):
    today = date.today().strftime("%B %d, %Y")
    password = get_app_password()

    msg = MIMEMultipart()
    msg["From"] = FROM_EMAIL
    msg["To"] = TO_EMAIL
    msg["Subject"] = f"Catchup with Claude — {today}"

    msg.attach(MIMEText("Your weekly Catchup with Claude newsletter is attached.", "plain"))

    # Attach .docx
    with open(docx_path, "rb") as f:
        part = MIMEBase("application", "octet-stream")
        part.set_payload(f.read())
    encoders.encode_base64(part)
    filename = os.path.basename(docx_path)
    part.add_header("Content-Disposition", f"attachment; filename={filename}")
    msg.attach(part)

    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
        server.login(FROM_EMAIL, password)
        server.sendmail(FROM_EMAIL, TO_EMAIL, msg.as_string())

    print(f"Email sent to {TO_EMAIL}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: send-email.py <docx_path> [md_path]")
        sys.exit(1)
    docx = sys.argv[1]
    md = sys.argv[2] if len(sys.argv) > 2 else None
    send(docx, md)
