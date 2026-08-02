# Connect an AI client to Docket MCP

Docket exposes its remote MCP server at:

```
https://YOUR-DOCKET-HOST/api/v1/mcp
```

The server publishes OAuth protected-resource metadata and authorization-server metadata. Clients register dynamically, open Docket's staff login and consent screen, use authorization code with PKCE S256, and receive resource-bound access and rotating refresh tokens. Granted OAuth scopes intersect with the signed-in user's Docket role and tenant entitlements.

## Before connecting

1. Configure **Admin → Settings → Public base URL** with the externally reachable HTTPS origin.
2. Confirm the tenant has the MCP feature enabled.
3. Confirm the connecting staff user has only the role permissions they need.
4. Use the tenant-specific host in shared deployments.

## ChatGPT

ChatGPT full MCP apps require an eligible workspace and developer mode. In ChatGPT workspace or user settings, open **Apps → Create**, enter the Docket MCP endpoint, select OAuth, scan tools, and complete Docket login and consent. Docket advertises `offline_access` and issues rotating refresh tokens for durable connectivity.

ChatGPT cannot connect directly to a localhost-only server. Use the supported secure MCP tunnel for a private development host, or use an externally reachable HTTPS Docket deployment.

## Claude and Claude Desktop

Open **Settings → Connectors**, choose **Add custom connector**, and enter the Docket MCP endpoint. Select **Connect**, sign in to Docket, review the requested scopes, and allow the connection. Claude supports Docket's dynamic client registration, token refresh, tools, prompts, and resources.

## Claude Code

Add the remote server, then authenticate from `/mcp`:

```sh
claude mcp add --transport http docket https://YOUR-DOCKET-HOST/api/v1/mcp
```

Open `/mcp`, select Docket, and follow the browser login and consent flow.

## Generic MCP clients

Start with the MCP endpoint. An unauthenticated request returns a Bearer challenge containing `resource_metadata`. The client then discovers:

- `/.well-known/oauth-protected-resource/api/v1/mcp`
- `/.well-known/oauth-authorization-server`
- `/oauth/register`
- `/oauth/authorize`
- `/oauth/token`

Use `response_type=code`, `code_challenge_method=S256`, the exact registered redirect URI, and `resource=https://YOUR-DOCKET-HOST/api/v1/mcp`. Send the same resource value during code and refresh exchanges.

## Available packaged workflows

The server exposes six prompts: `triage_case`, `resolve_case`, `customer_360`, `qualify_lead`, `review_decisions`, and `operational_health`. It exposes `docket://workflows`, `docket://operator-guide`, and `docket://openapi` resources. The distributable Agent Skill lives at `skills/docket/`.

## Disconnect or revoke

Remove the app in the AI client to delete its local tokens. A Docket operator can deactivate the registered OAuth client or staff user to revoke server-side authorization. Staff deactivation deletes that user's authorization codes, access tokens, refresh tokens, and browser sessions.
