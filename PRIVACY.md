# Privacy

Codex Usage Widget is designed to keep account data local.

- It does not read `auth.json`, browser cookies, API keys, access tokens, account IDs, or email addresses.
- It starts the locally installed `codex app-server --stdio` process and requests `account/rateLimits/read`, `account/usage/read`, and `account/read`.
- It uses only rate-limit percentages, reset times, plan name, login presence, and the aggregate lifetime token count for display.
- It does not persist responses, create logs, collect analytics, or send data to a developer-controlled server.
- Network requests needed to obtain Codex usage are made by the installed Codex process under the user's existing Codex authentication.

The installer writes application files to the current user's Local AppData directory, creates Desktop and Start menu shortcuts, and registers an uninstall entry under the current user's Windows registry hive.
