# 003: The passkey's relying party (decision D1)

**Status:** open, needs the owner's decision.

The plan assumes `pki.sgit.ai`, so the app's passkey, door, master vault and key are the same as the web
register's. That needs `https://pki.sgit.ai/.well-known/apple-app-site-association` listing this app under
`webcredentials`, and the Associated Domains capability on the app id. It makes that site vouch for this app.

The alternative is `voicedebrief.ai` (or this site), which gives a separate door and identity.
