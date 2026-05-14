@echo off
setlocal
cd /d "%~dp0"
python -m pip install -r requirements-windows.txt
python Windows\gamma_pet_windows.py

