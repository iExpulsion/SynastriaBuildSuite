"""Copies the LuaMaterialUI style kit into SynastriaBuildSuite/UI/Style.lua.

    py -I -X utf8 tools/sync_style.py

LUAMATERIALUI overrides where the LuaMaterialUI repo is (default: next to this repo).
"""
import os, runpy, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.environ.get('LUAMATERIALUI', os.path.join(ROOT, '..', 'LuaMaterialUI'))
sys.argv = [sys.argv[0], ROOT, 'SynastriaBuildSuite']
runpy.run_path(os.path.join(LIB, 'tools', 'sync_style.py'), run_name='__main__')
