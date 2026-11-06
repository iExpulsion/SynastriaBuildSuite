"""Copies the MaterialCraftUI style kit into SynastriaBuildSuite/UI/Style.lua.

    py -I -X utf8 tools/sync_style.py

MATERIALCRAFTUI overrides where the MaterialCraftUI repo is (default: next to this repo).
"""
import os, runpy, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.environ.get('MATERIALCRAFTUI', os.path.join(ROOT, '..', 'MaterialCraftUI'))
sys.argv = [sys.argv[0], ROOT, 'SynastriaBuildSuite']
runpy.run_path(os.path.join(LIB, 'tools', 'sync_style.py'), run_name='__main__')
