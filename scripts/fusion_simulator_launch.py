"""Launch the already-tested app; retry only the known Simulator install Busy race.
No installation, assertion bypass, generic retry or hidden background job.
"""
import subprocess
import sys
import time


def launch(simulator, bundle, arguments, run=subprocess.run, sleep=time.sleep):
    for attempt in range(4):
        result = run(['xcrun','simctl','launch',simulator,bundle,*arguments],
                     text=True,capture_output=True,timeout=45)
        if result.returncode == 0:
            print(result.stdout.strip())
            return
        diagnostic = result.stdout + result.stderr
        known_busy = ('FBSOpenApplicationServiceErrorDomain' in diagnostic and
                      'Busy' in diagnostic and 'installing or uninstalling' in diagnostic)
        if not known_busy or attempt == 3:
            raise RuntimeError('Simulator launch failed: '+diagnostic[-3000:])
        print(f'Simulator installation busy; bounded retry {attempt+1}/3.',flush=True)
        sleep(3 * (attempt + 1))


if __name__ == '__main__':
    if len(sys.argv)<3: raise SystemExit('Usage: fusion_simulator_launch.py UDID bundle [arguments]')
    launch(sys.argv[1],sys.argv[2],sys.argv[3:])
