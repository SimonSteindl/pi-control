const API_ORIGIN = "https://shape-squeegee-unblended.ngrok-free.dev";

function withSecurityHeaders(response) {
  const headers = new Headers(response.headers);
  headers.set("X-Robots-Tag", "noindex, nofollow");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  headers.set("X-Frame-Options", "DENY");
  headers.set("Cache-Control", "no-store");
  return new Response(
    [204, 205, 304].includes(response.status) ? null : response.body,
    {
      status: response.status,
      statusText: response.statusText,
      headers,
    },
  );
}

export default {
  async fetch(request, env) {
    const incomingUrl = new URL(request.url);

    // Forward only the fixed /api path to the existing Pi-Control server.
    // This is intentionally not a generic/open proxy.
    if (incomingUrl.pathname === "/api" || incomingUrl.pathname.startsWith("/api/")) {
      const upstreamUrl = new URL(API_ORIGIN);
      upstreamUrl.pathname = incomingUrl.pathname;
      upstreamUrl.search = incomingUrl.search;

      const headers = new Headers(request.headers);
      headers.delete("host");

      const init = {
        method: request.method,
        headers,
        redirect: "manual",
      };
      if (request.method !== "GET" && request.method !== "HEAD") {
        init.body = request.body;
      }

      const upstreamResponse = await fetch(new Request(upstreamUrl.toString(), init));
      // Preserve authentication cookies and API response headers.
      return new Response(
        [204, 205, 304].includes(upstreamResponse.status) ? null : upstreamResponse.body,
        {
          status: upstreamResponse.status,
          statusText: upstreamResponse.statusText,
          headers: upstreamResponse.headers,
        },
      );
    }

    const assetResponse = await env.ASSETS.fetch(request);
    return withSecurityHeaders(assetResponse);
  },
};
