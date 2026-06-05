# Privacy Policy

Effective date: June 5, 2026

This Privacy Policy explains how [Business Name] collects, uses, stores, and shares information when you use TindaPOS, including the POS app and the web license/admin portal.

TindaPOS is a POS and business-management app. Most business data is stored locally on your device. Supabase is used for cloud license activation, cloud sync, online backups, password reset, and admin/license management.

## Information We Collect

- Account and license information, including owner or admin email address, password-auth account data, store name, license code and status, subscription expiry, and device slot count.
- Device activation information, including device name, device record ID, activation time, last-seen time, revoked status, and cloud session metadata used to authorize cloud sync and license access.
- POS business data entered into the app, including products, barcodes, categories, prices, cost prices, stock counts, product images, sales, receipt numbers, discounts, void records, shifts, Z-readings, reports, and audit logs.
- Staff account data, including staff full name, username, role, hashed PIN or password data, created dates, and staff activity audit entries.
- Backup and sync data uploaded to Supabase Storage or Supabase database tables when you enable cloud backup or cloud sync.

## How We Use Information

- To run POS features such as product management, sales, receipts, shifts, staff access, reports, backups, and restores.
- To activate and verify licenses, manage subscription status, enforce device slot limits, recover lost devices, and support password reset flows.
- To sync store data between authorized devices when cloud sync is enabled.
- To help authorized admin or license portal users provide support, manage licenses, review device access, and audit administrative changes.

## Cloud Sync and Backups

- TindaPOS stores most POS data locally on your device. If you use cloud sync or online backup, selected POS data, product images, backup archives, store records, device records, and account/license records are sent to Supabase.
- Online backups are uploaded only when the backup feature is used. Cloud sync sends supported store data to Supabase so authorized devices can stay up to date.
- Deleting or changing cloud, license, or device records may affect activation, sync, backup access, password reset, or device access.

## Device Permissions

- Internet access is used for license activation, Supabase sync, online backup, password reset, and admin portal access.
- Camera and photo access may be used for barcode scanning and product images.
- File access through the system file picker or file saver is used for backups, restore files, and report exports.
- Screen wake lock may be used to keep the POS screen active. It does not collect personal data.
- Based on the current app implementation, TindaPOS does not collect location data, microphone data, advertising identifiers, or analytics data.

## How We Share Information

- We share data with Supabase as the cloud infrastructure provider for authentication, license activation, cloud sync, online backups, password reset, private storage, and admin/license management.
- Authorized admin or license portal users may view license, store, owner email, device, and audit data for support and license management.
- We do not sell personal data. Based on the current app implementation, TindaPOS does not use ad networks or third-party analytics services.

## Data Security

- The local POS database is encrypted with SQLCipher.
- Local app secrets and credentials are stored with secure storage where supported by the operating system.
- Supabase data is protected by authentication, row-level security, private storage bucket policies, and admin-only management flows.
- Passwords and PINs are not stored as plain text in local POS tables; they are hashed or securely handled for authentication.

## Data Retention

- Local POS data remains on the device until you delete it, restore over it, uninstall the app, or clear app data through device settings.
- Cloud data remains in Supabase while your license, cloud sync, backup, or support relationship is active, unless deletion is requested and deletion is technically and legally possible.
- Some records may be retained as needed for security, fraud prevention, license management, audit logs, backup integrity, dispute handling, or legal compliance.

## Your Choices

- You can use local POS features without enabling cloud sync where applicable.
- You can choose whether to upload online backups.
- You can request access, correction, deletion, or support by contacting [Contact Email].
- Some requests may affect your ability to use activation, cloud sync, online backups, password reset, or authorized device access.

## Children's Privacy

TindaPOS is intended for business use and is not directed to children. We do not knowingly collect personal information from children.

## Changes

We may update this Privacy Policy from time to time. When we make changes, we will update the effective date and make the revised policy available in the app or through another appropriate channel.

## Contact Us

Operator: [Business Name]

Email: [Contact Email]

Address: [Business Address, if applicable]

This policy is provided for product transparency and should not be treated as legal advice.
