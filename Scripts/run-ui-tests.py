#!/usr/bin/env python3
"""Run real Android UI checks without activating windows or sharing guest data."""
import argparse
import os
from pathlib import Path
import signal
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True, help='Debug Mandroid.app')
parser.add_argument('--apk', type=Path)
parser.add_argument('--test', choices=['smoke', 'volume'], default='smoke')
parser.add_argument('--package', default='com.github.shadowsocks')
parser.add_argument('--sdk-data', type=Path, default=Path.home() / 'Library/Application Support/Mandroid')
parser.add_argument('--app-arg', action='append', default=[], metavar='ARG',
                    help='extra launch argument for the app, repeatable; write --app-arg=-hostMicrophone --app-arg=YES')
args = parser.parse_args()
app = args.app.resolve()
apk = args.apk.resolve() if args.apk else None
if not (app / 'Contents/MacOS/Mandroid').is_file():
    parser.error('App executable must exist')
if args.test == 'smoke' and (apk is None or not apk.is_file()):
    parser.error('The smoke test requires --apk')
for name in ('sdk', 'tools'):
    if not (args.sdk_data / name).is_dir():
        parser.error(f'Missing installed {name} in --sdk-data')
root = Path(tempfile.mkdtemp(prefix='mandroid-ui-', dir=Path.home() / 'Library/Caches'))
if apk is not None:
    # Read user-selected inputs from the shell, then let the hidden app use
    # its own cache. Downloads/external volumes may require a visible TCC prompt.
    staged_apk = root / 'input.apk'
    shutil.copy2(apk, staged_apk)
    apk = staged_apk
for name in ('sdk', 'tools'):
    (root / name).symlink_to((args.sdk_data / name).resolve(), target_is_directory=True)
control = root / 'control'
control.mkdir()
out = root / 'artifacts'
out.mkdir()
env = dict(os.environ, APP=str(app), APK=str(apk) if apk else "", PKG=args.package,
           UI_TEST_DATA_ROOT=str(root), UI_TEST_CONTROL=str(control), OUT=str(out))
print(f'Offscreen test data and artifacts: {root}', flush=True)
with (root / 'host.log').open('w') as log:
    process = subprocess.Popen([str(app / 'Contents/MacOS/Mandroid'),
        '-dataRoot', str(root), '-uiTestControlDirectory', str(control),
        '-launcherStubs', 'NO', *args.app_arg], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    script = 'volume-test.sh' if args.test == 'volume' else 'integration-test.sh'
    test = None
    try:
        test = subprocess.Popen(['zsh', str(Path(__file__).with_name(script))],
                                env=env, start_new_session=True)
        while test.poll() is None and process.poll() is None:
            time.sleep(0.2)
        if test.poll() is None:
            raise RuntimeError(f'Test app exited early; see {root}/host.log')
    finally:
        if test is not None and test.poll() is None:
            try:
                os.killpg(test.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                test.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(test.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                test.wait()
        command = control / f'{time.time_ns()}.tmp'
        command.write_text('mandroid://debug/quit')
        command.rename(command.with_suffix('.command'))
        try:
            process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    if process.returncode != 0:
        raise SystemExit(f'Test app exited {process.returncode}; see {root}/host.log')
raise SystemExit(test.returncode)
