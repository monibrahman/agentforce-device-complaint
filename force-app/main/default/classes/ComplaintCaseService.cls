/**
 * Creates a device complaint Case and routes it to the Complaint Review queue.
 *
 * The adverse-event screen runs again here, server-side, so a complaint is flagged
 * correctly even if the conversation never reached the agent's own screening step.
 */
public with sharing class ComplaintCaseService {
    @TestVisible
    private static final String QUEUE_NAME = 'Complaint_Review';

    public class Request {
        @InvocableVariable(label='Device Name' description='Device name or model' required=true)
        public String deviceName;

        @InvocableVariable(label='Manufacturer' description='Device manufacturer, if known')
        public String manufacturer;

        @InvocableVariable(label='Lot or Serial Number' description='Lot or serial number from the device label, if available')
        public String lotOrSerial;

        @InvocableVariable(label='Event Date' description='Date the problem happened, in YYYY-MM-DD format')
        public String eventDate;

        @InvocableVariable(label='Description' description='What happened with the device, in the customer words' required=true)
        public String description;

        @InvocableVariable(label='Harm Answer' description='Whether anyone was hurt or needed medical attention: yes, no, or unsure')
        public String harmAnswer;

        @InvocableVariable(label='Contact Name' description='Full name of the person reporting' required=true)
        public String contactName;

        @InvocableVariable(label='Contact Email' description='Email address of the person reporting' required=true)
        public String contactEmail;

        @InvocableVariable(label='Contact Phone' description='Phone number of the person reporting, if given')
        public String contactPhone;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True if the complaint case was created')
        public Boolean success;

        @InvocableVariable(label='Case Number' description='Complaint number to give the customer')
        public String caseNumber;

        @InvocableVariable(label='Case Id' description='Salesforce record Id of the complaint case')
        public String caseId;

        @InvocableVariable(label='Is Potential Adverse Event' description='True if the case was flagged for urgent specialist review')
        public Boolean isPotentialAdverseEvent;

        @InvocableVariable(label='Message' description='Error details if the case was not created')
        public String message;
    }

    @InvocableMethod(
        label='Create Device Complaint Case'
        description='Creates a device complaint case, screens it for potential adverse events, and routes it to the Complaint Review queue.'
    )
    public static List<Result> createComplaints(List<Request> requests) {
        Id queueId = getQueueId();
        List<Result> results = new List<Result>();
        List<Case> toInsert = new List<Case>();
        List<Integer> insertIndexes = new List<Integer>();

        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result res = new Result();
            res.success = false;
            results.add(res);

            String validationError = validate(req);
            if (validationError != null) {
                res.message = validationError;
                continue;
            }

            AdverseEventScreener.Result screen = AdverseEventScreener.screenOne(req.description, req.harmAnswer);
            res.isPotentialAdverseEvent = screen.isPotentialAdverseEvent;

            Case c = new Case(
                Subject = ('Device complaint: ' + req.deviceName.trim()).left(255),
                Description = req.description,
                Origin = 'Web',
                Status = 'New',
                Priority = screen.isPotentialAdverseEvent ? 'High' : 'Medium',
                SuppliedName = req.contactName.trim().left(80),
                SuppliedEmail = req.contactEmail.trim(),
                SuppliedPhone = String.isBlank(req.contactPhone) ? null : req.contactPhone.trim().left(40),
                Device_Name__c = req.deviceName.trim().left(120),
                Manufacturer__c = String.isBlank(req.manufacturer) ? null : req.manufacturer.trim().left(120),
                Lot_or_Serial_Number__c = String.isBlank(req.lotOrSerial) ? null : req.lotOrSerial.trim().left(80),
                Event_Date__c = parseDate(req.eventDate),
                Patient_Harm_Reported__c = AdverseEventScreener.isHarmReported(req.harmAnswer),
                Potential_Adverse_Event__c = screen.isPotentialAdverseEvent,
                AE_Screening_Reason__c = screen.screeningReason
            );
            if (queueId != null) {
                c.OwnerId = queueId;
            }
            toInsert.add(c);
            insertIndexes.add(i);
        }

        if (toInsert.isEmpty()) {
            return results;
        }

        Database.SaveResult[] saves = Database.insert(toInsert, false);
        Set<Id> createdIds = new Set<Id>();
        for (Integer j = 0; j < saves.size(); j++) {
            Result res = results[insertIndexes[j]];
            if (saves[j].isSuccess()) {
                res.success = true;
                res.caseId = saves[j].getId();
                createdIds.add(saves[j].getId());
            } else {
                res.message = 'The complaint could not be saved: ' + saves[j].getErrors()[0].getMessage();
            }
        }

        // The agent user may lose read access once the case is owned by the queue,
        // so the case number is read back without sharing.
        Map<Id, String> numbers = new CaseNumberReader().read(createdIds);
        for (Result res : results) {
            if (res.caseId != null) {
                res.caseNumber = numbers.get(res.caseId);
            }
        }
        return results;
    }

    @TestVisible
    private static String validate(Request req) {
        if (String.isBlank(req.deviceName)) {
            return 'Device name is required.';
        }
        if (String.isBlank(req.description)) {
            return 'A description of what happened is required.';
        }
        if (String.isBlank(req.contactName)) {
            return 'Contact name is required.';
        }
        if (String.isBlank(req.contactEmail) ||
            !Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', req.contactEmail.trim())) {
            return 'A valid contact email address is required.';
        }
        return null;
    }

    /** Accepts YYYY-MM-DD. Anything else is left blank rather than failing the complaint. */
    @TestVisible
    private static Date parseDate(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Date d = Date.valueOf(value.trim());
            return d > Date.today() ? null : d;
        } catch (Exception e) {
            return null;
        }
    }

    private static Id getQueueId() {
        List<Group> queues = [
            SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :QUEUE_NAME LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0].Id;
    }

    private without sharing class CaseNumberReader {
        public Map<Id, String> read(Set<Id> caseIds) {
            Map<Id, String> numbers = new Map<Id, String>();
            for (Case c : [SELECT Id, CaseNumber FROM Case WHERE Id IN :caseIds]) {
                numbers.put(c.Id, c.CaseNumber);
            }
            return numbers;
        }
    }
}
