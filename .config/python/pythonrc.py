import os
import atexit
import readline
from pathlib import Path
from pint import UnitRegistry
from functools import reduce
from random import *
import numpy as np

# save unit registry as "unit"
unit = UnitRegistry()
def set_conv(*from_units):
    unit_list = lambda t: list(map(lambda x: f"{x}", t))
    
    from_sort = tuple(sorted(from_units, reverse=True))
    if from_units != from_sort:
        raise Exception(f"From units not in decreasing order, expecting {unit_list(list(from_sort))}")

    def set_conv_inner(*to_units):
        
        to_sort = tuple(sorted(to_units, reverse=True))
        if to_units != to_sort:
            raise Exception(f"To units not in decreasing order, expecting {unit_list(list(to_sort))}")
        
        def inner(*quantities):
            # args should be the same length as from_units.
            if len(from_units) != len(quantities):
                raise Exception(f"Not enough input arguments, expecting {unit_list(from_units)}")

            # calculate output
            tmp = 0
            for i in range(len(quantities)):
                tmp += quantities[i] * from_units[i]
            tmp_arr = [0.0 for i in range(len(to_units))]
            for i in range(len(to_units)):
                tmp_arr[i] = tmp.to(to_units[i]).magnitude // 1
                tmp_arr[i] = tmp_arr[i] * to_units[i]
                tmp -= tmp_arr[i]
            tmp_str = ", ".join([f"{tmp_arr[i]}" for i in range(len(tmp_arr))])
            print(tmp_str)
            tmp_arr = [a.magnitude for a in tmp_arr]
            if len(tmp_arr) == 1: return tmp_arr[0]
            return tmp_arr 

        global conv
        conv = inner
        print(f"'conv' set to convert {unit_list(from_units)} to {unit_list(to_units)}, call set_conv(unit.to,)(unit.from,) to change")

    return set_conv_inner
set_conv(unit.oz)(unit.g)

# get xdg state directory, build history file path, make sure it exists.
xdg_state = Path(os.environ.get("XDG_STATE_HOME"))
history_file = xdg_state / "python" / "history"
history_file.parent.mkdir(parents=True, exist_ok=True)

# read current history file, create if it doesn't exist, cap length at 1000 lines.
if not history_file.exists(): history_file.touch(mode=0o600)
try:
    readline.read_history_file(str(history_file))
except OSError:
    pass
readline.set_history_length(1000)

# override standard readline path so default exit handler doesnt use ~/.python_history
try:
    readline.set_auto_history(True)
except AttributeError:
    pass

# explicitly assign history_File back into python's default path variable
try:
    readline.write_history_file(str(history_file))
except OSError:
    pass

# function to save history on exit
def save_history():
    try:
        readline.write_history_file(str(history_file))
    except OSError:
        pass

# on exit
atexit.register(save_history)
