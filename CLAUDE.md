# CLAUDE.md

Context for Claude Code working in this repo.

## What this is

An Agentforce **service agent** for a fictional medical device distributor, Mock Medical Supplier. It takes device complaints, screens every complaint for potential adverse events, checks the public FDA recall API (openFDA), and reports complaint status. It is a portfolio project for a Salesforce Partner Technical Architect (Agentforce) interview, so **the reasoning behind changes matters as much as the changes**. Read `docs/DESIGN.md` before changing behavior.

**Design rule: the conversation is flexible, but safety and record-keeping aren't.** Anything with a compliance consequence (harm screening, escalation, saving the complaint) must be deterministic (`run`, `available when`, `after_reasoning` transitions, server-side Apex), never left to the LLM's discretion.

## Layout

- `force-app/main/default/aiAuthoringBundles/MedTech_Complaint_Agent/MedTech_Complaint_Agent.agent`: the agent, in Agent Script
- `force-app/main/default/classes/`: invocable Apex actions (`AdverseEventScreener`, `ComplaintCaseService`, `DeviceRecallLookup`, `CaseStatusLookup`) and their tests
- `objects/Case/fields`, `queues/Complaint_Review`, `remoteSiteSettings/OpenFDA`, `permissionsets/Complaint_Agent_Access`
- `scripts/deploy.ps1` (Windows) and `scripts/deploy.sh`: deploy, run tests, publish, activate
- `docs/DESIGN.md`: decisions and trade-offs. `docs/BUILD_LOG.md`: every bug, root cause, fix and lesson

## Environment

- Windows, PowerShell. Salesforce CLI (`sf`) is installed and authenticated. The org alias is `complaints`.
- Agent user (the service agent runs as this, **never** the admin): `agent.user.78ad7989505e@agentforce.com`
- The `.agent` file keeps `__AGENT_USER_PLACEHOLDER__` in git. The deploy script swaps the real username in only during publish. Never commit the real username into the `.agent` file.

## Commands

```powershell
# Full deploy: backend, Apex tests, permissions, publish, activate
powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1 complaints -AgentUser agent.user.78ad7989505e@agentforce.com

# Validate Agent Script only (fast; compiles against the org)
# Note: needs the placeholder swapped, so prefer the deploy script for publish.
sf agent validate authoring-bundle --target-org complaints --api-name MedTech_Complaint_Agent

# Apex tests
sf apex run test --target-org complaints --test-level RunLocalTests --code-coverage --result-format human --wait 10

# Talk to the live agent (interactive; the human runs this)
sf agent preview --target-org complaints --api-name MedTech_Complaint_Agent

# Scripted, non-interactive conversation for testing fixes
sf agent preview start --target-org complaints --api-name MedTech_Complaint_Agent
sf agent preview send  --target-org complaints --api-name MedTech_Complaint_Agent --session-id <id> --utterance "..."
sf agent preview end   --target-org complaints --api-name MedTech_Complaint_Agent --session-id <id>
# (check `sf agent preview start --help` etc. for exact flags)

# Traces: which actions ran, which variables were set
sf agent trace list --target-org complaints
sf agent trace read --target-org complaints ...   # see --help
```

## Agent Script references

- Syntax rules: https://github.com/trailheadapps/agent-script-recipes/blob/main/.airules/AGENT_SCRIPT.md
- Working examples: https://github.com/trailheadapps/agent-script-recipes (see `force-app-service/customerServiceAgent` and `force-app/main/04_architecturalPatterns/`)
- Key gotchas: `@utils.setVariables` can't be used with `run`; `run @actions.X` only works for subagent-level actions with a `target`; boolean literals are `True`/`False`; each turn starts at `start_agent`, so the router must route follow-up messages back to an in-progress subagent.

## Open bug (fix this first)

Live test 1 (routine complaint), 2026-09-30. The customer gave the device, error, manufacturer, lot, date, "no one was hurt", name and email.

1. The agent replied "Your report will be recorded…", but **no case was created**. There was no summary read-back and no complaint number.
2. The next message ("can you check and is there a case number?") was routed to `case_status`, which asked for a complaint number the customer never received.
3. The first reply asked four questions at once (the rule is two at most).

Leading hypothesis: `save_complaint_details` / `save_harm_answer` (`@utils.setVariables`) never fired. So `screening_done` stayed False, `submit_complaint` stayed hidden (`available when`), the LLM improvised a false confirmation, and the router re-routed the next turn.

**Confirm with evidence before changing code** (traces or preview transcripts in `temp/agent-preview/`). Likely fixes:
- Stronger "call save immediately whenever the customer provides any detail" instruction (the pattern used in the recipe's CustomerServiceAgent)
- A rule never to say a complaint is recorded or logged until `case_created` is True and a complaint number exists
- Router continuity: if a complaint is in progress and not yet created, route to `complaint_intake`
- Tighter two-questions-at-most guidance in intake

## Working rules

- After any fix: deploy, re-run the failing conversation, and check the Case in the org (Complaint Review queue, Priority, flags).
- Add a row to `docs/BUILD_LOG.md` for every bug: symptom, root cause, fix, lesson. Include wrong turns; they're part of the story.
- Small, focused commits with descriptive messages. Don't force-push.
- Never weaken the adverse-event screening, the server-side re-screen, or the two-factor case status check to make a test pass.
- Explain reasoning in plain language as you go. The repo owner needs to be able to defend every change in an interview.
