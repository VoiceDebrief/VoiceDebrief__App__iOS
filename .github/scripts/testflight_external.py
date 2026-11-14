#!/usr/bin/env python3
"""Puts a TestFlight build in front of external testers: waits for App Store Connect to finish
processing it, writes its "What to Test" from the version's release notes, adds it to the app's
external group and submits it for Beta App Review. Run by .github/workflows/testflight-external.yml.

    testflight_external.py --bundle ai.voicedebrief.app --build 160 --notes website/versions/v0.1.60/index.md

Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8_BASE64 from the environment and prints no secret.
Needs: pip install pyjwt cryptography requests.
"""
import argparse, base64, os, re, sys, time
import jwt, requests

API = 'https://api.appstoreconnect.apple.com/v1'


def token():
    key = base64.b64decode(os.environ['ASC_KEY_P8_BASE64']).decode()
    now = int(time.time())
    return jwt.encode({'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 1100, 'aud': 'appstoreconnect-v1'},
                      key, algorithm='ES256', headers={'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'})


def call(method, path, **kw):
    r = requests.request(method, API + path, headers={'Authorization': f'Bearer {token()}'}, timeout=60, **kw)
    if r.status_code >= 400:
        detail = '; '.join(e.get('detail', '') for e in r.json().get('errors', [])) if r.headers.get('content-type', '').startswith('application/json') else r.text[:300]
        raise RuntimeError(f'{method} {path.split("?")[0]}: {r.status_code} {detail}')
    return r.json() if r.content else {}


def what_to_test(notes_path):
    if not notes_path or not os.path.exists(notes_path):
        return None
    text = open(notes_path).read()
    text = re.sub(r'^# .*\n', '', text)                      # the title
    text = re.sub(r'!?\[([^\]]*)\]\([^)]*\)', r'\1', text)    # links and pictures to their words
    text = re.sub(r'[*`|]', '', text)
    text = re.sub(r'\n{3,}', '\n\n', text).strip()
    return text[:3900]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bundle', required=True)
    ap.add_argument('--build', required=True, help='CFBundleVersion: the CI run number')
    ap.add_argument('--notes', help='the version page to take What to Test from')
    ap.add_argument('--group', default='', help='part of the external group name; default: the first external group')
    ap.add_argument('--no-submit', action='store_true')
    a = ap.parse_args()

    apps = call('GET', f'/apps?filter[bundleId]={a.bundle}')['data']
    if not apps: sys.exit(f'no app with bundle {a.bundle}')
    app = apps[0]['id']

    build = None
    for attempt in range(60):                               # up to 30 minutes for processing
        found = call('GET', f'/builds?filter[app]={app}&filter[version]={a.build}&limit=1')['data']
        if found:
            build = found[0]
            state = build['attributes'].get('processingState')
            print(f'build {a.build}: {state}')
            if state == 'VALID': break
            if state in ('FAILED', 'INVALID'): sys.exit(f'build {a.build} is {state}')
        else:
            print(f'build {a.build}: not in App Store Connect yet')
        time.sleep(30)
    else:
        sys.exit(f'build {a.build} did not finish processing in 30 minutes')
    build_id = build['id']

    if build['attributes'].get('usesNonExemptEncryption') is None:
        call('PATCH', f'/builds/{build_id}', json={'data': {'type': 'builds', 'id': build_id, 'attributes': {'usesNonExemptEncryption': False}}})

    notes = what_to_test(a.notes)
    if notes:
        locs = call('GET', f'/builds/{build_id}/betaBuildLocalizations')['data']
        if locs:
            call('PATCH', f'/betaBuildLocalizations/{locs[0]["id"]}', json={'data': {'type': 'betaBuildLocalizations', 'id': locs[0]['id'], 'attributes': {'whatsNew': notes}}})
        else:
            call('POST', '/betaBuildLocalizations', json={'data': {'type': 'betaBuildLocalizations', 'attributes': {'whatsNew': notes, 'locale': 'en-GB'},
                                                                   'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
        print('What to Test written from', a.notes)

    groups = [g for g in call('GET', f'/betaGroups?filter[app]={app}&limit=50')['data'] if not g['attributes'].get('isInternalGroup')]
    groups = [g for g in groups if a.group.lower() in g['attributes']['name'].lower()] or groups
    if not groups: sys.exit('the app has no external group')
    group = groups[0]
    call('POST', f'/betaGroups/{group["id"]}/relationships/builds', json={'data': [{'type': 'builds', 'id': build_id}]})
    print(f'added to "{group["attributes"]["name"]}"')

    if not a.no_submit:
        try:
            call('POST', '/betaAppReviewSubmissions', json={'data': {'type': 'betaAppReviewSubmissions',
                                                                     'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
            print('submitted for Beta App Review')
        except RuntimeError as e:
            print('not submitted:', e)                    # already submitted, or not needed for this version


if __name__ == '__main__':
    main()
