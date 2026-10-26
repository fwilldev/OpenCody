# OpenCody 1.10 – App Store release notes

Fixes:
• Windows servers: OpenCody no longer puts a slash in front of folder paths like C:\Projects\App, which made the server report "Location not found". Sessions created before this update still point to the broken path, so please start a new session in those projects.
