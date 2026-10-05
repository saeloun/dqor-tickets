import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify_codeql_results.py"


class ResultVerificationTest(unittest.TestCase):
    def verify(self, documents):
        with tempfile.TemporaryDirectory() as directory:
            for index, document in enumerate(documents):
                content = document if isinstance(document, str) else json.dumps(document)
                Path(directory, f"{index}.sarif").write_text(content)
            return subprocess.run(
                [sys.executable, str(SCRIPT), directory], capture_output=True, text=True
            )

    def analysis(self, results=None, invocations=None):
        return {"runs": [{"tool": {"driver": {"rules": []}},
                          "results": results or [], "invocations": invocations or [],
                          "properties": {"metricResults": [{
                              "ruleId": "java/summary/lines-of-code-kotlin", "value": 1
                          }]}}]}

    def test_clean_analysis(self):
        self.assertEqual(self.verify([self.analysis(), self.analysis()]).returncode, 0)

    def test_unrated_finding_is_not_ignored(self):
        self.assertNotEqual(self.verify([self.analysis([{"ruleId": "java/example"}])]).returncode, 0)

    def test_missing_malformed_or_empty_analysis(self):
        for documents in [[], ["broken"], [{"runs": []}], [self.analysis(), "broken"]]:
            with self.subTest(documents=documents):
                self.assertNotEqual(self.verify(documents).returncode, 0)

    def test_failed_execution_or_error_diagnostic(self):
        for invocation in [{"executionSuccessful": False},
                           {"toolExecutionNotifications": [{"level": "error"}]},
                           {"toolConfigurationNotifications": [{"level": "error"}]}]:
            with self.subTest(invocation=invocation):
                self.assertNotEqual(self.verify([self.analysis(invocations=[invocation])]).returncode, 0)

    def test_conversion_error_is_not_ignored(self):
        document = self.analysis()
        document["runs"][0]["conversion"] = {"invocation": {
            "executionSuccessful": True,
            "toolConfigurationNotifications": [{"level": "error"}]
        }}
        self.assertNotEqual(self.verify([document]).returncode, 0)

    def test_missing_or_zero_kotlin_coverage(self):
        for metrics in [[], [{"ruleId": "java/summary/lines-of-code-kotlin", "value": 0}]]:
            with self.subTest(metrics=metrics):
                document = self.analysis()
                document["runs"][0]["properties"]["metricResults"] = metrics
                self.assertNotEqual(self.verify([document]).returncode, 0)

    def test_optional_extension_rules_and_security_rating(self):
        document = self.analysis()
        document["runs"][0]["tool"]["extensions"] = [{"name": "empty-pack"}]
        self.assertEqual(self.verify([document]).returncode, 0)
        document["runs"][0]["tool"]["extensions"].append({"rules": [{
            "id": "java/example", "properties": {"security-severity": "8.0"}
        }]})
        document["runs"][0]["results"] = [{"ruleId": "java/example"}]
        result = self.verify([document])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("security severity 8.0", result.stdout)
