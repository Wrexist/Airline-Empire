#!/usr/bin/env python3
"""Require successful launch and full device evidence for the uploaded commit."""
import json
import os
import urllib.parse
import urllib.request

REQUIRED_JOURNEYS = ("campaign", "economy", "shell + map", "arrival", "map home")

def has_full_device_evidence(jobs):
    completed = [j for j in jobs if j.get("conclusion") == "success"]
    for journey in REQUIRED_JOURNEYS:
        matching = [j for j in completed if j.get("name") == f"iOS app (xcodebuild) · {journey}"]
        if not any(any(s.get("name") == "Run the UI tests" and s.get("conclusion") == "success"
                       for s in j.get("steps", [])) for j in matching):
            return False
    return any(j.get("name") == "iPad shell (regular width)" for j in completed)

def main():
    repository = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    token = os.environ["GH_TOKEN"]
    base = f"https://api.github.com/repos/{repository}/actions/"
    def get(path):
        request = urllib.request.Request(base + path, headers={
            "Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    runs = get("runs?" + urllib.parse.urlencode({"head_sha": sha, "status": "success", "per_page": 100}))["workflow_runs"]
    runs = [r for r in runs if r.get("head_sha") == sha and r.get("conclusion") == "success"]
    launch = [r for r in runs if r.get("path") == ".github/workflows/launch-safety.yml"]
    if not launch:
        raise SystemExit("Upload blocked: Launch safety has not passed for this exact commit.")
    for run in runs:
        if run.get("path") != ".github/workflows/ci.yml":
            continue
        jobs = get(f"runs/{run['id']}/jobs?per_page=100")["jobs"]
        if has_full_device_evidence(jobs):
            print(f"Release evidence passed for {sha}: CI {run['id']}, Launch safety {launch[0]['id']}")
            return
    raise SystemExit("Upload blocked: run CI with suite=full and ipad=true on this exact commit, and resolve every failure.")

if __name__ == "__main__":
    main()
