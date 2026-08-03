# OlcRTC Manager source provenance

This directory is the canonical, already integrated Olc-cost-l manager source.

- Upstream repository: `BigDaddy3334/olcrtc-manager-panel`
- Upstream base used by the legacy pipeline: `ad8ec6f6f84c9869230dd06d85724c9808ebec6b`
- Audited upstream head: `df626030d21d00286304bc8ef1e990e28c247a55`
- Materialized from clean Olc-cost-l patch-stack: `54aab55988227a785770a133e71971dbcfe6ccb9`
- Materialized: 2026-08-03 on RU Linux build host

Do not replace this directory with upstream wholesale. Audit upstream commits and adapt accepted changes into this source. Production install/update must build this source directly; the old clone/golden/manager-patch path is temporary comparison and rollback machinery only.
