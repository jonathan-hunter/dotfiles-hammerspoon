-- Marks every account's junk folder read, plus any extra "Account/Mailbox"
-- pairs passed as arguments (mail_junk.lua reads them from the gitignored
-- helpers/mail_extra_mailboxes.txt so account names stay out of git).
on run extras
	if application "Mail" is not running then return

	tell application "Mail"
		repeat with acct in every account
			repeat with n in {"Junk", "Junk Email", "[Gmail]/Spam"}
				try -- most accounts have only one of these names
					set mb to mailbox (n as text) of acct
					set read status of (every message of mb whose read status is false) to true
				end try
			end repeat
		end repeat

		set savedDelims to AppleScript's text item delimiters
		set AppleScript's text item delimiters to "/"
		repeat with pair in extras
			set acctName to text item 1 of (pair as text)
			set mbName to (text items 2 thru -1 of (pair as text)) as text
			set mb to mailbox mbName of account acctName
			set read status of (every message of mb whose read status is false) to true
		end repeat
		set AppleScript's text item delimiters to savedDelims
	end tell
end run
