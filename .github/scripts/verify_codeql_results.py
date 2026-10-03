import json
import sys
from pathlib import Path

files = list(Path(sys.argv[1]).glob("*.sarif"))
if not files:
    raise SystemExit("No native analysis results were produced")

findings = []
for path in files:
    document = json.loads(path.read_text())
    if not document.get("runs"):
        raise SystemExit(f"No analysis runs in {path.name}")
    for run in document["runs"]:
        invocations = list(run.get("invocations", []))
        conversion = run.get("conversion", {}).get("invocation")
        if conversion is not None:
            invocations.append(conversion)
        for invocation in invocations:
            notifications = [
                notification
                for field in ("toolExecutionNotifications", "toolConfigurationNotifications")
                for notification in invocation.get(field, [])
            ]
            if invocation.get("executionSuccessful") is False or any(
                notification.get("level") == "error" for notification in notifications
            ):
                raise SystemExit(f"Analysis error diagnostics in {path.name}")
        rules = {rule["id"]: rule for rule in run["tool"]["driver"]["rules"]}
        for result in run.get("results", []):
            rule_id = result["ruleId"]
            severity = rules.get(rule_id, {}).get("properties", {}).get("security-severity")
            findings.append((path.name, rule_id, severity or "unrated"))

for filename, rule_id, severity in findings:
    print(f"{filename}: {rule_id} (security severity {severity})")
print(f"Analyzed {len(files)} native SARIF file(s); {len(findings)} finding(s)")
raise SystemExit(1 if findings else 0)
