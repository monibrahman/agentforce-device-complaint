@IsTest
private class AdverseEventScreenerTest {
    private static AdverseEventScreener.Result run(String description, String harmAnswer) {
        AdverseEventScreener.Request req = new AdverseEventScreener.Request();
        req.description = description;
        req.harmAnswer = harmAnswer;
        return AdverseEventScreener.screen(new List<AdverseEventScreener.Request>{ req })[0];
    }

    @IsTest
    static void flagsWhenCustomerReportsHarm() {
        AdverseEventScreener.Result r = run('The screen went blank.', 'Yes');
        System.assertEquals(true, r.isPotentialAdverseEvent);
        System.assert(r.screeningReason.contains('Customer reported'));
    }

    @IsTest
    static void flagsUnsureAnswer() {
        System.assertEquals(true, run('The screen went blank.', 'not sure').isPotentialAdverseEvent);
    }

    @IsTest
    static void flagsHarmTermsEvenWhenAnswerIsNo() {
        AdverseEventScreener.Result r = run('My mom went to the ER after the pump gave too much insulin.', 'no');
        System.assertEquals(true, r.isPotentialAdverseEvent);
        System.assert(r.screeningReason.contains('er'));
        System.assert(r.screeningReason.contains('too much insulin'));
    }

    @IsTest
    static void handlesPunctuationAroundTerms() {
        System.assertEquals(true, run('He was taken to the ER. Burned his hand.', null).isPotentialAdverseEvent);
    }

    @IsTest
    static void doesNotFlagOrdinaryMalfunction() {
        AdverseEventScreener.Result r = run('The display flickers and the user manual is missing.', 'no');
        System.assertEquals(false, r.isPotentialAdverseEvent);
        System.assertEquals('No indicators of patient harm found.', r.screeningReason);
    }

    @IsTest
    static void handlesBlankInput() {
        AdverseEventScreener.Result r = run(null, null);
        System.assertEquals(false, r.isPotentialAdverseEvent);
    }

    @IsTest
    static void reasonIsTruncatedTo255() {
        String longText = '';
        for (Integer i = 0; i < 20; i++) {
            longText += 'injury burn bleeding hospital surgery seizure ';
        }
        System.assert(run(longText, 'yes').screeningReason.length() <= 255);
    }
}
