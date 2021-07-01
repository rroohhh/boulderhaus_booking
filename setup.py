#!/usr/bin/env python3

from setuptools import setup

setup(
    name='bhbooking',
    version='0.0.1',
    install_requires=[
        'flask',
        'pyquery',
        'requests',
        'pyquery',
        'influxdb_client',
        'tinycss2'
    ],
    scripts=[
        'server.py',
        'notify.py',
        'trafficlight.py'
    ]
)
