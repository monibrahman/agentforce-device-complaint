# Agentforce Medical Device Complaint Agent

An Agentforce service agent for a medical device manufacturer and distributor. It takes  complaints regarding the device and screens every complaint for potential adverse events without leaving that decision to the LLM will escalate to a human, uses public API's to checks the  FDA recall database, and reports complaint status behind a two-factor check.

Uses guardrails, checks in with a human in case for escalation, an external API integration that elegantly fails, least-privilege data access, and an evaluation suite.



Consider all instances of device data to be fictional and for demonstration purposes only. Recall data comes from the real openFDA device recall API(https://open.fda.gov/apis/device/recall/).



## Architecture PFD



```mermaid

flowchart TD

&#x20;   U(\[Customer]) --> R\[agent\_router]

&#x20;   R --> I\[complaint\_intake]

&#x20;   R --> L\[recall\_lookup]

&#x20;   R --> S\[case\_status]

&#x20;   R --> O\[off\_topic]



&#x20;   I -- "run: AdverseEventScreener" --> D{Potential harm?}

&#x20;   D -- "no" --> C\["ComplaintCaseService<br/>Priority: Medium"]

&#x20;   D -- "yes (after\_reasoning)" --> E\[adverse\_event\_escalation]

&#x20;   E --> H\["ComplaintCaseService<br/>Priority: High, flagged"]



&#x20;   C --> Q\[(Complaint Review queue)]

&#x20;   H --> Q



&#x20;   L --> F\[DeviceRecallLookup]

&#x20;   F --> API\[(openFDA API)]



&#x20;   S --> V\["CaseStatusLookup<br/>case number + email"]

```



## Files

|Path|What it is|
|-|-|
|`force-app/main/default/aiAuthoringBundles/MedTech\\\\\\\_Complaint\\\\\\\_Agent/`|The agent, written in Agent Script|
|`force-app/main/default/classes/`|Invocable Apex actions and their tests|
|`force-app/main/default/objects/Case/fields/`|Complaint fields on Case|
|`force-app/main/default/queues/`|Complaint Review queue|
|`force-app/main/default/remoteSiteSettings/`|Allows callouts to api.fda.gov|
|`force-app/main/default/permissionsets/`|Least-privilege access for the agent user|
|`specs/`|Agent evaluation suite|
|`scripts/deploy.sh`|One-command deploy, publish, and activate|
|`docs/`|Design and build log|

## 

## Setup

Prerequisites: a [Developer Edition org with Agentforce](https://developer.salesforce.com/), the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli), and VS Code with the Salesforce Extension Pack and Agentforce DX extensions.

```bash
sf org login web --alias complaints --set-default
./scripts/deploy.sh complaints
sf agent preview --target-org complaints --api-name MedTech\\\\\\\_Complaint\\\\\\\_Agent
```

To try the conversation design before deploying anything, preview the Agent Script in simulated mode. The LLM mocks the actions:

```bash
sf agent preview --target-org complaints --authoring-bundle MedTech\\\\\\\_Complaint\\\\\\\_Agent
```

## Mock Demo:

1. **Routine complaint:** "My glucose meter keeps showing error when I insert a strip." The agent collects details, asks whether anyone was hurt, confirms, and logs a Medium-priority case.
2. **Potential adverse event:** "My dad's insulin pump gave him too much insulin and he ended up in the ER." The agent points to emergency care, skips the read-back, and logs a High-priority flagged case.
3. **Hidden harm:** The customer answers "no" to the harm question, but the description mentions a burn. The server-side screen still flags the case.
4. **Recall lookup:** "Have there been any recalls on infusion pumps?" returns live FDA data with the right caveats.
5. **Case status:** A wrong email returns the same message as a wrong case number.
6. **Guardrail:** "Should I keep using the pump?" The agent declines to give medical advice.

