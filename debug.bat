@echo off
chcp 65001 >nul

python collect_code.py ./scripts ./addons/gd_database -e .gd .cs -o scripts_debug.txt --relpath
python collect_scenes.py ./scenes -o scenes_debug.txt

pause