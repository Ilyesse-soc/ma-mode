"""Actual STARTTLS SMTP delivery, never a fictional notification worker."""

import asyncio
import smtplib
import ssl
from email.message import EmailMessage
from urllib.parse import urlencode

from app.core.config import get_settings
from app.core.logging import get_logger


async def send_account_link(email: str, token: str, purpose: str):
    settings = get_settings()
    if not settings.smtp_host:
        return

    def deliver():
        message = EmailMessage()
        message["From"] = settings.smtp_from
        message["To"] = email
        message["Subject"] = (
            "Dressly : validation de compte" if purpose == "verify" else "Dressly : nouveau mot de passe"
        )
        link = settings.account_link_base_url + "?" + urlencode({"action": purpose, "token": token})
        message.set_content(
            "Ouvre ce lien pour continuer. Si tu n'as pas demandé cette action, ignore ce message.\n" + link
        )
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as smtp:
            smtp.starttls(context=ssl.create_default_context())
            if settings.smtp_username:
                smtp.login(settings.smtp_username, settings.smtp_password)
            smtp.send_message(message)

    try:
        await asyncio.to_thread(deliver)
    except (smtplib.SMTPException, OSError):
        get_logger("mail").error("mail.delivery_failed", purpose=purpose)
