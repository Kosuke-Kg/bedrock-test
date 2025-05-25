#!/bin/sh
mise settings add idiomatic_version_file_enable_tools python
cd backend
uv sync
. ./backend/.venv/bin/activate