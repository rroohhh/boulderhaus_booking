from html.parser import HTMLParser
from requests import Session
import requests
import json
from pyquery import PyQuery as pq

slot_name = "2h-slot-fuer-getestete-genesene-und-vollstaendig-geimpfte"
api_base = f"https://187.webclimber.de/de/booking/offer/{slot_name}"

class BoulderHausApi:
    def get_slots(date):
        params = {
            'type': 'getTimes',
            'date': date,
            'period': '2',
            'place_id': '',
            'places': '1',
            'persons': '1'
        }

        r = requests.get(url = api_base,
                params = params,
                headers = {
                    'Referer': api_base,
                    'X-Requested-With': 'XMLHttpRequest'
                })

        class TableParser(HTMLParser):
            def __init__(self):
                super(TableParser, self).__init__()
                self.in_row = False
                self.spots = []

            def handle_starttag(self, tag, attrs):
                if tag == "tr":
                    self.row_pos = 0
                    self.in_row = True

                if tag == "button" and self.in_row:
                    attrs = dict(attrs)

                    assert self.row_pos == 2

                    if self.row_pos == 2:
                        self.link = attrs["data-url"]


            def handle_endtag(self, tag):
                if tag == "td":
                    self.row_pos += 1

                if tag == "tr":
                    self.in_row = False

                    try:
                        self.spots.append((self.date, self.free_spots, self.link))
                    except:
                        pass

            def handle_data(self, data):
                if self.in_row:
                    if self.row_pos == 0:
                        self.date = data
                    elif self.row_pos == 1:
                        self.free_spots = data

        parser = TableParser()
        parser.feed(r.text)

        return parser.spots

    def book_slot(slot, user_info):
        s = Session()
        s.head(api_base)

        r = s.get(slot)

        token = pq(r.text)('input[name="YII_CSRF_TOKEN"]').attr.value

        new_url = r.url

        data = {
            "webclimber_session": s.cookies["webclimber_session"],
            "YII_CSRF_TOKEN": token,
            "yt0": "",
            "BookingOrder[0][firmenname]": "",
            "BookingOrder[0][vorname]": user_info["firstname"],
            "BookingOrder[0][nachname]": user_info["lastname"],
            "BookingOrder[0][strasse]": user_info["street"],
            "BookingOrder[0][plz]": user_info["postal_code"],
            "BookingOrder[0][ort]": user_info["city"],
            "BookingOrder[0][email]": user_info["email"],
            "BookingOrder[0][telefon]": user_info["phone"],
            "BookingOrder[0][geburtstag_form]": user_info["birthdate"],
            "BookingOrder[0][customer_no]": user_info["customer_no"],
            "BookingOrder[0][artikel_id]": "28",
            "BookingOrder[0][teilnehmer]": "1",
            "BookingOrder[0][bemerkung]": "",
            "BookingOrder[1][vorname]": "",
            "BookingOrder[1][nachname]": "",
            "BookingOrder[1][strasse]": "",
            "BookingOrder[1][plz]": "",
            "BookingOrder[1][ort]": "",
            "BookingOrder[1][email]": "",
            "BookingOrder[1][telefon]": "",
            "BookingOrder[1][geburtstag_form]": "",
            "BookingOrder[1][customer_no]": "",
            "BookingOrder[1][artikel_id]": "23",
            "BookingOrder[2][vorname]": "",
            "BookingOrder[2][nachname]": "",
            "BookingOrder[2][strasse]": "",
            "BookingOrder[2][plz]": "",
            "BookingOrder[2][ort]": "",
            "BookingOrder[2][email]": "",
            "BookingOrder[2][telefon]": "",
            "BookingOrder[2][geburtstag_form]": "",
            "BookingOrder[2][customer_no]": "",
            "BookingOrder[2][artikel_id]": "23",
        }

        r = s.post(new_url, data, headers = {
            'Origin': 'https://187.webclimber.de',
            'Referer': new_url.rsplit('#', 1)[0],
            'X-Requested-With': 'XMLHttpRequest'
        })

        new_url = new_url.replace("checkoutPurchase", "checkoutConfirm").rsplit('?', 1)[0]

        data["BookingOrder[checkAgb]"] = 1


        r = s.post(new_url, data, headers = {
            'Origin': 'https://187.webclimber.de',
            'Referer': new_url.rsplit('#', 1)[0],
            'X-Requested-With': 'XMLHttpRequest'
        })

        if "Termin Buchung erfolgreich" in r.text:
            return True
        else:
            return False


from flask import Flask, request, make_response
from pathlib import Path
import hashlib
import os
import base64

class UserManager:
    def __init__(self):
        self.users_file = Path("users.json")

        if self.users_file.exists():
            self.users = json.loads(self.users_file.read_text())
        else:
            self.users = {}
            self.save()

    def check_token(self, username, token):
        m = hashlib.sha256()
        m.update(self.users[username]["password"].encode("utf-8"))
        m.update(self.users[username]["secret"].encode("utf-8"))
        return token == m.hexdigest()

    def login(self, username, password):
        if username in self.users and self.users[username]["password"] == password:
            m = hashlib.sha256()
            m.update(self.users[username]["password"].encode("utf-8"))
            m.update(self.users[username]["secret"].encode("utf-8"))

            return m.hexdigest()

    def save(self):
        self.users_file.write_text(json.dumps(self.users))

    def create(self, username, password, info):
        if username not in self.users:
            secret = base64.b64encode(os.urandom(256)).decode('utf-8')
            self.users[username] = {}
            self.users[username]["secret"] = secret
            self.users[username]["password"] = password
            self.users[username]["info"] = info
            self.save()

            m = hashlib.sha256()
            m.update(self.users[username]["password"].encode("utf-8"))
            m.update(self.users[username]["secret"].encode("utf-8"))
            return m.hexdigest()
        else:
            return None

    def modify(self, username, token, info):
        if self.check_token(username, token):
            self.users[username]["info"] = info
            self.save()
            return True

    def get_info(self, username, token):
        if self.check_token(username, token):
            return self.users[username]["info"]

app = Flask(__name__)
user_manager = UserManager()
api = BoulderHausApi()

@app.route('/api/login', methods=['POST'])
def login():
    username = request.json["username"]
    password = request.json["password"]

    token = user_manager.login(username, password)

    if token:
        response = make_response('{"status":"ok"}')
        response.headers["Access-Control-Expose-Headers"] = "*"
        response.headers["Access-Control-Allow-Credentials"] = "true"
        response.headers["X-Token"] = token
        response.headers["X-Username"] = username
        response.set_cookie('username', username)
        response.set_cookie('token', token)
        return response

    return '{"status":"failed"}'

@app.route('/api/user_info', methods=['GET', 'POST'])
def user_info():
    if request.method == 'GET':
        if (data := user_manager.get_info(username_from(request), token_from(request))):
            return data
    else:
        if user_manager.modify(username_from(request), token_from(request), request.json):
            return '{"status":"ok"}'

    return '{"status":"failed"}'

@app.route('/api/create_user', methods=['POST'])
def create_user():
    r = request.json
    username = r["username"]
    password = r["password"]
    info = r["info"]

    if (token := user_manager.create(username, password, info)) is not None:
        response = make_response('{"status":"ok"}')
        response.headers["Access-Control-Expose-Headers"] = "*"
        response.headers["Access-Control-Allow-Credentials"] = "true"
        response.headers["X-Token"] = token
        response.headers["X-Username"] = username
        response.set_cookie('username', username)
        response.set_cookie('token', token)
        return response

    return '{"status":"failed"}'

@app.route('/api/list_slots', methods=['POST'])
def list_slots():
    r = request.json
    date = r["date"]

    return json.dumps(BoulderHausApi.get_slots(date))

@app.route('/api/status', methods=['GET'])
def status():
    if all(info is not None for info in [username_from(request), token_from(request)]):
        return '{"status":"logged_in"}'

    return '{"status":"logged_out"}'

@app.route('/api/logout', methods=['GET'])
def log_out():
    resp = make_response('{"status":"ok"}')
    resp.set_cookie('username', '', expires=0)
    resp.set_cookie('token', '', expires=0)

    return resp

@app.route('/api/book_slot', methods=['POST'])
def book_slot():
    r = request.json
    slot = r["slot"]

    if BoulderHausApi.book_slot(slot, user_manager.get_info(username_from(request), token_from(request))):
        return '{"status":"ok"}'

    return '{"status":"failed"}'

def username_from(r):
    if "username" in r.cookies:
        return r.cookies["username"]
    if "X-Username" in r.headers:
        return r.headers["X-Username"]

def token_from(r):
    if "token" in r.cookies:
        return r.cookies["token"]
    if "X-Token" in r.headers:
        return r.headers["X-Token"]
