/**
 * Level 1 Mediafly content search for the P&G Sales Companion.
 *
 * Called by the mediafly_content_search subagent when a rep asks for sales
 * assets ("what materials do I have for Oral-B iO hygienist training?", "pull
 * up the Gingivitis ER sell sheet"). Searches Mediafly's Launchpad API and
 * returns a short, ranked list of matching assets with direct links back into
 * Mediafly.
 *
 * LEVEL 1 SCOPE — find & link only:
 * Mediafly stays the single source of truth. This action returns asset metadata
 * (title, type) and the shareable Mediafly link.href. It does NOT return or
 * reason over the text inside PDFs, decks, or videos — the Launchpad search API
 * does not expose document contents (results are ItemModel objects carrying a
 * free-form `metadata` dictionary plus `link.href`, not extracted text). See
 * specs/Mediafly-Agent-Action-Walkthrough.md for the Level 2 (in-asset Q&A)
 * discussion and why it is out of scope.
 *
 * Auth: uses MediaflyAuthService for the cached service-account bearer token.
 */
public with sharing class SearchMediaflyContentAction {

    private static final Integer DEFAULT_LIMIT = 3;
    private static final Integer MAX_LIMIT = 5;
    private static final String LAUNCHPAD_NAMED_CREDENTIAL = 'callout:Mediafly_Launchpad';

    @InvocableMethod(
        label='Search Mediafly Content'
        description='Searches Mediafly for P&G sales materials (sell sheets, training decks, videos, leave-behinds) and returns direct links. Call when the rep asks for content or assets. Do NOT call for account briefings or visit logging.'
        category='P&G Sales Companion'
    )
    public static List<Response> search(List<Request> requests) {
        Request req = requests[0];
        Response out = new Response();
        out.results = new List<String>();

        if (String.isBlank(req.searchTerm)) {
            out.isSuccess = false;
            out.errorMessage = 'Tell me what you are looking for and I will search Mediafly.';
            out.summary = out.errorMessage;
            return new List<Response>{ out };
        }

        Integer resultLimit = normalizeLimit(req.resultLimit);

        try {
            HttpResponse res = callLaunchpad(req.searchTerm, resultLimit, MediaflyAuthService.getAccessToken());

            // Retry once with a fresh token if the cached one was rejected.
            if (res.getStatusCode() == 401) {
                System.debug('SearchMediaflyContentAction: token rejected, refreshing and retrying.');
                res = callLaunchpad(req.searchTerm, resultLimit, MediaflyAuthService.refreshAccessToken());
            }

            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                System.debug('SearchMediaflyContentAction: Launchpad HTTP ' + res.getStatusCode());
                out.isSuccess = false;
                out.errorMessage = 'I could not reach Mediafly just now. Please try again in a moment, or contact your admin if it keeps happening.';
                out.summary = out.errorMessage;
                return new List<Response>{ out };
            }

            List<Asset> assets = parseAssets(res.getBody(), resultLimit);
            if (assets.isEmpty()) {
                out.isSuccess = true;
                out.summary = 'I did not find any Mediafly assets for "' + req.searchTerm + '". Try a more specific product, topic, or asset name.';
                return new List<Response>{ out };
            }

            out.isSuccess = true;
            out.summary = formatSummary(req.searchTerm, assets);
            for (Asset a : assets) {
                out.results.add(
                    a.title
                    + (String.isNotBlank(a.contentType) ? ' (' + a.contentType + ')' : '')
                    + (String.isNotBlank(a.link) ? ' — ' + a.link : '')
                );
            }
            return new List<Response>{ out };

        } catch (Exception ex) {
            System.debug('SearchMediaflyContentAction: error — ' + ex.getMessage());
            out.isSuccess = false;
            out.errorMessage = 'Something went wrong searching Mediafly. Please try again in a moment.';
            out.summary = out.errorMessage;
            return new List<Response>{ out };
        }
    }

    private static Integer normalizeLimit(Integer requested) {
        if (requested == null || requested <= 0) {
            return DEFAULT_LIMIT;
        }
        return Math.min(requested, MAX_LIMIT);
    }

    private static HttpResponse callLaunchpad(String term, Integer resultLimit, String token) {
        String endpoint = LAUNCHPAD_NAMED_CREDENTIAL
            + '/' + MediaflyConfig.apiVersion() + '/items/search'
            + '?productId=' + EncodingUtil.urlEncode(nullSafe(MediaflyConfig.productId()), 'UTF-8')
            + '&Term=' + EncodingUtil.urlEncode(term, 'UTF-8')
            + '&Limit=' + resultLimit
            + '&IsAISearch=true';

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(endpoint);
        httpReq.setMethod('GET');
        httpReq.setHeader('Authorization', 'Bearer ' + token);
        httpReq.setHeader('Accept', 'application/json');
        httpReq.setTimeout(20000);
        return new Http().send(httpReq);
    }

    /**
     * Parses the SearchResultsApiResponse envelope:
     *   { success, message, response: { results: [ ItemModel ... ] }, errorCode }
     * Each ItemModel keeps its descriptive fields in a free-form `metadata`
     * dictionary; the shareable URL is on `link.href`.
     */
    private static List<Asset> parseAssets(String body, Integer resultLimit) {
        List<Asset> assets = new List<Asset>();
        Map<String, Object> envelope = (Map<String, Object>) JSON.deserializeUntyped(body);

        Object responseObj = envelope.get('response');
        if (!(responseObj instanceof Map<String, Object>)) {
            return assets;
        }
        Object resultsObj = ((Map<String, Object>) responseObj).get('results');
        if (!(resultsObj instanceof List<Object>)) {
            return assets;
        }

        for (Object itemObj : (List<Object>) resultsObj) {
            if (!(itemObj instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> item = (Map<String, Object>) itemObj;
            Map<String, Object> metadata = item.get('metadata') instanceof Map<String, Object>
                ? (Map<String, Object>) item.get('metadata')
                : new Map<String, Object>();

            Asset a = new Asset();
            a.title = firstNonBlank(new List<String>{
                asString(metadata.get('title')),
                asString(metadata.get('name')),
                asString(item.get('type'))
            });
            if (String.isBlank(a.title)) {
                a.title = 'Untitled Mediafly asset';
            }
            a.contentType = firstNonBlank(new List<String>{
                asString(metadata.get('contentType')),
                asString(metadata.get('fileType')),
                asString(item.get('type'))
            });
            a.link = extractHref(item.get('link'));

            assets.add(a);
            if (assets.size() >= resultLimit) {
                break;
            }
        }
        return assets;
    }

    private static String extractHref(Object linkObj) {
        if (linkObj instanceof Map<String, Object>) {
            return asString(((Map<String, Object>) linkObj).get('href'));
        }
        return asString(linkObj);
    }

    private static String formatSummary(String term, List<Asset> assets) {
        String s = 'Here are the top Mediafly matches for "' + term + '":\n';
        Integer i = 1;
        for (Asset a : assets) {
            s += '\n' + i + '. ' + a.title
                + (String.isNotBlank(a.contentType) ? ' (' + a.contentType + ')' : '')
                + (String.isNotBlank(a.link) ? ' — ' + a.link : '');
            i++;
        }
        return s;
    }

    private static String asString(Object o) {
        return o == null ? null : String.valueOf(o);
    }

    private static String nullSafe(String s) {
        return s == null ? '' : s;
    }

    private static String firstNonBlank(List<String> vals) {
        for (String v : vals) {
            if (String.isNotBlank(v)) {
                return v;
            }
        }
        return null;
    }

    public class Request {
        @InvocableVariable(label='Search Term' description='The product, topic, or asset name the rep asked for.' required=true)
        public String searchTerm;

        @InvocableVariable(label='Account ID' description='Optional Salesforce Account Id if already resolved. Reserved for account-aware search in a later phase.')
        public String accountId;

        @InvocableVariable(label='Limit' description='Maximum number of Mediafly results to return. Defaults to 3, capped at 5.')
        public Integer resultLimit;
    }

    public class Response {
        @InvocableVariable(label='Summary' description='Short ranked list of Mediafly assets with links, ready to show the rep.')
        public String summary;

        @InvocableVariable(label='Results' description='Structured per-asset result strings.')
        public List<String> results;

        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    private class Asset {
        String title;
        String contentType;
        String link;
    }
}
