# Zero-cost starter deployment

This repository contains a Render Blueprint at the repository root (`render.yaml`). The FastAPI backend supports PostgreSQL through `DATABASE_URL`; do not use its local SQLite file for a hosted Render Free instance because that filesystem is ephemeral.

## One-time account setup

1. Create a free PostgreSQL project at Neon: https://neon.com/
2. Choose a region close to the Render service (the current Blueprint uses Frankfurt).
3. In the Neon dashboard, copy the pooled PostgreSQL connection string. Keep it private.
4. Sign in to Render with the GitHub account that can access `mynovavpnproxy1/HamidHamid`.
5. In Render, choose **New → Blueprint**, select this repository, and deploy the Blueprint.
6. When Render asks for values, enter:
   - `DATABASE_URL`: the Neon pooled connection string.
   - `ADMIN_USERNAME`: a new administrator username.
   - `ADMIN_PASSWORD`: a unique password of at least 16 characters.
   - `JWT_SECRET`: Render generates this value from `render.yaml`; do not replace it with a weak or reused password.
7. Keep the service on the Free plan. Do not add a payment method just to complete this setup.

## Verify the backend

After the Render deployment finishes, copy the service's HTTPS URL, for example `https://nova-vpn-api.onrender.com`. The actual hostname is assigned by Render and must be copied from the dashboard; do not assume the example hostname is yours.

Open `<your-service-url>/health` to confirm the web process is alive. Then open `<your-service-url>/ready`; this endpoint also checks that the PostgreSQL database can be reached and returns HTTP 200 with:

```json
{"status":"ready"}
```

Render uses `/ready` as its health-check path, so a database outage is not reported as a healthy deployment. Then open `<your-service-url>/admin` and sign in using the administrator credentials you set in Render. Do not put any real VPN profile into the admin panel until the deployment and database have been verified.

## Connect the Android build to the deployed API

In GitHub, open this repository's **Settings → Secrets and variables → Actions → Variables** and create a repository variable:

- Name: `API_BASE_URL`
- Value: the actual Render HTTPS service URL, without a trailing slash.

Do not put administrator passwords, JWT secrets, database connection strings, or VPN profiles in GitHub Variables or in the Android app. Those belong only in the hosting provider's secret/environment settings.

After saving the variable, open **Actions → NOVA VPN CI → Run workflow**. The workflow checks the HTTPS URL, runs the Flutter checks and tests, builds the Android APK, and uploads it as the `nova-vpn-debug-apk` artifact if every required step succeeds.

## Free-tier limitations

This is a zero-cost starter arrangement, not a production uptime guarantee:

- Render Free web services spin down after 15 minutes without inbound traffic and can take about one minute to wake up.
- Render Free local files are ephemeral. The backend must use Neon PostgreSQL for persistent server and device records.
- Neon Free currently has monthly compute and network-transfer quotas and automatically scales idle compute to zero.
- Free services may be restarted or suspended when limits are reached. Do not promise always-on connectivity or commercial-grade availability on these plans.

The backend is only the control plane for accounts, server metadata, and protected profile delivery. VPN user traffic goes directly through the configured VPN server; it does not pass through Render or Neon.

Never commit real server profiles or credentials to this repository. Use the authenticated `/admin` panel over HTTPS to manage them.
