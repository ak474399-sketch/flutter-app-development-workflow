#!/usr/bin/env python3
"""Validate only this bundle, never production services or attached devices."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

BASE=Path(__file__).resolve().parents[1]
REPO=BASE.parents[1]
def run(args,cwd):
    result=subprocess.run(args,cwd=str(cwd),text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    print(result.stdout,end='')
    return {'command':args,'cwd':str(cwd.relative_to(REPO)),'exit_code':result.returncode}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native',action='store_true',help='Build credential-free Android debug host; no installation.')
    args=parser.parse_args()
    steps=[run([sys.executable,'-m','unittest','discover','-s','tests','-v'],BASE)]
    flutter=shutil.which('flutter')
    if not flutter:
        raise SystemExit('Flutter unavailable; Python result alone does not validate SDKs.')
    for name in ['app_growth_sdk','app_iaa_sdk','app_subscription_sdk']:
        folder=BASE/'assets/sdk'/name
        for command in ['pub','analyze','test']:
            options={'pub':['get'],'analyze':[],'test':['--reporter','expanded']}[command]
            step=run([flutter,command]+options,folder);steps.append(step)
            if step['exit_code']:
                raise SystemExit('SDK validation failed: '+name)
    example=BASE/'assets/sdk/example_app'
    for command in [[flutter,'pub','get'],[flutter,'analyze']]:
        steps.append(run(command,example))
    if args.native:
        steps.append(run([flutter,'build','apk','--debug'],example))
    apk=example/'build/app/outputs/flutter-apk/app-debug.apk'
    runtime=json.loads(subprocess.check_output([flutter,'--version','--machine'],text=True))
    report={'environment':{'flutter':runtime.get('frameworkVersion'),'dart':runtime.get('dartSdkVersion'),'scope':'local isolated tests; no device or live-service validation'},'steps':steps,'ok':all(s['exit_code']==0 for s in steps),'expected_tests':{'workflow_and_exports':15,'growth':7,'iaa':8,'subscription':11},'behavior_evaluation':'same-agent walkthrough; no independent model evaluation','limitations':['Real Firebase/Meta receipt and attribution not verified','Real ad fill, SSV and income not verified','Per-product verification backend and store transactions not provided or verified','iOS Meta adapter and iOS builds not implemented/verified']}
    if args.native and apk.exists():
        report['android_debug_host']={'bytes':apk.stat().st_size,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'file':str(apk.relative_to(REPO))}
    (REPO/'VALIDATION.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    raise SystemExit(0 if report['ok'] else 1)
if __name__=='__main__':main()
