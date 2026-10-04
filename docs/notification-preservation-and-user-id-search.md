# Push preservation and user-ID search

The existing **Сохранять удаленки** switch also controls the notification service extension. Its retention settings are shared through the app group; opening the updated main app once migrates the existing choices without resetting them. **Сохранять в ботах** continues to apply. Secret chats remain excluded.

After decrypting a cloud-message push, the extension attempts to fetch the complete API message before polling differences. A successful fetch stores the message, including text, entities, media references, date and topic/album metadata, in the existing encrypted account Postbox. Both a server deletion in the difference and a `MESSAGE_DELETED` push then mark that record as locally deleted. User-initiated deletion still uses the normal deletion path.

This works while the main app is closed **when iOS launches the notification extension and the complete message is available**. Alert previews are not treated as full messages. A message deleted before it can be fetched, a missing push, inaccessible channel, expired extension deadline or unavailable network cannot be recovered. Media references do not guarantee that the complete media file was downloaded before deletion.

In the normal chat-list search, enter a positive decimal user ID, for example `1234567890`. The client uses a known full user first; otherwise it makes one bounded `users.getUsers` attempt. A resolvable user appears as a normal peer result and opens the usual chat when tapped. Telegram normally requires a session-specific access hash, so an arbitrary unknown ID may produce no user result. This does not bypass privacy, contact restrictions, paid messages or sending permissions. Normal username, phone and message search continues to work.

## Validation

`python3 Tests/notification_id_search/run.py` on macOS compiles the production settings and selected production helpers, checks preference migration across processes, deletion handling, numeric ID parsing and result deduplication, and parses the modified Swift sources. Postbox fixtures model transactions; they do not replace the full IPA build or device validation. Windows can run `--source-only` for extraction and integration checks.

Device checks after installing the IPA:

1. Open the app once. Enable message retention, then close the app. Receive a message push and delete the message from another client after delivery. Reopen: the full captured message should have the existing deleted marker.
2. Repeat with retention disabled, then with bot retention disabled/enabled. Verify disabled cases are deleted normally.
3. Test a topic/album and a text message with entities. Test a message deleted before fetch and ensure no notification-preview message is invented.
4. Search a known user ID and tap the result; verify the chat opens and Telegram's sending rules apply. Search an unknown ID, invalid ID, username and phone number; verify ordinary search still works and no fake user appears.
