# Test Plan

Contract Revision: 1
Status: draft

## Scope

- Acceptance contract: `doc/acceptance-contract.json`
- Target routes / surfaces: see contract `surfaces`
- P0 flows: see contract `p0_user_flows`

## Inputs

- FE self-check: `doc/fe-self-check.md`
- BE self-check: `doc/be-self-check.md`
- Screenshot manifest: `doc/acceptance-screenshots/manifest.json`

## Planned Coverage

- Contract-defined P0 user flows
- Required UI / API states
- Non-regression constraints listed in the contract
- Screenshot evidence listed in the contract

## Planned Checks

- Automated tests: pending first QA run
- Manual QA: pending first QA run
- Visual review handoff: pending first QA run

## Risks To Watch

- Context recovery mismatch between implementation and acceptance artifacts
- Missing FE / BE self-check evidence
- Screenshot evidence out of date with contract revision

## Notes

- This file exists so resumed sessions know where QA planning evidence belongs.
