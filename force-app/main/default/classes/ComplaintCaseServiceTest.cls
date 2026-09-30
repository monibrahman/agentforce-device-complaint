@IsTest
private class ComplaintCaseServiceTest {
    private static ComplaintCaseService.Request baseRequest() {
        ComplaintCaseService.Request req = new ComplaintCaseService.Request();
        req.deviceName = 'GlucoCheck 3 meter';
        req.manufacturer = 'Acme Diagnostics';
        req.lotOrSerial = 'LOT-4471';
        req.eventDate = '2026-09-01';
        req.description = 'The meter shows an error code E4 every time I insert a strip.';
        req.harmAnswer = 'no';
        req.contactName = 'Jordan Lee';
        req.contactEmail = 'jordan.lee@example.com';
        req.contactPhone = '555-0100';
        return req;
    }

    private static ComplaintCaseService.Result create(ComplaintCaseService.Request req) {
        return ComplaintCaseService.createComplaints(new List<ComplaintCaseService.Request>{ req })[0];
    }

    @IsTest
    static void createsStandardComplaint() {
        ComplaintCaseService.Result res = create(baseRequest());

        System.assertEquals(true, res.success, 'Case not created: ' + res.message);
        System.assertNotEquals(null, res.caseNumber);
        System.assertEquals(false, res.isPotentialAdverseEvent);

        Case c = [
            SELECT Priority, Origin, SuppliedEmail, Device_Name__c, Event_Date__c,
                Potential_Adverse_Event__c, Patient_Harm_Reported__c, OwnerId
            FROM Case WHERE Id = :res.caseId
        ];
        System.assertEquals('Medium', c.Priority);
        System.assertEquals('Web', c.Origin);
        System.assertEquals('jordan.lee@example.com', c.SuppliedEmail);
        System.assertEquals('GlucoCheck 3 meter', c.Device_Name__c);
        System.assertEquals(Date.newInstance(2026, 9, 1), c.Event_Date__c);
        System.assertEquals(false, c.Potential_Adverse_Event__c);
        Id queueId = [
            SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :ComplaintCaseService.QUEUE_NAME
        ].Id;
        System.assertEquals(queueId, c.OwnerId, 'Complaint should be owned by the Complaint Review queue');
    }

    @IsTest
    static void flagsAdverseEventServerSideEvenIfAnswerIsNo() {
        ComplaintCaseService.Request req = baseRequest();
        req.description = 'The pump over-delivered and my son was hospitalized.';
        req.harmAnswer = 'no';

        ComplaintCaseService.Result res = create(req);

        System.assertEquals(true, res.success, 'Case not created: ' + res.message);
        System.assertEquals(true, res.isPotentialAdverseEvent);
        Case c = [SELECT Priority, Potential_Adverse_Event__c, AE_Screening_Reason__c FROM Case WHERE Id = :res.caseId];
        System.assertEquals('High', c.Priority);
        System.assertEquals(true, c.Potential_Adverse_Event__c);
        System.assert(c.AE_Screening_Reason__c.contains('hospital'));
    }

    @IsTest
    static void recordsReportedHarm() {
        ComplaintCaseService.Request req = baseRequest();
        req.harmAnswer = 'yes';
        ComplaintCaseService.Result res = create(req);
        Case c = [SELECT Patient_Harm_Reported__c, Priority FROM Case WHERE Id = :res.caseId];
        System.assertEquals(true, c.Patient_Harm_Reported__c);
        System.assertEquals('High', c.Priority);
    }

    @IsTest
    static void rejectsInvalidEmail() {
        ComplaintCaseService.Request req = baseRequest();
        req.contactEmail = 'not-an-email';
        ComplaintCaseService.Result res = create(req);
        System.assertEquals(false, res.success);
        System.assertEquals(0, [SELECT COUNT() FROM Case]);
    }

    @IsTest
    static void rejectsMissingRequiredFields() {
        ComplaintCaseService.Request req = baseRequest();
        req.deviceName = ' ';
        System.assertEquals('Device name is required.', create(req).message);

        req = baseRequest();
        req.description = null;
        System.assertEquals(false, create(req).success);

        req = baseRequest();
        req.contactName = '';
        System.assertEquals(false, create(req).success);
    }

    @IsTest
    static void ignoresUnparseableOrFutureDates() {
        System.assertEquals(null, ComplaintCaseService.parseDate('last Tuesday'));
        System.assertEquals(null, ComplaintCaseService.parseDate(String.valueOf(Date.today().addDays(3))));
        System.assertEquals(null, ComplaintCaseService.parseDate(null));

        ComplaintCaseService.Request req = baseRequest();
        req.eventDate = 'last Tuesday';
        ComplaintCaseService.Result res = create(req);
        System.assertEquals(true, res.success, 'Case not created: ' + res.message);
    }

    @IsTest
    static void handlesBulkRequests() {
        List<ComplaintCaseService.Request> reqs = new List<ComplaintCaseService.Request>();
        for (Integer i = 0; i < 50; i++) {
            reqs.add(baseRequest());
        }
        ComplaintCaseService.Request bad = baseRequest();
        bad.contactEmail = 'bad';
        reqs.add(bad);

        List<ComplaintCaseService.Result> results = ComplaintCaseService.createComplaints(reqs);

        System.assertEquals(51, results.size());
        System.assertEquals(false, results[50].success);
        System.assertEquals(50, [SELECT COUNT() FROM Case]);
    }
}
