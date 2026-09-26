/**
 * Searches the public FDA openFDA device recall database.
 * https://open.fda.gov/apis/device/recall/
 *
 * Fails soft: on timeouts or server errors it returns success = false with a
 * plain message, so the agent says it can't check right now instead of guessing.
 * openFDA returns HTTP 404 when nothing matches; that is a valid "zero recalls" answer.
 */
public with sharing class DeviceRecallLookup {
    @TestVisible
    private static final String ENDPOINT = 'https://api.fda.gov/device/recall.json';
    private static final Integer MAX_RESULTS = 5;
    private static final Integer MAX_IN_SUMMARY = 3;

    public class Request {
        @InvocableVariable(label='Device Name' description='Device type or name to search for, for example insulin pump or glucose meter' required=true)
        public String deviceName;

        @InvocableVariable(label='Manufacturer' description='Manufacturer name to narrow the search, if the customer gave one')
        public String manufacturer;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True if the FDA database was searched successfully')
        public Boolean success;

        @InvocableVariable(label='Recall Count' description='Total number of matching recall records')
        public Integer recallCount;

        @InvocableVariable(label='Summary' description='Plain-text summary of the most recent matching recalls')
        public String summary;

        @InvocableVariable(label='Error Message' description='Why the search could not be completed')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Search FDA Device Recalls'
        description='Searches the public FDA device recall database by device name and optional manufacturer, newest first.'
    )
    public static List<Result> search(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(searchOne(req));
        }
        return results;
    }

    private static Result searchOne(Request req) {
        Result res = new Result();
        res.success = false;
        res.recallCount = 0;

        String device = sanitize(req.deviceName);
        if (String.isBlank(device)) {
            res.errorMessage = 'A device name is required to search for recalls.';
            return res;
        }

        HttpRequest http = new HttpRequest();
        http.setEndpoint(buildUrl(device, sanitize(req.manufacturer)));
        http.setMethod('GET');
        http.setTimeout(10000);

        try {
            HttpResponse resp = new Http().send(http);
            Integer status = resp.getStatusCode();
            if (status == 404) {
                res.success = true;
                res.summary = 'No FDA recall records matched "' + device + '".';
            } else if (status == 200) {
                parse(resp.getBody(), res);
                res.success = true;
            } else {
                res.errorMessage = 'The FDA recall database returned an error (HTTP ' + status + '). Please try again later.';
            }
        } catch (Exception e) {
            res.errorMessage = 'The FDA recall database could not be reached right now. Please try again later.';
        }
        return res;
    }

    @TestVisible
    private static String buildUrl(String device, String manufacturer) {
        String query = 'product_description:"' + device + '"';
        if (String.isNotBlank(manufacturer)) {
            query += ' AND recalling_firm:"' + manufacturer + '"';
        }
        return ENDPOINT +
            '?search=' + EncodingUtil.urlEncode(query, 'UTF-8') +
            '&sort=event_date_initiated:desc' +
            '&limit=' + MAX_RESULTS;
    }

    /** Strips characters that would break the openFDA query syntax. */
    @TestVisible
    private static String sanitize(String value) {
        if (value == null) {
            return null;
        }
        return value.replaceAll('[^A-Za-z0-9 \\-]', ' ').normalizeSpace().left(100);
    }

    private static void parse(String body, Result res) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> meta = (Map<String, Object>) root.get('meta');
        Map<String, Object> metaResults = meta == null ? null : (Map<String, Object>) meta.get('results');
        List<Object> records = (List<Object>) root.get('results');
        if (records == null) {
            records = new List<Object>();
        }

        res.recallCount = metaResults != null && metaResults.get('total') != null
            ? Integer.valueOf(metaResults.get('total'))
            : records.size();

        List<String> lines = new List<String>();
        for (Integer i = 0; i < Math.min(records.size(), MAX_IN_SUMMARY); i++) {
            Map<String, Object> r = (Map<String, Object>) records[i];
            lines.add(
                '- ' + str(r, 'recalling_firm', 120) +
                ' | initiated ' + formatDate(str(r, 'event_date_initiated', 10)) +
                ' | status: ' + str(r, 'recall_status', 40) +
                ' | product: ' + str(r, 'product_description', 150) +
                ' | reason: ' + str(r, 'reason_for_recall', 250)
            );
        }
        res.summary = String.valueOf(res.recallCount) + ' FDA recall record(s) found. Most recent:\n' + String.join(lines, '\n') +
            '\nSource: FDA openFDA device recall database. This is data about the product line, not a finding about any specific unit.';
    }

    private static String str(Map<String, Object> r, String key, Integer maxLen) {
        Object v = r.get(key);
        return v == null ? 'unknown' : String.valueOf(v).normalizeSpace().abbreviate(maxLen);
    }

    /** openFDA dates look like 2024-03-15 or 20240315. */
    @TestVisible
    private static String formatDate(String raw) {
        if (raw != null && raw.length() == 8 && raw.isNumeric()) {
            return raw.substring(0, 4) + '-' + raw.substring(4, 6) + '-' + raw.substring(6, 8);
        }
        return raw;
    }
}
