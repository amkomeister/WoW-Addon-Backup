# Security

Restore only archives you created and trust. SHA-256 checks detect corruption but do not authenticate authors or make addon code trustworthy.

Archive validation rejects unexpected roots, traversal, unsafe Windows names, duplicates, symbolic links, reparse points, size mismatches and changed contents. Validation holds the archive open without allowing writers during extraction. Backup/restore rejects known running WoW clients and attempts to detect changes to source files.

These safeguards do not make an actively hostile local filesystem safe. Another privileged process could race filesystem changes. Keep WoW, addon managers and sync tools closed, and use ordinary local directories under your control.

For a security report, use GitHub's private vulnerability reporting option if available. Otherwise open a minimal issue asking for a private reporting route, without exploit details or personal data. Never upload a real backup. Include a synthetic reproduction when a private channel has been established.
