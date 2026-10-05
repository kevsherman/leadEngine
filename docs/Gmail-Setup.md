# Connect Google Workspace Gmail

The app reads `kevin.sherman@breezeblock.ca` and sends approved replies as `sales@breezeblock.ca`. Its own OAuth client is required; Gmail authorization in ChatGPT or Codex is not runtime authorization for Rails.

## Local startup

```sh
cd /Users/kevinshouse/Projects/inquiry-to-quote
bin/setup
```

Use **http://127.0.0.1:3000**, sign in with the local operator credentials, and open **Gmail connection** in the header. `bin/setup` generates private local encryption keys, prepares the PostgreSQL schemas, and starts web, CSS and the dedicated Solid Queue worker. Run `source script/env` before standalone Rails commands.

The exact default callback is:

```text
http://127.0.0.1:3000/gmail/callback
```

Use 127.0.0.1 consistently for login and callback: cookies from `localhost` do not accompany a callback to 127.0.0.1. If using another port or a later hosted address, set `GMAIL_REDIRECT_URI` before starting web and worker, and register that exact URI with Google. Google permits localhost loopback redirects for local web-app testing. [Web-server OAuth](https://developers.google.com/identity/protocols/oauth2/web-server)

## Create the business-owned Google Cloud project

1. Sign in to [Google Cloud Console](https://console.cloud.google.com/) as `kevin.sherman@breezeblock.ca`.
2. Open the project selector → **New project**. Use a name such as **Breeze Block Inquiry Desk — Local**. Select the Breeze Block Google Workspace organization and its appropriate parent location. Create and select the project.
3. Go to **APIs & Services → Library**, search for **Gmail API**, and enable it for that project. No service account or domain-wide delegation is needed.

These are the Cloud project and API registration steps from [Google's project guide](https://developers.google.com/workspace/guides/create-project).

## Configure consent and OAuth credentials

1. Open **Google Auth Platform**. If prompted, click **Get started**.
2. In **Branding**, set the application name and Kevin's business email as user support and developer contact.
3. In **Audience**, choose **Internal**. If Internal is unavailable, check that the project is under the Workspace organization rather than a personal account. An external app in Testing can have short-lived refresh authorization; it is not the production background connection described in the spec.
4. In **Data Access**, add only:
   - `https://www.googleapis.com/auth/gmail.readonly`
   - `https://www.googleapis.com/auth/gmail.send`
5. In **Clients → Create client**, choose **Web application**, name it **Inquiry desk local Rails**, and add `http://127.0.0.1:3000/gmail/callback` under **Authorized redirect URIs**. The server-side flow does not need an authorized JavaScript origin.
6. Create the client, copy its client ID and client secret directly into the private app's Gmail configuration form, and click **Save Gmail configuration**. Leave a saved secret blank to preserve it when changing nonsecret settings.
7. Click **Connect / reconnect Google**. Select Kevin's exact business account and consent to both scopes. The app checks the returned mailbox identity, rejects another Google account, and obtains offline authorization for the worker.

Google documents [consent configuration](https://developers.google.com/workspace/guides/configure-oauth-consent), [the scope meanings](https://developers.google.com/workspace/gmail/api/auth/scopes), and [refresh-token expiration conditions](https://developers.google.com/identity/protocols/oauth2#expiration). No `gmail.modify`, settings-write permissions, broad mailbox deletion scope or impersonation authority is requested.

Google consent grants read access to the underlying mailbox, not just the sales alias. The application checks headers before requesting bodies and does not store unrelated mailbox bodies or pass anything to an LLM. There is no LLM integration in this slice.

## Configure Shopify form intake

In Gmail, inspect an actual contact-form notification and enter its exact sender in **Shopify contact-form notification sender addresses**. The conservative starting value is `mailer@shopify.com`; it must be checked against your store. Multiple addresses are comma-separated.

Recognized subjects include **New customer message**, **Contact form**, and **Nouveau message client**. The parser supports plain text and multipart HTML with Name / Nom, Email / E-mail / Courriel, Phone / Phone Number / Téléphone and Body / Message fields. It identifies the customer from form fields, checks any Reply-To against the form email, and never uses the notification sender as the customer. A changed or ambiguous format enters **Messages needing import review**. Inspect the thread in Gmail, enter the confirmed customer identity and explicitly import that selected inquiry; or dismiss it without importing its body.

The actual notification format has not been checked against your mailbox yet. Its sender, field labels and subject should be confirmed with your first real form test. Attachments are recorded as filenames, types, sizes and provider IDs; their contents are not fetched or interpreted. Open them in Gmail for now.

**Import sales messages since** defaults to 14 days before configuration. Change it to control the initial and recovery search. Expanding the date or changing sender filters resets the cursor for a filtered bootstrap without deleting existing conversations. The scheduled worker checks due connections every 15 seconds; the connection's default polling interval is 60 seconds, so actual polls run roughly once per minute. **Sync now** requests an immediate poll. Jobs store only connection/operation IDs, not credentials or message bodies in queue arguments.

## Verify sending identity separately

Connecting enables reading and leaves live sending **off**.

1. In Gmail, open **Settings → See all settings → Accounts → Send mail as**.
2. Confirm `sales@breezeblock.ca` exists and is accepted/verified. Add or verify it in Gmail if necessary.
3. Back in the app, check the confirmation box and click **Verify alias and enable reviewed sending**. The app verifies the alias with read-only API access before allowing sends. [Google send-as read endpoint](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs/get)
4. Each Gmail draft has a review screen identifying live delivery, full To/CC, sales From/Reply-To, subject, body and attachments (none in this slice). **Approve** saves authority for that exact version. It does not send. A separate checkbox and **Send approved reply through Gmail** action request one live send.

Keep the subject unchanged when you want Gmail to group replies in the same thread. The app sends the Gmail thread ID and proper RFC Message-ID, In-Reply-To and References headers. It also follows reference headers when a relevant customer reply starts another Gmail thread. [Gmail threading requirements](https://developers.google.com/workspace/gmail/api/guides/threads)

Fake example conversations always use the fake provider, even when Gmail is connected. The app never falls back between Gmail and fake delivery after a failure. Polling, importing, draft creation, approvals and alias verification do not send emails. Action Mailer remains disabled.

## Failures, reconnecting and uncertain delivery

The connection page shows authorization/connection status, last successful sync, polling and sending state, plus safe error codes. A revoked or expired offline grant requires **Connect / reconnect Google**. Reconnecting retains imported history and the cursor, rotates the authorization version, and turns live sending off until the alias is confirmed again. Changed credentials clear old tokens. Disconnecting stops polls and removes locally stored tokens; Google account → third-party connections can additionally revoke the grant.

A failed sync keeps the last successful cursor; a later poll retries reads. If Gmail's history cursor expires, the app performs a filtered full sync and recovers tracked conversations while deduplicating provider IDs. [Gmail synchronization guide](https://developers.google.com/workspace/gmail/api/guides/sync)

A definite send rejection leaves the operation **Failed**. Fix the connection or alias and explicitly retry the same reviewed operation, or start a new reviewed draft if the old operation is no longer valid. A timeout, 5xx response, malformed success response or worker crash after claiming a send is **Unknown**. Click **Check Gmail send status**: this searches Sent mail using the persisted RFC Message-ID and never issues another send. An empty search is not proof the email was not sent. If it remains unknown, inspect Gmail manually and keep reconciliation pending; automatic resend is deliberately unavailable. Duplicate workers or submissions reuse one operation.

New customer or operator-inbox messages remove pending approval. A queued reply with newer thread activity is blocked before sending. New customer replies after a sent draft open a fresh editable draft; sent drafts and receipts remain available in history. Generic drafting placeholders must be replaced before approval.

## Protect credentials

Client secrets and access/refresh tokens use Active Record Encryption. The local key file is `.local/gmail-encryption.json`, created with mode 0600 and ignored by Git. Do not print it, copy it into chat, or commit it. Preserve it in a secure local backup separately from source; losing it prevents decryption of saved tokens. A future production configuration uses the three `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` environment settings rather than local keys.

The credential form never redisplays secrets. OAuth callback codes/state, tokens, client secrets and raw MIME are filtered from logs; Google HTTP bodies are not logged or used as exception messages. Ordinary errors are fixed codes. OAuth client JSON downloads and `.env` files are ignored by Git. Credentials are not required for automated tests, which use synthetic responses.

## Walkthrough: send yourself a real inquiry

1. Start the app/worker, connect Gmail, and leave live sending **off** for the first intake test.
2. From a personal or second email account that you control, send to **sales@breezeblock.ca** with a unique subject, for example **Gmail integration test — courtyard October 4**, and a body such as **I am considering 80 large white Clover blocks for a courtyard in Vancouver. Could you tell me the next steps?** Using a second account accurately simulates a customer; messages sent from Kevin to the sales alias are not treated as new customer intake.
3. Wait about a minute, or click **Sync now** and refresh the conversation queue. Confirm one Gmail conversation appears, with your sender as the customer and the body you wrote. The app prepares a blank reply scaffold for you, not an AI-generated response.
4. Click **Sync now** again. Confirm the inquiry and message still appear only once. Send an unrelated message from your second account to **kevin.sherman@breezeblock.ca** using a new unrelated subject; it should stay outside the queue.
5. When ready to receive a real test reply in your own second mailbox, verify the sales alias and enable reviewed sending. Edit the draft to **Thanks for your test inquiry. Could you confirm your delivery address?** Save, review the exact recipient/body, approve, then check the separate live-send confirmation and click **Send approved reply through Gmail** once.
6. Confirm the app shows **Sent**, Gmail has one sent message with From and Reply-To **sales@breezeblock.ca**, and your second mailbox received one copy. The app should move to **Waiting for customer**.
7. Reply from your second account to that email. To test direct-to-Kevin handling, address the reply to **kevin.sherman@breezeblock.ca** while retaining the reply thread. After the next poll, it should join the existing app conversation and create a fresh editable draft.
8. Send a relevant reply manually from Kevin's Gmail in that tracked thread to the second account. The next poll should import it as outbound history without duplicating the earlier app-sent reply. Repeat sync to confirm stability.
9. Submit the store's actual Shopify contact form using your second address. Confirm the new inquiry names that customer, not Shopify's notification sender. If it enters import review, confirm the actual sender/labels/Reply-To and resolve the selected message as described above.
10. Finish by disabling live sending if you only want read-only synchronization. Nothing sends automatically; every future app email still needs approval and explicit confirmation.

The Google account/consent, real form structure, actual Gmail delivery and Workspace policy must be tested through these steps after you supply OAuth credentials. Implementation checks do not claim live-account verification.

## Checks and code entry points

```sh
source script/env
bin/rails test
bin/rails test:system
bin/rails worker:health
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --no-pager
```

Read `Gmail::Synchronizer` for polling/cursors, `Gmail::Importer` for privacy and identity rules, `Gmail::Oauth`/`Client` for connection and refresh, `ReplyWorkflow` for approval, and `GmailSendJob`/`GmailReconcileJob` for external-write safety. No Gmail credential is placed in a job argument.
