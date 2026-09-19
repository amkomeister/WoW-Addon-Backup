# Contributing

Keep runtime code compatible with Windows PowerShell 5.1 and PowerShell 7 and avoid external dependencies. Keep user-facing text in English. Add meaningful tests for changes to data handling, archive validation or recovery.

Run these commands from a clone on Windows:

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
pwsh -NoProfile -File .\tests\Run-Tests.ps1
.\scripts\Build-Release.ps1
.\tests\Check-Privacy.ps1 -Staged
~~~

The first two commands use temporary synthetic folders. Do not point tests at a real WoW installation. Some tests replace only the OS process query inside a test module/child process so an open game cannot affect fixtures. The production application has no process-check bypass.

The test suite performs actual filesystem operations, NTFS permission denial and an intentionally terminated child restore. A test child PID is owned by that invocation. Fixture cleanup is bounded to generated temporary folders.

The release builder writes only generated artifacts under dist/ and packages files named in scripts/release-files.json. Review that list, the staged tree and all commit author/committer metadata before publishing. Use a generic contributor name and a GitHub noreply address. Never commit real settings, backups, fixtures generated locally, runtime state or diagnostics.

## Publishing

1. Run both engine suites and the release/privacy checks.
2. Push the reviewed commit and wait for successful Windows checks for that exact SHA.
3. Create and push the version tag, matching the tool and package version.
4. The tag workflow reruns both engine suites and publishes a release only after both pass. It creates a draft, uploads the runnable ZIP and SHA256SUMS.txt, then makes the release public.
5. Verify the published asset checksum and its file list.

Never replace a published version's assets silently; publish a new version for changes. A failed publication may leave a private draft. Inspect it before retrying.
