#!/usr/bin/env python3
"""Prints the newest TestFlight crash reports of an app (the ones testers chose to Share), with their crash
logs, so the developer can read them without opening App Store Connect. Prints no secret.

    testflight_crashes.py --bundle ai.voicedebrief.app [--limit 5]

Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8_BASE64 from the environment. Needs pyjwt cryptography requests.
"""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from testflight_external import call


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bundle', required=True)
    ap.add_argument('--limit', type=int, default=5)
    a = ap.parse_args()
    apps = call('GET', f'/apps?filter[bundleId]={a.bundle}')['data']
    if not apps: sys.exit(f'no app with bundle {a.bundle}')
    app = apps[0]['id']
    subs = call('GET', f'/apps/{app}/betaFeedbackCrashSubmissions?sort=-createdDate&limit={a.limit}')['data']
    print(f'{len(subs)} crash report(s) shared by testers, newest first\n')
    for s in subs:
        at = s['attributes']
        print('=' * 72)
        for k in ('createdDate', 'buildBundleId', 'appPlatform', 'deviceModel', 'osVersion', 'locale', 'comment', 'deviceFamily'):
            if at.get(k) is not None: print(f'{k}: {at[k]}')
        try:
            log = call('GET', f'/betaFeedbackCrashSubmissions/{s["id"]}/crashLog')['data']['attributes'].get('logText', '')
            print('\n' + log[:60000])
        except RuntimeError as e:
            print('crash log not available:', e)
        print()


if __name__ == '__main__':
    main()
