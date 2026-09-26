/**
 * Returns the status of a complaint only when the caller supplies BOTH the case
 * number and the email address on the complaint.
 *
 * Runs without sharing because the agent user does not own complaint cases
 * (they belong to the Complaint Review queue). The two-factor match below is the
 * access control. A wrong number and a wrong email return the same message, so
 * the action can't be used to discover which case numbers exist.
 */
public without sharing class CaseStatusLookup {
    @TestVisible
    private static final String NOT_FOUND =
        'No complaint matched that complaint number and email address.';

    public class Request {
        @InvocableVariable(label='Case Number' description='Complaint number the customer was given, for example 00001026' required=true)
        public String caseNumber;

        @InvocableVariable(label='Email' description='Email address the customer used on the complaint' required=true)
        public String email;
    }

    public class Result {
        @InvocableVariable(label='Found' description='True if a complaint matched both the number and the email')
        public Boolean found;

        @InvocableVariable(label='Status' description='Current status of the complaint')
        public String status;

        @InvocableVariable(label='Last Updated' description='Date the complaint was last updated, YYYY-MM-DD')
        public String lastUpdated;

        @InvocableVariable(label='Subject' description='Complaint subject')
        public String subject;

        @InvocableVariable(label='Message' description='Message to relay when no complaint is found')
        public String message;
    }

    @InvocableMethod(
        label='Get Complaint Status'
        description='Looks up a complaint by complaint number and the email address on the complaint.'
    )
    public static List<Result> lookup(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(lookupOne(req));
        }
        return results;
    }

    private static Result lookupOne(Request req) {
        Result res = new Result();
        res.found = false;
        res.message = NOT_FOUND;

        String num = normalizeCaseNumber(req.caseNumber);
        String email = req.email == null ? null : req.email.trim();
        if (num == null || String.isBlank(email)) {
            return res;
        }

        // SOQL string comparison is case-insensitive, so email case doesn't matter.
        List<Case> cases = [
            SELECT CaseNumber, Status, Subject, LastModifiedDate
            FROM Case
            WHERE CaseNumber = :num AND SuppliedEmail = :email
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            return res;
        }

        Case c = cases[0];
        res.found = true;
        res.status = c.Status;
        res.subject = c.Subject;
        res.lastUpdated = String.valueOf(c.LastModifiedDate.date());
        res.message = null;
        return res;
    }

    /** Accepts "1026", "#1026", "Case 00001026" and pads to Salesforce's 8-digit format. */
    @TestVisible
    private static String normalizeCaseNumber(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String digits = raw.replaceAll('[^0-9]', '');
        if (String.isBlank(digits) || digits.length() > 10) {
            return null;
        }
        return digits.leftPad(8, '0');
    }
}
