# Connecting Outlook mail (Microsoft Graph)

## Why Graph and not AppleScript

Your Outlook is 16.112.2 running the new **Hx engine** (`IsRunningNewOutlook = 1`,
`AllAccountsMigratedFromLegacy = 1`). Verified on this machine:

- `get version` works, `count of mail folders` returns 10 — so scripting *is* alive
- but `get every account` fails with **-1728**, `every exchange account` is empty,
  and the only visible folders are the local "On My Computer" set, whose Inbox
  reports **0 messages**

Your real mailbox lives in `HxStore.hxd` and is not reachable through the legacy
scripting object model. Graph talks to the mailbox directly, so it also works
when Outlook is closed.

## What you need to do (about 5 minutes, free)

1. Go to <https://entra.microsoft.com> and sign in with your ADA account.
2. **Applications → App registrations → New registration**.
3. Name it `Pill`. Under *Supported account types* choose
   **Accounts in any organizational directory and personal Microsoft accounts**.
   Leave *Redirect URI* empty. Register.
4. On the app's **Overview** page copy the **Application (client) ID**.
5. Go to **Authentication** → *Advanced settings* → set
   **Allow public client flows** to **Yes** → Save.
   This is what enables the device-code sign-in; without it sign-in fails.
6. Go to **API permissions → Add a permission → Microsoft Graph →
   Delegated permissions** and add **`Mail.ReadBasic`**. (`offline_access` is
   requested automatically.)

If your university tenant blocks self-service app registration, step 2 will fail
and you will need an admin to register it — tell me and we will look at options.

## Then tell Pill the client ID

    mkdir -p ~/Library/Application\ Support/Pill
    cat > ~/Library/Application\ Support/Pill/graph.json <<'JSON'
    { "clientID": "PASTE-YOUR-CLIENT-ID-HERE", "tenant": "common",
      "scopes": ["offline_access", "Mail.ReadBasic"] }
    JSON

Restart Pill, hover the pill, and click **Connect Outlook**. A code appears in the
panel (and is copied to your clipboard) and your browser opens
microsoft.com/devicelogin — paste the code, approve, done.

## Why these choices

- **Device code flow.** A desktop app has no safe redirect URI and cannot keep a
  client secret, so the registration is a *public client* with no secret to leak.
- **`Mail.ReadBasic`, not `Mail.Read`.** ReadBasic returns everything except
  message bodies. The brief asked to prefer metadata-only scopes where they are
  sufficient, and for sender + subject it is. Archive-from-the-pill would need
  `Mail.ReadWrite`, which is a bigger consent and worth asking for separately
  when we build it.
- **The refresh token lives in the keychain**, not in this file. `graph.json`
  holds only the client ID, which is not a secret.

## Known limitation

Graph's push mechanism is webhooks, which need a public HTTPS endpoint a desktop
app does not have. So mail is fetched on a **120-second timer** — the second and
last deliberate exception to the project's no-polling rule (the other is the
countdown timer). The brief asks for batched digests rather than per-message
interruptions, so a periodic check matches the intended behaviour.
