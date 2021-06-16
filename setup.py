#!/usr/bin/env python3

from setuptools import setup

setup(
    name='bhbooking',
    version='0.0.1',
    install_requires=[
        'flask',
        'pyquery',
        'requests',
    ],
    scripts=[
        'server.py',
        'notify.py',
    ]
)
