# Agent instructions

Keep the runtime dependency-free and compatible with Windows PowerShell 5.1 and PowerShell 7. Use only disposable synthetic client folders in tests. Never test restoration against a real installation.

Keep backups, local paths, credentials and diagnostic captures out of Git and releases. Runtime work must stay local; do not add telemetry or gameplay interaction. Require explicit restore confirmation and a verified recovery archive before replacing settings. Preserve unrelated folders.

Run tests/Run-Tests.ps1 in both supported PowerShell versions and scripts/Build-Release.ps1 before publishing. Stage an explicit file list, review commit identity and privacy checks, and require successful Windows CI for the exact release commit. Never overwrite unrelated work.

## Agent skills

### Issue tracker

Use this repository's GitHub Issues. See docs/agents/issue-tracker.md.

### Triage labels

Use needs-triage, needs-info, ready-for-agent, ready-for-human and wontfix. See docs/agents/triage-labels.md.

### Domain docs

Use a single context at the repository root. See docs/agents/domain.md.
