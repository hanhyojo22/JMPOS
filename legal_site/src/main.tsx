import React from "react";
import ReactDOM from "react-dom/client";
import "./styles.css";

type Route = "privacy-policy" | "terms-and-conditions" | "contact";

type Section = {
  title: string;
  body?: string;
  items?: string[];
};

const effectiveDate = "June 5, 2026";

const privacySections: Section[] = [
  {
    title: "Information We Collect",
    items: [
      "Account and license information, including owner or admin email address, password-auth account data, store name, license code and status, subscription expiry, and device slot count.",
      "Device activation information, including device name, device record ID, activation time, last-seen time, revoked status, and cloud session metadata used to authorize cloud sync and license access.",
      "POS business data entered into the app, including products, barcodes, categories, prices, cost prices, stock counts, product images, sales, receipt numbers, discounts, void records, shifts, Z-readings, reports, and audit logs.",
      "Staff account data, including staff full name, username, role, hashed PIN or password data, created dates, and staff activity audit entries.",
      "Backup and sync data uploaded to Supabase Storage or Supabase database tables when you enable cloud backup or cloud sync.",
    ],
  },
  {
    title: "How We Use Information",
    items: [
      "To run POS features such as product management, sales, receipts, shifts, staff access, reports, backups, and restores.",
      "To activate and verify licenses, manage subscription status, enforce device slot limits, recover lost devices, and support password reset flows.",
      "To sync store data between authorized devices when cloud sync is enabled.",
      "To help authorized admin or license portal users provide support, manage licenses, review device access, and audit administrative changes.",
    ],
  },
  {
    title: "Cloud Sync and Backups",
    items: [
      "TindaPOS stores most POS data locally on your device. If you use cloud sync or online backup, selected POS data, product images, backup archives, store records, device records, and account/license records are sent to Supabase.",
      "Online backups are uploaded only when the backup feature is used. Cloud sync sends supported store data to Supabase so authorized devices can stay up to date.",
      "Deleting or changing cloud, license, or device records may affect activation, sync, backup access, password reset, or device access.",
    ],
  },
  {
    title: "Device Permissions",
    items: [
      "Internet access is used for license activation, Supabase sync, online backup, password reset, and admin portal access.",
      "Camera and photo access may be used for barcode scanning and product images.",
      "File access through the system file picker or file saver is used for backups, restore files, and report exports.",
      "Screen wake lock may be used to keep the POS screen active. It does not collect personal data.",
      "Based on the current app implementation, TindaPOS does not collect location data, microphone data, advertising identifiers, or analytics data.",
    ],
  },
  {
    title: "How We Share Information",
    items: [
      "We share data with Supabase as the cloud infrastructure provider for authentication, license activation, cloud sync, online backups, password reset, private storage, and admin/license management.",
      "Authorized admin or license portal users may view license, store, owner email, device, and audit data for support and license management.",
      "We do not sell personal data. Based on the current app implementation, TindaPOS does not use ad networks or third-party analytics services.",
    ],
  },
  {
    title: "Data Security",
    items: [
      "The local POS database is encrypted with SQLCipher.",
      "Local app secrets and credentials are stored with secure storage where supported by the operating system.",
      "Supabase data is protected by authentication, row-level security, private storage bucket policies, and admin-only management flows.",
      "Passwords and PINs are not stored as plain text in local POS tables; they are hashed or securely handled for authentication.",
    ],
  },
  {
    title: "Data Retention",
    items: [
      "Local POS data remains on the device until you delete it, restore over it, uninstall the app, or clear app data through device settings.",
      "Cloud data remains in Supabase while your license, cloud sync, backup, or support relationship is active, unless deletion is requested and deletion is technically and legally possible.",
      "Some records may be retained as needed for security, fraud prevention, license management, audit logs, backup integrity, dispute handling, or legal compliance.",
    ],
  },
  {
    title: "Your Choices",
    items: [
      "You can use local POS features without enabling cloud sync where applicable.",
      "You can choose whether to upload online backups.",
      "You can request access, correction, deletion, or support by contacting [Contact Email].",
      "Some requests may affect your ability to use activation, cloud sync, online backups, password reset, or authorized device access.",
    ],
  },
  {
    title: "Children's Privacy",
    body: "TindaPOS is intended for business use and is not directed to children. We do not knowingly collect personal information from children.",
  },
  {
    title: "Changes",
    body: "We may update this Privacy Policy from time to time. When we make changes, we will update the effective date and make the revised policy available in the app or through another appropriate channel.",
  },
  {
    title: "Contact Us",
    items: [
      "Operator: [Business Name]",
      "Email: [Contact Email]",
      "Address: [Business Address, if applicable]",
    ],
  },
];

const termsSections: Section[] = [
  {
    title: "Use of TindaPOS",
    body: "TindaPOS is provided for business point-of-sale, inventory, reporting, staff access, license activation, cloud sync, online backup, and related administrative workflows. You are responsible for using the app in compliance with laws that apply to your business.",
  },
  {
    title: "Accounts, Licenses, and Subscriptions",
    items: [
      "Access to some features may require a valid license, owner account, active subscription, and authorized device slot.",
      "You are responsible for keeping owner/admin credentials, staff PINs, and device access secure.",
      "Licenses may expire, be suspended, or have device limits. Cloud sync, backups, and activation may stop working if a license is expired, suspended, revoked, or otherwise invalid.",
    ],
  },
  {
    title: "Your Business Data",
    items: [
      "You are responsible for the accuracy of products, prices, inventory, sales, staff records, discounts, reports, tax treatment, receipt content, and business records entered into TindaPOS.",
      "You should keep your own backups and verify reports before relying on them for accounting, tax, inventory, or compliance decisions.",
      "If you use cloud sync or online backup, your selected business data may be sent to Supabase so authorized devices and backup features can work.",
    ],
  },
  {
    title: "Acceptable Use",
    items: [
      "Do not misuse, reverse engineer, disrupt, overload, or attempt unauthorized access to TindaPOS, the license/admin portal, Supabase services, or any connected system.",
      "Do not share license codes, recovery codes, owner accounts, or admin credentials with unauthorized people.",
      "Do not use TindaPOS to store or transmit unlawful, harmful, or unauthorized data.",
    ],
  },
  {
    title: "Support and Changes",
    body: "Support may be provided through [Contact Email] or other channels made available by [Business Name]. Features, license terms, subscriptions, support processes, and these Terms may be updated from time to time.",
  },
  {
    title: "Disclaimers",
    body: "TindaPOS is provided on an as-is and as-available basis to the fullest extent permitted by law. We do not guarantee uninterrupted operation, error-free reports, continuous cloud access, compatibility with every device, or that all data can be recovered after device loss, user error, service outage, or corrupted backups.",
  },
  {
    title: "Limitation of Liability",
    body: "To the fullest extent permitted by law, [Business Name] is not liable for indirect, incidental, special, consequential, or punitive damages, including lost profits, lost sales, lost data, business interruption, or accounting/tax losses arising from use of TindaPOS.",
  },
  {
    title: "Contact",
    body: "Questions about these Terms may be sent to [Contact Email].",
  },
];

function App() {
  const route = normalizeRoute(globalThis.location.pathname);

  return (
    <div className="site-shell">
      <Header activeRoute={route} />
      <main>
        {route === "privacy-policy" && <PrivacyPolicy />}
        {route === "terms-and-conditions" && <TermsAndConditions />}
        {route === "contact" && <Contact />}
      </main>
      <Footer />
    </div>
  );
}

function Header({ activeRoute }: { activeRoute: Route }) {
  return (
    <header className="site-header">
      <a className="brand" href="/privacy-policy" aria-label="TindaPOS Legal">
        <span className="brand-mark" aria-hidden="true">
          <img src="/appiconnobg.png" alt="" />
        </span>
        <span>
          <strong>TindaPOS</strong>
          <small>Legal Center</small>
        </span>
      </a>
      <nav aria-label="Legal pages">
        <NavLink route="privacy-policy" activeRoute={activeRoute}>
          Privacy Policy
        </NavLink>
        <NavLink route="terms-and-conditions" activeRoute={activeRoute}>
          Terms
        </NavLink>
        <NavLink route="contact" activeRoute={activeRoute}>
          Contact
        </NavLink>
      </nav>
    </header>
  );
}

function NavLink({
  route,
  activeRoute,
  children,
}: {
  route: Route;
  activeRoute: Route;
  children: React.ReactNode;
}) {
  return (
    <a className={route === activeRoute ? "active" : ""} href={`/${route}`}>
      {children}
    </a>
  );
}

function PrivacyPolicy() {
  return (
    <DocumentPage
      eyebrow="Privacy"
      title="Privacy Policy"
      intro={[
        `Effective date: ${effectiveDate}`,
        "This Privacy Policy explains how [Business Name] collects, uses, stores, and shares information when you use TindaPOS, including the POS app and the web license/admin portal.",
        "TindaPOS is a POS and business-management app. Most business data is stored locally on your device. Supabase is used for cloud license activation, cloud sync, online backups, password reset, and admin/license management.",
      ]}
      sections={privacySections}
      note="This policy is provided for product transparency and should not be treated as legal advice."
    />
  );
}

function TermsAndConditions() {
  return (
    <DocumentPage
      eyebrow="Terms"
      title="Terms and Conditions"
      intro={[
        `Effective date: ${effectiveDate}`,
        "These Terms and Conditions explain the basic rules for using TindaPOS and related license, cloud sync, backup, and admin services provided by [Business Name].",
        "These starter terms are provided for product transparency and should be reviewed by a qualified legal professional before publication as final legal terms.",
      ]}
      sections={termsSections}
    />
  );
}

function Contact() {
  return (
    <section className="contact-page">
      <div className="document-header">
        <span className="eyebrow">Support</span>
        <h1>Contact</h1>
        <p>
          For privacy requests, license support, subscription questions, device
          recovery, and general TindaPOS support, use the contact details below.
        </p>
      </div>
      <div className="contact-grid">
        <ContactCard label="Email" value="[Contact Email]" />
        <ContactCard label="Phone" value="[Support Phone]" />
        <ContactCard
          label="Address"
          value="[Business Address, if applicable]"
        />
      </div>
      <div className="support-note">
        Include your store name, owner email, license code if available, and a
        short description of the issue. Do not send staff PINs, passwords, or
        full payment details.
      </div>
    </section>
  );
}

function ContactCard({ label, value }: { label: string; value: string }) {
  return (
    <article className="contact-card">
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  );
}

function DocumentPage({
  eyebrow,
  title,
  intro,
  sections,
  note,
}: {
  eyebrow: string;
  title: string;
  intro: string[];
  sections: Section[];
  note?: string;
}) {
  return (
    <article className="document">
      <div className="document-header">
        <span className="eyebrow">{eyebrow}</span>
        <h1>{title}</h1>
        {intro.map((paragraph) => (
          <p key={paragraph}>{paragraph}</p>
        ))}
      </div>
      {sections.map((section) => (
        <section className="legal-section" key={section.title}>
          <h2>{section.title}</h2>
          {section.body && <p>{section.body}</p>}
          {section.items && (
            <ul>
              {section.items.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          )}
        </section>
      ))}
      {note && <p className="legal-note">{note}</p>}
    </article>
  );
}

function Footer() {
  return (
    <footer>
      <span>TindaPOS Legal Center</span>
      <span>© {new Date().getFullYear()} [Business Name]</span>
    </footer>
  );
}

function normalizeRoute(pathname: string): Route {
  const clean = pathname.replace(/^\/+|\/+$/g, "");
  if (
    clean === "privacy-policy" ||
    clean === "terms-and-conditions" ||
    clean === "contact"
  ) {
    return clean;
  }

  if (clean === "") {
    globalThis.history.replaceState(null, "", "/privacy-policy");
  }

  return "privacy-policy";
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
