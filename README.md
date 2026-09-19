# WoW Addon Backup

A small, local Windows tool for backing up and restoring World of Warcraft addons and settings. It has an English menu, a double-click launcher, verified ZIP backups and a recovery backup before every restore.

**[Download the latest release](https://github.com/amkomeister/WoW-Addon-Backup/releases/latest)** · [Privacy](PRIVACY.md) · [Report a problem](https://github.com/amkomeister/WoW-Addon-Backup/issues)

Works with Windows PowerShell 5.1 (included with Windows) and PowerShell 7. No installation, administrator access or additional runtime dependencies are normally needed. Use a local drive with enough free space and permission to read the game folders.

## Step-by-step: download and start

1. Open the **Download the latest release** link above.
2. Under **Assets**, download **wow-addon-backup-v1.0.0-windows.zip**. Download **SHA256SUMS.txt** too if you want to check the download. The automatically generated "Source code" archives are for developers.
3. Right-click the ZIP in File Explorer and choose **Extract All**. Extract it to a folder outside your WoW installation. Do not run the launcher from inside the ZIP.
4. Optionally verify the ZIP: open PowerShell in the download folder, run the command below and compare the resulting hash with SHA256SUMS.txt. This checks download integrity; it does not prove that an untrusted source is safe.
5. Close **all** World of Warcraft clients. Wait for the game to finish saving its settings. Close addon managers or other programs that could change those folders.
6. Open the extracted **WoW-Addon-Backup** folder.
7. Double-click **Start-WoWBackup.cmd**. A console with the English menu opens.
8. Choose **5. Help** for a short introduction, or follow the backup steps below.

~~~powershell
Get-FileHash -LiteralPath ".\wow-addon-backup-v1.0.0-windows.zip" -Algorithm SHA256
~~~

The launcher uses Windows PowerShell with an execution policy override for that process only. It does not change your system's execution policy. The scripts are unsigned and readable. Only run a copy you trust. If an organization policy blocks scripts, follow that organization's process; do not disable security software.

## Step-by-step: choose the correct client

1. Locate your World of Warcraft installation in File Explorer. Battle.net's game options may offer **Show in Explorer**.
2. Open the client subfolder you actually use. Select the folder containing a recognized game executable, not the parent "World of Warcraft" folder.
3. Copy that folder's full path from File Explorer's address bar.
4. When the tool asks for the client folder, paste the path. Surrounding double quotes are accepted.
5. Check the client shown by the tool before restoring anything. Use **6. Change Client / Backup Folder** to change it.

| Folder | Stored client type |
| --- | --- |
| _classic_beta_ | classic-beta |
| _classic_ / _classic_ptr_ | classic / classic-ptr |
| _classic_era_ / _classic_era_ptr_ | classic-era / classic-era-ptr |
| _retail_ / _ptr_ / _xptr_ / _beta_ | retail / retail-ptr / retail-xptr / retail-beta |
| _forever_ / _forever_beta_ | forever / forever-beta, if your installation uses these names |

Folder names identify the client type; the tool does not guess from a marketing name or read the game executable. A beta advertised under a different name may still use _classic_beta_. If your folder name is unsupported, report only the generic folder name and game edition. Do not rename the installation just to bypass validation.

## Step-by-step: make a backup

1. Keep WoW and addon managers closed.
2. Choose **1. Back Up**.
3. Paste the client folder path if requested.
4. Check the source and destination printed in the console.
5. Wait for **Backup verified** and the completed ZIP path. Large collections can take several minutes because files are hashed, compressed and read back.
6. Choose **2. List Backups** to see the saved archive.
7. Keep at least one private copy on another physical drive if you want protection from drive failure.

Backups are saved by default to:

~~~text
%LOCALAPPDATA%\WoWAddonBackup\Backups
~~~

Paste that expression into File Explorer's address bar to open the folder. Option **6** lets you choose another local destination, including a removable drive. It must be outside the client and tool folders. Selections last for the current session; the tool writes no persistent configuration.

Each backup has a timestamp and a random suffix, for example:

~~~text
wow-backup-YYYYMMDDTHHMMSSmmmZ-random.zip
~~~

The timestamp is UTC. Existing backups are never overwritten or automatically deleted. Regular backups and recovery backups both appear in the list. Listing a backup does not verify it.

## What is included?

| Included when present | Excluded |
| --- | --- |
| Interface, including AddOns | Game executables and Data |
| WTF, including saved addon and account/character settings | Cache, Logs and Screenshots |
| Fonts | Other installation folders |

Hidden files, empty folders, file contents, last-write times and basic read-only/hidden/system/archive attributes are recorded. A ZIP manifest contains relative paths and SHA-256 hashes. Missing optional folders are skipped. The tool uses explicit .NET ZIP handling because [PowerShell's Compress-Archive skips hidden files](https://learn.microsoft.com/mt-mt/powershell/module/microsoft.powershell.archive/compress-archive?view=powershell-5.1).

Backups are **private and unencrypted**. WTF and addon files may contain account or character names, chat history, server names, saved profiles, addon-specific tokens or other personal data. Restoring requires keeping that data intact. Never upload real backups or local restore state to this repository. See [PRIVACY.md](PRIVACY.md).

## Step-by-step: verify a backup

1. Choose **3. Verify Backup**.
2. Enter a listed backup number or paste a full ZIP path.
3. Wait for **Archive verified**. The tool checks every file against its manifest and rejects unexpected, missing, duplicate or unsafe entries.
4. If verification fails, keep the original archive for private diagnosis and use a different verified backup. A broken archive is never restored.

Only this tool's archive format is supported. ZIPs made with another backup utility are not interchangeable. Checksums detect corruption; they do not authenticate the archive. Restore only backups you created and trust: addon code inside a malicious but internally consistent ZIP could execute later when WoW loads it.

## Step-by-step: restore

1. Close all WoW clients and addon managers. Keep them closed throughout the operation.
2. Choose **4. Restore**.
3. Select the target client folder, then enter a backup number or full ZIP path.
4. Check the displayed archive, target, client type, folders to replace and recovery destination.
5. Type **RESTORE** exactly to continue. Any other answer cancels without writing files.
6. The tool creates and verifies a **wow-recovery-...zip** containing the current versions of the selected folders.
7. It extracts and verifies the requested backup in a staging folder, then replaces only folders named in that backup. Other client folders stay untouched. Files added to a selected folder after the backup are preserved in recovery, but are removed from the active restored folder.
8. Wait for **Restore verified** before opening WoW. Save the recovery ZIP location and the printed **Previous folders** location.

The previous uncompressed folders are retained under the client in **.wow-addon-backup-previous-.../old**. Together with the recovery ZIP, this uses additional disk space. Nothing is automatically deleted. After verifying the restored game setup, you may manually remove old copies that you no longer need. Keep at least one known-good private backup.

A backup can be restored only to the **same client type**. Retail, Classic and beta archives are not interchangeable. The tool does not migrate accounts, characters, addon versions or beta data to a later game release. Server-side settings and game compatibility are outside its scope.

## Interrupted operations and manual recovery

If a backup fails, it is not reported as successful. A normal failure removes only that invocation's unfinished ZIP. A hard shutdown may leave a **.zip.partial** file; the list ignores it. Once no operation is running, you may remove that unfinished file. Existing completed backups are retained.

If a restore fails during replacement, the tool attempts to put the original folders back and verifies them. **RESTORE_ROLLED_BACK** means that succeeded. If the process is killed, power is lost, the disk becomes unavailable or WoW starts during replacement, automatic rollback may be unable to finish.

**ROLLBACK_FAILED** or **RESTORE_RECOVERY_REQUIRED** means: keep WoW closed and preserve the recovery data. A **.wow-addon-backup-restore-...** folder blocks further backups/restores until the interrupted operation has been handled. Do not delete it just to clear the error.

1. Close WoW and this tool. Ensure no backup or restore is still running.
2. Make private copies of the entire **.wow-addon-backup-restore-...** folder, any current Interface/WTF/Fonts folders, and the recovery ZIP on a separate local drive if possible.
3. Inside the interrupted folder, open a **state-...json** file. The records contain the recovery ZIP path, selected **Folders** and **OriginallyPresent** folders. These records contain local paths and must remain private. Phase records may lag the last filesystem action after a sudden shutdown.
4. Open the tool and use **Verify Backup** on the recovery ZIP. Verification is available even while a restore marker blocks other operations.
5. Extract that verified recovery ZIP into a separate private folder, outside the client. It represents the settings just before the failed restore.
6. For each folder in the state's **Folders** list, move its current client copy, if present, into a separate holding folder. Then copy that folder from the extracted recovery ZIP back into the client if it existed there. Replace whole folders; do not merge their contents. Leave unrelated folders alone. A selected folder absent from the recovery ZIP was originally absent and should remain absent.
7. If the recovery ZIP describes an empty client, all its selected folders were originally absent. Moving the newly installed copies aside restores that empty state. The automatic restore command intentionally refuses an empty recovery record.
8. If the recovery ZIP cannot be used, the interrupted folder's **old** subfolder contains original folders already moved aside. **new** and **failed** contain staged or replaced copies. Keep every copy and seek help with a synthetic description before guessing which to discard.
9. Once the original state is recovered, move the entire interrupted transaction folder outside the client and keep it privately. Make a new backup and verify it before resuming normal use.

Folders named **.wow-addon-backup-rolled-back-...** or **.wow-addon-backup-aborted-...** retain evidence/copies from handled failures and do not block operations. They are excluded from backups along with all other non-payload folders.

## Troubleshooting and limits

- **GAME_RUNNING:** close all WoW clients yourself and try again. The tool checks known WoW process names repeatedly. Never start WoW while an operation is running; the tool cannot prevent another program from launching it.
- **PROCESS_CHECK_FAILED:** Windows could not provide the process list. The tool refuses to proceed.
- **Permissions / locked files:** choose a destination you can write to and close programs using the source files. Restore also needs write access to the client folder. Do not run as administrator as a first workaround.
- **Not enough disk space:** make room or choose another local backup drive. Restore needs space for its recovery ZIP and a full extracted copy while retaining the current folders.
- **LINK_NOT_ALLOWED:** symbolic links, junctions and other reparse points are rejected, including redirected/cloud-managed paths. Use ordinary local folders.
- **SOURCE_CHANGED:** settings changed during a snapshot. Close WoW, addon managers and sync tools; retry.
- Network/UNC/device paths, long/unsafe Windows filenames and alternate data streams are unsupported. Keep installation and destination paths reasonably short for PowerShell 5.1.
- Maximums: 100,000 file/directory entries; 100 GiB total expanded payload; each file smaller than 2 GiB; 240 characters per relative archive path. Filesystem path limits may be lower.
- NTFS permissions, ownership, alternate streams, creation/access times and full filesystem metadata are not backed up. This is a settings/file backup, not a disk image.
- Only local files are included. There is no server/cloud-settings backup, account remapping, scheduling, automatic retention cleanup or upload feature.
- Run only one operation for a client at a time in one Windows user session. The tool uses a session-scoped client lock.

## PowerShell commands

You can use the menu in PowerShell 7 as well:

~~~powershell
pwsh -NoProfile -File .\WoWAddonBackup.ps1
~~~

Examples use fictional paths:

~~~powershell
.\WoWAddonBackup.ps1 -Action Backup -GamePath "C:\Games\World of Warcraft\_classic_beta_"
.\WoWAddonBackup.ps1 -Action List -BackupDirectory "D:\PrivateWoWBackups"
.\WoWAddonBackup.ps1 -Action Verify -ArchivePath "D:\PrivateWoWBackups\your-backup.zip"
.\WoWAddonBackup.ps1 -Action Restore -GamePath "C:\Games\World of Warcraft\_classic_beta_" -ArchivePath "D:\PrivateWoWBackups\your-backup.zip" -WhatIf
~~~

Remove **-WhatIf** to perform a restore; the CLI still requires typing **RESTORE**. A successful command or cancellation exits with code 0; failure exits with code 1. The menu stays open after an error so you can correct your selection.

## Game boundaries

The application copies, hashes, archives and restores local files while WoW is closed. It reads process names only to refuse backup/restore when a known WoW client is running. It never sends input to the game, reads game memory, injects code, changes anti-cheat, automates gameplay or closes a process.

This is an independent file utility, not an in-game addon or an official Blizzard product. It does not claim publisher endorsement or guarantee future game compatibility. World of Warcraft is a trademark of Blizzard Entertainment.

## Development and verification

See [CONTRIBUTING.md](CONTRIBUTING.md). Tests use temporary synthetic client folders, including dummy executable files that are never executed. They cover hidden and Unicode files, exact content recovery, cancellation, process guards, unsafe archives, permission denial, rollback and a hard exit during replacement.

GitHub Actions runs the checks on Windows in both supported PowerShell engines. A tagged release is published only after both matrix jobs succeed for that tag's exact commit. Release packaging uses an explicit file allowlist and contains no fixtures, backups or local diagnostics.

MIT licensed. See [LICENSE](LICENSE).
