import os
from pathlib import Path
import subprocess

def main():
    os.system('pip install virtualenv')
    python_directory = Path('apps/strategies/priv/python')
    python38_interpreter = os.system('which python3.8')
    if python38_interpreter != 0:
        print("No interpreter for python 3.8 found, make sure it's installed")
        raise Exception()
    python38_interpreter = subprocess.check_output(['which', 'python3.8'])
    python38_interpreter = python38_interpreter.decode().strip()
    os.system(f'python -m virtualenv {python_directory} --python={python38_interpreter}')
    activate_env = Path('source apps/strategies/priv/python/bin/activate')
    install_requirements = f'pip install -r {Path.joinpath(python_directory, "requirements.txt")}'
    print(f'{activate_env} && {install_requirements}')
    os.system(f'{activate_env} && {install_requirements}')
    print(f"Virtual enviroment has been setup. To activate it run {activate_env}")

if __name__ == '__main__':
    main()
