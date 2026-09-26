#!/usr/bin/env python3
"""Build and run opt-in Release scrolling benchmarks on a connected iOS device."""
import argparse
import pathlib
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True, help='Connected device UDID from xcrun xctrace list devices')
parser.add_argument('--team', required=True, help='Apple development team ID for signing')
parser.add_argument('--output', required=True, type=pathlib.Path, help='New directory for build and results')
parser.add_argument('--include-behavior-tests', action='store_true')
parser.add_argument('--test', action='append', help='Run only this test identifier (repeatable)')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
derived = output / 'DerivedData'
destination = f'platform=iOS,id={args.device}'

def run(command):
    subprocess.run(command, cwd=root, check=True)

run(['xcodebuild', '-project', 'TOGridViewExample.xcodeproj', '-scheme', 'TOGridViewExample',
     '-configuration', 'Release', '-destination', destination, '-derivedDataPath', str(derived),
     '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration',
     f'DEVELOPMENT_TEAM={args.team}', 'build-for-testing'])
files = list((derived / 'Build/Products').glob('*.xctestrun'))
if len(files) != 1:
    raise RuntimeError(f'Expected one test-run file, got {files}')
path = files[0]
with path.open('rb') as stream:
    configuration = plistlib.load(stream)
# Xcode supports both the legacy target dictionary and version-2 configurations.
targets = [v for k, v in configuration.items() if k != '__xctestrun_metadata__' and isinstance(v, dict)]
for entry in configuration.get('TestConfigurations', []):
    targets.extend(entry['TestTargets'])
for target in targets:
    target.setdefault('EnvironmentVariables', {})['TOGRID_RUN_BENCHMARKS'] = '1'
with path.open('wb') as stream:
    plistlib.dump(configuration, stream)
tests = args.test or [f'TOGridViewExampleUITests/GridScrollBenchmarks/{name}' for name in [
    'testPortraitPreparationOn', 'testPortraitPreparationOff',
    'testLandscapePreparationOn', 'testLargeDataSet', 'testEditingScroll']]
if args.include_behavior_tests:
    tests += ['TOGridViewExampleTests'] + [f'TOGridViewExampleUITests/ExampleUITests/{name}' for name in [
        'testAddSelectAndDelete', 'testDragReordersCells', 'testRotationAndFullWindowLayout']]
# Isolate cases: this Xcode/iPadOS combination can lose its UI runner between tests.
for index, test in enumerate(tests):
    name = f'{index:02d}-{test.rsplit("/", 1)[-1]}'
    result = output / f'{name}.xcresult'
    run(['xcodebuild', 'test-without-building', '-xctestrun', str(path),
         '-destination', destination, '-parallel-testing-enabled', 'NO',
         '-resultBundlePath', str(result), f'-only-testing:{test}'])
    run(['xcrun', 'xcresulttool', 'export', 'metrics', '--path', str(result),
         '--output-path', str(output / f'{name}-metrics')])
print(f'Results: {output}')
