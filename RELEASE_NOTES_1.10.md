# OpenCody 1.10 – App Store release notes

Notifications for OpenCode 2. Get a notification when a run finishes, fails or needs your answer, even while OpenCody is closed. Allow or deny a permission right from the notification.

To set it up, install the OpenCody plugin on your OpenCode 2 server: in OpenCody go to Settings → Notifications, tap your server and follow the steps, or copy the ready-made prompt for your coding agent. Notifications are end-to-end encrypted. "Send Test Notification" asks your server to send one to this device, so it checks the whole setup (needs plugin 0.3.0 or later).

Notifications now arrive by push only. They need OpenCode 2 with the OpenCody plugin; OpenCode 1.x servers no longer send them.

Fixes:
• Windows servers: folder paths like C:\Projects\App no longer get a leading slash, which made the server report "Location not found". Sessions created before this update still point to the broken path, so please start a new session in those projects.
• iPad: more reliable navigation and connection status.
