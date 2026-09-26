@IsTest
private class DeviceRecallLookupTest {
    private class MockFda implements HttpCalloutMock {
        Integer status;
        String body;
        Boolean throwError = false;
        String lastEndpoint;

        MockFda(Integer status, String body) {
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            lastEndpoint = req.getEndpoint();
            if (throwError) {
                throw new CalloutException('Read timed out');
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    private static final String SAMPLE_BODY =
        '{"meta":{"results":{"skip":0,"limit":5,"total":12}},"results":[' +
        '{"recalling_firm":"Acme Infusion Inc","event_date_initiated":"2025-11-03","recall_status":"Open, Classified",' +
        '"product_description":"Acme SmartFlow infusion pump","reason_for_recall":"Software may cause over-infusion."},' +
        '{"recalling_firm":"Beta Medical","event_date_initiated":"20240115","recall_status":"Terminated",' +
        '"product_description":"Beta infusion pump set","reason_for_recall":"Occlusion alarm may fail."}]}';

    private static DeviceRecallLookup.Result run(String device, String manufacturer) {
        DeviceRecallLookup.Request req = new DeviceRecallLookup.Request();
        req.deviceName = device;
        req.manufacturer = manufacturer;
        return DeviceRecallLookup.search(new List<DeviceRecallLookup.Request>{ req })[0];
    }

    @IsTest
    static void returnsSummaryOfRecalls() {
        MockFda mock = new MockFda(200, SAMPLE_BODY);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        DeviceRecallLookup.Result res = run('infusion pump', 'Acme');
        Test.stopTest();

        System.assertEquals(true, res.success);
        System.assertEquals(12, res.recallCount);
        System.assert(res.summary.contains('Acme Infusion Inc'));
        System.assert(res.summary.contains('2024-01-15'), 'compact dates are formatted');
        System.assert(res.summary.contains('not a finding about any specific unit'));
        System.assert(mock.lastEndpoint.startsWith(DeviceRecallLookup.ENDPOINT));
        System.assert(mock.lastEndpoint.contains('recalling_firm'));
    }

    @IsTest
    static void treats404AsNoRecalls() {
        Test.setMock(HttpCalloutMock.class, new MockFda(404, '{"error":{"code":"NOT_FOUND"}}'));
        Test.startTest();
        DeviceRecallLookup.Result res = run('imaginary widget', null);
        Test.stopTest();

        System.assertEquals(true, res.success);
        System.assertEquals(0, res.recallCount);
        System.assert(res.summary.startsWith('No FDA recall records'));
    }

    @IsTest
    static void failsSoftOnServerError() {
        Test.setMock(HttpCalloutMock.class, new MockFda(500, 'oops'));
        Test.startTest();
        DeviceRecallLookup.Result res = run('insulin pump', null);
        Test.stopTest();

        System.assertEquals(false, res.success);
        System.assert(res.errorMessage.contains('HTTP 500'));
    }

    @IsTest
    static void failsSoftOnTimeout() {
        MockFda mock = new MockFda(200, SAMPLE_BODY);
        mock.throwError = true;
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        DeviceRecallLookup.Result res = run('insulin pump', null);
        Test.stopTest();

        System.assertEquals(false, res.success);
        System.assertNotEquals(null, res.errorMessage);
    }

    @IsTest
    static void requiresDeviceName() {
        DeviceRecallLookup.Result res = run('  "" ', null);
        System.assertEquals(false, res.success);
    }

    @IsTest
    static void sanitizesQueryInput() {
        System.assertEquals('pump AND x', DeviceRecallLookup.sanitize('pump" AND "x'));
        String url = DeviceRecallLookup.buildUrl('insulin pump', null);
        System.assert(!url.contains(' '), 'URL must be encoded');
        System.assert(url.contains('limit=5'));
    }
}
