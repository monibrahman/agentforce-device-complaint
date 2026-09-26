/**
 * Deterministic screen for signs of patient harm in a device complaint.
 *
 * Design choice: this is intentionally broad. A false positive costs a complaint
 * specialist a few minutes of review. A missed adverse event can mean a missed FDA
 * reporting deadline. The agent runs this screen with a `run` directive (the LLM
 * does not decide whether to call it), and ComplaintCaseService runs it again
 * server-side before inserting the case.
 */
public with sharing class AdverseEventScreener {
    // Matched against lower-cased text with punctuation replaced by spaces and
    // padded with a space on each side, so ' er ' matches "ER." but not "user".
    @TestVisible
    private static final List<String> HARM_TERMS = new List<String>{
        'injur', 'hurt', 'burn', 'bleed', 'wound', ' cut ', 'laceration',
        ' died ', 'death', 'fatal', 'passed away',
        'hospital', 'emergency room', ' er ', ' ed ', 'urgent care', 'ambulance', ' 911 ',
        'paramedic', 'medical attention', 'treated', 'surgery',
        'infection', 'shock', 'seizure', 'unconscious', 'passed out', 'fainted', 'collapsed',
        'overdose', 'too much insulin', 'underdose', 'hypoglyc', 'hyperglyc', 'low blood sugar',
        'allergic', 'swelling', ' rash', 'stopped breathing', 'could not breathe',
        'couldn t breathe', 'choking', 'cardiac', 'heart attack', ' stroke', ' pain'
    };

    public class Request {
        @InvocableVariable(
            label='Complaint Description'
            description='What the customer says happened with the device'
            required=true
        )
        public String description;

        @InvocableVariable(
            label='Harm Answer'
            description='Answer to whether anyone was hurt or needed medical attention: yes, no, or unsure'
        )
        public String harmAnswer;
    }

    public class Result {
        @InvocableVariable(
            label='Is Potential Adverse Event'
            description='True if a complaint specialist must review this as a potential adverse event'
        )
        public Boolean isPotentialAdverseEvent;

        @InvocableVariable(
            label='Screening Reason'
            description='Why the complaint was or was not flagged'
        )
        public String screeningReason;
    }

    @InvocableMethod(
        label='Screen Complaint for Adverse Event'
        description='Screens a device complaint for signs of patient harm. Returns whether it must be escalated as a potential adverse event.'
    )
    public static List<Result> screen(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(screenOne(req.description, req.harmAnswer));
        }
        return results;
    }

    /** Reused by ComplaintCaseService so the record is flagged even if the agent skipped the screen. */
    public static Result screenOne(String description, String harmAnswer) {
        Result r = new Result();
        Boolean harmReported = isHarmReported(harmAnswer);

        String text = ' ' + (description == null ? '' : description.toLowerCase()) + ' ';
        text = text.replaceAll('[^a-z0-9]', ' ');

        List<String> matched = new List<String>();
        for (String term : HARM_TERMS) {
            if (text.contains(term)) {
                matched.add(term.trim());
            }
        }

        r.isPotentialAdverseEvent = harmReported || !matched.isEmpty();
        if (harmReported) {
            r.screeningReason = 'Customer reported that someone was or may have been hurt or needed medical attention.';
            if (!matched.isEmpty()) {
                r.screeningReason += ' Terms found: ' + String.join(matched, ', ');
            }
        } else if (!matched.isEmpty()) {
            r.screeningReason = 'Harm-related terms found in description: ' + String.join(matched, ', ');
        } else {
            r.screeningReason = 'No indicators of patient harm found.';
        }
        r.screeningReason = r.screeningReason.left(255);
        return r;
    }

    /** "Unsure" counts as harm: when in doubt, a human reviews it. */
    public static Boolean isHarmReported(String harmAnswer) {
        if (String.isBlank(harmAnswer)) {
            return false;
        }
        String a = harmAnswer.trim().toLowerCase();
        return a.startsWith('y') || a.startsWith('unsure') || a.startsWith('not sure') ||
            a.startsWith('maybe') || a == 'true';
    }
}
