#!/usr/bin/env python3

from time import sleep
import os
import re
import requests
import tinycss2
from influxdb_client import InfluxDBClient
from pyquery import PyQuery as pq

urls = {
    "Heidelberg": "https://187.webclimber.de/de/trafficlight?key=kTmE7BqvaSKQ8ZY84y7b3Ufq7EU3Sv6A",
    "Darmstadt": "https://188.webclimber.de/de/trafficlight?key=PzPrM4d63pw6EQvAp7fmA1127FAFxEK3",
    "Mannheim": "https://189.webclimber.de/de/trafficlight?key=3Ph9YdB38BaqPcsh6hx20a49fKv0TaR4"
}

def parse_style(style):
    values = {}
    for rule in tinycss2.parse_declaration_list(style, skip_whitespace=True):
        name = rule.lower_name
        for token in rule.value:
            if token.type == "whitespace":
                continue
            try:
                values[name] = token.value
                break
            except:
                pass
    return values

def query(url):
    values = {}
    d = pq(requests.get(url).text)
    s = d(".barometer .bar").attr("style")
    values["utilization"] = parse_style(s)["width"]

    for b in d(".trafficlight_bar").items():
        title = re.search(r"\d+ Uhr", b.attr('title')).group(0)
        values[f"intra_day {title}"] = parse_style(b.attr("style"))["height"]

    return values

if __name__ == "__main__":
    INFLUXDB_HOST = os.environ["INFLUXDB_HOST"]
    INFLUXDB_TOKEN = os.environ["INFLUXDB_TOKEN"]

    client = InfluxDBClient(url=INFLUXDB_HOST, token=INFLUXDB_TOKEN, org="infra")
    write_api = client.write_api()

    while True:
        try:
            for location, url in urls.items():
                print(location)
                write_api.write("boulderhaus", "infra", [{"measurement": "trafficlight", "tags": {"location": location}, "fields": query(url)}])
        except:
            pass

        sleep(10)
