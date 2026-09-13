#!/usr/bin/env python3
"""Keep TestFlight's validation and immutable checkout contract intact."""
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]


def workflow(name):
    # BaseLoader preserves GitHub's `on` key and expression strings.
    return yaml.load((ROOT / f".github/workflows/{name}.yml").read_text(encoding="utf-8"),
                     Loader=yaml.BaseLoader)


class ReleaseWorkflowTests(unittest.TestCase):
    def test_archive_cannot_run_before_all_gates_succeed(self):
        jobs = workflow("ios-testflight")["jobs"]
        self.assertEqual(set(jobs["archive"]["needs"]),
                         {"preflight", "full-validation", "launch-validation"})
        for name in ("archive", "full-validation", "launch-validation"):
            self.assertNotIn("if", jobs[name], "Default success gating must not be bypassed")
            self.assertNotIn("continue-on-error", jobs[name])

    def test_release_explicitly_requests_full_iphone_and_ipad(self):
        job = workflow("ios-testflight")["jobs"]["full-validation"]
        self.assertEqual(job["uses"], "./.github/workflows/ci.yml")
        self.assertEqual(job["with"]["suite"], "full")
        self.assertEqual(job["with"]["ipad"], "true")

    def test_validation_and_archive_share_the_preflight_candidate(self):
        jobs = workflow("ios-testflight")["jobs"]
        expected = "${{ needs.preflight.outputs.candidate-sha }}"
        for name in ("full-validation", "launch-validation"):
            self.assertEqual(jobs[name]["needs"], "preflight")
            self.assertEqual(jobs[name]["with"]["candidate_sha"], expected)
        checkout = next(s for s in jobs["archive"]["steps"]
                        if s.get("uses", "").startswith("actions/checkout@"))
        self.assertEqual(checkout["with"]["ref"], expected)
        self.assertEqual(jobs["launch-validation"]["uses"],
                         "./.github/workflows/launch-safety.yml")

    def test_every_reusable_checkout_uses_the_candidate(self):
        for name in ("ci", "launch-safety"):
            data = workflow(name)
            self.assertEqual(data["on"]["workflow_call"]["inputs"]["candidate_sha"]["required"], "true")
            for job in data["jobs"].values():
                for step in job.get("steps", []):
                    if step.get("uses", "").startswith("actions/checkout@"):
                        self.assertEqual(step["with"]["ref"], "${{ inputs.candidate_sha || github.sha }}")

    def test_reusable_runs_do_not_cancel_their_caller_or_standalone_safety(self):
        groups = [workflow(name)["concurrency"]["group"]
                  for name in ("ci", "launch-safety", "ios-testflight")]
        self.assertEqual(len(set(groups)), 3)
        self.assertIn("github.workflow", groups[1])

    def test_all_five_phone_journeys_remain_in_the_full_matrix(self):
        plan = next(s for s in workflow("ci")["jobs"]["plan"]["steps"]
                    if s.get("name") == "Decide")
        full = plan["run"].split("full)", 1)[1].split(";;", 1)[0]
        for name in ("campaign", "economy", "shell + map", "arrival", "map home"):
            self.assertIn(f'name: "{name}"', full)
        self.assertIn('if [ -n "$CANDIDATE_SHA" ]', plan["run"])
        self.assertIn("inputs.ipad", workflow("ci")["jobs"]["app-ipad"]["if"])


if __name__ == "__main__":
    unittest.main()
