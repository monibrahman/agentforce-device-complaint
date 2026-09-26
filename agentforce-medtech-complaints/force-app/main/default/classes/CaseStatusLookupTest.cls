@IsTest
private class CaseStatusLookupTest {
    @TestSetup
    static void setup() {
        insert new Case(
            Subject = 'Device complaint: CPAP humidifier',
            Status = 'New',
            Origin = 'Web',
            SuppliedEmail = 'sam@example.com',
            SuppliedName = 'Sam Rivera'
        );
    }

    private static CaseStatusLookup.Result run(String num, String email) {
        CaseStatusLookup.Request req = new CaseStatusLookup.Request();
        req.caseNumber = num;
        req.email = email;
        return CaseStatusLookup.lookup(new List<CaseStatusLookup.Request>{ req })[0];
    }

    private static String existingNumber() {
        return [SELECT CaseNumber FROM Case LIMIT 1].CaseNumber;
    }

    @IsTest
    static void findsCaseWithMatchingNumberAndEmail() {
        CaseStatusLookup.Result res = run(existingNumber(), 'SAM@example.com');
        System.assertEquals(true, res.found);
        System.assertEquals('New', res.status);
        System.assertEquals('Device complaint: CPAP humidifier', res.subject);
        System.assertNotEquals(null, res.lastUpdated);
    }

    @IsTest
    static void acceptsNumberWithoutLeadingZeros() {
        String unpadded = String.valueOf(Integer.valueOf(existingNumber()));
        System.assertEquals(true, run('Case #' + unpadded, 'sam@example.com').found);
    }

    @IsTest
    static void wrongEmailAndWrongNumberGiveSameMessage() {
        CaseStatusLookup.Result wrongEmail = run(existingNumber(), 'someone.else@example.com');
        CaseStatusLookup.Result wrongNumber = run('99999999', 'sam@example.com');

        System.assertEquals(false, wrongEmail.found);
        System.assertEquals(false, wrongNumber.found);
        System.assertEquals(wrongEmail.message, wrongNumber.message);
        System.assertEquals(null, wrongEmail.status, 'no details leak on a failed match');
    }

    @IsTest
    static void rejectsBlankOrInvalidInput() {
        System.assertEquals(false, run(null, 'sam@example.com').found);
        System.assertEquals(false, run(existingNumber(), '').found);
        System.assertEquals(false, run('abc', 'sam@example.com').found);
    }
}
