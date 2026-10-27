# ML_Robocal

## Google Drive uploads

`START.bat` uploads archived logs from `D:\logs\<device serial>` to the
configured Google Drive folder under `yyyyMMdd/<device serial>`.
The `Robocal` subfolder is uploaded as `Robocal.zip`.
ZIP uploads retry transient failures and are checked against the destination
using rclone's size/hash comparison before being reported as successful.
Failed uploads or remote checks retain the ZIP under
`D:\logs\.upload-temp\<device serial>_<component>_<unique suffix>\`.
The console prints the retained path and a command to retry the original upload.
A successful retry builds and checks a fresh ZIP from the archived source;
older retained recovery ZIPs are not automatically deleted.
Background upload failures display an operator notification; a missing
`Robocal` archive is an error, not a successful skipped upload.

Set `GOOGLE_DRIVE_URL` in `START.bat` to the destination folder ID (recommended).
The shared uploader also accepts `https://drive.google.com/drive/folders/<ID>`
and account-specific URLs such as `https://drive.google.com/drive/u/2/folders/<ID>`.
The `/u/2/` account selector does not select the rclone account: uploads use the
account authorized for the `gdrive` remote.

Upload logs are in `ML_Robocal_1.00a_20260804\Tools\logs\rclone-upload-<device serial>.log`.
To check destination access without uploading files:

```powershell
rclone lsd "gdrive:" --drive-root-folder-id "1U9hKoGkFsbvxEMnuKuYXAAUKrL1CcUBn"
```

A `404` with the correct folder ID requires checking that the rclone account
has access to that folder. A `403 rateLimitExceeded` is a Google API quota
failure, not an upload success. Wait before retrying; if the shared-client quota
continues to block uploads, configure your own Google OAuth client ID and secret
for the `gdrive` remote using `rclone config`, then reauthorize it as instructed.
Do not store OAuth secrets or tokens in this repository.
See https://rclone.org/drive/#making-your-own-client-id.

### Dedicated OAuth client and recovery

Run `rclone config` locally, edit the `gdrive` remote, and set its `client_id`
and `client_secret` to your dedicated Google OAuth client. Follow rclone's
instructions to authorize the account that has access to the destination
folder (use `rclone config reconnect gdrive:` if reauthorization is needed).
Enter credentials only in rclone's local interactive configuration, never in
source files, command-line arguments, chat, or committed logs.
Verify folder access with the read-only `rclone lsd` command above.

For historical uploads, explicitly pass the original root folder and date;
do not change `START.bat` back to the old destination. For example, after
confirming that the local archive belongs to the missing historical run:

```powershell
& ".\ML_Robocal_1.00a_20260804\Tools\upload_Folder_to_google_drive.bat" "D:\logs\<device serial>" "1VuN9N7JXBBuHByXVgUjm1jEw18wSW_N6" "gdrive" "20261024/<device serial>"
```

Do not bulk-replay all serial folders into a historical date: local archives
can contain later retests. Check the run timestamps and remote contents first.

Run the offline uploader regression tests on Windows with:

```powershell
python -m unittest discover -s tests -p test_google_drive_upload.py
```