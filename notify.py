#!/usr/bin/env python3

import requests
from html.parser import HTMLParser
from urllib.parse import urlparse, urlunparse
import smtplib
import demjson
import re
from datetime import datetime, timedelta
from email.message import EmailMessage
import secret as config
import time
import sys

base = 'https://' + sys.argv[1] 
slot_url = base + '/de/booking/offer/1h-slot'

if "187" in base:
    place = "Heidelberg"
elif "188" in base:
    place = "Darmstadt"
else:
    place = "unknown"

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


def notify(notify_message):
    try:
        with smtplib.SMTP(config.mail_server, config.mail_port) as server:
            server.starttls()
            server.login(
                config.mail_user, config.mail_password)

            msg = EmailMessage()
            msg['Subject'] = "Boulderhaus slots changed"
            msg['From'] = config.mail_sender
            msg['To'] = ", ".join(config.mail_recipients)
            msg.set_content(notify_message)
            server.send_message(msg)
    except Exception as e:
        error_handler(e)

    tg_send_message(config.tg_chat_id, notify_message)


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


def get_1h_slots():
    global offset
    r = requests.get(slot_url)
    datepicker_config = re.search(r"datepicker\((\{[^{}]*\})\)", r.text, re.MULTILINE | re.DOTALL).group(1)
    config = demjson.decode(datepicker_config)

    def parse_available_dates(config):
        input_date_fmt = "%d/%m/%Y"
        start = datetime.strptime(config["startDate"], input_date_fmt)
        end = datetime.strptime(config["endDate"], input_date_fmt)

        disabled = [datetime.strptime(d, input_date_fmt) for d in config["datesDisabled"]]

        def dates_in_range(a: datetime, b: datetime):
            diff = b - a
            for d in range(diff.days + 1):
                yield a + timedelta(days=d)

        for date in dates_in_range(start, end):
            if date not in disabled:
                yield date

    return list(parse_available_dates(config))

def build_offers_change_message(offers):
    return f"""
Neue Angebotsliste ({place}):
{chr(10).join(name + ": " + link for link,
     name in sorted(offers.items(), key=lambda offer: offer[0]))}
"""


def build_new_1h_slots_message(slots):
    print("new slots")
    print(slots)
    fmt = '%d.%m.%Y'
    return f"""
Neue 1h slots ({place}):
{chr(10).join(slot.strftime(fmt) for slot in sorted(slots))}
{slot_url}
"""

def not_equal_1h_slots(new, old):
    if len(new) == 0:
        return False
    elif len(old) == 0:
        return True
    else:
        newest_new = list(reversed(sorted(new)))[0]
        newest_old = list(reversed(sorted(old)))[0]
        return newest_new > newest_old
    
old_offers = get_offers()
old_1h_slots = get_1h_slots()
while True:
    try:
        time.sleep(5)
        new_offers = get_offers()
        print("got offers", new_offers)

        if new_offers != old_offers:
            notify(build_offers_change_message(new_offers))

        old_offers = new_offers

        new_1h_slots = get_1h_slots()
        print("got 1h slots", new_1h_slots)

        if not_equal_1h_slots(new_1h_slots, old_1h_slots):
            notify(build_new_1h_slots_message(new_1h_slots))
            old_1h_slots = new_1h_slots 
    except Exception as e:
        error_handler(e)
