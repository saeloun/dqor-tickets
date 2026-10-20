import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify_codeql_dry_run.py"
SPEC = importlib.util.spec_from_file_location("dry_run", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DryRunVerificationTest(unittest.TestCase):
    def analysis(self, language="ruby"):
        return {"version": "2.1.0", "runs": [{
            "tool": {"driver": {"name": "CodeQL"}},
            "automationDetails": {"id": f"dry-run/{language}/"},
            "invocations": [{"executionSuccessful": True}], "results": []
        }]}

    def verify(self, documents, language="ruby"):
        with tempfile.TemporaryDirectory() as directory:
            for index, document in enumerate(documents):
                content = document if isinstance(document, str) else json.dumps(document)
                Path(directory, f"{index}.sarif").write_text(content)
            return MODULE.verify(directory, language)

    def test_all_expected_languages(self):
        for language in MODULE.LANGUAGES:
            with self.subTest(language=language):
                self.assertEqual(self.verify([self.analysis(language)], language), 0)

    def test_missing_malformed_or_empty_analysis(self):
        for documents in [[], ["broken"], [{"version": "2.1.0", "runs": []}]]:
            with self.subTest(documents=documents), self.assertRaises(ValueError):
                self.verify(documents)

    def test_wrong_tool_version_language_or_category(self):
        for field in ["tool", "version", "category"]:
            document = self.analysis()
            if field == "tool":
                document["runs"][0]["tool"]["driver"]["name"] = "Other"
            elif field == "version":
                document["version"] = "1.0.0"
            else:
                document["runs"][0]["automationDetails"]["id"] = "dry-run/python/"
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.verify([document])
        with self.assertRaises(ValueError):
            self.verify([self.analysis()], "unknown")

    def test_unsuccessful_missing_or_error_invocations(self):
        for invocation in [None, {}, {"executionSuccessful": False},
                           {"executionSuccessful": True, "toolExecutionNotifications": [{"level": "error"}]},
                           {"executionSuccessful": True, "toolConfigurationNotifications": [{"level": "error"}]}]:
            document = self.analysis()
            document["runs"][0]["invocations"] = [] if invocation is None else [invocation]
            with self.subTest(invocation=invocation), self.assertRaises(ValueError):
                self.verify([document])

    def test_conversion_error_and_mixed_invalid_run(self):
        document = self.analysis()
        document["runs"][0]["conversion"] = {"invocation": {
            "toolConfigurationNotifications": [{"level": "error"}]
        }}
        with self.assertRaises(ValueError):
            self.verify([document])
        with self.assertRaises(ValueError):
            self.verify([self.analysis(), document])

    def test_findings_fail_without_suppressing_results(self):
        document = self.analysis()
        document["runs"][0]["results"] = [{"ruleId": "ruby/example"}]
        self.assertEqual(self.verify([document]), 1)
