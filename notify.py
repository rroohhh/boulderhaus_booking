#!/usr/bin/env python3

import requests
from html.parser import HTMLParser
from urllib.parse import urlparse, urlunparse
import smtplib
from email.message import EmailMessage
import secret as config
import time

base = "https://187.webclimber.de"


class TableParser(HTMLParser):
    def __init__(self):
        super(TableParser, self).__init__()
        self.in_row = False
        self.offers = []

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row_pos = 0
            self.in_row = True

        if tag == "a" and self.in_row:
            attrs = dict(attrs)

            if self.row_pos == 0:
                self.link = attrs["href"]

    def handle_endtag(self, tag):
        if tag == "td":
            self.row_pos += 1

        if self.in_row and tag == "a" and self.row_pos == 0:
            try:
                self.offers.append((self.link, self.text))
            except Exception as e:
                error_handler(e)

        if tag == "tr":
            self.in_row = False

    def handle_data(self, data):
        if self.in_row:
            self.text = data


def sanitize_url(url):
    url = base + url
    url_parts = urlparse(url)
    url_parts = url_parts._replace(query="")
    url = urlunparse(url_parts)
    return url


def get_offers():
    r = requests.get(url=base + "/de/booking/offers")

    parser = TableParser()
    parser.feed(r.text)

    offers = {sanitize_url(offer[0]): offer[1]
              for offer in parser.offers}

    return offers


def notify(offers):
    offer_message = f"""
Neue Angebotsliste:
{chr(10).join(name + ": " + link for link,
     name in sorted(offers.items(), key=lambda offer: offer[0]))}
"""

    try:
        with smtplib.SMTP(config.mail_server, config.mail_port) as server:
            server.starttls()
            server.login(
                config.mail_user, config.mail_password)

            msg = EmailMessage()
            msg['Subject'] = "Boulderhaus slots changed"
            msg['From'] = config.mail_sender
            msg['To'] = ", ".join(config.mail_recipients)
            msg.set_content(offer_message)
            server.send_message(msg)
    except Exception as e:
        error_handler(e)

    tg_send_message(config.tg_chat_id, offer_message)


def tg_send_message(chat_id, message):
    try:
        requests.post('https://api.telegram.org/bot' +
                      config.tg_access_token + "/sendMessage", json={
                          "chat_id": chat_id,
                          "text": message
                      })
    except Exception as e:
        error_handler(e)


def error_handler(e):
    message = f"error: {e}"
    print(message)
    tg_send_message(config.tg_admin_chat_id, message)


old_offers = get_offers()
while True:
    try:
        time.sleep(5)
        new_offers = get_offers()
        print("got offers", new_offers)

        if new_offers != old_offers:
            notify(new_offers)

        old_offers = new_offers
    except Exception as e:
        error_handler(e)
