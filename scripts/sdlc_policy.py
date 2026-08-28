"""Stable path, risk, state, and artifact policy for Utter's SDLC validator."""

STATUSES = ("intent", "designed", "planned", "implementing", "verified", "released", "closed")
RISKS = ("low", "medium", "high")

REQUIRED_HEADINGS = {
    "intent": (
        "## Problem", "## Outcome", "## Scope", "## Constraints",
        "## Acceptance criteria", "## Open questions",
    ),
    "spec": (
        "## Context", "## Design", "## Safety and failure modes",
        "## Test strategy", "## Rollout and rollback",
    ),
    "plan": ("## Work items", "## Verification plan", "## Human gates"),
    "verification": (
        "## Evidence", "## Acceptance criteria", "## Residual risk", "## Decision",
    ),
}


def is_governed_path(path: str) -> bool:
    if path.startswith("docs/sdlc/changes/") or path.startswith("docs/research/"):
        return False
    if path in {"Package.swift", "Package.resolved", ".gitignore", "AGENTS.md", "CLAUDE.md"}:
        return True
    return path.startswith(
        (
            "Sources/", "SourcesCLI/", "Resources/", "Tests/", "scripts/",
            ".github/", "docs/sdlc/", "docs/index.html", "docs/assets/",
        )
    )


def minimum_risk(path: str) -> str:
    high_risk_paths = {
        "Resources/Info.plist", "Resources/OpenType.entitlements", "scripts/build-app.sh",
        "scripts/build-version.sh", "scripts/ci-basic-checks.sh",
        "scripts/create-signing-cert.sh", "scripts/sdlc.py",
        "scripts/release-version.sh", "scripts/sdlc_policy.py", "scripts/verify-release-artifact.sh",
    }
    high_risk_prefixes = (
        ".github/workflows/", "Sources/Audio/", "Sources/Integration/",
        "Sources/Hotkey/", "Sources/LLM/", "Sources/Output/", "Sources/Screen/",
    )
    high_risk_source_files = {
        "Sources/App/VoicePipeline+CorrectionCapture.swift",
        "Sources/App/VoicePipeline+ScreenContext.swift",
        "Sources/Config/AppSettings.swift",
        "Sources/Speech/AppleSpeechEngine.swift",
    }
    if path in high_risk_paths or path in high_risk_source_files or path.startswith(high_risk_prefixes):
        return "high"
    if path in {"Package.swift", "Package.resolved", ".gitignore", "AGENTS.md", "CLAUDE.md"}:
        return "medium"
    if path.startswith(
        (
            ".github/", "Sources/", "SourcesCLI/", "Resources/",
            "docs/sdlc/", "docs/index.html", "docs/assets/", "scripts/",
        )
    ):
        return "medium"
    return "low"
