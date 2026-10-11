import json
import sys
from pathlib import Path

LANGUAGES = {"actions", "javascript-typescript", "python", "ruby", "java-kotlin", "swift"}


def verify(directory, language):
    if language not in LANGUAGES:
        raise ValueError("Unexpected analysis language")
    files = list(Path(directory).glob("*.sarif"))
    if not files:
        raise ValueError("No dry-run analysis results were produced")
    findings = []
    for path in files:
        document = json.loads(path.read_text())
        if document.get("version") != "2.1.0" or not document.get("runs"):
            raise ValueError(f"Missing SARIF analysis in {path.name}")
        for run in document["runs"]:
            if run.get("tool", {}).get("driver", {}).get("name") != "CodeQL":
                raise ValueError(f"Unexpected analysis tool in {path.name}")
            category = run.get("automationDetails", {}).get("id", "")
            if category.rstrip("/") != f"dry-run/{language}":
                raise ValueError(f"Unexpected analysis category in {path.name}")
            invocations = list(run.get("invocations", []))
            if not any(item.get("executionSuccessful") is True for item in invocations):
                raise ValueError(f"No successful analysis invocation in {path.name}")
            conversion = run.get("conversion", {}).get("invocation")
            if conversion is not None:
                invocations.append(conversion)
            for invocation in invocations:
                notifications = [
                    item
                    for field in ("toolExecutionNotifications", "toolConfigurationNotifications")
                    for item in invocation.get(field, [])
                ]
                if invocation.get("executionSuccessful") is False or any(
                    item.get("level") == "error" for item in notifications
                ):
                    raise ValueError(f"Analysis error diagnostics in {path.name}")
            findings.extend((path.name, item["ruleId"]) for item in run.get("results", []))
    for filename, rule_id in findings:
        print(f"{filename}: {rule_id}")
    print(f"Verified {language}: {len(files)} SARIF file(s), {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    try:
        raise SystemExit(verify(sys.argv[1], sys.argv[2]))
    except (ValueError, KeyError, TypeError, IndexError, OSError) as error:
        raise SystemExit(f"Dry-run verification failed: {error}")
