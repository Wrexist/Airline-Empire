#!/usr/bin/env python3
"""Record the native UI journey and retain timestamped source windows for editing."""
import json
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

device, destination = sys.argv[1:3]
out = Path(destination).resolve()
out.mkdir(parents=True, exist_ok=True)
record_log = (out / 'recording.log').open('w')
started = time.time()
record = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo',
                           '--codec=h264', str(out / 'gameplay-source.mp4')],
                          stdout=record_log, stderr=subprocess.STDOUT)
command = ['xcodebuild', 'test-without-building', '-project', 'AirlineEmpire.xcodeproj',
           '-scheme', 'AirlineEmpire', '-configuration', 'Debug',
           '-derivedDataPath', 'LaunchDerived', '-destination', f'platform=iOS Simulator,id={device}',
           '-parallel-testing-enabled', 'NO',
           '-only-testing:AirlineEmpireUITests/LaunchClipCaptureUITests/testRecordLaunchClips',
           '-resultBundlePath', str(out / 'LaunchClips.xcresult'), 'CODE_SIGNING_ALLOWED=NO']
log = []
try:
    time.sleep(3)
    if record.poll() is not None:
        raise RuntimeError('Simulator recording exited before the journey started')
    with (out / 'capture.log').open('w') as stream:
        test = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, bufsize=1)
        for line in test.stdout:
            print(line, end='', flush=True)
            stream.write(line)
            log.append(line)
        result = test.wait()
finally:
    record.send_signal(signal.SIGINT)
    record.wait(timeout=30)
    record_log.close()
segments = {}
for line in log:
    match = re.search(r'AECLIP (\w+) (START|END) ([0-9.]+)', line)
    if match:
        name, edge, epoch = match.groups()
        segments.setdefault(name, {})[edge.lower()] = float(epoch) - started
receipt = {'recordingStartedEpoch': started, 'source': 'gameplay-source.mp4',
           'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
           'segments': segments, 'testExitCode': result,
           'note': 'Host timestamp windows. Verify first/last frames before editing; includes Pro gameplay.'}
(out / 'segments.json').write_text(json.dumps(receipt, indent=2) + '\n')
if result:
    raise SystemExit(result)
if set(segments) != {'network', 'fleet', 'route', 'finance'} or any(
        set(window) != {'start', 'end'} for window in segments.values()):
    raise SystemExit('Incomplete capture: every planned segment must be present')
