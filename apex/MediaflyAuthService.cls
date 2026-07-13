/**
 * Handles Mediafly's two-step authentication for the P&G Sales Companion
 * Level 1 content-search integration.
 *
 *   Step 1 — HTTP Basic Auth (service-account username:password + Company Code)
 *            against the Mediafly Accounts API returns an Access Token that is
 *            valid for roughly one hour.
 *   Step 2 — That token is sent as `Authorization: Bearer <token>` on Launchpad
 *            content calls (see SearchMediaflyContentAction). Launchpad has no
 *            login endpoint of its own; it only consumes the token.
 *
 * DESIGN DECISION — service account:
 * Mediafly's public API exposes no OAuth / delegated / on-behalf-of flow, so
 * this integration authenticates as a single dedicated Mediafly *user* (a
 * "service account"). All rep searches run under that one identity. See
 * Mediafly-Agent-Action-Walkthrough.md for the full rationale and
 * trade-offs.
 *
 * SECURITY:
 *   - Credentials live in the Mediafly_Accounts Named/External Credential,
 *     never in this class or in source control.
 *   - Company Code and Product Id live in Mediafly_Config__mdt, never hardcoded.
 *   - The ~1 hour token is cached in Platform Cache and reused across reps to
 *     avoid re-authenticating on every call.
 *
 * REFERENCE IMPLEMENTATION: the token endpoint path and the token field name in
 * the response are marked TODO — confirm them against the Mediafly Accounts API
 * documentation for the target tenant before deploying.
 */
public with sharing class MediaflyAuthService {

    // Named Credential storing the service-account username/password and
    // pointing at the Mediafly Accounts API host.
    private static final String ACCOUNTS_NAMED_CREDENTIAL = 'callout:Mediafly_Accounts';

    // Org Platform Cache partition used to share the short-lived token across
    // invocations and reps. Create an Org partition named 'Mediafly'.
    private static final String CACHE_PARTITION = 'Mediafly';
    private static final String CACHE_KEY = 'accessToken';

    // Refresh a little before the ~1 hour expiry to avoid edge-of-expiry 401s.
    private static final Integer TOKEN_TTL_SECONDS = 3000; // 50 minutes

    // Within-transaction memo so repeated calls in one execution reuse the token.
    private static String transactionToken;

    /**
     * Returns a valid Mediafly access token, fetching a new one only when the
     * cached token is missing or expired.
     */
    public static String getAccessToken() {
        if (String.isNotBlank(transactionToken)) {
            return transactionToken;
        }
        String cachedToken = readCache();
        if (String.isNotBlank(cachedToken)) {
            transactionToken = cachedToken;
            return cachedToken;
        }
        String fresh = requestNewToken();
        writeCache(fresh);
        transactionToken = fresh;
        return fresh;
    }

    /**
     * Forces a fresh token fetch. Call after Launchpad returns 401 so a stale
     * cached token is replaced rather than reused.
     */
    public static String refreshAccessToken() {
        transactionToken = null;
        clearCache();
        return getAccessToken();
    }

    private static String requestNewToken() {
        HttpRequest req = new HttpRequest();
        // TODO: confirm the exact Accounts API token path for the tenant.
        req.setEndpoint(ACCOUNTS_NAMED_CREDENTIAL + '/tokens');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        // The Named Credential supplies the Basic Authorization header when it is
        // configured with the service-account username/password. The Company Code
        // is supplied from custom metadata.
        req.setHeader('X-Company-Code', nullSafe(MediaflyConfig.companyCode()));
        req.setTimeout(20000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            System.debug('MediaflyAuthService: token request failed — HTTP ' + res.getStatusCode());
            throw new MediaflyAuthException('Unable to authenticate with Mediafly (HTTP ' + res.getStatusCode() + ').');
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        // TODO: confirm the token field name in the Accounts API response.
        String token = (String) body.get('accessToken');
        if (String.isBlank(token)) {
            throw new MediaflyAuthException('Mediafly authentication succeeded but returned no token.');
        }
        return token;
    }

    private static String readCache() {
        try {
            return (String) Cache.Org.getPartition(CACHE_PARTITION).get(CACHE_KEY);
        } catch (Exception e) {
            // Cache partition not configured — fall back to fetching a token.
            System.debug('MediaflyAuthService: cache read unavailable — ' + e.getMessage());
            return null;
        }
    }

    private static void writeCache(String token) {
        try {
            Cache.Org.getPartition(CACHE_PARTITION).put(CACHE_KEY, token, TOKEN_TTL_SECONDS);
        } catch (Exception e) {
            System.debug('MediaflyAuthService: cache write unavailable — ' + e.getMessage());
        }
    }

    private static void clearCache() {
        try {
            Cache.Org.getPartition(CACHE_PARTITION).remove(CACHE_KEY);
        } catch (Exception e) {
            System.debug('MediaflyAuthService: cache clear unavailable — ' + e.getMessage());
        }
    }

    private static String nullSafe(String s) {
        return s == null ? '' : s;
    }

    public class MediaflyAuthException extends Exception {}
}
