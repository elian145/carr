# DRAFT: what actually happens to data when a user deletes their account

**Status: DRAFT for the product owner. FLAG FOR LEGAL REVIEW before any of this wording is
published (privacy policy, `/delete-account` page, in-app strings, Play Data Safety, Apple App
Privacy).** This is not legal advice. It documents the behaviour of the code at base `1aab2ef`
(`kk/routes/auth.py::delete_account`, `kk/models.py`, `kk/routes/chat.py`). Nothing here changes
production behaviour; the live legal pages (`kk/legal/privacy.html`, `kk/legal/delete_account.html`)
and in-app l10n strings are **not** edited (they are pinned by tests and are a legal decision).
Background: an internal F-29 deletion-privacy matrix (kept outside the repository).

## 1. Chat messages and chat media remain after deletion (ACTUAL behaviour)

When a user deletes their account (Profile -> Delete account, SMS code or password):

- **Chat message text stays.** Chat messages the user sent or received are **not deleted**. The
  message rows are kept; the user's link is removed (`sender_id`/`receiver_id` become NULL through
  `ON DELETE SET NULL`). **The other participant (the counterpart) can still read the message text**,
  and so can administrators.
- **Chat media stays.** Photos, videos and voice messages sent in a chat (`attachment_url`,
  `attachments`, `listing_preview` on the message row, and the files in the chat storage bucket /
  `chat_uploads`) are **not deleted** by account deletion. The deletion routine only deletes listing
  media, the profile picture and dealer cover/verification files. The counterpart can keep
  opening chat media through the normal chat-media access path.
- **No retention period is stated or implemented.** There is no automatic expiry job for chat
  messages or chat media: they are retained for an **unspecified period; no automatic expiry is
  implemented**. No number of days or months should be promised anywhere.
- **Who could delete them afterwards?** The only chat-delete endpoint
  (`DELETE /api/chat/messages/<id>`) lets a user delete **their own sent** messages
  (`sender_id` must equal the caller). After account deletion the departed user's messages have
  `sender_id = NULL`, so **the counterpart has no in-app way to delete them** (they can only block
  or stop using the conversation). Removal would be an operator/database action. So "retained
  until deleted by the counterpart" would NOT be accurate for the departed user's messages; the
  accurate statement is "retained for an unspecified period, no automatic expiry".
- A user can delete their *own* message while their account still exists (message text, attachment
  reference and preview are cleared, the message is marked deleted). That is a different action
  from account deletion, and account deletion does **not** do it on the user's behalf. (Whether
  that per-message delete also removes the stored media *file* was not verified here.)

## 2. What is removed or anonymised on account deletion (verified from code)

| Data | After deletion |
|---|---|
| Account row: login, name, username, phone, email, password hash, locale, push token, profile-picture row | **Deleted** (hard delete of the `user` row) |
| Profile picture file | Deleted from storage (best effort; failures are only logged) |
| Favourites, recently viewed, saved searches (+ alerts), blocks, notifications, user action/analytics log | Deleted |
| Login tokens/blacklist entries, password-reset and e-mail-verification rows | Deleted |
| Listings | Taken offline (inactive/hidden), seller link removed; description, VIN, contact numbers and map coordinates cleared; listing photos/videos deleted (storage deletion best effort). The listing row with title/spec fields, price, free-text `location` and counters is **kept** |
| Chat messages and chat media | **Kept** (section 1). Sender/receiver link removed (NULL) but each row keeps `deleted_counterpart_marker` = the old numeric user id (not shown in API responses; used to group a conversation). That is a pseudonymous, re-linkable id inside the database, **not full anonymisation** |
| User reports / listing reports | Kept; reporter/reported link removed; free-text fields kept |
| Dealer application | Kept as an audit row with personal/contact/document fields cleared and files deleted; dealer public profile and cover photo deleted |
| App logs | `account_deleted user_id=<id> username=<username>` is written to the application log; the username is **not** purged from logs |
| Backups / provider-side records (SMS provider, mailbox for web deletion requests, error tracking) | Not purged by the app; retention is the provider's / operator's |

## 3. Suggested accurate wording (DRAFT, not yet published, needs legal sign-off)

> When you delete your account, your login, profile, favourites, saved searches and similar
> personal account data are deleted, and your listings are taken offline with their photos, videos,
> description, VIN and contact details removed.
> **Messages and media you exchanged in chats are not deleted.** The text of your messages, and any
> photos, videos or voice messages you sent in a chat, remain visible to the other person in that
> conversation (and to our administrators), and they are no longer linked to your name or account.
> We do not currently delete them automatically and we do not state a fixed retention period for
> them. [OPEN DECISION: whether and how the other participant or we can delete them later.]
> Do not share anything in a chat that you would not want the other person to keep.

Placeholders / not invented: no retention period, no "within N days", no statutory basis.

## 4. Open decisions (explicit; none are implemented)

1. **Keep as is, or change code?** Options: keep and disclose (this draft); redact `content` on
   deletion; delete the media the user sent from the chat bucket and mark messages "media removed";
   delete messages the user sent; add a retention TTL. (Product + legal.)
2. **Is retention for an unspecified period (no automatic expiry, no counterpart delete path)
   acceptable** under the applicable law (Iraq / KRG), or is a fixed period required or forbidden?
   Should the counterpart get a way to delete the departed user's messages? (Legal + product.)
3. **Pseudonymous marker:** may `deleted_counterpart_marker` (old user id) remain on chat rows, and
   is "no longer linked to you" accurate while it exists?
4. **Message bodies and media can contain personal data** (names, phones, licence plates, faces,
   documents). Is keeping them visible to the counterpart acceptable without redaction?
5. **Store forms:** Play Data Safety / Apple App Privacy must be consistent with section 1
   (chat media and messages are retained after account deletion; "data deletion" answers should not
   claim that all user content is deleted). Apple 5.1.1(v) / Google account-deletion policy review
   is needed.
6. **Logs:** whether to stop logging `username` in `account_deleted` (code change owned by the
   auth owner, not done here), and the retention of app logs, backups and provider records.
7. **Live pages:** the live `/privacy` and `/delete-account` texts currently mention only chat
   *message text* in their retention paragraphs (chat media is listed as collected). Updating them
   requires approval, new wording and updating the tests that pin the current text; deliberately not
   done in this change.

## 5. Related: demo/seed photos in the repository

Committed demo photos under `kk/static/uploads` / `static/uploads` are served publicly. In this
change the plates in the retained demo photos were blurred in place and one personal street photo
was replaced by a neutral placeholder (see `scripts/blur_demo_plates.py` and
`kk/tests/test_f27_demo_photo_plate_privacy.py`).
