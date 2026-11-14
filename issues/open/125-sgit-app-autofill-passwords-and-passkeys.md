# 125: sgit app: AutoFill, passwords and passkeys in other apps and in Safari

**Status:** open, needs the owner. **Owner:** the sgit app session (session_018yvwtQVQdrYtgUXUXD9cVB).

iOS lets a third-party app fill passwords and passkeys elsewhere only as an AutoFill credential provider: an app
extension (`ASCredentialProviderViewController`) with the AutoFill Credential Provider capability, which the
account holder switches on for `ai.sgit.vaults.app` in the developer portal, plus an App Group shared with the
extension (the same one issue 105 waits for). Until then, the app records which passkeys exist and where.
