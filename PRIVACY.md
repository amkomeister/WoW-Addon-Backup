# Privacy

The downloaded application has no networking, telemetry, uploads, analytics, crash reporting or update checks. It operates on the client and destination selected by the user. It reads running process names to detect known WoW clients; it does not inspect process memory.

The source code and release contain generic code and documentation only. Development tests generate artificial data in temporary folders. Those fixtures are not bundled with the runnable release.

## Your backups stay private

Backups preserve the original addon and settings data needed to restore your setup. That data can include account/character/server names, saved profiles, chat-related data and any personal information or credentials an addon has written into its files. The tool does not redact it. ZIP archives are not encrypted.

Default storage is %LOCALAPPDATA%\WoWAddonBackup\Backups. You may select another local folder. Restore also writes local transaction records and preserved folders inside the client. Transaction records include local paths and must remain private. The tool never sends these files to GitHub.

Keep private backups outside repositories, shared folders and cloud-sync folders. Files outside this tool's control may be synchronized by other software. Anyone who can read your backup files may be able to read their contents.

## Public bug reports

Share only the generic error code, tool version and a description using fictional paths and data. Do not attach real ZIP backups, manifests, saved variables, account/character details, local state JSON, console screenshots, system logs, computer names, personal paths or credentials.

Before publishing code changes, review the staged tree, commit metadata and release allowlist. The automated privacy check is a heuristic aid; it cannot recognize every kind of personal information.
