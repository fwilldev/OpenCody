# OpenCody 1.10 – App Store release notes

Notifications for OpenCode 2. Get a notification when a run finishes, fails or needs your answer, even while OpenCody is closed. Approve or deny a permission right from the notification.

To set it up, install the OpenCody plugin on your OpenCode 2 server: in OpenCody go to Settings → Servers, open your server, tap Push Notifications and follow the steps, or copy the ready-made prompt for your coding agent. Notifications are end-to-end encrypted.

Fixes:
• Windows servers: folder paths like C:\Projects\App no longer get a leading slash, which made the server report "Location not found". Sessions created before this update still point to the broken path, so please start a new session in those projects.
• Notifications no longer show internal request IDs, and alerts you already saw don't come back.
