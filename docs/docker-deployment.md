## Deploying with Docker

We provide pre-built Docker images that can be used to run Fizzy on your own server.

If you don't need to change the source code, and just want the out-of-the-box Fizzy experience, this can be a great way to get started.

You'll find the latest version of Fizzy's Docker image at `ghcr.io/basecamp/fizzy:main`.
To run it you'll need three things: a machine that runs Docker; a mounted volume (so that your database is stored somewhere that is kept around between restarts); and some environment variables for configuration.

### Mounting a storage volume

The standard Fizzy setup keeps all of its storage inside the path `/rails/storage`.
By default Docker containers don't persist storage between runs, so you'll want to mount a persistent volume into that location.

The simplest way to do this is with the `--volume` flag with `docker run`. For example:

```sh
docker run --volume fizzy:/rails/storage ghcr.io/basecamp/fizzy:main
```

That will create a named volume (called `fizzy`) and mount it into the correct path.
Docker will manage where that volume is actually stored on your server.

You can also specify the data location yourself, mount a network drive, and more.
Check the Docker documentation to find out more about what's available.

### Configuring with environment variables

To configure your Fizzy installation, you can use environment variables.
Fizzy has several of them.
Many of these are optional, but at a minimum you'll want to configure your secret key, your SSL domain, and your SMTP email settings.

#### Secret Key Base

Various features inside Fizzy rely on cryptography to work (such as secure links).
To set this up, you need to provide a secret value that will be used as the basis of those secrets.
This value can be anything, but it should be unguessable, and specific to your instance.

You can use any long random string for this, or you can have the Fizzy codebase generate one for you by running:

```sh
bin/rails secret
```

Once you have one, set it in the `SECRET_KEY_BASE` environment variable:

```sh
docker run --env SECRET_KEY_BASE=abcdefabcdef ...
```

#### SSL

If you want the Fizzy container to handle its own SSL automatically, you just need to specify the domain name that you're running it on.
You can do that with the `TLS_DOMAIN` environment variable.
Note that if you're using SSL, you'll want to allow traffic on ports 80 and 443.
So if you were running on `fizzy.example.com` you could enable SSL like this:

```sh
docker run --publish 80:80 --publish 443:443 --env TLS_DOMAIN=fizzy.example.com ...
```

If you are terminating SSL in some other proxy in front of Fizzy, then you don't need to set `TLS_DOMAIN`, and can just publish port 80:
```sh
docker run --publish 80:80 ...
```

If you aren't using SSL at all (for example, if you want to run it locally on your laptop) then you should specify `DISABLE_SSL=true` instead:

```sh
docker run --publish 80:80 --env DISABLE_SSL=true ...
```

#### SMTP Email

Fizzy needs to be able to send email for its sign up/sign in flow, and for its regular summary emails.
The easiest way to set this up is to use a 3rd-party email provider (such as Postmark, Sendgrid, and so on).
If email is not configured, you can still sign in by finding the 6-character verification code in your Docker container's logs.

You can then plug all your SMTP settings from that provider into Fizzy via the following environment variables:

- `MAILER_FROM_ADDRESS` - the "from" address that Fizzy should use to send email
- `SMTP_ADDRESS` - the address of the SMTP server you'll send through
- `SMTP_PORT` - the port number (defaults to 465 when `SMTP_TLS` is set, 587 otherwise)
- `SMTP_USERNAME`/`SMTP_PASSWORD` - the credentials for logging in to the SMTP server

Less commonly, you might also need to set some of the following:

- `SMTP_TLS` - set to `true` only for servers requiring implicit TLS (SMTPS on port 465); STARTTLS is used automatically by default so most servers don't need this
- `SMTP_DOMAIN` - the domain name advertised to the server when connecting
- `SMTP_AUTHENTICATION` - if you need an authentication method other than the default `plain`
- `SMTP_SSL_VERIFY_MODE` - set to `none` to skip certificate verification (for self-signed certs)

You can find out more about all these settings in the [Rails Action Mailer documentation](https://guides.rubyonrails.org/action_mailer_basics.html#action-mailer-configuration).

#### Base URL

Fizzy needs to know the public URL of your instance so it can generate correct links in certain situations (like when sending emails).
Set `BASE_URL` to the full URL where your Fizzy instance is accessible:

```sh
docker run --env BASE_URL=https://fizzy.example.com ...
```

#### VAPID keys

Fizzy can also send Web Push notifications.
To do this it needs a VAPID key pair.

You can create your own keys by starting a development console with:

```sh
bin/rails c
```

And then run the following to create the keypair:

```ruby
vapid_key = WebPush.generate_key

puts "VAPID_PRIVATE_KEY=#{vapid_key.private_key}"
puts "VAPID_PUBLIC_KEY=#{vapid_key.public_key}"
```

Set those in the `VAPID_PRIVATE_KEY` and `VAPID_PUBLIC_KEY` environment variables.

#### Authentik single sign-on (optional)

Fizzy can offer "Sign in with Authentik" alongside the usual email and passkey sign-ins, using OpenID Connect.
It's off unless you configure it, and it works with any OpenID Connect provider — Authentik is just what it's tested against.

In Authentik, create an **OAuth2/OpenID Provider** and an application for it:

- Set the redirect URI to `https://fizzy.example.com/auth/authentik/callback`, using your own host. Fizzy always uses this one path, so it doesn't change.
- Leave the client type as **Confidential**, and make sure the `openid`, `email` and `profile` scopes are available.
- Note the client ID and the client secret.
- Note the **OpenID Configuration URL** the provider's page shows, minus the trailing `.well-known/openid-configuration` — that's the value for `AUTHENTIK_ISSUER` below. The path segment in it is the *application's* slug, not the provider's name.

Then set these on your Fizzy container:

| Variable | Required | What it does |
| -------- | -------- | ------------ |
| `AUTHENTIK_ISSUER` | yes | The provider's OpenID Configuration URL without the `.well-known/openid-configuration` suffix, e.g. `https://auth.example.com/application/o/fizzy/`. Don't use the *OpenID Configuration Issuer* field instead: it only matches this when the provider's Issuer mode is the default per-application one, and is just the Authentik root URL when it's set to "Same identifier is used for all providers" |
| `AUTHENTIK_CLIENT_ID` | yes | The provider's client ID |
| `AUTHENTIK_CLIENT_SECRET` | yes | The provider's client secret |
| `AUTHENTIK_LABEL` | no | Name to show on the button. Defaults to `Authentik` |
| `AUTHENTIK_SCOPES` | no | Scopes to request. Defaults to `openid email profile` |
| `AUTHENTIK_ONLY` | no | Set to `true` to close email sign-in and signup. Passkeys stay available |
| `AUTHENTIK_SIGN_OUT_URL` | no | The provider's **End Session** URL, e.g. `https://auth.example.com/application/o/fizzy/end-session/`. When set, signing out of Fizzy signs you out of Authentik too |

You must also set `BASE_URL` (see above): Authentik will only redirect back to the one URI you registered, and Fizzy builds it from `BASE_URL`.
Your container needs to be able to reach Authentik over the network, since Fizzy reads the provider's configuration when someone signs in.

Fizzy adds your Authentik server's origin to its Content Security Policy automatically, which it has to: the sign-in button submits a form that redirects out to Authentik, and browsers check `form-action` against every hop of that redirect.
If you see `violates the following Content Security Policy directive: "form-action 'self'"` in the browser console when you click the button, `AUTHENTIK_ISSUER` isn't reaching the container — check it's set, then restart.
You can also name the origin yourself with `CSP_FORM_ACTION`.

**Who gets in.** Fizzy matches on the email address Authentik reports:

- If that email address already has a Fizzy account, they sign into it. Everything they already have — their boards, comments and notifications — is untouched, and they can still sign in by email or passkey afterwards.
- If it's an email address Fizzy hasn't seen, an account is created for them and they're added to your instance's account, already verified and named. This means anyone who can sign into Authentik can get into Fizzy, so restrict who's bound to the application in Authentik.
- If your instance has several accounts (see multi-tenant mode below), Fizzy won't guess which one to add them to, and they're asked to create their own instead.

Fizzy remembers the user ID Authentik reports the first time someone signs in this way, so changing their email address in Authentik later keeps them on the same Fizzy account.
Two situations are refused rather than guessed at, with an explanation on the sign-in page: an email address that's already linked to a different Authentik user, and an email address changed in Authentik to one that already belongs to somebody else in Fizzy.

A user who's been deactivated in Fizzy doesn't come back by signing in through Authentik — an admin has to re-invite them, exactly as with email sign-in.

**If you set `AUTHENTIK_ONLY=true`**, email sign-in and signup are both closed.
Passkeys keep working, and they're your way back in if Authentik itself becomes unreachable — register one before you lock the instance down.
Otherwise the only way to undo it is to unset the variable and recreate the container: a magic link can't be redeemed once email sign-in is closed, since the flow that issues one is the flow you've just turned off.

#### S3 storage (optional)

If you'd prefer that uploaded files were stored in an S3 bucket rather than in your mounted volume, you can set that up.

First set `ACTIVE_STORAGE_SERVICE` to `s3`.
Then set the following as appropriate for your S3 bucket:

- `S3_BUCKET`
- `S3_REGION`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `CSP_CONNECT_SRC`

If you're using a provider other than AWS, you will also need some of the following:

- `S3_ENDPOINT`
- `S3_FORCE_PATH_STYLE`
- `S3_REQUEST_CHECKSUM_CALCULATION`
- `S3_RESPONSE_CHECKSUM_VALIDATION`

If your storage provider is on a different site than your Fizzy instance and doesn't return CORS headers on presigned URL responses, inline images may fail to load.
In that case, set `SERVICE_WORKER_CORS_ENABLED=false` so the service worker fetches uploaded files without CORS mode.

#### Multi-tenant mode

By default, when you run the Fizzy Docker image you'll be limited to creating a single account (although that account can have as many users as you like).
This is for convenience: typically when you self-host you'll be running a single account, so in this mode new account signups are automatically disabled as soon as you've created your first account.

If you do want to allow multiple accounts to be created in your instance, set `MULTI_TENANT=true`

## Importing an existing Fizzy account

You can move an account between Fizzy instances by exporting it on the old instance and uploading the export zip to the new one during signup.

Imports need free space: at least twice the export file's size, beyond the export itself, since the imported attachments roughly mirror the zip's contents. If there isn't enough, the import fails before it starts and your logs record `import needs ~90 GB free, found 12 GB`. The person importing only sees a generic failure, so check the logs when an import fails for no apparent reason: free up space (or grow the volume) and have them try again. If free space can't be determined, the check is skipped and the import proceeds.

For very large exports:

- Browser uploads pass through Thruster, which drops slow uploads after its read timeout (a 502 before the import ever starts). Raise `THRUSTER_HTTP_READ_TIMEOUT` (seconds) and recreate the container so the setting takes effect.
- `script/import-account` runs the import directly on the server from a zip already on disk, bypassing the browser upload entirely — handy for multi-gigabyte exports.

## Example

Here's an example of a `docker-compose.yml` that you could use to run Fizzy via `docker compose up`

```yaml
services:
  web:
    image: ghcr.io/basecamp/fizzy:main
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      - SECRET_KEY_BASE=abcdefabcdef
      - TLS_DOMAIN=fizzy.example.com
      - BASE_URL=https://fizzy.example.com
      - MAILER_FROM_ADDRESS=fizzy@example.com
      - SMTP_ADDRESS=mail.example.com
      - SMTP_USERNAME=user
      - SMTP_PASSWORD=pass
      - VAPID_PRIVATE_KEY=myvapidprivatekey
      - VAPID_PUBLIC_KEY=myvapidpublickey
      # Optional: sign in with Authentik as well as by email
      - AUTHENTIK_ISSUER=https://auth.example.com/application/o/fizzy/
      - AUTHENTIK_CLIENT_ID=myauthentikclientid
      - AUTHENTIK_CLIENT_SECRET=myauthentikclientsecret
    volumes:
      - fizzy:/rails/storage

volumes:
  fizzy:
```
